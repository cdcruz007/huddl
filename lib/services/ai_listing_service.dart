import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import 'gemini_system_prompt_builder.dart';
import 'rehome_service.dart';

// =============================================================================
// AI LISTING GENERATOR SERVICE  — HYPERLOCAL EDITION
// Uses Gemini AI for genuine product analysis, description generation,
// smart pricing, and auto-categorisation from user input
// System prompt now assembled by GeminiSystemPromptBuilder (Step 3)
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

class AiListingService {
  static final AiListingService _instance = AiListingService._internal();
  factory AiListingService() => _instance;
  AiListingService._internal();

  final RehomeService _rehomeService = RehomeService();

  // Gemini API configuration (centralised in GeminiConfig)

  // Safety recall database (real safety data)
  static const _safetyRecalls = <String>[
    'Fisher-Price Rock \'n Play Sleeper',
    'Kids2 Rocking Sleeper',
    'Boppy Lounger',
  ];

  /// Use Gemini AI to analyse a product description and generate a listing
  Future<AiListingDraft> analyseAndGenerate({
    String? photoDescription,
    String? userHint,
  }) async {
    final hint = (photoDescription ?? userHint ?? '').trim();
    if (hint.isEmpty) {
      return _fallbackDraft('Baby Item', 'A quality baby item for sale.');
    }

    try {
      final aiResult = await _callGeminiForListing(hint);
      return aiResult;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Gemini listing AI error: $e');
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

    final url = Uri.parse(
        GeminiConfig.generateContentUrl);

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
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
            throw Exception('Failed to parse Gemini JSON response');
          }
        }
      }
      throw Exception('No content in Gemini response');
    } else {
      throw Exception('Gemini API error: ${response.statusCode}');
    }
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

    // Safety check
    String? safetyNote;
    for (final recall in _safetyRecalls) {
      if (lower.contains(recall.toLowerCase())) {
        safetyNote =
            'This item appears on a product recall list. Check the manufacturer\'s website before selling.';
        break;
      }
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

  /// Get price comparison for a given category/price
  PriceComparison getPriceComparison(
      ItemCategory category, double suggestedPrice) {
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

  /// Quick-list: one-tap listing from minimal input
  RehomeItem quickCreateListing(AiListingDraft draft,
      {List<String>? imageUrls}) {
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
      sellerName: 'You',
      sellerId: 'current_user',
      sellerLocation: 'Your area',
      listedAt: DateTime.now(),
    );

    _rehomeService.addListing(item);
    return item;
  }
}
