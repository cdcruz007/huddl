import 'dart:math';
import 'rehome_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AI LISTING GENERATOR SERVICE
// Generates listing titles, descriptions, smart pricing, and auto-categorisation
// from photo analysis (simulated) and minimal user input
// ═══════════════════════════════════════════════════════════════════════════════

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

  // ── Product recognition database (simulated AI vision) ─────────────
  static const _productDb = <String, Map<String, dynamic>>{
    'bugaboo': {
      'brand': 'Bugaboo',
      'products': ['Fox 3', 'Cameleon', 'Donkey 5', 'Butterfly', 'Dragonfly'],
      'category': 'pushchairsAndPrams',
      'retailRange': [499, 1599],
      'ageStage': 'newborn',
    },
    'silver cross': {
      'brand': 'Silver Cross',
      'products': ['Pioneer', 'Wave', 'Reef', 'Dune'],
      'category': 'pushchairsAndPrams',
      'retailRange': [350, 1200],
      'ageStage': 'newborn',
    },
    'ergobaby': {
      'brand': 'Ergobaby',
      'products': ['Embrace', 'Omni 360', 'Adapt'],
      'category': 'babyCareAndAccessories',
      'retailRange': [79, 189],
      'ageStage': 'newborn',
    },
    'stokke': {
      'brand': 'Stokke',
      'products': ['Tripp Trapp', 'Clikk', 'Steps'],
      'category': 'furniture',
      'retailRange': [199, 299],
      'ageStage': 'baby0to12',
    },
    'snuzpod': {
      'brand': 'Snuzpod',
      'products': ['4', '3', '2'],
      'category': 'furniture',
      'retailRange': [199, 299],
      'ageStage': 'newborn',
    },
    'maxi-cosi': {
      'brand': 'Maxi-Cosi',
      'products': ['Pebble 360', 'Pearl', 'Titan'],
      'category': 'forTheCar',
      'retailRange': [169, 399],
      'ageStage': 'allAges',
    },
    'lego duplo': {
      'brand': 'LEGO',
      'products': ['DUPLO Zoo', 'DUPLO Train', 'DUPLO Town'],
      'category': 'toysAndGames',
      'retailRange': [25, 89],
      'ageStage': 'toddler',
    },
    'tommee tippee': {
      'brand': 'Tommee Tippee',
      'products': ['Complete Feeding Set', 'Steriliser', 'Perfect Prep'],
      'category': 'babyCareAndAccessories',
      'retailRange': [39, 130],
      'ageStage': 'newborn',
    },
    'fisher-price': {
      'brand': 'Fisher-Price',
      'products': ['Jumperoo', 'Rainforest', 'Laugh & Learn'],
      'category': 'toysAndGames',
      'retailRange': [30, 120],
      'ageStage': 'baby0to12',
    },
    'joie': {
      'brand': 'Joie',
      'products': ['Spin 360', 'Every Stage', 'Stages'],
      'category': 'forTheCar',
      'retailRange': [150, 350],
      'ageStage': 'allAges',
    },
  };

  // ── Safety recall database ────────────────────────────────────────────
  static const _safetyRecalls = <String>[
    'Fisher-Price Rock \'n Play Sleeper',
    'Kids2 Rocking Sleeper',
    'Boppy Lounger',
  ];

  /// Simulate AI photo analysis and generate a listing draft
  AiListingDraft analyseAndGenerate({
    String? photoDescription,
    String? userHint,
  }) {
    final hint = (photoDescription ?? userHint ?? '').toLowerCase();
    final rng = Random(hint.hashCode);

    // Try to match a known product
    String? matchedBrand;
    Map<String, dynamic>? matchedProduct;

    for (final entry in _productDb.entries) {
      if (hint.contains(entry.key)) {
        matchedBrand = entry.key;
        matchedProduct = entry.value;
        break;
      }
    }

    // If no match, try keyword-based categorisation
    if (matchedProduct == null) {
      matchedProduct = _categoriseFromKeywords(hint);
    }

    final brand = (matchedProduct?['brand'] ?? 'Baby') as String;
    final products = (matchedProduct?['products'] as List<dynamic>?) ?? ['Item'];
    final product = products[rng.nextInt(products.length)] as String;
    final retailRange = (matchedProduct?['retailRange'] as List<dynamic>?) ?? [20, 100];
    final retailLow = (retailRange[0] as num).toDouble();
    final retailHigh = (retailRange[1] as num).toDouble();
    final retailPrice = retailLow + rng.nextDouble() * (retailHigh - retailLow);
    final categoryStr = (matchedProduct?['category'] ?? 'other') as String;
    final ageStr = (matchedProduct?['ageStage'] ?? 'allAges') as String;

    // Determine condition and price multiplier
    final conditionIndex = rng.nextInt(3); // 0=likeNew, 1=good, 2=wellUsed
    final condition = [ItemCondition.likeNew, ItemCondition.good, ItemCondition.wellUsed][conditionIndex];
    final priceMultiplier = [0.55, 0.40, 0.25][conditionIndex];
    final suggestedPrice = (retailPrice * priceMultiplier).roundToDouble();
    final savings = ((1 - priceMultiplier) * 100).round();

    // Generate description
    final title = '$brand $product';
    final description = _generateDescription(
      brand: brand,
      product: product,
      condition: condition,
      hint: hint,
    );

    // Safety check
    String? safetyNote;
    for (final recall in _safetyRecalls) {
      if (hint.contains(recall.toLowerCase())) {
        safetyNote = 'This item appears on a product recall list. Please check the manufacturer\'s website before selling.';
        break;
      }
    }

    final category = ItemCategory.values.firstWhere(
      (c) => c.name == categoryStr,
      orElse: () => ItemCategory.other,
    );
    final ageStage = AgeStage.values.firstWhere(
      (a) => a.name == ageStr,
      orElse: () => AgeStage.allAges,
    );

    return AiListingDraft(
      suggestedTitle: title,
      suggestedDescription: description,
      suggestedPrice: suggestedPrice,
      retailPrice: retailPrice,
      savingsPercent: savings,
      suggestedCategory: category,
      suggestedAgeStage: ageStage,
      suggestedCondition: condition,
      safetyNote: safetyNote,
      tags: _generateTags(brand, product, category, ageStage),
      confidence: matchedBrand != null ? 0.92 : 0.70,
    );
  }

  /// Get price comparison for a given category/price
  PriceComparison getPriceComparison(ItemCategory category, double suggestedPrice) {
    final items = _rehomeService.items.where((i) => i.category == category && !i.isSold).toList();
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
  RehomeItem quickCreateListing(AiListingDraft draft, {List<String>? imageUrls}) {
    final item = RehomeItem(
      id: 'rh_ai_${DateTime.now().millisecondsSinceEpoch}',
      title: draft.suggestedTitle,
      description: draft.suggestedDescription,
      ageStage: draft.suggestedAgeStage,
      category: draft.suggestedCategory,
      condition: draft.suggestedCondition,
      price: draft.suggestedPrice,
      imageUrls: imageUrls ?? [
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

  // ── Internal helpers ───────────────────────────────────────────────────
  Map<String, dynamic>? _categoriseFromKeywords(String hint) {
    if (hint.contains('clothes') || hint.contains('outfit') || hint.contains('dress')) {
      return {'brand': 'Baby', 'products': ['Clothes Bundle'], 'category': 'boysClothes', 'retailRange': [20, 60], 'ageStage': 'allAges'};
    }
    if (hint.contains('toy') || hint.contains('game') || hint.contains('play')) {
      return {'brand': 'Kids', 'products': ['Toy Set'], 'category': 'toysAndGames', 'retailRange': [15, 80], 'ageStage': 'toddler'};
    }
    if (hint.contains('book')) {
      return {'brand': 'Children\'s', 'products': ['Book Collection'], 'category': 'books', 'retailRange': [10, 40], 'ageStage': 'allAges'};
    }
    if (hint.contains('car seat') || hint.contains('isofix')) {
      return {'brand': 'Baby', 'products': ['Car Seat'], 'category': 'forTheCar', 'retailRange': [100, 300], 'ageStage': 'allAges'};
    }
    if (hint.contains('pram') || hint.contains('pushchair') || hint.contains('buggy') || hint.contains('stroller')) {
      return {'brand': 'Baby', 'products': ['Pushchair'], 'category': 'pushchairsAndPrams', 'retailRange': [100, 500], 'ageStage': 'newborn'};
    }
    if (hint.contains('cot') || hint.contains('crib') || hint.contains('bed') || hint.contains('chair')) {
      return {'brand': 'Baby', 'products': ['Furniture'], 'category': 'furniture', 'retailRange': [50, 200], 'ageStage': 'newborn'};
    }
    if (hint.contains('maternity') || hint.contains('pregnancy') || hint.contains('nursing')) {
      return {'brand': 'Maternity', 'products': ['Wear Bundle'], 'category': 'maternity', 'retailRange': [15, 60], 'ageStage': 'maternity'};
    }
    return null;
  }

  String _generateDescription({
    required String brand,
    required String product,
    required ItemCondition condition,
    required String hint,
  }) {
    final condText = switch (condition) {
      ItemCondition.brandNew => 'Brand new, never used.',
      ItemCondition.likeNew => 'Excellent condition \u2014 barely used. Looks and works like new.',
      ItemCondition.good => 'Good condition with normal signs of use. Well cared for.',
      ItemCondition.wellUsed => 'Well loved with visible wear, but still works perfectly.',
    };

    final extras = <String>[
      'Comes from a clean, smoke-free home.',
      'All original parts included.',
    ];

    if (brand.contains('Bugaboo') || brand.contains('Silver Cross') || brand.contains('Stokke')) {
      extras.add('Premium brand \u2014 built to last. RRP much higher than asking price.');
    }
    if (hint.contains('baby') || hint.contains('newborn')) {
      extras.add('Perfect for newborns and young babies.');
    }

    return '$brand $product. $condText ${extras.join(' ')} Collection available or happy to meet locally.';
  }

  List<String> _generateTags(String brand, String product, ItemCategory category, AgeStage ageStage) {
    return [
      brand.toLowerCase(),
      product.toLowerCase().replaceAll(' ', '-'),
      category.label.toLowerCase(),
      ageStage.shortLabel.toLowerCase(),
      'preloved',
      'baby-gear',
    ];
  }
}
