import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'revglue_service.dart';

// =====================================================================================
// HUDDL CONNECT -- AI DEALS CURATION SERVICE  (Gemini 2.0 Flash)
// =====================================================================================
//
// Uses Google Gemini to analyse RevGlue stores, coupons and categories and produce
// parent-personalised deal recommendations based on:
//   - Child ages & life stages (expecting, newborn, toddler, pre-school, school-age)
//   - Season / time of year (back-to-school, Christmas, summer holidays)
//   - Local borough context
//   - Category affinity (baby gear, travel, food, fashion, etc.)
//
// Three AI capabilities:
//   1. Smart Picks  -- scores & ranks ALL stores, returns top N with "why" copy
//   2. Deal Insights -- given a coupon list, generates parent-specific tips per deal
//   3. Seasonal Spotlight -- generates a short editorial-style seasonal savings guide
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

class AiOffersService {
  // ---- Singleton ----
  static final AiOffersService _instance = AiOffersService._internal();
  factory AiOffersService() => _instance;
  AiOffersService._internal();

  // ---- Dependencies ----
  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();
  final RevGlueService _revglue = RevGlueService();

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
      return recommendations;
    } catch (e) {
      if (kDebugMode) debugPrint('AiOffersService smart picks error: $e');
      return _fallbackSmartPicks(stores);
    }
  }

  Future<List<AiDealRecommendation>> _callGeminiSmartPicks(
      List<RevGlueStore> stores) async {
    final userContext = _buildUserContext();
    final season = _currentSeason();

    // Build a concise store list for the prompt
    final storeList = stores
        .take(40)
        .map((s) =>
            '{"id":"${s.id}","name":"${s.title}","offers":"${s.offerCouponStr}"}')
        .join(',\n');

    final systemPrompt = '''
You are Huddl's AI Offers Curator for UK parents. Your job is to analyse retail stores
and their current offers, then rank them by relevance for THIS specific parent.

USER CONTEXT:
$userContext

CURRENT SEASON: $season

TASK:
From the store list below, select the TOP 8 most relevant stores for this parent.
For each, provide:
- relevanceScore (0-100): how useful this deal is for this parent right now
- parentTip: a short (max 15 words), warm, practical British English tip explaining WHY
  this deal matters for them specifically. Reference their child's age/stage if relevant.
- badge: a short label (2-3 words) like "Nappy Saver", "Weaning Must", "Travel Deal",
  "School Kit", "Mum Treat", "Baby Essential", "Top Pick", "Budget Win"
- tags: 2-3 short tags relevant to the deal

RESPONSE FORMAT (strict JSON array, no markdown):
[
  {"storeId":"...","storeName":"...","relevanceScore":85,"parentTip":"...","badge":"...","tags":["...","..."]}
]

STORES:
[$storeList]
''';

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
    final userContext = _buildUserContext();

    final couponList = coupons
        .take(10)
        .map((c) =>
            '{"id":"${c.id}","title":"${c.title}","code":"${c.voucherCode}","expires":"${c.expiryDate}","type":"${c.offerCoupon}"}')
        .join(',\n');

    final storeName =
        coupons.isNotEmpty ? coupons.first.storeTitle : 'this store';

    final systemPrompt = '''
You are Huddl's AI Offers Advisor for UK parents. Analyse these coupons from $storeName
and provide personalised money-saving insights.

USER CONTEXT:
$userContext

TASK:
For each coupon, provide:
- savvyTip: a short (max 20 words), practical, warm British English tip for this parent.
  Think "savvy mum/dad advice" -- combine the offer with what the parent actually needs.
  Examples: "Pair this with their 20% baby event for double savings on formula"
  or "Stock up on nappies now -- this code rarely comes around"
- worthItVerdict: one of "Must-grab", "Great deal", "Worth it", "Decent", "Skip it"
- isTopPick: true if this is the standout deal from this store for this parent

RESPONSE FORMAT (strict JSON array, no markdown):
[
  {"couponId":"...","savvyTip":"...","worthItVerdict":"...","isTopPick":false}
]

Mark exactly ONE coupon as isTopPick: true (the best one for this parent).

COUPONS:
[$couponList]
''';

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
    final userContext = _buildUserContext();
    final season = _currentSeason();
    final month = _currentMonth();

    final storeNames = stores.take(25).map((s) => s.title).join(', ');

    final systemPrompt = '''
You are Huddl's AI Offers Editor for UK parents. Write a short seasonal savings spotlight
personalised for this parent.

USER CONTEXT:
$userContext

CURRENT MONTH: $month
SEASON: $season
AVAILABLE STORES: $storeNames

TASK:
Create a seasonal savings spotlight with:
- title: catchy seasonal title (max 6 words), reference the season and parenting stage
- summary: 2-3 sentences of warm, practical British English editorial copy. Address the
  parent directly. Mention their child's age/stage. Include specific saving strategies
  for this time of year. Sound like a savvy parent friend, not a marketing bot.
- topStoreNames: 3-4 store names from the available list most relevant right now
- savingTips: 4 short (max 12 words each) actionable money-saving tips for this parent
  this season. Be specific to their child's needs.

RESPONSE FORMAT (strict JSON, no markdown):
{"title":"...","summary":"...","topStoreNames":["..."],"savingTips":["..."]}
''';

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
  // USER CONTEXT BUILDER
  // ===========================================================================

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
    // Simple keyword-based scoring as fallback
    final stages = _onboarding.stagesOfLife;
    final hasNewborn = stages.any((s) => s.toLowerCase().contains('newborn'));
    final hasToddler = stages.any((s) => s.toLowerCase().contains('toddler'));
    final isExpecting = _onboarding.dueDate != null;

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
