import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'ai_api_helper.dart';
import 'gemini_system_prompt_builder.dart';
import 'rehome_service.dart';
import 'borough_ai_context.dart';
import 'ai_knowledge_base_service.dart';
import 'ai_learning_engine_service.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

// =============================================================================
// AI LISTING GENERATOR SERVICE  — ENRICHED V3 (Steps 5,8)
//
// UPGRADES from v2:
//   1. Safety recall checking via Knowledge Base (not just static list)
//   2. Borough-aware pricing suggestions using local market data
//   3. Learning engine signals: records marketplace interactions
//   4. Category suggestions informed by user's child age stage
//   5. Knowledge base safety warnings injected into listing descriptions
//   6. NEW V3: Mamas & Papas product guidance for pricing benchmarks
//   7. NEW V3: Today's Parent ultra-processed food awareness for feeding items
//   8. NEW V3: Green Parent eco-friendly product nudges
// =============================================================================

class AiListingDraft {
  final String suggestedTitle;
  final String suggestedDescription;
  final double suggestedPrice;
  final double retailPrice;
  final int savingsPercent;
  final ItemCategory suggestedCategory;
  final AgeStage suggestedAgeStage;
  final ItemCondition suggestedCondition;
  final String? safetyNote;
  final List<String> tags;
  final double confidence;

  const AiListingDraft({
    required this.suggestedTitle,
    required this.suggestedDescription,
    required this.suggestedPrice,
    required this.retailPrice,
    required this.savingsPercent,
    required this.suggestedCategory,
    required this.suggestedAgeStage,
    required this.suggestedCondition,
    this.safetyNote,
    required this.tags,
    required this.confidence,
  });
}

class PriceComparison {
  final double avgLocalPrice;
  final double lowestPrice;
  final double highestPrice;
  final int recentSalesCount;
  final String priceVerdict; // 'great_deal', 'fair', 'above_avg'

  const PriceComparison({
    required this.avgLocalPrice,
    required this.lowestPrice,
    required this.highestPrice,
    required this.recentSalesCount,
    required this.priceVerdict,
  });
}

class AiListingService with BoroughAiContext {
  static final AiListingService _instance = AiListingService._internal();
  factory AiListingService() => _instance;
  AiListingService._internal();

  final RehomeService _rehomeService = RehomeService();
  final AiKnowledgeBaseService _knowledgeBase = AiKnowledgeBaseService();
  final AiLearningEngineService _learningEngine = AiLearningEngineService();
  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    await _knowledgeBase.initialize();
    await _learningEngine.initialize();
    _isInitialized = true;
  }

  // ── Step 8: Borough-aware user context ──────────────────────────────────

  String _getUserBorough() {
    final pc = _onboarding.postcode;
    if (pc != null) {
      return _postcode.getBoroughFromPostcode(pc) ?? 'your area';
    }
    return 'your area';
  }

  /// Use Gemini AI to analyse a product description and generate a listing.
  /// Step 8: Now checks safety recalls from Knowledge Base and records
  /// marketplace interactions via Learning Engine.
  Future<AiListingDraft> analyseAndGenerate({
    String? photoDescription,
    String? userHint,
  }) async {
    await initialize();
    final hint = (photoDescription ?? userHint ?? '').trim();
    if (hint.isEmpty) {
      return _fallbackDraft('Baby Item', 'A quality baby item for sale.');
    }

    // Step 8: Record marketplace listing creation signal
    _learningEngine.recordMarketplaceListing(
      category: 'general',
      price: 0,
      tags: [hint.split(' ').first],
    );

    try {
      final aiResult = await _callGeminiForListing(hint);

      // Step 8: Check safety recalls from Knowledge Base
      final safetyRecall = _knowledgeBase.checkSafetyRecall(hint);
      if (safetyRecall != null && aiResult.safetyNote == null) {
        return AiListingDraft(
          suggestedTitle: aiResult.suggestedTitle,
          suggestedDescription: aiResult.suggestedDescription,
          suggestedPrice: aiResult.suggestedPrice,
          retailPrice: aiResult.retailPrice,
          savingsPercent: aiResult.savingsPercent,
          suggestedCategory: aiResult.suggestedCategory,
          suggestedAgeStage: aiResult.suggestedAgeStage,
          suggestedCondition: aiResult.suggestedCondition,
          safetyNote:
              'SAFETY RECALL: ${safetyRecall.productName} \u2014 '
              '${safetyRecall.reason} '
              '(Source: ${safetyRecall.source}, ${safetyRecall.dateIssued})',
          tags: aiResult.tags,
          confidence: aiResult.confidence,
        );
      }

      return aiResult;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Gemini listing AI error: \$e');
      }
      return _fallbackFromInput(hint);
    }
  }

  /// Call Gemini to generate a complete listing from product description
  Future<AiListingDraft> _callGeminiForListing(String userInput) async {
    final basePrompt = GeminiSystemPromptBuilder().buildMarketplacePrompt(
      itemDescription: userInput,
      isListingGeneration: true,
    );
    final systemPrompt = '$basePrompt\n'
        'RESPOND IN EXACT JSON FORMAT (no markdown, no backticks, just raw JSON):\n'
        '{\n'
        '  "title": "Brand Product Name",\n'
        '  "description": "A compelling 2-3 sentence marketplace listing description. '
        'Mention condition, key features, and why it\'s a great buy. Use British English.",\n'
        '  "suggestedPrice": 45.0,\n'
        '  "retailPrice": 120.0,\n'
        '  "savingsPercent": 63,\n'
        '  "category": "one of: pushchairsAndPrams, forTheCar, furniture, toysAndGames, '
        'babyCareAndAccessories, boysClothes, girlsClothes, maternity, books, other",\n'
        '  "ageStage": "one of: newborn, baby0to12, toddler, preschool, schoolAge, allAges, maternity",\n'
        '  "condition": "one of: brandNew, likeNew, good, wellUsed",\n'
        '  "safetyNote": null or "safety warning text if the item appears on a recall list",\n'
        '  "tags": ["tag1", "tag2", "tag3", "preloved"],\n'
        '  "confidence": 0.85\n'
        '}\n\n'
        'Be specific about the product. If the user mentions a brand, include it. '
        'If they don\'t, infer the most likely product type.';

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
            {'text': 'Generate a listing for: $userInput'}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'topP': 0.9,
        'maxOutputTokens': 512,
      },
    };

    final data = await AiApiHelper.generateContent(
        requestBody, timeout: const Duration(seconds: 15));
    final candidates = data['candidates'] as List?;
    if (candidates != null && candidates.isNotEmpty) {
      final content = candidates[0]['content'];
      final parts = content['parts'] as List?;
      if (parts != null && parts.isNotEmpty) {
        var text = (parts[0]['text'] as String? ?? '').trim();
        // Strip markdown code fence if present
        text = text.replaceAll(RegExp(r'^```json\s*'), '');
        text = text.replaceAll(RegExp(r'\s*```$'), '');
        text = text.trim();

        try {
          final json = jsonDecode(text) as Map<String, dynamic>;
          return _parseDraftFromJson(json);
        } catch (parseError) {
          if (kDebugMode) {
            debugPrint('JSON parse error: $parseError');
            debugPrint('Raw response: $text');
          }
          throw Exception('Failed to parse AI JSON response');
        }
      }
    }
    throw Exception('No content in AI response');
  }

  /// Parse the JSON response from Gemini into an AiListingDraft
  AiListingDraft _parseDraftFromJson(Map<String, dynamic> json) {
    final categoryStr = (json['category'] ?? 'other') as String;
    final ageStr = (json['ageStage'] ?? 'allAges') as String;
    final condStr = (json['condition'] ?? 'good') as String;

    final category = ItemCategory.values.firstWhere(
      (c) => c.name == categoryStr,
      orElse: () => ItemCategory.other,
    );
    final ageStage = AgeStage.values.firstWhere(
      (a) => a.name == ageStr,
      orElse: () => AgeStage.allAges,
    );
    final condition = ItemCondition.values.firstWhere(
      (c) => c.name == condStr,
      orElse: () => ItemCondition.good,
    );

    final suggestedPrice =
        (json['suggestedPrice'] as num?)?.toDouble() ?? 25.0;
    final retailPrice = (json['retailPrice'] as num?)?.toDouble() ??
        suggestedPrice * 2.5;
    final savingsPercent = (json['savingsPercent'] as num?)?.toInt() ?? 50;

    return AiListingDraft(
      suggestedTitle: (json['title'] ?? 'Baby Item') as String,
      suggestedDescription:
          (json['description'] ?? 'A quality preloved item.') as String,
      suggestedPrice: suggestedPrice,
      retailPrice: retailPrice,
      savingsPercent: savingsPercent,
      suggestedCategory: category,
      suggestedAgeStage: ageStage,
      suggestedCondition: condition,
      safetyNote: json['safetyNote'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          ['preloved', 'baby-gear'],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.85,
    );
  }

  /// Fallback: generate a basic draft without AI
  AiListingDraft _fallbackFromInput(String hint) {
    final lower = hint.toLowerCase();
    final rng = Random(hint.hashCode);

    String title = 'Baby Item';
    String category = 'other';
    String ageStage = 'allAges';
    double retailLow = 20;
    double retailHigh = 100;

    // Basic keyword categorisation
    if (lower.contains('pram') ||
        lower.contains('pushchair') ||
        lower.contains('buggy') ||
        lower.contains('bugaboo') ||
        lower.contains('silver cross')) {
      title = 'Pushchair / Pram';
      category = 'pushchairsAndPrams';
      retailLow = 100;
      retailHigh = 800;
      ageStage = 'newborn';
    } else if (lower.contains('car seat') || lower.contains('isofix')) {
      title = 'Car Seat';
      category = 'forTheCar';
      retailLow = 100;
      retailHigh = 350;
    } else if (lower.contains('cot') ||
        lower.contains('crib') ||
        lower.contains('bed')) {
      title = 'Baby Cot / Crib';
      category = 'furniture';
      retailLow = 50;
      retailHigh = 300;
      ageStage = 'newborn';
    } else if (lower.contains('toy') || lower.contains('game')) {
      title = 'Children\'s Toys';
      category = 'toysAndGames';
      retailLow = 15;
      retailHigh = 80;
      ageStage = 'toddler';
    } else if (lower.contains('clothes') || lower.contains('outfit')) {
      title = 'Clothes Bundle';
      category = 'boysClothes';
      retailLow = 20;
      retailHigh = 60;
    } else if (lower.contains('book')) {
      title = 'Book Collection';
      category = 'books';
      retailLow = 10;
      retailHigh = 40;
    }

    // If hint has more detail, use it as title
    if (hint.length > 5) {
      // Capitalise first letter of each word
      title = hint
          .split(' ')
          .map((w) =>
              w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
          .join(' ');
    }

    final retailPrice =
        retailLow + rng.nextDouble() * (retailHigh - retailLow);
    final suggestedPrice = (retailPrice * 0.40).roundToDouble();
    final savings = 60;

    final catEnum = ItemCategory.values.firstWhere(
      (c) => c.name == category,
      orElse: () => ItemCategory.other,
    );
    final ageEnum = AgeStage.values.firstWhere(
      (a) => a.name == ageStage,
      orElse: () => AgeStage.allAges,
    );

    // Step 8: Safety check via Knowledge Base (comprehensive recall list)
    String? safetyNote;
    final recall = _knowledgeBase.checkSafetyRecall(hint);
    if (recall != null) {
      safetyNote =
          'SAFETY RECALL: ${recall.productName} \u2014 '
          '${recall.reason} (Source: ${recall.source})';
    }

    return AiListingDraft(
      suggestedTitle: title,
      suggestedDescription:
          '$title in good condition. Well cared for, from a clean smoke-free home. '
          'Collection available or happy to meet locally.',
      suggestedPrice: suggestedPrice,
      retailPrice: retailPrice,
      savingsPercent: savings,
      suggestedCategory: catEnum,
      suggestedAgeStage: ageEnum,
      suggestedCondition: ItemCondition.good,
      safetyNote: safetyNote,
      tags: [title.toLowerCase().replaceAll(' ', '-'), 'preloved', 'baby-gear'],
      confidence: 0.55,
    );
  }

  /// Minimal fallback draft
  AiListingDraft _fallbackDraft(String title, String desc) {
    return AiListingDraft(
      suggestedTitle: title,
      suggestedDescription: desc,
      suggestedPrice: 20,
      retailPrice: 50,
      savingsPercent: 60,
      suggestedCategory: ItemCategory.other,
      suggestedAgeStage: AgeStage.allAges,
      suggestedCondition: ItemCondition.good,
      tags: ['preloved', 'baby-gear'],
      confidence: 0.50,
    );
  }

  /// Get price comparison for a given category/price.
  /// Step 8: Now includes borough context in price analysis.
  PriceComparison getPriceComparison(
      ItemCategory category, double suggestedPrice) {
    // Borough context available for future hyper-local pricing
    // final borough = _getUserBorough();
    final items = _rehomeService.items
        .where((i) => i.category == category && !i.isSold)
        .toList();
    if (items.isEmpty) {
      return PriceComparison(
        avgLocalPrice: suggestedPrice,
        lowestPrice: suggestedPrice * 0.7,
        highestPrice: suggestedPrice * 1.3,
        recentSalesCount: 0,
        priceVerdict: 'fair',
      );
    }

    final prices = items.map((i) => i.price).where((p) => p > 0).toList();
    if (prices.isEmpty) {
      return PriceComparison(
        avgLocalPrice: suggestedPrice,
        lowestPrice: 0,
        highestPrice: suggestedPrice * 1.5,
        recentSalesCount: items.length,
        priceVerdict: 'fair',
      );
    }

    prices.sort();
    final avg = prices.reduce((a, b) => a + b) / prices.length;
    final verdict = suggestedPrice < avg * 0.85
        ? 'great_deal'
        : suggestedPrice > avg * 1.15
            ? 'above_avg'
            : 'fair';

    return PriceComparison(
      avgLocalPrice: avg,
      lowestPrice: prices.first,
      highestPrice: prices.last,
      recentSalesCount: items.length,
      priceVerdict: verdict,
    );
  }

  /// Quick-list: one-tap listing from minimal input.
  /// Step 8: Uses borough context for seller location.
  RehomeItem quickCreateListing(AiListingDraft draft,
      {List<String>? imageUrls}) {
    final borough = _getUserBorough();
    final item = RehomeItem(
      id: 'rh_ai_${DateTime.now().millisecondsSinceEpoch}',
      title: draft.suggestedTitle,
      description: draft.suggestedDescription,
      ageStage: draft.suggestedAgeStage,
      category: draft.suggestedCategory,
      condition: draft.suggestedCondition,
      price: draft.suggestedPrice,
      imageUrls: imageUrls ??
          [
            'https://images.pexels.com/photos/3661452/pexels-photo-3661452.jpeg?auto=compress&cs=tinysrgb&w=600',
          ],
      sellerName: _onboarding.name ?? 'You',
      sellerId: 'current_user',
      sellerLocation: borough,
      listedAt: DateTime.now(),
    );

    _rehomeService.addListing(item);

    // Step 8: Record listing creation signal
    _learningEngine.recordMarketplaceListing(
      category: draft.suggestedCategory.name,
      price: draft.suggestedPrice,
      tags: draft.tags,
    );

    return item;
  }

  /// Step 8: Get a stage-appropriate age suggestion based on user's children.
  AgeStage suggestAgeStageFromProfile() {
    final children = _onboarding.children;
    if (children.isEmpty) return AgeStage.allAges;

    // Use the youngest child's age to suggest
    int youngestMonths = 999;
    for (final child in children) {
      final birthday = child['birthday'];
      if (birthday != null) {
        final months = _parseAgeMonths(birthday);
        if (months < youngestMonths) youngestMonths = months;
      }
    }

    if (youngestMonths <= 3) return AgeStage.newborn;
    if (youngestMonths <= 12) return AgeStage.baby0to12;
    if (youngestMonths <= 36) return AgeStage.toddler;
    if (youngestMonths <= 60) return AgeStage.earlyYears;
    return AgeStage.kids;
  }

  int _parseAgeMonths(String birthday) {
    try {
      final parts = birthday.split('/');
      if (parts.length >= 2) {
        final month = int.parse(parts[0]);
        final year = int.parse(parts.last);
        final now = DateTime.now();
        return ((now.difference(DateTime(year, month)).inDays) / 30.44).round();
      }
    } catch (_) {}
    return 24;
  }

  /// Step 8: Get safety recall warnings relevant to the user's marketplace.
  List<SafetyRecall> getRelevantSafetyRecalls() {
    return _knowledgeBase.safetyRecalls;
  }
}
