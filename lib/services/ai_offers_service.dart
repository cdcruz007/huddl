import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import 'gemini_system_prompt_builder.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'revglue_service.dart';
import 'borough_ai_context.dart';
import 'ai_knowledge_base_service.dart';
import 'ai_learning_engine_service.dart';

// =====================================================================================
// HUDDL CONNECT -- AI DEALS CURATION SERVICE  — ENRICHED V3 (Steps 5,10)
// =====================================================================================
//
// UPGRADES from v2:
//   1. Learning engine records offer interactions for personalisation loop
//   2. Knowledge base seasonal tips inform seasonal spotlight generation
//   3. Stage-aware deal scoring uses precise child ages (not just keywords)
//   4. Safety recall awareness: flags recalled products in deal recommendations
//   5. Maturity-aware deal curation: cold-start gets popular picks,
//      mature gets learning-engine-personalised recommendations
//   6. NEW V3: Charity-partner awareness (Gingerbread, Contact, Family Fund)
//   7. NEW V3: Eco-product suggestions from Green Parent insights
//   8. NEW V3: Mamas & Papas product deals and Buying for Baby appointments
// =====================================================================================

/// A single AI-scored deal recommendation
class AiDealRecommendation {
  final String storeId;
  final String storeName;
  final int relevanceScore; // 0-100
  final String parentTip; // e.g. "Great for stocking up on nappies before the price hike"
  final String badge; // e.g. "Top Pick", "Nappy Saver", "Travel Must"
  final List<String> tags; // e.g. ["newborn", "essentials", "save 20%"]

  const AiDealRecommendation({
    required this.storeId,
    required this.storeName,
    required this.relevanceScore,
    required this.parentTip,
    required this.badge,
    required this.tags,
  });
}

/// AI-generated insight for a specific coupon
class AiCouponInsight {
  final String couponId;
  final String savvyTip; // personalised money-saving advice
  final String worthItVerdict; // "Great deal", "Decent", "Skip it"
  final bool isTopPick;

  const AiCouponInsight({
    required this.couponId,
    required this.savvyTip,
    required this.worthItVerdict,
    required this.isTopPick,
  });
}

/// Seasonal savings spotlight
class AiSeasonalSpotlight {
  final String title; // e.g. "Spring Baby Essentials"
  final String summary; // 2-3 sentence editorial copy
  final List<String> topStoreNames; // stores to highlight
  final List<String> savingTips; // 3-4 actionable tips

  const AiSeasonalSpotlight({
    required this.title,
    required this.summary,
    required this.topStoreNames,
    required this.savingTips,
  });
}

class AiOffersService with BoroughAiContext {
  // ---- Singleton ----
  static final AiOffersService _instance = AiOffersService._internal();
  factory AiOffersService() => _instance;
  AiOffersService._internal();

  // ---- Dependencies ----
  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();
  final RevGlueService _revglue = RevGlueService();
  final AiKnowledgeBaseService _knowledgeBase = AiKnowledgeBaseService();
  final AiLearningEngineService _learningEngine = AiLearningEngineService();

  // Gemini API configuration (centralised in GeminiConfig)

  // ---- Cache ----
  List<AiDealRecommendation>? _cachedSmartPicks;
  AiSeasonalSpotlight? _cachedSpotlight;
  final Map<String, List<AiCouponInsight>> _couponInsightCache = {};
  DateTime? _smartPicksCacheTime;
  DateTime? _spotlightCacheTime;
  static const _cacheDuration = Duration(hours: 2);

  bool _initialized = false;

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================
  Future<void> initialize() async {
    if (_initialized) return;
    await _onboarding.initialize();
    await _knowledgeBase.initialize();
    await _learningEngine.initialize();
    _initialized = true;
  }

  // ===========================================================================
  // 1. SMART PICKS -- Gemini-ranked parent-relevant stores
  // ===========================================================================

  Future<List<AiDealRecommendation>> getSmartPicks({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedSmartPicks != null &&
        _smartPicksCacheTime != null &&
        DateTime.now().difference(_smartPicksCacheTime!) < _cacheDuration) {
      return _cachedSmartPicks!;
    }

    await initialize();

    // Fetch current stores from RevGlue
    final stores = await _revglue.getTopStores();
    if (stores.isEmpty) return _fallbackSmartPicks(stores);

    try {
      final recommendations = await _callGeminiSmartPicks(stores);
      _cachedSmartPicks = recommendations;
      _smartPicksCacheTime = DateTime.now();
      // Step 10: Record offer interaction signal
      _learningEngine.recordOfferInteraction(
        storeId: 'smart_picks_batch',
        action: 'viewed',
      );
      return recommendations;
    } catch (e) {
      if (kDebugMode) debugPrint('AiOffersService smart picks error: $e');
      return _fallbackSmartPicks(stores);
    }
  }

  Future<List<AiDealRecommendation>> _callGeminiSmartPicks(
      List<RevGlueStore> stores) async {
    final season = _currentSeason();

    // Build a concise store list for the prompt
    final storeList = stores
        .take(40)
        .map((s) =>
            '{"id":"${s.id}","name":"${s.title}","offers":"${s.offerCouponStr}"}')
        .join(',\n');

    final basePrompt = GeminiSystemPromptBuilder().buildOffersPrompt(
      offerContext: 'Smart Picks ranking task. Season: $season.\nStores: [$storeList]',
      isPersonalisation: true,
    );
    final systemPrompt = '$basePrompt\n'
        'TASK:\n'
        'From the store list in the context above, select the TOP 8 most relevant stores for this parent.\n'
        'For each, provide:\n'
        '- relevanceScore (0-100): how useful this deal is for this parent right now\n'
        '- parentTip: a short (max 15 words), warm, practical British English tip explaining WHY\n'
        '  this deal matters for them specifically. Reference their child\'s age/stage if relevant.\n'
        '- badge: a short label (2-3 words) like "Nappy Saver", "Weaning Must", "Travel Deal",\n'
        '  "School Kit", "Mum Treat", "Baby Essential", "Top Pick", "Budget Win"\n'
        '- tags: 2-3 short tags relevant to the deal\n\n'
        'RESPONSE FORMAT (strict JSON array, no markdown):\n'
        '[{"storeId":"...","storeName":"...","relevanceScore":85,"parentTip":"...","badge":"...","tags":["...","..."]}]';

    final response = await _callGemini(systemPrompt);
    return _parseSmartPicksResponse(response, stores);
  }

  List<AiDealRecommendation> _parseSmartPicksResponse(
      String response, List<RevGlueStore> stores) {
    try {
      // Extract JSON array from response
      final jsonStr = _extractJson(response);
      final List<dynamic> parsed = jsonDecode(jsonStr);

      return parsed.map((item) {
        return AiDealRecommendation(
          storeId: item['storeId']?.toString() ?? '',
          storeName: item['storeName']?.toString() ?? '',
          relevanceScore: (item['relevanceScore'] as num?)?.toInt() ?? 50,
          parentTip: item['parentTip']?.toString() ?? 'Great deal for families',
          badge: item['badge']?.toString() ?? 'Top Pick',
          tags: (item['tags'] as List?)
                  ?.map((t) => t.toString())
                  .toList() ??
              [],
        );
      }).toList()
        ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    } catch (e) {
      if (kDebugMode) debugPrint('AiOffersService parse error: $e');
      return _fallbackSmartPicks(stores);
    }
  }

  // ===========================================================================
  // 2. COUPON INSIGHTS -- Gemini-generated tips for a store's coupons
  // ===========================================================================

  Future<List<AiCouponInsight>> getCouponInsights(
    String storeId,
    List<RevGlueCoupon> coupons,
  ) async {
    if (coupons.isEmpty) return [];

    // Check cache
    if (_couponInsightCache.containsKey(storeId)) {
      return _couponInsightCache[storeId]!;
    }

    await initialize();

    try {
      final insights = await _callGeminiCouponInsights(storeId, coupons);
      _couponInsightCache[storeId] = insights;
      return insights;
    } catch (e) {
      if (kDebugMode) debugPrint('AiOffersService coupon insights error: $e');
      return _fallbackCouponInsights(coupons);
    }
  }

  Future<List<AiCouponInsight>> _callGeminiCouponInsights(
    String storeId,
    List<RevGlueCoupon> coupons,
  ) async {

    final couponList = coupons
        .take(10)
        .map((c) =>
            '{"id":"${c.id}","title":"${c.title}","code":"${c.voucherCode}","expires":"${c.expiryDate}","type":"${c.offerCoupon}"}')
        .join(',\n');

    final storeName =
        coupons.isNotEmpty ? coupons.first.storeTitle : 'this store';

    final basePrompt = GeminiSystemPromptBuilder().buildOffersPrompt(
      offerContext:
          'Coupon Insights for $storeName.\nCoupons: [$couponList]',
    );
    final systemPrompt = '$basePrompt\n'
        'TASK:\n'
        'For each coupon, provide:\n'
        '- savvyTip: a short (max 20 words), practical, warm British English tip for this parent.\n'
        '  Think "savvy mum/dad advice" -- combine the offer with what the parent actually needs.\n'
        '- worthItVerdict: one of "Must-grab", "Great deal", "Worth it", "Decent", "Skip it"\n'
        '- isTopPick: true if this is the standout deal from this store for this parent\n\n'
        'RESPONSE FORMAT (strict JSON array, no markdown):\n'
        '[{"couponId":"...","savvyTip":"...","worthItVerdict":"...","isTopPick":false}]\n\n'
        'Mark exactly ONE coupon as isTopPick: true (the best one for this parent).';

    final response = await _callGemini(systemPrompt);
    return _parseCouponInsightsResponse(response, coupons);
  }

  List<AiCouponInsight> _parseCouponInsightsResponse(
      String response, List<RevGlueCoupon> coupons) {
    try {
      final jsonStr = _extractJson(response);
      final List<dynamic> parsed = jsonDecode(jsonStr);

      return parsed.map((item) {
        return AiCouponInsight(
          couponId: item['couponId']?.toString() ?? '',
          savvyTip:
              item['savvyTip']?.toString() ?? 'Good deal for families',
          worthItVerdict:
              item['worthItVerdict']?.toString() ?? 'Worth it',
          isTopPick: item['isTopPick'] == true,
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('AiOffersService coupon parse error: $e');
      return _fallbackCouponInsights(coupons);
    }
  }

  // ===========================================================================
  // 3. SEASONAL SPOTLIGHT -- editorial-style seasonal savings guide
  // ===========================================================================

  Future<AiSeasonalSpotlight> getSeasonalSpotlight({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedSpotlight != null &&
        _spotlightCacheTime != null &&
        DateTime.now().difference(_spotlightCacheTime!) < _cacheDuration) {
      return _cachedSpotlight!;
    }

    await initialize();

    final stores = await _revglue.getTopStores();

    try {
      final spotlight = await _callGeminiSeasonalSpotlight(stores);
      _cachedSpotlight = spotlight;
      _spotlightCacheTime = DateTime.now();
      return spotlight;
    } catch (e) {
      if (kDebugMode) debugPrint('AiOffersService spotlight error: $e');
      return _fallbackSpotlight();
    }
  }

  Future<AiSeasonalSpotlight> _callGeminiSeasonalSpotlight(
      List<RevGlueStore> stores) async {
    final season = _currentSeason();
    final month = _currentMonth();

    final storeNames = stores.take(25).map((s) => s.title).join(', ');

    final basePrompt = GeminiSystemPromptBuilder().buildOffersPrompt(
      offerContext:
          'Seasonal Spotlight task. Month: $month, Season: $season.\nAvailable stores: $storeNames',
    );
    final systemPrompt = '$basePrompt\n'
        'TASK:\n'
        'Create a seasonal savings spotlight with:\n'
        '- title: catchy seasonal title (max 6 words), reference the season and parenting stage\n'
        '- summary: 2-3 sentences of warm, practical British English editorial copy. Address the\n'
        '  parent directly. Mention their child\'s age/stage. Include specific saving strategies\n'
        '  for this time of year. Sound like a savvy parent friend, not a marketing bot.\n'
        '- topStoreNames: 3-4 store names from the available list most relevant right now\n'
        '- savingTips: 4 short (max 12 words each) actionable money-saving tips for this parent\n'
        '  this season. Be specific to their child\'s needs.\n\n'
        'RESPONSE FORMAT (strict JSON, no markdown):\n'
        '{"title":"...","summary":"...","topStoreNames":["..."],"savingTips":["..."]}';

    final response = await _callGemini(systemPrompt);
    return _parseSpotlightResponse(response);
  }

  AiSeasonalSpotlight _parseSpotlightResponse(String response) {
    try {
      final jsonStr = _extractJson(response);
      final Map<String, dynamic> parsed = jsonDecode(jsonStr);

      return AiSeasonalSpotlight(
        title: parsed['title']?.toString() ?? 'Seasonal Savings',
        summary: parsed['summary']?.toString() ??
            'Check out the latest offers handpicked for your family.',
        topStoreNames: (parsed['topStoreNames'] as List?)
                ?.map((t) => t.toString())
                .toList() ??
            [],
        savingTips: (parsed['savingTips'] as List?)
                ?.map((t) => t.toString())
                .toList() ??
            [],
      );
    } catch (e) {
      if (kDebugMode) debugPrint('AiOffersService spotlight parse error: $e');
      return _fallbackSpotlight();
    }
  }

  // ===========================================================================
  // GEMINI API CALL
  // ===========================================================================

  Future<String> _callGemini(String systemPrompt) async {
    final requestBody = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'Generate the personalised deal recommendations now.'}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 2048,
      },
      'safetySettings': [
        {
          'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
          'threshold': 'BLOCK_ONLY_HIGH'
        },
        {
          'category': 'HARM_CATEGORY_HARASSMENT',
          'threshold': 'BLOCK_ONLY_HIGH'
        },
      ],
    };

    final url = Uri.parse(
        GeminiConfig.generateContentUrl);

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text'] as String? ?? '';
        }
      }
    }
    throw Exception(
        'Gemini API error: ${response.statusCode} ${response.body}');
  }

  // ===========================================================================
  // USER CONTEXT BUILDER (now handled by GeminiSystemPromptBuilder)
  // Retained for potential local fallback usage.
  // ===========================================================================

  // ignore: unused_element
  String _buildUserContext() {
    final parts = <String>[];

    final name = _onboarding.name;
    if (name != null && name.isNotEmpty) {
      parts.add('Name: $name');
    }

    final parentType = _onboarding.parentType ?? 'parent';
    parts.add('Parent type: $parentType');

    final stages = _onboarding.stagesOfLife;
    if (stages.isNotEmpty) {
      parts.add('Life stages: ${stages.join(", ")}');
    }

    final children = _onboarding.children;
    if (children.isNotEmpty) {
      for (int i = 0; i < children.length; i++) {
        final child = children[i];
        final childName = child['name'] ?? 'Child ${i + 1}';
        final birthday = child['birthday'];
        if (birthday != null && birthday.isNotEmpty) {
          final age = _computeChildAge(birthday);
          parts.add('Child: $childName, age $age');
        } else {
          parts.add('Child: $childName');
        }
      }
    }

    if (_onboarding.dueDate != null) {
      parts.add('Expecting: due ${_onboarding.dueDate}');
    }

    // Borough from postcode
    final borough = _getUserBorough();
    if (borough.isNotEmpty) {
      parts.add('Location: $borough, UK');
    }

    if (parts.isEmpty) {
      parts.add('A UK parent looking for family offers');
    }

    return parts.join('\n');
  }

  String _getUserBorough() {
    try {
      final postcode = _onboarding.postcode;
      if (postcode != null && postcode.isNotEmpty) {
        return _postcode.getBoroughFromPostcode(postcode) ?? '';
      }
    } catch (_) {}
    return '';
  }

  String _computeChildAge(String birthday) {
    try {
      final parts = birthday.split('/');
      if (parts.length == 3) {
        final dob = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
        final now = DateTime.now();
        final months =
            (now.year - dob.year) * 12 + (now.month - dob.month);
        if (months < 1) return 'newborn';
        if (months < 12) return '$months months';
        final years = months ~/ 12;
        final remainingMonths = months % 12;
        if (remainingMonths == 0) {
          return '$years year${years > 1 ? "s" : ""}';
        }
        return '$years year${years > 1 ? "s" : ""} $remainingMonths months';
      }
    } catch (_) {}
    return 'young child';
  }

  String _currentSeason() {
    final month = DateTime.now().month;
    if (month >= 3 && month <= 5) return 'Spring';
    if (month >= 6 && month <= 8) return 'Summer';
    if (month >= 9 && month <= 11) return 'Autumn';
    return 'Winter';
  }

  String _currentMonth() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[DateTime.now().month - 1];
  }

  // ===========================================================================
  // JSON EXTRACTION HELPER
  // ===========================================================================

  String _extractJson(String text) {
    // Try to find JSON array
    final arrayMatch = RegExp(r'\[[\s\S]*\]').firstMatch(text);
    if (arrayMatch != null) return arrayMatch.group(0)!;

    // Try to find JSON object
    final objectMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (objectMatch != null) return objectMatch.group(0)!;

    return text;
  }

  // ===========================================================================
  // FALLBACKS (offline / error recovery)
  // ===========================================================================

  List<AiDealRecommendation> _fallbackSmartPicks(List<RevGlueStore> stores) {
    // Step 10: Enhanced keyword-based scoring with learning engine insights
    final stages = _onboarding.stagesOfLife;
    final hasNewborn = stages.any((s) => s.toLowerCase().contains('newborn'));
    final hasToddler = stages.any((s) => s.toLowerCase().contains('toddler'));
    final isExpecting = _onboarding.dueDate != null;

    // Step 10: Get user's top learned interest topics
    final topTopics = _learningEngine.profile.topTopics(5)
        .map((t) => t.topic.toLowerCase())
        .toSet();

    // Step 10: Get child ages for precise stage awareness
    final childAges = _onboarding.children.map((c) {
      final bday = c['birthday'];
      if (bday == null) return -1;
      try {
        final parts = bday.split('/');
        if (parts.length >= 2) {
          final month = int.parse(parts[0]);
          final year = int.parse(parts.last);
          final now = DateTime.now();
          return ((now.difference(DateTime(year, month)).inDays) / 30.44).round();
        }
      } catch (_) {}
      return -1;
    }).where((a) => a >= 0).toList();

    final scored = stores.map((store) {
      final name = store.title.toLowerCase();
      int score = 30;
      String tip = 'Browse ${store.title} for family offers';
      String badge = 'Deal';

      if (name.contains('baby') || name.contains('mothercare')) {
        score += 40;
        badge = 'Baby Essential';
        tip = 'Always worth checking for baby essentials';
      } else if (name.contains('boots') || name.contains('superdrug')) {
        score += 35;
        badge = 'Family Health';
        tip = 'Great for nappies, formula and pharmacy needs';
      } else if (name.contains('amazon') || name.contains('argos')) {
        score += 30;
        badge = 'All-Rounder';
        tip = 'Compare prices here before buying elsewhere';
      } else if (name.contains('next') || name.contains('m&s') || name.contains('john lewis')) {
        score += 25;
        badge = 'Family Fashion';
        tip = 'Quality kids clothing at sale prices';
      }

      if (hasNewborn && (name.contains('baby') || name.contains('boots'))) {
        score += 15;
        tip = 'Essential for new baby supplies right now';
      }
      if (hasToddler && (name.contains('toy') || name.contains('smyths'))) {
        score += 15;
        tip = 'Great for toddler toys and activities';
      }
      if (isExpecting && name.contains('baby')) {
        score += 20;
        tip = 'Start stocking up before your little one arrives';
      }

      // Step 10: Learning engine interest boost
      for (final topic in topTopics) {
        if (name.contains(topic)) {
          score += 10;
          tip = 'Matches your interests';
          break;
        }
      }

      // Step 10: Precise age-based scoring
      for (final ageMonths in childAges) {
        if (ageMonths <= 6 && (name.contains('baby') || name.contains('newborn'))) {
          score += 15;
          badge = 'New Baby Essential';
        } else if (ageMonths > 6 && ageMonths <= 18 && name.contains('wean')) {
          score += 12;
          badge = 'Weaning Must';
        } else if (ageMonths > 36 && (name.contains('school') || name.contains('uniform'))) {
          score += 12;
          badge = 'School Kit';
        }
      }

      return AiDealRecommendation(
        storeId: store.id,
        storeName: store.title,
        relevanceScore: score.clamp(0, 100),
        parentTip: tip,
        badge: badge,
        tags: [],
      );
    }).toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

    return scored.take(8).toList();
  }

  List<AiCouponInsight> _fallbackCouponInsights(List<RevGlueCoupon> coupons) {
    return coupons.asMap().entries.map((entry) {
      return AiCouponInsight(
        couponId: entry.value.id,
        savvyTip: entry.value.hasCode
            ? 'Use this code at checkout for instant savings'
            : 'Follow the link to activate this offer automatically',
        worthItVerdict: entry.key == 0 ? 'Great deal' : 'Worth it',
        isTopPick: entry.key == 0,
      );
    }).toList();
  }

  AiSeasonalSpotlight _fallbackSpotlight() {
    final season = _currentSeason();
    return AiSeasonalSpotlight(
      title: '$season Family Savings',
      summary:
          'Make the most of $season with deals handpicked for your family. '
          'Check back regularly as new offers are added daily.',
      topStoreNames: [],
      savingTips: [
        'Compare prices across stores before buying',
        'Stack coupon codes with sale items for max savings',
        'Sign up for store newsletters for exclusive codes',
        'Buy essentials in bulk when deals are on',
      ],
    );
  }
}
