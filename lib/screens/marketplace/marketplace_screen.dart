import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // removed — provided by material.dart
import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';
import '../../widgets/animations/huddl_spring_animations.dart';
import '../../widgets/cards/huddl_photo_card.dart';
import '../../widgets/common/huddl_network_image.dart';
import '../../widgets/huddl_widgets.dart';
import '../../widgets/common/huddl_button.dart';
import '../../widgets/common/huddl_card.dart';
import '../../constants/app_text_styles.dart';
import '../../services/rehome_service.dart';
import '../../services/firestore_service.dart';
import '../../services/huddl_notification_service.dart';
import '../../services/backend_api_service.dart';
import 'item_detail_screen.dart';
import '../rehome/create_listing_screen.dart';
import '../../services/borough_scope_guard.dart';
import '../../services/subscription_service.dart';
import '../../models/subscription.dart';
import '../../widgets/borough_badge.dart';
import '../../widgets/huddl_character.dart';
import '../../widgets/animations/huddl_loading_states.dart';
import '../search/unified_search_screen.dart';
import '../ai/ai_listing_generator_sheet.dart';



// 12 deterministic Unsplash face URLs for seller avatar stack
const List<String> _kMarketAvatarPool = [
  'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=48&q=70',
  'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=48&q=70',
  'https://images.unsplash.com/photo-1527980965255-d3b416303d12?w=48&q=70',
  'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=48&q=70',
  'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=48&q=70',
  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=48&q=70',
  'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=48&q=70',
  'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=48&q=70',
  'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=48&q=70',
  'https://images.unsplash.com/photo-1520813792240-56fc4a3765a7?w=48&q=70',
  'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=48&q=70',
  'https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=48&q=70',
];


// =============================================================================
// INVISIBLE AI ENGINE — learns silently, surfaces results naturally
// No badges, no score displays, no ON/OFF toggles.
// The AI works behind the scenes: ranking, pre-filling, and adapting.
// =============================================================================
class _InvisibleAiEngine {
  // ── Silent Behavioral Tracking ──
  final Map<String, int> _categoryViews = {};
  final Map<String, int> _ageViews = {};
  final Set<String> _viewedItemIds = {};
  final Set<String> _likedCategories = {};
  final Set<String> _dislikedCategories = {};
  final Map<String, int> _searchHistory = {};
  final List<String> _recentSearches = [];
  final Map<String, int> _sellerViews = {};
  int _totalViews = 0;

  // ── Contextual Intelligence ──

  ItemCategory? _inferredPreferredCategory;
  AgeStage? _inferredPreferredAge;

  void recordView(RehomeItem item) {
    _viewedItemIds.add(item.id);
    _totalViews++;
    _categoryViews[item.category.label] =
        (_categoryViews[item.category.label] ?? 0) + 1;
    _ageViews[item.ageStage.label] =
        (_ageViews[item.ageStage.label] ?? 0) + 1;
    _sellerViews[item.sellerId] =
        (_sellerViews[item.sellerId] ?? 0) + 1;
    _inferPreferences();
  }

  void recordSearch(String query) {
    if (query.isEmpty) return;
    _searchHistory[query.toLowerCase()] =
        (_searchHistory[query.toLowerCase()] ?? 0) + 1;
    _recentSearches.remove(query);
    _recentSearches.insert(0, query);
    if (_recentSearches.length > 10) _recentSearches.removeLast();

  }

  void recordSave(RehomeItem item) {
    _likedCategories.add(item.category.label);
    _dislikedCategories.remove(item.category.label);
    _inferPreferences();
  }

  void recordUnsave(RehomeItem item) {
    // Lighter signal -- don't immediately dislike
  }

  void recordDismiss(RehomeItem item) {
    // Long-press "not interested" — stronger negative signal
    _dislikedCategories.add(item.category.label);
    _likedCategories.remove(item.category.label);
  }

  void _inferPreferences() {
    // Infer preferred category from top-viewed
    if (_categoryViews.isNotEmpty) {
      final sorted = _categoryViews.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topLabel = sorted.first.key;
      _inferredPreferredCategory = ItemCategory.values
          .where((c) => c.label == topLabel)
          .firstOrNull;
    }
    // Infer preferred age stage
    if (_ageViews.isNotEmpty) {
      final sorted = _ageViews.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topLabel = sorted.first.key;
      _inferredPreferredAge = AgeStage.values
          .where((a) => a.label == topLabel)
          .firstOrNull;
    }
  }

  // ── Invisible Ranking — items just "feel right" ──
  int _matchScore(RehomeItem item) {
    int score = 50;
    final catViews = _categoryViews[item.category.label] ?? 0;
    final ageViews = _ageViews[item.ageStage.label] ?? 0;
    score += (catViews * 8).clamp(0, 25);
    score += (ageViews * 6).clamp(0, 15);
    if (_likedCategories.contains(item.category.label)) score += 15;
    if (_dislikedCategories.contains(item.category.label)) score -= 25;
    if (item.condition == ItemCondition.brandNew ||
        item.condition == ItemCondition.likeNew) {
      score += 5;
    }
    if (item.isFree) score += 3;
    // Freshness bonus — newer items rank slightly higher
    final age = DateTime.now().difference(item.listedAt).inHours;
    if (age < 24) {
      score += 8;
    } else if (age < 72) {
      score += 4;
    }
    return score.clamp(0, 100);
  }

  List<RehomeItem> rankItems(List<RehomeItem> items) {
    final ranked = List<RehomeItem>.from(items);
    ranked.sort((a, b) => _matchScore(b).compareTo(_matchScore(a)));
    return ranked;
  }

  // ── Contextual Search Suggestions (no AI branding) ──
  List<String> searchSuggestions(String query) {
    final suggestions = <String>[];

    // Recent searches first (user's own history)
    for (final s in _recentSearches) {
      if (query.isEmpty ||
          s.toLowerCase().contains(query.toLowerCase())) {
        if (!suggestions.contains(s)) suggestions.add(s);
      }
      if (suggestions.length >= 4) break;
    }

    // Inferred from browsing behavior
    final topCategories = _categoryViews.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in topCategories.take(2)) {
      if (!suggestions.contains(entry.key)) {
        if (query.isEmpty ||
            entry.key.toLowerCase().contains(query.toLowerCase())) {
          suggestions.add(entry.key);
        }
      }
      if (suggestions.length >= 6) break;
    }

    // Fill with popular defaults
    const defaults = ['Pushchair', 'Baby clothes', 'Toys', 'Car seat',
        'Books', 'Cot', 'Highchair'];
    for (final d in defaults) {
      if (query.isEmpty ||
          d.toLowerCase().contains(query.toLowerCase())) {
        if (!suggestions.contains(d)) suggestions.add(d);
      }
      if (suggestions.length >= 6) break;
    }

    return suggestions;
  }

  // ── Predictive Offer Amount ──
  double? suggestOfferPrice(RehomeItem item) {
    if (item.isFree || item.price <= 0) return null;
    // Suggest 80-90% of asking price based on condition
    final factor = switch (item.condition) {
      ItemCondition.brandNew => 0.92,
      ItemCondition.likeNew => 0.88,
      ItemCondition.good => 0.82,
      ItemCondition.wellUsed => 0.75,
    };
    return (item.price * factor).roundToDouble();
  }

  // ── Adaptive Filter Suggestions ──
  // Returns a filter preset based on user behavior, or null if not enough data
  ({AgeStage? age, ItemCategory? category})? suggestFilters() {
    if (_totalViews < 5) return null;
    return (
      age: _inferredPreferredAge,
      category: _inferredPreferredCategory,
    );
  }

  // ── Smart Search Placeholder ──
  String smartPlaceholder() {
    if (_inferredPreferredCategory != null && _totalViews > 3) {
      return 'Search ${_inferredPreferredCategory!.label.toLowerCase()}...';
    }
    if (_inferredPreferredAge != null && _totalViews > 3) {
      return 'Search for ${_inferredPreferredAge!.shortLabel.toLowerCase()}...';
    }
    return 'Search market items...';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SELL-TAB INVISIBLE AI — automates seller tasks, reduces manual buttons
  //
  // Strategy: predictive pre-filling, contextual intelligence, auto task flow
  // - Tracks seller patterns → pre-fills category/age/price on next listing
  // - Listing health scoring → AI nudges only when actionable
  // - Adaptive ordering → items needing attention surface first
  // - Predictive pricing → suggests competitive price from market data
  // - Auto-relist detection → silently suggests re-listing stale sold items
  // - Feedback loops → learn from accept/decline/dismiss signals
  // - Adaptive interface → reorder sections based on usage patterns
  // ═══════════════════════════════════════════════════════════════════════════

  // Track seller listing patterns for predictive pre-filling
  final Map<String, int> _listedCategories = {};
  final Map<String, int> _listedAges = {};
  final Map<String, double> _listedPrices = {};
  int _totalListings = 0;
  int _totalSold = 0;
  int _totalAccepts = 0;
  int _totalDeclines = 0;
  int _totalEarnings = 0; // pence

  // ── Feedback loop tracking ──
  final Map<String, bool> _insightFeedback = {}; // insightId → helpful?

  void recordInsightFeedback(String itemId, bool helpful) {
    _insightFeedback[itemId] = helpful;
  }

  bool? getInsightFeedback(String itemId) => _insightFeedback[itemId];

  void recordListing(RehomeItem item) {
    _totalListings++;
    _listedCategories[item.category.label] =
        (_listedCategories[item.category.label] ?? 0) + 1;
    _listedAges[item.ageStage.label] =
        (_listedAges[item.ageStage.label] ?? 0) + 1;
    if (item.price > 0) {
      _listedPrices[item.category.label] = item.price;
    }
  }

  void recordSold(RehomeItem item) {
    _totalSold++;
    _totalEarnings += (item.price * 100).round();
  }

  void recordOfferAccept() => _totalAccepts++;
  void recordOfferDecline() => _totalDeclines++;

  // Contextual sell prompt — adapts message based on seller experience level
  // and time-of-day contextual intelligence
  String sellPrompt() {
    final hour = DateTime.now().hour;
    if (_totalListings == 0) {
      return 'Snap a photo to create your first listing';
    }
    if (_totalSold > 0 && _totalListings < 5) {
      return 'You\u2019ve sold $_totalSold item${_totalSold > 1 ? 's' : ''} \u2014 keep going!';
    }
    // Contextual: evening prompts are softer
    if (hour >= 20 || hour < 7) {
      return 'Quick list before bed \u2014 one tap';
    }
    return 'Your next listing is one photo away';
  }

  // Contextual sell subtitle — persona-aware encouragement
  String sellSubtitle() {
    if (_totalListings == 0) {
      return 'We\'ll auto-fill the title, price & description for you';
    }
    final predictedCat = predictNextCategory();
    if (predictedCat != null) {
      return 'Pre-fills ${predictedCat.label.toLowerCase()} from your history';
    }
    return 'Auto-fills from your previous listings';
  }

  // ── Seller Performance Summary (adaptive interface) ──
  // Returns null when no stats to show (new seller), keeping it minimal.
  ({int listed, int sold, String earnings})? sellerStats() {
    if (_totalListings == 0 && _totalSold == 0) return null;
    return (
      listed: _totalListings,
      sold: _totalSold,
      earnings: '\u00A3${(_totalEarnings / 100).toStringAsFixed(0)}',
    );
  }

  // ── Listing Health Scoring (0-100) ──
  // Higher = needs more attention. Used for ranking and nudge priority.
  int listingHealthScore(RehomeItem item) {
    if (item.isSold) return 0;
    int score = 0;
    final days = DateTime.now().difference(item.listedAt).inDays;
    // Stale penalty
    if (days > 14) {
      score += 40;
    } else if (days > 7) {
      score += 20;
    }
    // Low-view penalty
    if (item.viewCount < 5 && days > 3) score += 25;
    // No-offer penalty
    if (item.offerCount == 0 && days > 5) score += 20;
    // Pending offers = needs action
    if (item.offerCount > 0) score += 30;
    return score.clamp(0, 100);
  }

  // ── Health category for visual indicators ──
  String listingHealthCategory(RehomeItem item) {
    final score = listingHealthScore(item);
    if (score >= 50) return 'urgent';
    if (score >= 20) return 'attention';
    return 'healthy';
  }

  // Smart listing insight — returns contextual AI nudge text + icon hint
  // Returns null when no action needed (clean, no clutter).
  ({String text, String type})? listingInsight(RehomeItem item) {
    // Check if user dismissed this insight
    if (_insightFeedback[item.id] == false) return null;

    if (item.isSold) {
      final daysSinceSold = DateTime.now().difference(item.listedAt).inDays;
      if (daysSinceSold > 30) {
        return (text: 'Relist similar items \u2014 demand is up', type: 'relist');
      }
      return null;
    }
    final days = DateTime.now().difference(item.listedAt).inDays;
    if (item.offerCount > 0) {
      return (
        text: '${item.offerCount} offer${item.offerCount > 1 ? 's' : ''} waiting',
        type: 'offers',
      );
    }
    if (days > 14 && item.offerCount == 0) {
      final suggested = suggestSellerPrice(item);
      if (suggested != null && suggested < item.price) {
        return (
          text: 'Try \u00A3${suggested.toStringAsFixed(0)} \u2014 similar items sold at this price',
          type: 'price',
        );
      }
      return (text: 'No offers in ${days}d \u2014 try a lower price', type: 'price');
    }
    if (days > 7 && item.viewCount < 5) {
      return (text: 'Low visibility \u2014 adding photos may help', type: 'photos');
    }
    if (days > 3 && item.viewCount > 20 && item.offerCount == 0) {
      return (text: 'Lots of views but no offers \u2014 review your price', type: 'price');
    }
    return null;
  }

  // ── Predictive Pricing for Sellers ──
  double? suggestSellerPrice(RehomeItem item) {
    if (item.price <= 0) return null;
    final factor = switch (item.condition) {
      ItemCondition.brandNew => 1.0,
      ItemCondition.likeNew => 0.85,
      ItemCondition.good => 0.70,
      ItemCondition.wellUsed => 0.50,
    };
    final historicPrice = _listedPrices[item.category.label];
    if (historicPrice != null) {
      return (historicPrice * factor).roundToDouble();
    }
    return (item.price * 0.85).roundToDouble();
  }

  // Rank seller's own listings — AI-driven, items needing attention first
  List<RehomeItem> rankMyListings(List<RehomeItem> items) {
    final ranked = List<RehomeItem>.from(items);
    ranked.sort((a, b) {
      final scoreA = listingHealthScore(a);
      final scoreB = listingHealthScore(b);
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      if (!a.isSold && b.isSold) return -1;
      if (a.isSold && !b.isSold) return 1;
      return b.listedAt.compareTo(a.listedAt);
    });
    return ranked;
  }

  // Should we show the offers section first? (contextual intelligence)
  bool offersNeedAttention(List<RehomeOffer> offers) {
    return offers.length >= 2;
  }

  // ── Auto-Relist Suggestion ──
  bool shouldSuggestRelist(RehomeItem soldItem) {
    if (!soldItem.isSold) return false;
    final catSearches = _searchHistory.entries
        .where((e) => e.key.contains(soldItem.category.label.toLowerCase()))
        .fold<int>(0, (sum, e) => sum + e.value);
    return catSearches >= 2;
  }

  // ── Predictive Category/Age for new listing ──
  ItemCategory? predictNextCategory() {
    if (_listedCategories.isEmpty) return null;
    final sorted = _listedCategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ItemCategory.values
        .where((c) => c.label == sorted.first.key)
        .firstOrNull;
  }

  AgeStage? predictNextAgeStage() {
    if (_listedAges.isEmpty) return null;
    final sorted = _listedAges.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return AgeStage.values
        .where((a) => a.label == sorted.first.key)
        .firstOrNull;
  }

  // ── Offer Context Summary ──
  String offerSummary(RehomeOffer offer, RehomeItem? item) {
    if (item == null) return '';
    final pct = item.price > 0
        ? ((offer.amount / item.price) * 100).round()
        : 100;
    if (pct >= 90) return 'Strong offer \u2014 $pct% of asking price';
    if (pct >= 75) return 'Fair offer \u2014 $pct% of asking price';
    return 'Low offer \u2014 $pct% of asking price';
  }

  // ── Offer Sentiment for visual coding ──
  String offerSentiment(RehomeOffer offer, RehomeItem? item) {
    if (item == null) return 'neutral';
    final pct = item.price > 0
        ? ((offer.amount / item.price) * 100).round()
        : 100;
    if (pct >= 90) return 'strong';
    if (pct >= 75) return 'fair';
    return 'low';
  }

  // ── Quick sell suggestions (adaptive interface) ──
  // Based on what sells best in the community
  List<String> quickSellSuggestions() {
    final suggestions = <String>[];
    // Top categories from buyer interest
    final topCategories = _categoryViews.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in topCategories.take(3)) {
      suggestions.add(entry.key);
    }
    if (suggestions.isEmpty) {
      suggestions.addAll(['Clothes', 'Toys', 'Pushchairs']);
    }
    return suggestions;
  }
}


// =============================================================================
// REHOME MARKETPLACE SCREEN — "Less is More" with Invisible AI
//
// Philosophy:
// - No AI badges, score displays, or ON/OFF toggles
// - AI silently ranks, suggests, and adapts
// - Progressive disclosure: sparkle icon → AI assistant bottom sheet
// - Contextual intelligence: search hints adapt to behavior
// - Automated: AI classifies, tags, and pre-fills behind the scenes
// =============================================================================

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _service = RehomeService();
  final _ai = _InvisibleAiEngine();

  // Filters
  AgeStage? _selectedAge;
  Set<ItemCategory> _selectedCategories = {}; // multi-select (filter sheet)
  ItemCategory? _selectedCategory; // single-select from category rail (null = All)
  PriceType? _selectedPriceType;
  ItemCondition? _selectedCondition;
  String _searchQuery = '';
  int _sortIndex = 0; // 0=Most relevant, 1=Newest, 2=Price asc, 3=Price desc
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  // UI state
  bool _isLoadingItems = false;
  bool _isSearchActive = false;
  bool _isGridView = true; // grid is the default — Pinterest/Vinted/Depop standard

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Defer service listener registration to avoid setState-during-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _service.addListener(_onServiceChange);
      // Load real listings from Firestore on first open
      _loadListingsFromFirestore();
    });

  }

  /// Load all active marketplace listings from Firestore and populate the
  /// in-memory RehomeService so they survive screen rebuilds.
  /// Also restores the current user's saved-item state and seller offers.
  Future<void> _loadListingsFromFirestore() async {
    if (_isLoadingItems) return;
    setState(() => _isLoadingItems = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      // ── 1a. All active listings (Buy tab) ─────────────────────────────────
      final docs = await FirestoreService().getMarketplaceListings();
      for (final d in docs) {
        final item = RehomeItem.fromFirestore(d);
        if (item.id.isEmpty) continue;
        if (_service.allItems.any((i) => i.id == item.id)) continue;
        _service.addListing(item);
        if (uid != null && item.sellerId == uid) {
          _service.addMyListing(item);
        }
      }

      // ── 1b. Own listings — ALL statuses (active + sold) for Sell tab ────────
      // getMyListings() queries sellerId == uid with no status filter, so the
      // user's sold history shows up in the Sell tab regardless of how old it is.
      if (uid != null) {
        try {
          final myDocs = await FirestoreService().getMyListings();
          for (final d in myDocs) {
            final item = RehomeItem.fromFirestore(d);
            if (item.id.isEmpty) continue;
            // Add to global list if not already there
            if (!_service.allItems.any((i) => i.id == item.id)) {
              _service.addListing(item);
            }
            // Always register as own listing (avoids duplicates internally)
            if (!_service.myListings.any((i) => i.id == item.id)) {
              _service.addMyListing(item);
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Marketplace] getMyListings error: $e');
        }
      }

      // ── 2. Saved / favourites — restore heart state cross-device ──────────
      if (uid != null) {
        try {
          final savedIds = await FirestoreService().loadMySavedListingIds();
          for (final id in savedIds) {
            // Use setSaved (no Firestore write-back) to avoid ping-pong
            _service.setSaved(id, saved: true);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Marketplace] loadSaved error: $e');
        }
      }

      // ── 3. Seller offers — load pending offers for this user's listings ───
      if (uid != null) {
        try {
          final offerMaps = await FirestoreService().getOffersForMyListings();
          for (final m in offerMaps) {
            final offerId = m['id'] as String? ?? '';
            if (offerId.isEmpty) continue;
            // Avoid duplicates
            if (_service.offers.any((o) => o.id == offerId)) continue;
            final offer = RehomeOffer(
              id: offerId,
              itemId: m['itemId'] as String? ?? '',
              itemTitle: m['itemTitle'] as String? ?? '',
              buyerName: m['buyerName'] as String? ?? '',
              buyerId: m['buyerId'] as String? ?? '',
              amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
              createdAt: m['createdAt'] != null
                  ? DateTime.tryParse(m['createdAt'].toString()) ??
                      DateTime.now()
                  : DateTime.now(),
              status: m['status'] as String? ?? 'pending',
              responseMessage: m['responseMessage'] as String?,
            );
            // Silently insert without triggering another Firestore write
            _service.loadOffer(offer);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Marketplace] loadOffers error: $e');
        }
      }

      // ── 4. Prefetch saved-by cache for seller's own listings ─────────────
      // Ensures savedByUserIds() has fresh data when markSold / relistItem
      // fire notifications during this session.
      if (uid != null) {
        final myListingIds = _service.myListings.map((i) => i.id).toList();
        for (final listingId in myListingIds) {
          _service.prefetchSavedByUserIds(listingId);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Marketplace] loadFromFirestore error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingItems = false);
    }
  }

  void _onServiceChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _service.removeListener(_onServiceChange);
    _tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    // Dismiss search bar when the user switches tabs.
    if (_isSearchActive) {
      _searchController.clear();
      _searchFocus.unfocus();
      _isSearchActive = false;
      _searchQuery = '';
    }
    setState(() {});
  }

  List<RehomeItem> get _filteredItems {
    var raw = _service.filter(
      ageStage: _selectedAge,
      categories: _selectedCategories.isEmpty ? null : _selectedCategories,
      condition: _selectedCondition,
      priceType: _selectedPriceType,
      query: _searchQuery,
    );

    // ── Category rail filter (single-select, layered on top of sheet filters) ─
    if (_selectedCategory != null) {
      raw = raw.where((i) => i.category == _selectedCategory).toList();
    }

    // AI ranks first; sort modal then overrides order
    final aiRanked = _ai.rankItems(raw);

    switch (_sortIndex) {
      case 1: // Newest first — by listedAt desc
        final sorted = List<RehomeItem>.from(aiRanked)
          ..sort((a, b) => b.listedAt.compareTo(a.listedAt));
        return sorted;
      case 2: // Price low → high (free items first, then ascending)
        final sorted = List<RehomeItem>.from(aiRanked)
          ..sort((a, b) => a.price.compareTo(b.price));
        return sorted;
      case 3: // Price high → low (descending; free items at end)
        final sorted = List<RehomeItem>.from(aiRanked)
          ..sort((a, b) => b.price.compareTo(a.price));
        return sorted;
      case 0: // Most relevant — AI ranking (default)
      default:
        return aiRanked;
    }
  }

  bool get _hasActiveFilters =>
      _selectedAge != null ||
      _selectedCategories.isNotEmpty ||
      _selectedPriceType != null ||
      _selectedCondition != null;

  void _clearAllFilters() {
    HuddlAnimations.lightTap();
    setState(() {
      _selectedAge = null;
      _selectedCategories = {};
      _selectedPriceType = null;
      _selectedCondition = null;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  int get _activeFilterCount {
    int n = 0;
    if (_selectedAge != null) n++;
    n += _selectedCategories.length;
    if (_selectedPriceType != null) n++;
    if (_selectedCondition != null) n++;
    return n;
  }

  /// Short label shown inside the filter pill when exactly one filter is active.
  String get _activeFilterLabel {
    if (_selectedAge != null) return _selectedAge!.shortLabel;
    if (_selectedCategories.length == 1) return _selectedCategories.first.label;
    if (_selectedCategories.length > 1) return '${_selectedCategories.length} categories';
    if (_selectedPriceType == PriceType.free) return 'Free';
    if (_selectedPriceType == PriceType.paid) return 'Paid';
    if (_selectedCondition != null) return _selectedCondition!.label;
    return 'Filter';
  }

  void _showAllFiltersSheet(HuddlContextColors hc) {
    HuddlAnimations.selectionClick();

    AgeStage? sheetAge = _selectedAge;
    Set<ItemCategory> sheetCats = Set<ItemCategory>.from(_selectedCategories);
    PriceType? sheetPrice = _selectedPriceType;
    ItemCondition? sheetCond = _selectedCondition;
    RangeValues sheetPriceRange = const RangeValues(0, 500);
    int sheetSortIndex = _sortIndex;
    const sortOptions = [
      ('Most relevant',     Icons.auto_awesome_outlined),
      ('Newest first',      Icons.schedule_outlined),
      ('Price: low → high', Icons.south_outlined),
      ('Price: high → low', Icons.north_outlined),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final shc = ctx.hc;
          final hasAny = sheetAge != null ||
              sheetCats.isNotEmpty ||
              sheetPrice != null ||
              sheetCond != null ||
              sheetSortIndex != 0;

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.80,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollController) => SafeArea(
              child: Column(
                children: [
                  // ── Fixed header ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Handle
                        Center(
                          child: Container(
                            width: 36, height: 4,
                            decoration: BoxDecoration(
                              color: HuddlColors.divider,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text('Filter and sort',
                              style: HuddlText.heading(color: shc.textPrimary)),
                            const Spacer(),
                            if (hasAny)
                              GestureDetector(
                                onTap: () {
                                  setSheetState(() {
                                    sheetAge = null; sheetCats = {};
                                    sheetPrice = null; sheetCond = null;
                                    sheetSortIndex = 0;
                                  });
                                  setState(() {
                                    _selectedAge = null; _selectedCategories = {};
                                    _selectedPriceType = null; _selectedCondition = null;
                                    _sortIndex = 0;
                                  });
                                },
                                child: Text('Clear all',
                                  style: HuddlText.body(color: shc.textSecondary).copyWith(decoration: TextDecoration.underline)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),

                  // ── Scrollable sections ───────────────────────────────
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      children: [
                        // ══ SECTION: Recommended quick-filters ══════════
                        // Icon tiles row (key amenities/attributes)
                        Text('Recommended for you',
                          style: HuddlText.body(weight: FontWeight.w600, color: shc.textSecondary)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            // Tile: Like New
                            Expanded(child: _FilterIconTile(
                              icon: Icons.star_outline_rounded,
                              label: 'Like New',
                              isSelected: sheetCond == ItemCondition.likeNew,
                              onTap: () {
                                HuddlAnimations.selectionClick();
                                final next = sheetCond == ItemCondition.likeNew
                                    ? null : ItemCondition.likeNew;
                                setSheetState(() => sheetCond = next);
                                setState(() => _selectedCondition = next);
                              },
                            )),
                            const SizedBox(width: 10),
                            // Tile: Brand New
                            Expanded(child: _FilterIconTile(
                              icon: Icons.auto_awesome_rounded,
                              label: 'Brand New',
                              isSelected: sheetCond == ItemCondition.brandNew,
                              onTap: () {
                                HuddlAnimations.selectionClick();
                                final next = sheetCond == ItemCondition.brandNew
                                    ? null : ItemCondition.brandNew;
                                setSheetState(() => sheetCond = next);
                                setState(() => _selectedCondition = next);
                              },
                            )),
                            const SizedBox(width: 10),
                            // Tile: Free
                            Expanded(child: _FilterIconTile(
                              icon: Icons.volunteer_activism_outlined,
                              label: 'Free items',
                              isSelected: sheetPrice == PriceType.free,
                              onTap: () {
                                HuddlAnimations.selectionClick();
                                final next = sheetPrice == PriceType.free
                                    ? null : PriceType.free;
                                setSheetState(() => sheetPrice = next);
                                setState(() => _selectedPriceType = next);
                              },
                            )),
                          ],
                        ),
                        const SizedBox(height: 28),

                        // ══ SECTION: Price type (segmented control) ══════
                        Text('Type',
                          style: HuddlText.body(weight: FontWeight.w600, color: shc.textSecondary)),
                        const SizedBox(height: 10),
                        _SegmentedPriceControl(
                          selected: sheetPrice,
                          onChanged: (val) {
                            HuddlAnimations.selectionClick();
                            setSheetState(() => sheetPrice = val);
                            setState(() => _selectedPriceType = val);
                          },
                        ),
                        const SizedBox(height: 28),

                        // ══ SECTION: Condition ═══════════════════════════
                        Text('Condition',
                          style: HuddlText.body(weight: FontWeight.w600, color: shc.textSecondary)),
                        const SizedBox(height: 8),
                        _FilterChip(
                          label: 'Any',
                          isSelected: sheetCond == null,
                          onTap: () {
                            HuddlAnimations.selectionClick();
                            setSheetState(() => sheetCond = null);
                            setState(() => _selectedCondition = null);
                          },
                        ),
                        ...ItemCondition.values.map((cond) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _FilterChip(
                            label: cond.label,
                            isSelected: sheetCond == cond,
                            onTap: () {
                              HuddlAnimations.selectionClick();
                              final next = sheetCond == cond ? null : cond;
                              setSheetState(() => sheetCond = next);
                              setState(() => _selectedCondition = next);
                            },
                          ),
                        )),
                        const SizedBox(height: 28),

                        // ══ SECTION: Age group ═══════════════════════════
                        Text('Age group',
                          style: HuddlText.body(weight: FontWeight.w600, color: shc.textSecondary)),
                        const SizedBox(height: 8),
                        _FilterChip(
                          label: 'Any age',
                          isSelected: sheetAge == null,
                          onTap: () {
                            HuddlAnimations.selectionClick();
                            setSheetState(() => sheetAge = null);
                            setState(() => _selectedAge = null);
                          },
                        ),
                        ...AgeStage.values.map((age) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _FilterChip(
                            label: age.shortLabel,
                            isSelected: sheetAge == age,
                            onTap: () {
                              HuddlAnimations.selectionClick();
                              final next = sheetAge == age ? null : age;
                              setSheetState(() => sheetAge = next);
                              setState(() => _selectedAge = next);
                            },
                          ),
                        )),
                        const SizedBox(height: 28),

                        // ══ SECTION: Price range histogram slider ═════════
                        Row(
                          children: [
                            Text('Price range',
                              style: HuddlText.body(weight: FontWeight.w600, color: shc.textSecondary)),
                            const Spacer(),
                            Text(
                              sheetPriceRange.start == 0 && sheetPriceRange.end >= 500
                                  ? 'Any price'
                                  : '£${sheetPriceRange.start.toInt()} – £${sheetPriceRange.end >= 500 ? "500+" : sheetPriceRange.end.toInt().toString()}',
                              style: HuddlText.caption(color: shc.textTertiary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Listing price, excluding delivery',
                          style: HuddlText.caption(color: shc.textTertiary)),
                        const SizedBox(height: 10),
                        // Histogram bars
                        _PriceHistogram(
                          low: sheetPriceRange.start,
                          high: sheetPriceRange.end,
                          maxPrice: 500,
                        ),
                        // Range slider — orange active track
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: HuddlColors.primary,    // warm orange
                            inactiveTrackColor: HuddlColors.divider,
                            thumbColor: Colors.white,
                            overlayColor: HuddlColors.primary.withValues(alpha: 0.15),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 12,
                              elevation: 3,
                            ),
                            rangeThumbShape: const RoundRangeSliderThumbShape(
                              enabledThumbRadius: 12,
                              elevation: 3,
                            ),
                            trackHeight: 3,
                          ),
                          child: RangeSlider(
                            values: sheetPriceRange,
                            min: 0,
                            max: 500,
                            divisions: 50,
                            onChanged: (vals) {
                              setSheetState(() => sheetPriceRange = vals);
                            },
                          ),
                        ),
                        const SizedBox(height: 4),

                        // ══ SECTION: Sort by ════════════════════════════
                        Text('Sort by',
                          style: HuddlText.body(weight: FontWeight.w600, color: shc.textSecondary)),
                        const SizedBox(height: 10),
                        ...sortOptions.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final (label, icon) = entry.value;
                          final isSelected = sheetSortIndex == idx;
                          return GestureDetector(
                            onTap: () {
                              HuddlAnimations.selectionClick();
                              setSheetState(() => sheetSortIndex = idx);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              color: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(icon,
                                    size: 20,
                                    color: isSelected
                                        ? HuddlColors.primary
                                        : shc.textTertiary),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(label,
                                      style: HuddlText.body()),
                                  ),
                                  Container(
                                    width: 22, height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? HuddlColors.primary
                                            : HuddlColors.divider,
                                        width: isSelected ? 5.5 : 1.5,
                                      ),
                                      color: isSelected
                                          ? HuddlColors.primary
                                          : Colors.transparent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 28),

                        // ══ SECTION: Category (multi-select) ════════════
                        Row(
                          children: [
                            Text('Category',
                              style: HuddlText.body(weight: FontWeight.w600, color: shc.textSecondary)),
                            const Spacer(),
                            if (sheetCats.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  HuddlAnimations.selectionClick();
                                  setSheetState(() => sheetCats = {});
                                  setState(() => _selectedCategories = {});
                                },
                                child: Text('Clear',
                                  style: HuddlText.caption(color: HuddlColors.primary).copyWith(decoration: TextDecoration.underline)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // "All categories" deselect row
                        _MultiSelectChip(
                          label: 'All categories',
                          isSelected: sheetCats.isEmpty,
                          onTap: () {
                            HuddlAnimations.selectionClick();
                            setSheetState(() => sheetCats = {});
                            setState(() => _selectedCategories = {});
                          },
                        ),
                        ...ItemCategory.values.map((cat) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _MultiSelectChip(
                            label: cat.label,
                            isSelected: sheetCats.contains(cat),
                            onTap: () {
                              HuddlAnimations.selectionClick();
                              setSheetState(() {
                                if (sheetCats.contains(cat)) {
                                  sheetCats = Set.from(sheetCats)..remove(cat);
                                } else {
                                  sheetCats = Set.from(sheetCats)..add(cat);
                                }
                              });
                              setState(() =>
                                  _selectedCategories = Set.from(sheetCats));
                            },
                          ),
                        )),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),

                  // ── Orange "Show items" CTA ────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: HuddlButton(
                      label: 'Show items',
                      onPressed: () {
                        HuddlAnimations.mediumTap();
                        setState(() => _sortIndex = sheetSortIndex);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openCreateListing() async {
    HuddlAnimations.mediumTap();

    // Show the "getting things ready" overlay while the listing
    // screen initialises.  We capture the overlay's navigator context so we
    // can dismiss it precisely after the push resolves.
    if (!mounted) return;
    bool overlayShowing = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (_) => const HuddlProcessLoadingOverlay(
        message: 'Setting up your listing',
        submessage: 'Just a moment…',
      ),
    ).then((_) => overlayShowing = false);

    // Brief artificial delay so the overlay is visible for at least one frame
    // before the page route transition starts — avoids a flash of the overlay
    // appearing and immediately disappearing on fast devices.
    await Future.delayed(const Duration(milliseconds: 300));

    // Push the create-listing screen.
    final result = await Navigator.push<RehomeItem>(
      context,
      HuddlSpringPageRoute(page: const CreateListingScreen()),
    );

    // Dismiss the overlay if it is still displayed.
    if (mounted && overlayShowing) {
      Navigator.of(context).pop();
    }

    if (result != null && mounted) {
      _tabController.animateTo(1);
    }
  }

  void _openItemDetail(RehomeItem item) {
    _ai.recordView(item);
    Navigator.push(
      context,
      HuddlSpringPageRoute(page: ItemDetailScreen(item: item)),
    );
  }

  void _openEditListing(RehomeItem item) async {
    final result = await Navigator.push<RehomeItem>(
      context,
      HuddlSpringPageRoute(
        page: CreateListingScreen(existingItem: item),
      ),
    );
    if (result != null && mounted) {
      setState(() {});
    }
  }

  void _confirmDelistItem(RehomeItem item) {
    showDialog(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: hc.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: HuddlColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline,
                      size: 28, color: HuddlColors.error),
                ),
                const SizedBox(height: 16),
                Text(
                  'Delist this item?',
                  style: HuddlText.heading(color: hc.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to delist "${item.title}"? This will remove it from the marketplace.',
                  textAlign: TextAlign.center,
                  style: HuddlText.body(color: hc.textSecondary).copyWith(height: 1.5),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'Cancel delisting',
                        button: true,
                        child: HuddlButton(
                          label: 'Cancel',
                          variant: HuddlButtonVariant.secondary,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        label: 'Confirm delist ${item.title}',
                        button: true,
                        child: HuddlButton(
                          label: 'Delist',
                          variant: HuddlButtonVariant.destructive,
                          onPressed: () {
                            HuddlAnimations.mediumTap();
                            Navigator.pop(ctx);
                            _service.deleteListing(item.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('"${item.title}" has been delisted')),
                                  ],
                                ),
                                backgroundColor: HuddlColors.textDark,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // AI assistant removed — AI works invisibly behind the scenes.

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Scaffold(
      backgroundColor: hc.scaffold,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Main content column ──
            Column(
              children: [
                _buildHeader(hc),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBuyTab(hc),
                      _buildSellTab(hc),
                      _buildSavedTab(hc),
                    ],
                  ),
                ),
              ],
            ),
            // ── FAB — visible on Buy and Sell tabs ────────────────────────
            if (_tabController.index == 0 || _tabController.index == 1)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 64 + 12 + 16,
                right: 20,
                child: GestureDetector(
                  onTap: _openCreateListing,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: HuddlColors.primary,      // warm orange FAB
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: HuddlColors.primary.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // == HEADER ================================================================
  // Clean header: title + subtle sparkle entry point (progressive disclosure)
  // No gradient AI button, no prominent branding

  Widget _buildHeader(HuddlContextColors hc) {
    return Container(
      color: hc.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row — Market + borough scope chip (matches Groups/Discover) + search icon
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _isSearchActive
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text('Market', style: HuddlText.display()),
                ),
                const SizedBox(width: 8),
                // Borough scope chip
                const BoroughScopeChip(feature: HuddlFeature.marketplace),
                const Spacer(),
                // Grid/list toggle — immediately left of search icon
                ScaleOnPress(
                  scale: 0.88,
                  onTap: () {
                    HuddlAnimations.lightTap();
                    setState(() => _isGridView = !_isGridView);
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _isGridView ? Icons.view_list_outlined : Icons.grid_view_outlined,
                      key: ValueKey(_isGridView),
                      size: 22,
                      color: hc.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Search icon — top-right.
                // Tap → inline market search. Long-press → unified search.
                Semantics(
                  label: 'Search market items',
                  button: true,
                  child: Tooltip(
                    message: 'Search · Hold for universal search',
                    child: GestureDetector(
                      onTap: () {
                        HuddlAnimations.lightTap();
                        setState(() => _isSearchActive = true);
                        Future.microtask(() => _searchFocus.requestFocus());
                      },
                      onLongPress: () {
                        HuddlAnimations.mediumTap();
                        Navigator.of(context).push(HuddlSpringPageRoute(
                          page: const UnifiedSearchScreen(),
                        ));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.search,
                          color: hc.textSecondary,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Expanded search bar — replaces title row when active
            secondChild: SizedBox(
              height: 36,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: hc.inputBg,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(Icons.search, size: 16,
                              color: hc.textTertiary.withValues(alpha: 0.7)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocus,
                              autofocus: false,
                              onChanged: (val) {
                                _ai.recordSearch(val);
                                setState(() => _searchQuery = val);
                              },
                              onSubmitted: (_) => _searchFocus.unfocus(),
                              style: HuddlText.caption(color: hc.textPrimary),
                              decoration: InputDecoration(
                                hintText: _ai.smartPlaceholder(),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isDense: true,
                                hintStyle: HuddlText.caption(color: hc.textTertiary),
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.close, size: 15,
                                    color: hc.textTertiary),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _isSearchActive = false;
                      });
                      _searchFocus.unfocus();
                    },
                    child: Text(
                      'Cancel',
                      style: HuddlText.body(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── Standard orange-underline tab bar — matches all other screens ─
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Buy'),
              Tab(text: 'Sell'),
              Tab(text: 'Saved'),
            ],
            labelColor: HuddlColors.primary,
            unselectedLabelColor: HuddlColors.textHint,
            labelStyle: HuddlText.caption(weight: FontWeight.w600),
            unselectedLabelStyle: HuddlText.caption(),
            indicatorColor: HuddlColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 2.5,
            dividerColor: HuddlColors.divider,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  // == FILTER BOTTOM SHEETS ==================================================
  // Individual filter sheets are accessed via _showAllFiltersSheet (combined).

  // == CATEGORY RAIL =========================================================

  Widget _buildCategoryRail(HuddlContextColors hc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Only show categories that have at least one active (non-sold) listing
    final activeCats = ItemCategory.values.where((cat) =>
      _service.allItems.any((item) => item.category == cat && !item.isSold)
    ).toList();

    if (activeCats.isEmpty) return const SizedBox.shrink();

    final chipBg       = isDark ? HuddlColors.darkSurfaceVariant : const Color(0xFFF5F2EE);
    final chipBorder   = isDark ? HuddlColors.darkDivider : const Color(0xFFE5E5E5);
    final selectedBg   = isDark ? HuddlColors.darkTextPrimary : HuddlColors.nearBlack;
    final selectedText = isDark ? HuddlColors.darkBackground : Colors.white;

    return Container(
      color: hc.surface,
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: activeCats.length + 1, // +1 for "All" chip
        itemBuilder: (context, index) {
          if (index == 0) {
            // "All" chip — always first
            final isSelected = _selectedCategory == null;
            return ScaleOnPress(
              scale: 0.93,
              onTap: () {
                HuddlAnimations.lightTap();
                setState(() => _selectedCategory = null);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? selectedBg : chipBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isSelected ? selectedBg : chipBorder,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  'All',
                  style: HuddlText.body(
                    color: isSelected ? selectedText : hc.textPrimary,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }

          final cat = activeCats[index - 1];
          final isSelected = _selectedCategory == cat;
          final count = _service.allItems
              .where((i) => i.category == cat && !i.isSold)
              .length;

          return ScaleOnPress(
            scale: 0.93,
            onTap: () {
              HuddlAnimations.lightTap();
              setState(() => _selectedCategory = isSelected ? null : cat);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? selectedBg : chipBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected ? selectedBg : chipBorder,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(cat.icon, size: 14,
                    color: isSelected ? selectedText : hc.textPrimary),
                  const SizedBox(width: 5),
                  Text(
                    cat.label,
                    style: HuddlText.body(
                      color: isSelected ? selectedText : hc.textPrimary,
                      weight: FontWeight.w600,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 5),
                    Text(
                      '$count',
                      style: HuddlText.caption(
                        color: isSelected
                            ? selectedText.withValues(alpha: 0.7)
                            : hc.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // == JUST IN STRIP ==========================================================

  Widget _buildJustInStrip(HuddlContextColors hc) {
    final now = DateTime.now();
    final fresh = _service.allItems
        .where((i) =>
          !i.isSold &&
          now.difference(i.listedAt).inHours < 6 &&
          (_selectedCategory == null || i.category == _selectedCategory))
        .take(6)
        .toList();

    if (fresh.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: HuddlColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Just in',
                style: HuddlText.body(
                  color: hc.textPrimary,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${fresh.length} new listing${fresh.length == 1 ? '' : 's'}',
                style: HuddlText.caption(color: hc.textTertiary),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemCount: fresh.length,
            itemBuilder: (context, i) {
              final item = fresh[i];
              final hasImage = item.imageUrls.isNotEmpty;
              return ScaleOnPress(
                scale: 0.97,
                onTap: () => _openItemDetail(item),
                child: Container(
                  width: 140,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: hc.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hc.divider, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Image ───────────────────────────────────────
                      SizedBox(
                        height: 130,
                        width: double.infinity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            hasImage
                                ? Image.network(
                                    item.imageUrls.first,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (_, child, progress) =>
                                      progress == null
                                          ? child
                                          : Container(color: hc.inputBg),
                                    errorBuilder: (_, __, ___) =>
                                      _MarketPhotoFallback(item: item),
                                  )
                                : _MarketPhotoFallback(item: item),
                            // "NEW" badge
                            Positioned(
                              top: 8, left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: HuddlColors.nearBlack,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('NEW',
                                  style: HuddlText.label(color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ── Body ────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: HuddlText.body(
                                color: hc.textPrimary,
                                weight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.isFree ? 'Free' : '£${item.price.toStringAsFixed(0)}',
                              style: HuddlText.caption(
                                color: hc.textPrimary,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Divider(height: 1, thickness: 0.5, color: hc.divider),
      ],
    );
  }

  // == BUY TAB — clean, uncluttered ==========================================
  // No AI badges, no thumbs up/down, no smart ranking toggle.
  // AI works silently: ranking results, adapting search placeholder.

  Widget _buildBuyTab(HuddlContextColors hc) {
    final items = _filteredItems;

    final bool hasActiveSortOrFilter = _hasActiveFilters || _sortIndex != 0;
    final String pillLabel = _hasActiveFilters && _activeFilterCount > 1
        ? 'Filter and sort · $_activeFilterCount'
        : _hasActiveFilters
            ? 'Filter and sort · $_activeFilterLabel'
            : _sortIndex != 0
                ? 'Filter and sort · sorted'
                : 'Filter and sort';

    return Column(
      children: [
        // ── Unified "Filter and sort" pill row ────────────────────────
        Container(
          color: hc.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Semantics(
                label: hasActiveSortOrFilter
                    ? 'Active filters. Tap to change.'
                    : 'Filter and sort items',
                button: true,
                child: GestureDetector(
                  onTap: () {
                    HuddlAnimations.lightTap();
                    _showAllFiltersSheet(hc);
                  },
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: hc.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: hc.divider, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: hasActiveSortOrFilter
                                  ? HuddlColors.primary
                                  : hc.textPrimary,
                            ),
                            if (hasActiveSortOrFilter)
                              Positioned(
                                top: -3,
                                right: -3,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: HuddlColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          pillLabel,
                          style: HuddlText.body(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Semantics(
                liveRegion: true,
                child: Text(
                  '${items.length} item${items.length == 1 ? '' : 's'}${_hasActiveFilters ? ' · filtered' : ''}',
                  style: HuddlText.caption(color: hc.textTertiary),
                ),
              ),
            ],
          ),
        ),
        // ── Category rail ─────────────────────────────────────────────
        _buildCategoryRail(hc),
        Divider(height: 1, thickness: 0.5, color: hc.divider),

        // ── Main content area ─────────────────────────────────────────
        Expanded(
          child: items.isEmpty
              ? (_hasActiveFilters || _searchQuery.isNotEmpty || _selectedCategory != null
                  ? HuddlEmptyState(
                      mood: HuddlMood.curious,
                      title: 'No items found',
                      subtitle: 'Try adjusting your filters to see more results.',
                      ctaLabel: 'Clear filters',
                      onCtaTap: () {
                        _clearAllFilters();
                        setState(() {
                          _searchQuery = '';
                          _selectedCategory = null;
                        });
                        _searchController.clear();
                      },
                    )
                  : const HuddlEmptyState(
                      mood: HuddlMood.celebrating,
                      illustrationAsset: 'assets/illustrations/mobile_store.webp',
                      title: 'Nothing listed yet',
                      subtitle: 'Be the first to list something — Cambridge parents love a good find.',
                    ))
              : _isSearchActive
                  // ── Compact search rows (search active) ──────────────
                  ? ListView.separated(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: 92,
                        endIndent: 0,
                        color: context.hc.divider,
                      ),
                      itemBuilder: (context, index) {
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        final isOwn = uid != null && items[index].sellerId == uid;
                        return _MarketSearchRow(
                          item: items[index],
                          isOwn: isOwn,
                          onTap: () => _openItemDetail(items[index]),
                          onToggleSave: () {
                            HuddlAnimations.lightTap();
                            final item = items[index];
                            if (!item.isSaved) {
                              _ai.recordSave(item);
                            } else {
                              _ai.recordUnsave(item);
                            }
                            _service.toggleSaved(item.id);
                          },
                        );
                      },
                    )
                  // ── Grid or list with Just-In strip ──────────────────
                  : CustomScrollView(
                      slivers: [
                        // ── Just In strip ─────────────────────────────
                        SliverToBoxAdapter(child: _buildJustInStrip(hc)),

                        // ── Grid or list ──────────────────────────────
                        if (_isGridView)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 100),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.68,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final uid = FirebaseAuth.instance.currentUser?.uid;
                                  final item = items[index];
                                  return HuddlSpringMount(
                                    delay: Duration(milliseconds: (index * 30).clamp(0, 300)),
                                    child: _MarketGridBuyCard(
                                      item: item,
                                      isOwn: uid != null && item.sellerId == uid,
                                      onTap: () => _openItemDetail(item),
                                      onToggleSave: () {
                                        HuddlAnimations.lightTap();
                                        if (!item.isSaved) {
                                          _ai.recordSave(item);
                                        } else {
                                          _ai.recordUnsave(item);
                                        }
                                        _service.toggleSaved(item.id);
                                      },
                                    ),
                                  );
                                },
                                childCount: items.length,
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final item = items[index];
                                  return _MarketItemCard(
                                    item: item,
                                    onTap: () => _openItemDetail(item),
                                    onToggleSave: () {
                                      HuddlAnimations.lightTap();
                                      if (!item.isSaved) {
                                        _ai.recordSave(item);
                                      } else {
                                        _ai.recordUnsave(item);
                                      }
                                      _service.toggleSaved(item.id);
                                    },
                                  );
                                },
                                childCount: items.length,
                              ),
                            ),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }

  // == SELL TAB — Invisible AI: "Less is More" v2 =============================
  //
  // Redesign philosophy — radical minimalism with Invisible AI:
  //
  // 1. ONE clear CTA: the entire prompt card IS the button.
  //    AI pre-fills category/age/price from seller history. Zero learning curve.
  //
  // 2. Listings: NO visible action buttons. Swipe-left to delete (Dismissible).
  //    Long-press → bottom sheet (progressive disclosure).
  //    The tile shows ONLY: image, title, price, subtle AI insight, status dot.
  //
  // 3. Offers: AI-summarised context ("Strong offer — 91% of asking").
  //    Swipe-right to accept, swipe-left to decline. Undo via SnackBar.
  //    Feedback loop: thumbs up/down on AI summary.
  //
  // 4. Section ordering adapts: offers surface first when >= 2 pending.
  //
  // 5. Sold items auto-collapse after 48h (adaptive interface).
  //
  // 6. Seller stats — unobtrusive performance summary (adaptive, hidden until
  //    the seller has data).
  //
  // 7. Quick sell suggestions — AI-driven trending categories.
  //
  // 8. Transparency: subtle footer note about personalisation.
  //
  // 9. Voice command & AI assistant accessible via sparkle icon.
  // ==========================================================================

  Widget _buildSellTab(HuddlContextColors hc) {
    final myListings = _ai.rankMyListings(_service.myListings);
    final offers = _service.pendingOffers;
    final offersFirst = _ai.offersNeedAttention(offers);

    // Separate active vs sold vs expired — show full sold history, no time filter
    // Archive any expired listings (updates isExpiredFlag in-place)
    _service.archiveExpiredListings();
    final expired = myListings.where((i) => i.isExpiredFlag && !i.isSold).toList();
    final active = myListings.where((i) => !i.isSold && !i.isExpiredFlag).toList();
    final sold = myListings.where((i) => i.isSold).toList();
    // Sort sold: most recently sold first
    sold.sort((a, b) => b.listedAt.compareTo(a.listedAt));
    final recentlySold = sold; // Show all sold, not just last 48h

    // ── Search-active: flat filtered compact list ─────────────────────────
    if (_isSearchActive) {
      final q = _searchQuery.toLowerCase().trim();
      final filtered = myListings.where((item) {
        if (q.isEmpty) return true;
        return item.title.toLowerCase().contains(q) ||
            item.category.label.toLowerCase().contains(q) ||
            item.sellerLocation.toLowerCase().contains(q);
      }).toList();

      return Column(
        children: [
          // Count row
          Container(
            color: hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filtered.length} listing${filtered.length == 1 ? '' : 's'}${q.isNotEmpty ? ' matching "$_searchQuery"' : ''}',
                style: HuddlText.caption(color: hc.textTertiary),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const HuddlEmptyState(
                    mood: HuddlMood.curious,
                    title: 'No listings found',
                    subtitle: 'Try a different search term.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 92,
                      endIndent: 0,
                      color: hc.divider,
                    ),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _MarketSearchRow(
                        item: item,
                        isOwn: true,
                        onTap: () => _openItemDetail(item),
                        onToggleSave: () {},
                      );
                    },
                  ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: HuddlColors.textTertiary,
      onRefresh: () async {
        HuddlAnimations.mediumTap();
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          // ── Listing slot counter (free users only) ──────────────────────
          Builder(builder: (context) {
            final ss = SubscriptionService();
            if (TierLimits.isUnlimited(ss.limits.maxListingsCreatedLifetime)) {
              return const SizedBox.shrink();
            }
            final used = ss.listingsCreatedTotal;
            final max = ss.limits.maxListingsCreatedLifetime;
            final remaining = ss.listingsCreatedRemaining;
            return GestureDetector(
              onTap: remaining == 0
                  ? () => Navigator.pushNamed(context, '/subscription_plans')
                  : null,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: remaining == 0
                      ? HuddlColors.primary.withValues(alpha: 0.08)
                      : hc.inputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: remaining == 0
                      ? Border.all(color: HuddlColors.primary.withValues(alpha: 0.20))
                      : null,
                ),
                child: Row(children: [
                  Icon(Icons.storefront_outlined,
                      size: 15,
                      color: remaining == 0
                          ? HuddlColors.primary
                          : hc.textTertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      remaining == 0
                          ? 'All $max free listing slots used — upgrade for unlimited'
                          : '$used of $max free listing slots used · 7-day duration',
                      style: HuddlText.caption(
                        color: remaining == 0
                            ? HuddlColors.primary
                            : hc.textTertiary,
                      ),
                    ),
                  ),
                  if (remaining == 0)
                    Text('Upgrade →',
                        style: HuddlText.caption(
                            color: HuddlColors.primary)),
                ]),
              ),
            );
          }),

          // ── Single-tap listing prompt — AI adapts the copy ──
          _buildSellCTA(hc),

          // ── Adaptive section ordering ──
          if (offersFirst && offers.isNotEmpty) ...[
            _buildOffersSection(hc, offers),
            if (active.isNotEmpty) _buildListingsSection(hc, active, 'Active listings'),
            if (expired.isNotEmpty) _buildExpiredSection(hc, expired),
            if (recentlySold.isNotEmpty) _buildSoldSection(hc, recentlySold),
          ] else ...[
            if (active.isNotEmpty) _buildListingsSection(hc, active, 'My listings'),
            if (expired.isNotEmpty) _buildExpiredSection(hc, expired),
            if (offers.isNotEmpty) _buildOffersSection(hc, offers),
            if (recentlySold.isNotEmpty) _buildSoldSection(hc, recentlySold),
          ],

          // ── Empty state ──
          // liveRegion: screen readers announce when seller's listings become empty
          if (active.isEmpty && expired.isEmpty && offers.isEmpty && sold.isEmpty)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: HuddlEmptyState(
                  mood: HuddlMood.celebrating,
                  illustrationAsset: 'assets/illustrations/sending.webp',
                  title: 'No listings yet',
                  subtitle: 'Tap the + button to snap a photo and list your first item.',
                ),
              ),
            ),

          // ── AI transparency note (subtle, non-intrusive) ──
          if (active.isNotEmpty || offers.isNotEmpty || sold.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Center(
                child: Text(
                  'Listings are ordered by what needs your attention first.',
                  style: HuddlText.caption(color: hc.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }


  // ── Expired listings section ─────────────────────────────────────────────
  Widget _buildExpiredSection(HuddlContextColors hc, List<RehomeItem> expired) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Expired listings',
            style: HuddlText.label(color: hc.textTertiary)),
        const SizedBox(height: 8),
        ...expired.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: HuddlColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title,
                  style: HuddlText.body(
                    weight: FontWeight.w600,
                    color: hc.textTertiary,
                  ).copyWith(decoration: TextDecoration.lineThrough)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.schedule_outlined,
                    size: 14, color: HuddlColors.textTertiary),
                const SizedBox(width: 4),
                Text('Listing expired after ${SubscriptionService().limits.listingDurationDays} days',
                    style: HuddlText.caption(color: HuddlColors.textTertiary)),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _relistExpiredItem(item),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: Text(
                    SubscriptionService().listingsCreatedRemaining > 0
                        ? 'Relist — ${SubscriptionService().listingsCreatedRemaining} '
                          'slot${SubscriptionService().listingsCreatedRemaining == 1 ? "" : "s"} remaining'
                        : 'Upgrade to relist',
                    style: HuddlText.body(
                        weight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Future<void> _relistExpiredItem(RehomeItem item) async {
    final ss = SubscriptionService();
    await ss.initialize();

    if (!ss.canCreateListing) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/subscription_gate', arguments: {
        'featureTitle': 'Free listing limit reached',
        'featureDescription':
            'Relisting uses one of your 3 free listing slots. '
            'Upgrade to Huddl Plus for unlimited listings with 60-day duration.',
        'requiredPlan': 'Huddl Plus',
        'featureIcon': Icons.storefront_outlined.codePoint,
      });
      return;
    }

    final remaining = ss.listingsCreatedRemaining;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Relist this item?',
            style: HuddlText.body(weight: FontWeight.w600)),
        content: Text(
          'Relisting uses 1 of your $remaining free listing '
          '${remaining == 1 ? "slot" : "slots"}. '
          'After relisting you will have ${remaining - 1} '
          '${remaining - 1 == 1 ? "slot" : "slots"} remaining.',
          style: HuddlText.body(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: HuddlText.body(color: ctx.hc.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Relist',
                style: HuddlText.body(
                    color: HuddlColors.primary,
                    weight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await ss.recordListingCreated();
    final newExpiry = TierLimits.isUnlimited(ss.limits.listingDurationDays)
        ? null
        : DateTime.now().add(Duration(days: ss.listingDurationDays));
    _service.relistItem(item.id, newExpiry: newExpiry);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${item.title} relisted.',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: HuddlColors.primary,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ── Sell CTA — compact single-row prompt, AI-adapted copy ──
  Widget _buildSellCTA(HuddlContextColors hc) {
    final ss = SubscriptionService();
    final maxListings = ss.limits.maxMarketplaceListings;
    final usedListings = ss.marketplaceListings;
    final isCapped = !TierLimits.isUnlimited(maxListings);

    return Semantics(
      label: 'Create a new listing',
      hint: 'Opens listing form. We\'ll fill in the details from your photo.',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _openCreateListing,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(14),
              border: hc.cardBorder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: hc.inputBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.camera_alt_rounded,
                          color: HuddlColors.primary, size: 18), // orange icon
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _ai.sellPrompt(),
                        style: HuddlText.body(color: hc.textPrimary, weight: FontWeight.w500),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 13, color: hc.textTertiary),
                  ],
                ),
                // AI Write secondary action row — tier-aware: free locked, Plus counted, Partner unlimited
                const SizedBox(height: 10),
                Builder(builder: (bCtx) {
                  final ss        = SubscriptionService();
                  final hasAccess = ss.hasAiListingGenerator;
                  final canUse    = ss.canUseAiListingGenerator;
                  final remaining = ss.aiListingGenerationsRemaining;
                  final isFinite  = !TierLimits.isUnlimited(
                      ss.limits.maxAiListingGenerationsPerMonth);
                  // Count badge when 3 or fewer remain and limit is finite
                  final showCount = hasAccess && isFinite && remaining <= 3;

                  return GestureDetector(
                    onTap: () {
                      if (!hasAccess) {
                        Navigator.pushNamed(context, '/subscription_gate',
                            arguments: {
                              'featureTitle': 'AI Listing Writer',
                              'featureDescription':
                                  'Describe your item and AI writes the perfect '
                                  'listing title, description, and price in seconds.',
                              'requiredPlan': 'Huddl Plus',
                              'featureIcon':
                                  Icons.auto_awesome_outlined.codePoint,
                            });
                        return;
                      }
                      if (!canUse) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                            'You\'ve used your '
                            '${ss.limits.maxAiListingGenerationsPerMonth} AI listing '
                            'generations this month. Resets on your billing date.',
                            style: HuddlText.body(color: Colors.white),
                          ),
                          backgroundColor: HuddlColors.nearBlack,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ));
                        return;
                      }
                      _openAiListingGenerator();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: !hasAccess
                            ? HuddlColors.primary.withValues(alpha: 0.12)
                            : !canUse
                                ? HuddlColors.gray100
                                : HuddlColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 16,
                            color: (!hasAccess || !canUse)
                                ? HuddlColors.primary
                                : Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            !canUse && hasAccess ? 'Limit reached' : 'AI Write',
                            style: HuddlText.caption(
                              weight: FontWeight.w600,
                              color: (!hasAccess || !canUse)
                                  ? HuddlColors.primary
                                  : Colors.white,
                            ),
                          ),
                          // Free users: Plus upgrade badge
                          if (!hasAccess) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: HuddlColors.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Plus',
                                style: HuddlText.caption(
                                  weight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                          // Plus users near monthly limit: count badge
                          if (hasAccess && showCount) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: !canUse
                                    ? HuddlColors.error
                                    : Colors.white.withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                !canUse ? '0 left' : '$remaining left',
                                style: HuddlText.caption(
                                  weight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
                // P12: listing usage indicator for capped tiers
                if (isCapped) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 48), // align under text
                      Text(
                        '$usedListings / $maxListings listings used',
                        style: HuddlText.caption(color: HuddlColors.textTertiary),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: (usedListings / maxListings).clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor: HuddlColors.divider,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              usedListings >= maxListings
                                  ? Colors.red.shade400
                                  : HuddlColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openAiListingGenerator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AiListingGeneratorSheet(),
    );
  }

  // ── Listings section — swipeable tiles with AI insights ──
  Widget _buildListingsSection(HuddlContextColors hc, List<RehomeItem> listings, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text(
                  title,
                  style: HuddlText.body(color: hc.textPrimary, weight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Text(
                  '${listings.length}',
                  style: HuddlText.caption(color: hc.textTertiary),
                ),
            ],
          ),
        ),
        ),
        ...listings.map((item) => _SellListingTile(
              key: ValueKey('listing_${item.id}'),
              item: item,
              insight: _ai.listingInsight(item),
              healthCategory: _ai.listingHealthCategory(item),
              onTap: () => _openItemDetail(item),
              onLongPress: () => _showListingActions(item, hc),
              onDismissed: () {
                HuddlAnimations.mediumTap();
                _confirmDelistItem(item);
              },
              onInsightFeedback: (helpful) {
                _ai.recordInsightFeedback(item.id, helpful);
                setState(() {});
              },
            )),
      ],
    );
  }

  // ── Sold items section (auto-collapsed, subtle) ──
  Widget _buildSoldSection(HuddlContextColors hc, List<RehomeItem> soldItems) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Sold history',
            style: HuddlText.caption(color: hc.textTertiary, weight: FontWeight.w500),
          ),
        ),
        ...soldItems.map((item) => _SellListingTile(
              key: ValueKey('sold_${item.id}'),
              item: item,
              insight: _ai.listingInsight(item),
              healthCategory: 'healthy',
              onTap: () => _openItemDetail(item),
              onLongPress: () => _showListingActions(item, hc),
              isSold: true,
            )),
      ],
    );
  }

  // ── Offers section — swipeable tiles with AI context ──
  Widget _buildOffersSection(HuddlContextColors hc, List<RehomeOffer> offers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text(
                  'Offers',
                  style: HuddlText.body(color: hc.textPrimary, weight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: HuddlColors.textHint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${offers.length}',
                    style: HuddlText.caption(color: HuddlColors.textSecondary, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        ...offers.map((offer) {
          final item = _service.getItemById(offer.itemId);
          return _SmartOfferTile(
            key: ValueKey('offer_${offer.id}'),
            offer: offer,
            aiSummary: _ai.offerSummary(offer, item),
            sentiment: _ai.offerSentiment(offer, item),
            onAccept: () => _showOfferResponseSheet(offer, hc, isAccept: true),
            onDecline: () => _showOfferResponseSheet(offer, hc, isAccept: false),
          );
        }),
      ],
    );
  }

  // ── Offer response sheet: accept or decline with optional message ─────────
  void _showOfferResponseSheet(
    RehomeOffer offer,
    HuddlContextColors hc, {
    required bool isAccept,
  }) {
    HuddlAnimations.mediumTap();
    final msgController = TextEditingController();
    final focusNode = FocusNode();

    final accentColor = isAccept ? HuddlColors.success : HuddlColors.error;
    final actionLabel = isAccept ? 'Accept offer' : 'Decline offer';
    final icon = isAccept ? Icons.handshake_outlined : Icons.close_outlined;

    // Suggested quick replies differ by action
    final quickReplies = isAccept
        ? [
            'Looking forward to it! I\'ll arrange collection soon.',
            'Great, please get in touch to arrange pick-up.',
            'Accepted! Let me know when you\'re free to collect.',
          ]
        : [
            'Sorry, I\'ve decided to keep this item for now.',
            'I\'ve had a higher offer — thanks for your interest.',
            'Sorry, I\'m no longer selling this item.',
          ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final shc = ctx.hc;
          return Padding(
            // Shift up when keyboard appears
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    const HuddlBottomSheetHandle(),
                    const SizedBox(height: 10),

                    // ── Header ───────────────────────────────────────────
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, size: 18, color: accentColor),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAccept ? 'Accept offer' : 'Decline offer',
                                style: HuddlText.heading(color: shc.textPrimary),
                              ),
                              Text(
                                '${offer.buyerName} · ${offer.amountDisplay} for ${offer.itemTitle}',
                                style: HuddlText.caption(color: shc.textTertiary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Optional message ─────────────────────────────────
                    Text(
                      'Send a message (optional)',
                      style: HuddlText.caption(color: shc.textSecondary, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: shc.inputBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: shc.divider),
                      ),
                      child: TextField(
                        controller: msgController,
                        focusNode: focusNode,
                        maxLines: 3,
                        minLines: 2,
                        maxLength: 200,
                        style: HuddlText.body(color: shc.textPrimary),
                        decoration: InputDecoration(
                          hintText: isAccept
                              ? 'e.g. "Great! Please get in touch to arrange pick-up."'
                              : 'e.g. "Sorry, I\'ve had another offer."',
                          hintStyle: HuddlText.caption(color: shc.textTertiary),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(14),
                          counterStyle: HuddlText.caption(color: shc.textTertiary),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Quick-reply suggestions ──────────────────────────
                    Text(
                      'Quick replies',
                      style: HuddlText.caption(color: shc.textTertiary, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    ...quickReplies.map((reply) => GestureDetector(
                          onTap: () {
                            HuddlAnimations.selectionClick();
                            msgController.text = reply;
                            msgController.selection = TextSelection.fromPosition(
                              TextPosition(offset: reply.length),
                            );
                            setSheetState(() {});
                          },
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: msgController.text == reply
                                  ? accentColor.withValues(alpha: 0.08)
                                  : shc.inputBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: msgController.text == reply
                                    ? accentColor.withValues(alpha: 0.3)
                                    : shc.divider,
                              ),
                            ),
                            child: Text(
                              reply,
                              style: HuddlText.caption(color: msgController.text == reply
                                    ? accentColor
                                    : shc.textSecondary),
                            ),
                          ),
                        )),
                    const SizedBox(height: 20),

                    // ── Action buttons ───────────────────────────────────
                    Row(
                      children: [
                        // Cancel
                        Expanded(
                          child: HuddlButton(
                            label: 'Cancel',
                            variant: HuddlButtonVariant.secondary,
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Confirm action
                        Expanded(
                          flex: 2,
                          child: HuddlButton(
                            label: actionLabel,
                            variant: isAccept ? HuddlButtonVariant.primary : HuddlButtonVariant.destructive,
                            onPressed: () {
                              final msg = msgController.text.trim().isEmpty
                                  ? null
                                  : msgController.text.trim();
                              Navigator.pop(ctx);

                              if (isAccept) {
                                _ai.recordOfferAccept();
                                // acceptOffer() handles Firestore write +
                                // HuddlNotification in one place — no duplicate here.
                                _service.acceptOffer(offer.id, message: msg);
                                // BackendApiService = FCM push (separate channel)
                                final offerItem = _service.getItemById(offer.itemId);
                                final me = offerItem?.sellerName
                                    ?? (_service.myListings.isNotEmpty
                                        ? _service.myListings.first.sellerName
                                        : 'Seller');
                                BackendApiService().notifyOfferResponse(
                                  buyerId: offer.buyerId,
                                  sellerName: me,
                                  itemTitle: offer.itemTitle,
                                  itemId: offer.itemId,
                                  accepted: true,
                                  responseMessage: msg,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.handshake,
                                            color: Colors.white, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Accepted ${offer.buyerName}\'s offer'
                                            '${msg != null ? ' · Message sent' : ''}',
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: HuddlColors.success,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    action: SnackBarAction(
                                      label: 'Undo',
                                      textColor: Colors.white,
                                      onPressed: () =>
                                          _service.restoreOfferToPending(
                                              offer.id),
                                    ),
                                  ));
                                }
                              } else {
                                _ai.recordOfferDecline();
                                // declineOffer() handles Firestore write +
                                // HuddlNotification in one place — no duplicate here.
                                _service.declineOffer(offer.id, message: msg);
                                // BackendApiService = FCM push (separate channel)
                                final offerItem = _service.getItemById(offer.itemId);
                                final me = offerItem?.sellerName
                                    ?? (_service.myListings.isNotEmpty
                                        ? _service.myListings.first.sellerName
                                        : 'Seller');
                                BackendApiService().notifyOfferResponse(
                                  buyerId: offer.buyerId,
                                  sellerName: me,
                                  itemTitle: offer.itemTitle,
                                  itemId: offer.itemId,
                                  accepted: false,
                                  responseMessage: msg,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: Text(
                                      'Declined ${offer.buyerName}\'s offer'
                                      '${msg != null ? ' · Message sent' : ''}',
                                    ),
                                    backgroundColor: hc.textSecondary,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    action: SnackBarAction(
                                      label: 'Undo',
                                      textColor: Colors.white,
                                      onPressed: () =>
                                          _service.restoreOfferToPending(
                                              offer.id),
                                    ),
                                  ));
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      msgController.dispose();
      focusNode.dispose();
    });
  }

  // ── Progressive Disclosure: Listing actions via bottom sheet ──
  // Replaces the 3-4 visible buttons per tile (Edit, Mark sold, Delete, Relist)
  // with a single long-press → clean action list. AI decides the order.
  void _showListingActions(RehomeItem item, HuddlContextColors hc) {
    HuddlAnimations.mediumTap();
    showModalBottomSheet(
      context: context,
      backgroundColor: hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HuddlBottomSheetHandle(),
              // Item preview header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 48, height: 48,
                        child: HuddlPhotoImage(
                          url: item.imageUrls.first,
                          fallbackIcon: item.category.icon,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title,
                            style: HuddlText.body(color: hc.textPrimary, weight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(item.priceDisplay,
                            style: HuddlText.caption(color: HuddlColors.nearBlack, weight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: hc.divider),
              // AI-ordered actions — most relevant first
              if (!item.isSold) ...[
                _sheetAction(Icons.edit_outlined, 'Edit listing', hc, () {
                  Navigator.pop(context);
                  _openEditListing(item);
                }),
                _sheetAction(Icons.check_circle_outline, 'Mark as sold', hc, () {
                  Navigator.pop(context);
                  HuddlAnimations.mediumTap();
                  _service.markSold(item.id);
                  // Notify seller + all buyers who had pending offers
                  final pendingBuyerIds = _service.pendingOffers
                      .where((o) => o.itemId == item.id && o.buyerId.isNotEmpty)
                      .map((o) => o.buyerId)
                      .toList();
                  HuddlNotificationService().itemSold(
                    sellerId: item.sellerId,
                    itemTitle: item.title,
                    itemId: item.id,
                    buyerName: pendingBuyerIds.isNotEmpty
                        ? (_service.pendingOffers
                            .firstWhere((o) => o.itemId == item.id,
                                orElse: () => _service.pendingOffers.first)
                            .buyerName)
                        : 'a buyer',
                    itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
                  );
                  BackendApiService().notifyItemSold(
                    sellerId: item.sellerId,
                    itemTitle: item.title,
                    itemId: item.id,
                    otherBuyerIds: pendingBuyerIds,
                    itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
                  );
                  // Notify saved-item users
                  for (final savedUser in _service.savedByUserIds(item.id)) {
                    HuddlNotificationService().savedItemSold(
                      savedByUserId: savedUser,
                      itemTitle: item.title,
                      itemId: item.id,
                      itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
                    );
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(children: [
                        const Icon(Icons.celebration, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('"${item.title}" marked as sold!')),
                      ]),
                      backgroundColor: HuddlColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }),
              ] else ...[
                _sheetAction(Icons.refresh, 'Relist item', hc, () {
                  Navigator.pop(context);
                  HuddlAnimations.mediumTap();
                  _service.relistItem(item.id);
                  // Notify users who saved this item
                  for (final savedUser in _service.savedByUserIds(item.id)) {
                    HuddlNotificationService().itemRelisted(
                      savedByUserId: savedUser,
                      itemTitle: item.title,
                      itemId: item.id,
                      itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
                    );
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(children: [
                        const Icon(Icons.check_circle, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('"${item.title}" is back on sale')),
                      ]),
                      backgroundColor: HuddlColors.textDark,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }),
              ],
              _sheetAction(Icons.delete_outline, 'Delist', hc, () {
                Navigator.pop(context);
                _confirmDelistItem(item);
              }, isDestructive: true),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetAction(IconData icon, String label, HuddlContextColors hc,
      VoidCallback onTap, {bool isDestructive = false}) {
    return Semantics(
      label: label,
      button: true,
      child: ListTile(
        leading: Icon(icon, size: 22,
            color: isDestructive ? HuddlColors.error : hc.textSecondary),
        title: Text(label,
          style: HuddlText.body(color: isDestructive ? HuddlColors.error : hc.textPrimary)),
        onTap: onTap,
        minTileHeight: 48,
      ),
    );
  }

  // == SAVED TAB =============================================================

  Widget _buildSavedTab(HuddlContextColors hc) {
    final allSaved = _service.savedItems;

    // ── Saved items slot counter (free users only) ─────────────────────
    final ssSaved = SubscriptionService();
    final showSavedCounter = !TierLimits.isUnlimited(
        ssSaved.limits.maxSavedItemsLifetime);

    // Filter by search query when search is active
    final q = _isSearchActive ? _searchQuery.toLowerCase().trim() : '';
    final saved = q.isEmpty
        ? allSaved
        : allSaved.where((item) {
            return item.title.toLowerCase().contains(q) ||
                item.category.label.toLowerCase().contains(q) ||
                item.sellerLocation.toLowerCase().contains(q);
          }).toList();

    if (allSaved.isEmpty) {
      // liveRegion: screen readers announce when saved list becomes empty
      return Semantics(
        liveRegion: true,
        child: HuddlEmptyState(
          mood: HuddlMood.supportive,
          title: 'Nothing saved yet',
          subtitle: 'Tap the ❤️ on any listing to save it here.',
        ),
      );
    }

    return Column(
      children: [
        // Saved items slot counter — free users only
        if (showSavedCounter) Builder(builder: (context) {
          final remaining = ssSaved.savedItemsRemaining;
          final max       = ssSaved.limits.maxSavedItemsLifetime;
          final used      = ssSaved.savedItemsTotal;
          return Container(
            width: double.infinity,
            color: remaining == 0
                ? HuddlColors.primary.withValues(alpha: 0.08)
                : HuddlColors.primary.withValues(alpha: 0.04),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              remaining == 0
                  ? 'Save limit reached ($used/$max) — upgrade for unlimited'
                  : 'Saved $used of $max — $remaining slot${remaining == 1 ? "" : "s"} remaining',
              style: HuddlText.caption(
                  color: remaining == 0
                      ? HuddlColors.primary
                      : HuddlColors.textTertiary),
              textAlign: TextAlign.center,
            ),
          );
        }),
        // Count row
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${saved.length} saved item${saved.length == 1 ? '' : 's'}${q.isNotEmpty ? ' matching "$_searchQuery"' : ''}',
                style: HuddlText.caption(color: hc.textTertiary),
              ),
            ),
          ),
        ),
        Expanded(
          child: saved.isEmpty
              ? const HuddlEmptyState(
                  mood: HuddlMood.curious,
                  title: 'No results found',
                  subtitle: 'Try a different search or keyword.',
                )
              : _isSearchActive
                  // ── Compact search rows ────────────────────────────────
                  ? ListView.separated(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
                      itemCount: saved.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: 92,
                        endIndent: 0,
                        color: hc.divider,
                      ),
                      itemBuilder: (context, index) => _MarketSearchRow(
                        item: saved[index],
                        onTap: () => _openItemDetail(saved[index]),
                        onToggleSave: () {
                          HuddlAnimations.lightTap();
                          _service.toggleSaved(saved[index].id);
                        },
                      ),
                    )
                  // ── Full hero cards (default) ──────────────────────────
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: saved.length,
                      itemBuilder: (context, index) => _MarketItemCard(
                        item: saved[index],
                        onTap: () => _openItemDetail(saved[index]),
                        onToggleSave: () {
                          HuddlAnimations.lightTap();
                          _service.toggleSaved(saved[index].id);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  // == FAB removed — now rendered as Positioned inside Stack in build() ==
  // Matches Groups/Meetups pattern: Positioned(bottom:24, right:16).
}

// =============================================================================
// SHARED IMAGE HELPER — handles data:URI (base64), http, and empty URLs
// =============================================================================

Widget _buildItemImage(String url, RehomeItem item) {
  final iconFallback = Container(
    color: const Color(0xFFF7F7F7),
    child: Center(
      child: Icon(item.category.icon,
          size: 44, color: item.category.color.withValues(alpha: 0.5)),
    ),
  );

  // Stock photo fallback — used when URL is empty OR when a real URL fails
  // to load (e.g. expired Firebase Storage tokens, deleted files).
  // Always shows a contextual category image rather than a bare icon.
  Widget stockPhotoFallback() {
    final stockUrl = _MarketGridCardState._categoryStockPhoto(item.category, item.title);
    return Image.network(
      stockUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => iconFallback,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return const HuddlShimmer(width: double.infinity, height: double.infinity);
      },
    );
  }

  // No URL → go straight to stock photo
  if (url.isEmpty) return stockPhotoFallback();

  if (url.startsWith('data:')) {
    try {
      final comma = url.indexOf(',');
      if (comma >= 0) {
        final bytes = base64Decode(url.substring(comma + 1));
        return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity,
            height: double.infinity,
            // base64 decode errors → stock photo, not bare icon
            errorBuilder: (_, __, ___) => stockPhotoFallback());
      }
    } catch (_) {}
    return stockPhotoFallback();
  }

  if (url.startsWith('http')) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // Broken/expired URL (404, 403, network error) → stock photo fallback,
      // NOT bare icon. This handles stale Firebase Storage download tokens.
      errorBuilder: (_, __, ___) => stockPhotoFallback(),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return const HuddlShimmer(width: double.infinity, height: double.infinity);
      },
    );
  }

  return stockPhotoFallback();
}

// =============================================================================
// MARKET ITEM CARD — full-width Events-style hero card for Buy + Saved tabs
//
// Layout mirrors _EventListCard exactly:
//   Container(margin: only(bottom:18), radius:20, clipBehavior:antiAlias)
//   Hero image: SizedBox(height:190) → Image fit:cover
//   Bottom gradient: height:60, transparent → black.withValues(alpha:0.22)
//   Top-left badge: Free (teal) OR nothing
//   Top-right badge: Condition pill (scrim)
//   Top-right heart: save button (white circle, 48dp)
//   Body: Padding(LTRB:16,14,16,0)
//     → category row (emoji icon + 12px label)
//     → bold title (16px w700)
//     → price row
//     → location row (icon size:14 + gap:5)
//   Bottom row: Padding(LTRB:16,10,16,14)
//     → SizedBox(w:62,h:24) avatar stack (3 overlapping 24px circles)
//     → count text
//     → "Message" action pill (grey resting, matches Events "Join")
// =============================================================================

// =============================================================================
// BUY TAB — 2-COLUMN GRID CARD
// =============================================================================
// URGENCY SIGNAL ROW
//
// Renders the highest-priority urgency signal for a listing.
// Priority: offerCount > viewCount ≥10 > isFree > hoursListed < 24 > brandNew
// Only one signal shown at a time. Returns SizedBox.shrink() for stale
// low-activity listings — no wasted vertical space.
// =============================================================================

class _UrgencySignalRow extends StatelessWidget {
  final RehomeItem item;
  const _UrgencySignalRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final signal = _resolveSignal();
    if (signal == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(signal.icon, size: 11, color: signal.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              signal.label,
              style: HuddlText.caption(
                color: signal.color,
                weight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  _UrgencySignal? _resolveSignal() {
    // Priority 1 — Offers pending (highest intent signal)
    if (item.offerCount > 0) {
      return _UrgencySignal(
        icon: Icons.local_offer_outlined,
        label: item.offerCount == 1
            ? '1 person made an offer'
            : '${item.offerCount} people made offers',
        color: HuddlColors.primary,
      );
    }

    // Priority 2 — High view count (social proof)
    if (item.viewCount >= 10) {
      return _UrgencySignal(
        icon: Icons.visibility_outlined,
        label: item.viewCount >= 50
            ? '${item.viewCount}+ views — popular item'
            : '${item.viewCount} people viewed this',
        color: HuddlColors.infoBlue,
      );
    }

    // Priority 3 — Free item (goes fast)
    if (item.isFree) {
      return _UrgencySignal(
        icon: Icons.volunteer_activism_outlined,
        label: 'Free — first to message gets it',
        color: HuddlColors.yellowDark,
      );
    }

    // Priority 4 — Recently listed (freshness signal)
    final hoursSinceListed = DateTime.now().difference(item.listedAt).inHours;
    if (hoursSinceListed < 24) {
      return _UrgencySignal(
        icon: Icons.access_time_outlined,
        label: hoursSinceListed < 2
            ? 'Just listed'
            : 'Listed ${item.timeAgo}',
        color: HuddlColors.textTertiary,
      );
    }

    // Priority 5 — Brand new condition (value signal)
    if (item.condition == ItemCondition.brandNew) {
      return _UrgencySignal(
        icon: Icons.auto_awesome,
        label: 'Brand new — never used',
        color: HuddlColors.primary,
      );
    }

    // No signal — stale, low-activity listing
    return null;
  }
}

class _UrgencySignal {
  final IconData icon;
  final String   label;
  final Color    color;
  const _UrgencySignal({
    required this.icon,
    required this.label,
    required this.color,
  });
}

// Half-screen-width card: photo (top, fills width, fixed ratio) + body.
// Image area:
//   - Count badge top-left (grey pill, hidden if only 1 photo)
//   - Condition badge top-right (scrim pill)
//   - Save heart bottom-right (white circle)
// Body: category (small caps), bold title (2 lines max), price (right),
//       location row, bottom "Near you" label.
// =============================================================================
class _MarketGridBuyCard extends StatefulWidget {
  final RehomeItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;
  final bool isOwn;

  const _MarketGridBuyCard({
    required this.item,
    required this.onTap,
    required this.onToggleSave,
    // ignore: unused_element_parameter
    this.isOwn = false,
  });

  @override
  State<_MarketGridBuyCard> createState() => _MarketGridBuyCardState();
}

class _MarketGridBuyCardState extends State<_MarketGridBuyCard> {

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hc = context.hc;
    final photoCount = item.imageUrls.length;

    // SizedBox.expand() forces the card to fill the tight GridView cell
    // constraints, which makes Expanded widgets inside the Column work
    // correctly regardless of widget wrapping layers.
    return SizedBox.expand(
      child: Semantics(
      label: '${item.title}, ${item.priceDisplay}, ${item.condition.label}, '
          '${item.ageStage.shortLabel}, ${item.sellerLocation}.',
      button: true,
      child: ScaleOnPress(
        scale: 0.97,
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: hc.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image area — square (1:1) — Depop/Vinted standard ─────────────
              AspectRatio(
                aspectRatio: 1.0,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Photo or category fallback
                    _buildItemImage(
                      item.imageUrls.isNotEmpty ? item.imageUrls.first : '',
                      item,
                    ),
                    // Bottom gradient scrim
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Photo count badge — top-left (hidden when only 1 photo)
                    if (photoCount > 1)
                      Positioned(
                        top: 8, left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.52),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_library_outlined,
                                  size: 10, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                '$photoCount',
                                style: HuddlText.caption(color: Colors.white, weight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Condition / Free badge — top-right
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: item.isFree
                              ? HuddlColors.yellowSoft
                              : Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item.isFree ? 'Free' : item.condition.label,
                          style: HuddlText.caption(
                            color: item.isFree ? HuddlColors.yellowDark : Colors.white,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    // Save heart — bottom-right
                    Positioned(
                      bottom: 8, right: 8,
                      child: Semantics(
                        label: item.isSaved
                            ? 'Remove ${item.title} from saved'
                            : 'Save ${item.title}',
                        button: true,
                        child: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? HuddlColors.darkSurface.withValues(alpha: 0.92)
                                : Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: HeartPopButton(
                              isLiked: item.isSaved,
                              onToggle: widget.onToggleSave,
                              size: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Card body — title, price, location ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Price + title row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: HuddlText.caption(color: hc.textPrimary, weight: FontWeight.w600).copyWith(height: 1.25),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.priceDisplay,
                          style: HuddlText.body(color: hc.textPrimary, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Location row
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 11, color: hc.textTertiary),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            item.sellerLocation.isNotEmpty
                                ? item.sellerLocation
                                : 'Near you',
                            style: HuddlText.caption(color: hc.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // Compact urgency signal
                    if (_resolveGridUrgency(item) != null) ...[
                      const SizedBox(height: 3),
                      _resolveGridUrgency(item)!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ), // SizedBox.expand
    );
  }

  Widget? _resolveGridUrgency(RehomeItem item) {
    if (item.offerCount > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_offer_outlined, size: 10, color: HuddlColors.primary),
          const SizedBox(width: 3),
          Text(
            '${item.offerCount} offer${item.offerCount == 1 ? '' : 's'}',
            style: HuddlText.caption(color: HuddlColors.primary, weight: FontWeight.w600),
          ),
        ],
      );
    }
    if (item.viewCount >= 10) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_outlined, size: 10, color: HuddlColors.infoBlue),
          const SizedBox(width: 3),
          Text(
            '${item.viewCount} views',
            style: HuddlText.caption(color: HuddlColors.infoBlue, weight: FontWeight.w600),
          ),
        ],
      );
    }
    final hours = DateTime.now().difference(item.listedAt).inHours;
    if (hours < 24) {
      return Text(
        hours < 2 ? 'Just listed' : item.timeAgo,
        style: HuddlText.caption(color: HuddlColors.textTertiary, weight: FontWeight.w600),
      );
    }
    return null;
  }
}

// =============================================================================
class _MarketItemCard extends StatefulWidget {
  final RehomeItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;
  final VoidCallback? onDismiss;

  const _MarketItemCard({
    required this.item,
    required this.onTap,
    required this.onToggleSave,
    // ignore: unused_element_parameter
    this.onDismiss,
  });

  @override
  State<_MarketItemCard> createState() => _MarketItemCardState();
}

class _MarketItemCardState extends State<_MarketItemCard> {

  String _avatarUrl(int i) {
    final idx = (widget.item.id.hashCode + i).abs() % _kMarketAvatarPool.length;
    return _kMarketAvatarPool[idx];
  }

  @override
  void initState() {
    super.initState();
    // Increment view count when this card first appears in the list.
    // Fire-and-forget, non-blocking. Only fires for other users' items
    // that have never been viewed (viewCount == 0), so counts aren't
    // inflated on every rebuild.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null
        && widget.item.sellerId != uid
        && widget.item.id.isNotEmpty
        && !widget.item.id.startsWith('local_')
        && widget.item.viewCount < 1) {
      FirestoreService().incrementListingViews(widget.item.id).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hc = context.hc;

    return Semantics(
      label: '${item.title}, ${item.priceDisplay}, ${item.condition.label}, '
          '${item.ageStage.shortLabel}, ${item.sellerLocation}.',
      button: true,
      child: GestureDetector(
        onLongPress: () {
          if (widget.onDismiss != null) widget.onDismiss!();
        },
        child: ScaleOnPress(
          scale: 0.98,
          onTap: widget.onTap,
          child: HuddlCard(
            variant: HuddlCardVariant.standard,
            margin: const EdgeInsets.only(bottom: 18),
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero image ──────────────────────────────────────
                SizedBox(
                  height: 190,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildItemImage(
                        item.imageUrls.isNotEmpty ? item.imageUrls.first : '',
                        item,
                      ),
                      // Bottom gradient scrim
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.22),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Free badge — top-left: yellowSoft bg, yellowDark text (celebration).
                      if (item.isFree)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: HuddlColors.yellowSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Free',
                              style: HuddlText.caption(
                                  weight: FontWeight.w700,
                                  color: HuddlColors.yellowDark),
                            ),
                          ),
                        ),
                      // Condition badge — top-right scrim pill
                      if (!item.isFree)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: _MarketBadgePill(
                            label: item.condition.label,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                      // Save heart button — top-right (or below condition badge)
                      Positioned(
                        top: item.isFree ? 12 : 46,
                        right: 12,
                        child: Semantics(
                          label: item.isSaved
                              ? 'Remove ${item.title} from saved'
                              : 'Save ${item.title}',
                          button: true,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? HuddlColors.darkSurface.withValues(alpha: 0.92)
                                  : Colors.white.withValues(alpha: 0.92),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: HeartPopButton(
                                isLiked: item.isSaved,
                                onToggle: widget.onToggleSave,
                                size: 17,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Card body ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category row — category icon + 12px label
                      Row(
                        children: [
                          Icon(item.category.icon,
                              size: 13, color: hc.textTertiary),
                          const SizedBox(width: 5),
                          Text(
                            item.category.label.toUpperCase(),
                            style: HuddlText.caption(color: hc.textTertiary, weight: FontWeight.w600),
                          ),
                          const Spacer(),
                          // Price — right-aligned in category row
                          Text(
                            item.priceDisplay,
                            style: HuddlText.body(color: HuddlColors.nearBlack, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Title
                      Text(
                        item.title,
                        style: HuddlText.body(color: hc.textPrimary, weight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Location row
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 14, color: hc.textTertiary),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '${item.ageStage.shortLabel} \u2022 ${item.sellerLocation}',
                              style: HuddlText.caption(color: hc.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Urgency signal — offer / view / freshness hint
                      _UrgencySignalRow(item: item),
                    ],
                  ),
                ),

                // ── Bottom row: avatars + count + action pill ───────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Row(
                    children: [
                      // 3 overlapping avatar circles (24px each)
                      SizedBox(
                        width: 62,
                        height: 24,
                        child: Stack(
                          children: List.generate(3, (i) {
                            return Positioned(
                              left: i * 18.0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: hc.surface, width: 1.5),
                                ),
                                child: ClipOval(
                                  child: Image.network(
                                    _avatarUrl(i),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: const Color(0xFFF7F7F7),
                                      child: Icon(Icons.person,
                                          size: 14,
                                          color: HuddlColors.textHint),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Near you',
                          style: HuddlText.caption(color: hc.textTertiary),
                        ),
                      ),
                      // Action pill — matches Events "Join" pill exactly
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Message',
                          style: HuddlText.caption(color: HuddlColors.textDark, weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Badge pill for market cards — same spec as Services _BadgePill
// =============================================================================
// BUY TAB — 2-COLUMN COMPACT GRID CARD
// Half-screen-width card with product image + title, price, location, save.
// =============================================================================

// ─── Single-column list card (Buy tab) ───────────────────────────────────────
// ─── Market full card (Groups/Meetups style — hero photo + card body) ─────────
// ─── Compact search result row ────────────────────────────────────────────────
// Shown in Buy/Sell tabs when _isSearchActive == true.
// Layout: 64×64 thumbnail | category / title / location | price pill
// Mirrors _ServiceSearchRow and _GroupMessageRow patterns.
class _MarketSearchRow extends StatelessWidget {
  final RehomeItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;
  final bool isOwn;

  const _MarketSearchRow({
    required this.item,
    required this.onTap,
    required this.onToggleSave,
    this.isOwn = false,
  });

  Color get _conditionColor {
    switch (item.condition.label.toLowerCase()) {
      case 'new':       return HuddlColors.nearBlack;
      case 'like new':  return HuddlColors.nearBlack;
      case 'good':      return HuddlColors.primary;
      default:          return HuddlColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final hasImage = item.imageUrls.isNotEmpty;
    final priceStr = item.isFree
        ? 'Free'
        : '£${item.price % 1 == 0 ? item.price.toInt() : item.price.toStringAsFixed(2)}';
    final priceColor = HuddlColors.nearBlack;

    return ScaleOnPress(
      scale: 0.99,
      onTap: onTap,
      child: Container(
        color: hc.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Square thumbnail 64×64 ──────────────────────────────────
            SizedBox(
              width: 64,
              height: 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: hasImage
                    ? HuddlNetworkImage(
                        url: item.imageUrls.first,
                        width: 64,
                        height: 64,
                        fallbackWidget: _MarketPhotoFallback(item: item),
                      )
                    : _MarketPhotoFallback(item: item),
              ),
            ),
            const SizedBox(width: 12),
            // ── Centre text block ───────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Category label — small caps
                  Text(
                    item.category.label.toUpperCase(),
                    style: HuddlText.caption(color: hc.textTertiary, weight: FontWeight.w600).copyWith(letterSpacing: 0.4),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Title
                  Text(
                    item.title,
                    style: HuddlText.body(color: hc.textPrimary, weight: FontWeight.w600).copyWith(height: 1.25),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  // Location row + urgency signal beneath
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: hc.textTertiary),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.sellerLocation.isNotEmpty
                                  ? item.sellerLocation
                                  : 'Near you',
                              style: HuddlText.caption(color: hc.textTertiary).copyWith(fontStyle: FontStyle.italic),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (item.offerCount > 0)
                              Text(
                                '${item.offerCount} offer${item.offerCount == 1 ? '' : 's'}',
                                style: HuddlText.caption(color: HuddlColors.primary, weight: FontWeight.w600),
                              )
                            else if (item.viewCount >= 10)
                              Text(
                                '${item.viewCount} views',
                                style: HuddlText.caption(color: HuddlColors.infoBlue, weight: FontWeight.w600),
                              )
                            else
                              Text(
                                item.timeAgo,
                                style: HuddlText.caption(color: hc.textTertiary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // ── Right: condition badge + price pill ─────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Condition badge — three-way: Sold / Yours / condition label
                Builder(builder: (context) {
                  final isSoldOwn = isOwn && item.isSold;
                  final badgeLabel = isSoldOwn
                      ? 'Sold'
                      : isOwn
                          ? 'Yours'
                          : item.condition.label;
                  final badgeBg = isSoldOwn
                      ? HuddlColors.error.withValues(alpha: 0.90)
                      : isOwn
                          ? HuddlColors.textTertiary.withValues(alpha: 0.12)
                          : _conditionColor.withValues(alpha: 0.12);
                  final badgeFg = isSoldOwn
                      ? Colors.white
                      : isOwn
                          ? HuddlColors.textTertiary
                          : _conditionColor;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeLabel,
                      style: HuddlText.caption(color: badgeFg, weight: FontWeight.w600),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                // Price pill — Free: yellowSoft/yellowDark. Paid: neutral grey.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: item.isFree
                        ? HuddlColors.yellowSoft
                        : const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    priceStr,
                    style: HuddlText.caption(
                      color: item.isFree ? HuddlColors.yellowDark : priceColor,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Full listing card (default Buy/Saved view) ───────────────────────────────
class _MarketListCard extends StatefulWidget {
  final RehomeItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;
  final bool isOwn;

  const _MarketListCard({
    required this.item,
    required this.onTap,
    required this.onToggleSave,
    // ignore: unused_element_parameter
    this.isOwn = false,
  });

  @override
  State<_MarketListCard> createState() => _MarketListCardState();
}

class _MarketListCardState extends State<_MarketListCard> {

  Color get _conditionColor {
    switch (widget.item.condition.label.toLowerCase()) {
      case 'new':       return HuddlColors.nearBlack;
      case 'like new':  return HuddlColors.nearBlack;
      case 'good':      return HuddlColors.primary;
      default:          return HuddlColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hc = context.hc;
    final hasImage = item.imageUrls.isNotEmpty;
    final priceStr = item.isFree
        ? 'Free'
        : '£${item.price % 1 == 0 ? item.price.toInt() : item.price.toStringAsFixed(2)}';
    final priceColor = HuddlColors.nearBlack;

    return ScaleOnPress(
      scale: 0.98,
      onTap: widget.onTap,
      child: HuddlCard(
        // Full-width card — same shape/shadow as Groups discover card
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero photo (top, 160px, full-width) ───────────────────
            SizedBox(
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo or fallback
                  hasImage
                      ? HuddlNetworkImage(
                          url: item.imageUrls.first,
                          width: double.infinity,
                          height: 160,
                          fallbackWidget: _MarketPhotoFallback(item: item),
                        )
                      : _MarketPhotoFallback(item: item),
                  // Subtle gradient at bottom for text legibility
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x22000000)],
                        stops: [0.55, 1.0],
                      ),
                    ),
                  ),
                  // Condition badge — top-right
                  Positioned(
                    top: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.isOwn ? HuddlColors.textTertiary : _conditionColor,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
                      ),
                      child: Text(
                        widget.isOwn ? 'Your listing' : item.condition.label,
                        style: HuddlText.caption(color: Colors.white, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                  // Multiple-image indicator — top-left (if > 1 photo)
                  if (item.imageUrls.length > 1)
                    Positioned(
                      top: 10, left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_library_outlined, size: 11, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              '${item.imageUrls.length}',
                              style: HuddlText.caption(color: Colors.white, weight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Card body ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category label — small uppercase grey (Groups pattern)
                  Text(
                    item.category.label.toUpperCase(),
                    style: HuddlText.caption(color: hc.textTertiary, weight: FontWeight.w600).copyWith(letterSpacing: 0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Title — bold dark
                  Text(
                    item.title,
                    style: HuddlText.body(color: hc.textPrimary, weight: FontWeight.w600).copyWith(height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Description / seller location — italic grey
                  if (item.sellerLocation.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 12, color: hc.textTertiary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            item.sellerLocation,
                            style: HuddlText.caption(color: hc.textTertiary).copyWith(fontStyle: FontStyle.italic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  // Urgency signal — offer / view / freshness hint
                  _UrgencySignalRow(item: item),
                  const SizedBox(height: 6),

                  // Bottom row — price bold + save heart (Groups join-button pattern)
                  Row(
                    children: [
                      // Seller avatar stack (3 deterministic)
                      SizedBox(
                        width: 56,
                        height: 22,
                        child: Stack(
                          children: [
                            for (int i = 0; i < 3; i++)
                              Positioned(
                                left: i * 16.0,
                                child: Container(
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: hc.surface, width: 1.5),
                                  ),
                                  child: ClipOval(
                                    child: Image.network(
                                      _kMarketAvatarPool[
                                          (item.id.hashCode + i) % _kMarketAvatarPool.length],
                                      width: 22, height: 22,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: const Color(0xFFF7F7F7),
                                        child: const Icon(Icons.person, size: 11, color: HuddlColors.textHint),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // timeAgo — when this was listed
                      Expanded(
                        child: Text(
                          item.timeAgo,
                          style: HuddlText.caption(color: hc.textTertiary),
                        ),
                      ),
                      // Save heart (hidden for own listings)
                      if (!widget.isOwn) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: HeartPopButton(
                            isLiked: item.isSaved,
                            onToggle: widget.onToggleSave,
                            size: 20,
                          ),
                        ),
                      ],
                      // Price pill — Free: yellowSoft/yellowDark. Paid: neutral grey.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: item.isFree
                              ? HuddlColors.yellowSoft
                              : const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          priceStr,
                          style: HuddlText.body(
                            color: item.isFree ? HuddlColors.yellowDark : priceColor,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Fallback when no item photo is available
class _MarketPhotoFallback extends StatelessWidget {
  final RehomeItem item;
  const _MarketPhotoFallback({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F7F7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.category.icon, size: 44, color: HuddlColors.textHint.withValues(alpha: 0.5)),
            const SizedBox(height: 6),
            Text(
              item.category.label,
              style: HuddlText.caption(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Grid card (kept for reference / future use) ─────────────────────────────
class _MarketGridCard extends StatefulWidget {
  final RehomeItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;
  /// True when the signed-in user is the seller — hides the save heart.
  final bool isOwn;

  const _MarketGridCard({
    required this.item,
    required this.onTap,
    required this.onToggleSave,
    // ignore: unused_element_parameter
    this.isOwn = false,
  });

  @override
  State<_MarketGridCard> createState() => _MarketGridCardState();
}

class _MarketGridCardState extends State<_MarketGridCard> {

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hc = context.hc;
    final hasImage = item.imageUrls.isNotEmpty && item.imageUrls.first.isNotEmpty;

    // High-quality grid card:
    // • No card border or shadow — clean edge-to-edge photo grid
    // • Photo fills top ~62% with consistent aspect ratio
    // • Single nearBlack pill badge top-left (condition or "Yours")
    // • Heart top-right on white scrim circle
    // • Text below: title (w500), price (w700 nearBlack), location (muted)
    // • surface background, zero decorative noise

    return Semantics(
      label: '${item.title}, ${item.priceDisplay}, ${item.condition.label}, ${item.sellerLocation}',
      button: true,
      child: ScaleOnPress(
        scale: 0.97,
        onTap: widget.onTap,
        child: ColoredBox(
          color: hc.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Photo area ──────────────────────────────────────────────
              Expanded(
                flex: 62,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Image
                    hasImage
                        ? _buildItemImage(item.imageUrls.first, item)
                        : _gridPlaceholder(hc, item),

                    // Condition / ownership badge — top-left nearBlack pill
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.56),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.isOwn ? 'Yours' : item.condition.label,
                          style: HuddlText.label(color: Colors.white),
                        ),
                      ),
                    ),

                    // Save heart — top-right white scrim circle
                    if (!widget.isOwn)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Semantics(
                          label: item.isSaved ? 'Remove from saved' : 'Save item',
                          button: true,
                          child: GestureDetector(
                            onTap: widget.onToggleSave,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: HeartPopButton(
                                  isLiked: item.isSaved,
                                  onToggle: widget.onToggleSave,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Text area ───────────────────────────────────────────────
              Expanded(
                flex: 38,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      // Title — 2 lines max, medium weight
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HuddlText.body(color: hc.textPrimary),
                      ),
                      const SizedBox(height: 5),
                      // Price — bold, nearBlack, prominent
                      Text(
                        item.isFree
                            ? 'Free'
                            : '£${item.price % 1 == 0 ? item.price.toInt() : item.price.toStringAsFixed(2)}',
                        style: HuddlText.body(weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      // Location — small, muted, no icon clutter
                      Text(
                        item.sellerLocation.isNotEmpty
                            ? item.sellerLocation
                            : 'Near you',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HuddlText.caption(color: hc.textTertiary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gridPlaceholder(HuddlContextColors hc, RehomeItem item) {
    // Rich UHD category-matched stock photo fallback — much better than an icon
    final url = _categoryStockPhoto(item.category, item.title);
    return Stack(
      fit: StackFit.expand,
      children: [
        HuddlNetworkImage(
          url: url,
          width: double.infinity,
          height: double.infinity,
          fallbackWidget: Container(
            color: hc.surfaceAlt,
            child: Center(
              child: Icon(item.category.icon,
                  size: 40,
                  color: hc.textTertiary.withValues(alpha: 0.3)),
            ),
          ),
        ),
        // Subtle darkening scrim so text/badges remain legible
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.08),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Returns a UHD Unsplash stock photo URL matched to the item's category.
  /// Multiple photos per category so the grid looks varied.
  static String _categoryStockPhoto(ItemCategory category, String title) {
    final t = title.toLowerCase();

    // Title-level overrides for very specific items
    if (t.contains('mamaroo') || t.contains('swing') || t.contains('bouncer')) {
      return 'https://images.unsplash.com/photo-1544022613-e87ca75a784a?w=600&q=80';
    }
    if (t.contains('pushchair') || t.contains('pram') || t.contains('stroller') || t.contains('icandy')) {
      return 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=600&q=80';
    }
    if (t.contains('crib') || t.contains('cot') || t.contains('moses') || t.contains('snüz') || t.contains('snuz')) {
      return 'https://images.unsplash.com/photo-1586105251261-72a756497a11?w=600&q=80';
    }
    if (t.contains('car seat') || t.contains('carseat')) {
      return 'https://images.unsplash.com/photo-1449965408869-eaa3f722e40d?w=600&q=80';
    }
    if (t.contains('clothes') || t.contains('bundle') || t.contains('outfit') || t.contains('dress') || t.contains('babygrow')) {
      return 'https://images.unsplash.com/photo-1522771930-78848d9293e8?w=600&q=80';
    }
    if (t.contains('high chair') || t.contains('highchair')) {
      return 'https://images.unsplash.com/photo-1609599006353-e629aaabfeae?w=600&q=80';
    }
    if (t.contains('carrier') || t.contains('sling') || t.contains('wrap') || t.contains('tula') || t.contains('ergo')) {
      return 'https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4?w=600&q=80';
    }
    if (t.contains('sleepyhead') || t.contains('pod') || t.contains('lounger') || t.contains('dock')) {
      return 'https://images.unsplash.com/photo-1561037404-61cd46aa615b?w=600&q=80';
    }
    if (t.contains('monitor') || t.contains('camera')) {
      return 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=600&q=80';
    }
    if (t.contains('bath') || t.contains('tub')) {
      return 'https://images.unsplash.com/photo-1556909172-54557c7e4fb7?w=600&q=80';
    }

    // Category-level fallbacks — varied within each category
    switch (category) {
      case ItemCategory.boysClothes:
        return 'https://images.unsplash.com/photo-1519689680058-324335c77eba?w=600&q=80';
      case ItemCategory.girlsClothes:
        return 'https://images.unsplash.com/photo-1522771930-78848d9293e8?w=600&q=80';
      case ItemCategory.toysAndGames:
        return 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=600&q=80';
      case ItemCategory.pushchairsAndPrams:
        return 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=600&q=80';
      case ItemCategory.forTheCar:
        return 'https://images.unsplash.com/photo-1449965408869-eaa3f722e40d?w=600&q=80';
      case ItemCategory.furniture:
        // Nursery furniture — crib/cot image
        return 'https://images.unsplash.com/photo-1586105251261-72a756497a11?w=600&q=80';
      case ItemCategory.books:
        return 'https://images.unsplash.com/photo-1524578271613-d550eacf6090?w=600&q=80';
      case ItemCategory.maternity:
        return 'https://images.unsplash.com/photo-1555252333-9f8e92e65df9?w=600&q=80';
      case ItemCategory.babyCareAndAccessories:
        return 'https://images.unsplash.com/photo-1544022613-e87ca75a784a?w=600&q=80';
      case ItemCategory.other:
        return 'https://images.unsplash.com/photo-1555252333-9f8e92e65df9?w=600&q=80';
    }
  }
}

// =============================================================================

class _MarketBadgePill extends StatelessWidget {
  final String label;
  final Color color;

  const _MarketBadgePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: HuddlText.caption(color: Colors.white, weight: FontWeight.w700),
      ),
    );
  }
}

// =============================================================================
// SELL LISTING TILE — "Invisible AI" v2 redesign
//
// Radical minimalism:
// - Swipe-left → delist (Dismissible with confirmation)
// - Long-press → contextual action bottom sheet (progressive disclosure)
// - Tap → view detail
// - AI insight with animated fade + feedback loop (thumbs up/down)
// - Health status indicator (dot color: green/amber/red)
// - 48dp+ touch targets throughout
// - Semantics-complete, dark-mode aware
// =============================================================================

class _SellListingTile extends StatefulWidget {
  final RehomeItem item;
  final ({String text, String type})? insight;
  final String healthCategory;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onDismissed;
  final void Function(bool helpful)? onInsightFeedback;
  final bool isSold;

  const _SellListingTile({
    super.key,
    required this.item,
    this.insight,
    this.healthCategory = 'healthy',
    required this.onTap,
    required this.onLongPress,
    this.onDismissed,
    this.onInsightFeedback,
    this.isSold = false,
  });

  @override
  State<_SellListingTile> createState() => _SellListingTileState();
}

class _SellListingTileState extends State<_SellListingTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _insightAnim;
  late Animation<double> _insightFade;

  @override
  void initState() {
    super.initState();
    _insightAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _insightFade = CurvedAnimation(parent: _insightAnim, curve: Curves.easeOut);
    if (widget.insight != null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _insightAnim.forward();
      });
    }
  }

  @override
  void didUpdateWidget(_SellListingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.insight != null && oldWidget.insight == null) {
      _insightAnim.forward(from: 0);
    } else if (widget.insight == null && oldWidget.insight != null) {
      _insightAnim.reverse();
    }
  }

  @override
  void dispose() {
    _insightAnim.dispose();
    super.dispose();
  }

  IconData _insightIcon(String type) {
    return switch (type) {
      'offers' => Icons.local_offer_outlined,
      'price' => Icons.trending_down,
      'photos' => Icons.add_a_photo_outlined,
      'relist' => Icons.refresh,
      _ => Icons.info_outline,
    };
  }

  Color _insightColor(String type) {
    return switch (type) {
      'offers' => HuddlColors.primary,
      'price' => HuddlColors.warning,
      'photos' => HuddlColors.primary,
      'relist' => HuddlColors.nearBlack,
      _ => HuddlColors.textTertiary,
    };
  }

  Color _healthDotColor() {
    return switch (widget.healthCategory) {
      'urgent' => HuddlColors.primary,
      'attention' => HuddlColors.warning,
      _ => HuddlColors.success,
    };
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hc = context.hc;
    final insight = widget.insight;

    final tile = Semantics(
      label: 'Your listing: ${item.title}, ${item.priceDisplay}, '
          '${item.viewCount} views, ${item.offerCount} offers'
          '${item.isSold ? ", sold" : ""}. '
          'Long press for actions. Swipe left to delist.',
      hint: insight != null ? 'Suggestion: ${insight.text}' : null,
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: () {
              HuddlAnimations.mediumTap();
              widget.onLongPress();
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hc.surface,
                borderRadius: BorderRadius.circular(14),
                border: hc.cardBorder,
                boxShadow: [
                  BoxShadow(color: hc.shadow, blurRadius: 6, offset: const Offset(0, 1)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Main row: image + info ──
                  Row(
                    children: [
                      // Thumbnail with status overlay
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 60,
                              height: 60,
                              child: Opacity(
                                opacity: widget.isSold ? 0.5 : 1.0,
                                child: _buildItemImage(
                                  item.imageUrls.isNotEmpty ? item.imageUrls.first : '',
                                  item,
                                ),
                              ),
                            ),
                          ),
                          if (widget.isSold)
                            Positioned(
                              top: 0,
                              left: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: HuddlColors.error.withValues(alpha: 0.85),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(10),
                                    bottomRight: Radius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'Sold',
                                  style: HuddlText.caption(color: Colors.white, weight: FontWeight.w600),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: HuddlText.body(color: widget.isSold
                                          ? hc.textTertiary
                                          : hc.textPrimary, weight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // Health status dot — color-coded
                                if (!widget.isSold)
                                  ExcludeSemantics(
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(left: 6),
                                      decoration: BoxDecoration(
                                        color: _healthDotColor(),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  item.priceDisplay,
                                  style: HuddlText.body(color: widget.isSold
                                        ? hc.textTertiary
                                        : HuddlColors.nearBlack, weight: FontWeight.w600),
                                ),
                                const SizedBox(width: 8),
                                // View count — infoBlue: engagement metric, informational.
                                ExcludeSemantics(
                                  child: Text(
                                    '${item.viewCount} views \u2022 ${item.timeAgo}',
                                    style: HuddlText.caption(color: HuddlColors.infoBlue),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // More actions — tappable ⋮ button (48dp target)
                      Semantics(
                        label: 'More actions for ${item.title}',
                        button: true,
                        child: GestureDetector(
                          onTap: () {
                            HuddlAnimations.mediumTap();
                            widget.onLongPress();
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                            child: Icon(Icons.more_vert,
                                size: 18, color: hc.textTertiary),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── AI insight row with feedback loop ──
                  if (insight != null)
                    FadeTransition(
                      opacity: _insightFade,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _insightColor(insight.type).withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _insightIcon(insight.type),
                                size: 14,
                                color: _insightColor(insight.type),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  insight.text,
                                  style: HuddlText.caption(color: _insightColor(insight.type), weight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Feedback loop: was this helpful?
                              if (widget.onInsightFeedback != null) ...[
                                const SizedBox(width: 4),
                                Semantics(
                                  label: 'Helpful suggestion',
                                  button: true,
                                  child: InkWell(
                                    onTap: () {
                                      HuddlAnimations.selectionClick();
                                      widget.onInsightFeedback!(true);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Center(
                                        child: Icon(
                                          Icons.thumb_up_outlined,
                                          size: 14,
                                          color: _insightColor(insight.type).withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Semantics(
                                  label: 'Not helpful, dismiss suggestion',
                                  button: true,
                                  child: InkWell(
                                    onTap: () {
                                      HuddlAnimations.selectionClick();
                                      widget.onInsightFeedback!(false);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Center(
                                        child: Icon(
                                          Icons.thumb_down_outlined,
                                          size: 14,
                                          color: _insightColor(insight.type).withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Wrap in Dismissible for swipe-to-delist (active items only)
    if (!widget.isSold && widget.onDismissed != null) {
      return Dismissible(
        key: ValueKey('dismiss_${item.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          HuddlAnimations.mediumTap();
          // Let the parent handle confirmation dialog
          widget.onDismissed!();
          return false; // Don't auto-remove; parent controls via dialog
        },
        background: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: HuddlColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Delist',
                style: HuddlText.caption(color: HuddlColors.error, weight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.delete_outline, size: 20, color: HuddlColors.error),
            ],
          ),
        ),
        child: tile,
      );
    }

    return tile;
  }
}

// =============================================================================
// SMART OFFER TILE — v2: swipeable, AI-summarised, feedback loop
//
// - Swipe-right to accept, swipe-left to decline (gesture-based navigation)
// - AI summary with sentiment color-coding (green/amber/red)
// - Inline Accept/Decline as fallback for non-swipe users (48dp touch targets)
// - Human-in-the-loop: undo via SnackBar after any action
// - Dark-mode aware, semantics-complete
// =============================================================================

class _SmartOfferTile extends StatelessWidget {
  final RehomeOffer offer;
  final String aiSummary;
  final String sentiment;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _SmartOfferTile({
    super.key,
    required this.offer,
    required this.aiSummary,
    this.sentiment = 'neutral',
    required this.onAccept,
    required this.onDecline,
  });

  Color _sentimentColor() {
    return switch (sentiment) {
      'strong' => HuddlColors.success,
      'fair' => HuddlColors.warning,
      'low' => HuddlColors.error,
      _ => HuddlColors.textTertiary,
    };
  }

  IconData _sentimentIcon() {
    return switch (sentiment) {
      'strong' => Icons.thumb_up_outlined,
      'fair' => Icons.thumbs_up_down_outlined,
      'low' => Icons.trending_down,
      _ => Icons.info_outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final sentColor = _sentimentColor();

    return Dismissible(
      key: ValueKey('offer_dismiss_${offer.id}'),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: HuddlColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.handshake, size: 20, color: HuddlColors.success),
            const SizedBox(width: 6),
            Text(
              'Accept',
              style: HuddlText.caption(color: HuddlColors.success, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: HuddlColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Decline',
              style: HuddlText.caption(color: HuddlColors.error, weight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.close, size: 20, color: HuddlColors.error),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onAccept();
        } else {
          onDecline();
        }
        return false; // Parent manages the state; don't auto-remove
      },
      child: Semantics(
        label: '${offer.buyerName} offered ${offer.amountDisplay} for ${offer.itemTitle}. $aiSummary. '
            'Tap Accept or Decline, or swipe right to accept, left to decline.',
        hint: 'Opens response sheet to accept or decline with an optional message',
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(14),
            border: hc.cardBorder,
            boxShadow: [
              BoxShadow(color: hc.shadow, blurRadius: 6, offset: const Offset(0, 1)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Buyer info + amount ──
              Row(
                children: [
                  MemberAvatar(name: offer.buyerName, size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: HuddlText.caption(color: hc.textPrimary),
                            children: [
                              TextSpan(
                                text: offer.buyerName,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const TextSpan(text: ' offered '),
                              TextSpan(
                                text: offer.amountDisplay,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'for ${offer.itemTitle}',
                          style: HuddlText.caption(color: hc.textTertiary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // ── AI summary + inline action buttons ──
              const SizedBox(height: 10),
              Row(
                children: [
                  // AI sentiment indicator
                  Expanded(
                    child: Row(
                      children: [
                        Icon(_sentimentIcon(), size: 14, color: sentColor),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            aiSummary,
                            style: HuddlText.caption(color: sentColor, weight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Decline — subtle, understated
                  Semantics(
                    label: 'Decline offer from ${offer.buyerName}',
                    button: true,
                    child: InkWell(
                      onTap: onDecline,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 38,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        constraints: const BoxConstraints(minWidth: 48),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: hc.divider),
                        ),
                        child: Text(
                          'Decline',
                          style: HuddlText.caption(color: hc.textSecondary, weight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Accept — primary, stands out
                  Semantics(
                    label: 'Accept offer from ${offer.buyerName}',
                    button: true,
                    child: InkWell(
                      onTap: onAccept,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 38,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        constraints: const BoxConstraints(minWidth: 48),
                        decoration: BoxDecoration(
                          color: HuddlColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Accept',
                          style: HuddlText.caption(color: HuddlColors.success, weight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // ── Swipe hint — subtle affordance for discoverability ──
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      'Swipe to respond',
                      style: HuddlText.caption(color: hc.textTertiary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



// ═══════════════════════════════════════════════════════════════════════════════
// FILTER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// ── _FilterIconTile ──────────────────────────────────────────────────────────
// Bordered square tile with icon + label.
// Used in "Recommended for you" quick-filter row inside the filter sheet.
// Selected state: nearBlack border + nearBlack icon/text on white bg.
// Unselected: 1px divider border, grey icon/text.
class _FilterIconTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterIconTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 90,
        decoration: BoxDecoration(
          // Warm peach tint when selected
          color: isSelected
              ? HuddlColors.primaryPale.withValues(alpha: 0.35)
              : (Theme.of(context).brightness == Brightness.dark
                  ? HuddlColors.darkSurface
                  : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? HuddlColors.primary : HuddlColors.divider,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected
                  ? HuddlColors.primary              // orange icon when active
                  : HuddlColors.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: HuddlText.caption(color: HuddlColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _SegmentedPriceControl ───────────────────────────────────────────────────
// 3-segment selection control.
// Segments: All / Free / Paid — with clear border and animated fill.
class _SegmentedPriceControl extends StatelessWidget {
  final PriceType? selected;
  final void Function(PriceType?) onChanged;

  const _SegmentedPriceControl({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const segments = [
      (null,          'All'),
      (PriceType.free, 'Free'),
      (PriceType.paid, 'Paid'),
    ];

    return Container(
      height: 42,
      decoration: BoxDecoration(
        border: Border.all(color: HuddlColors.divider, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: segments.asMap().entries.map((entry) {
          final idx = entry.key;
          final (type, label) = entry.value;
          final isSelected = selected == type;
          final isFirst = idx == 0;
          final isLast = idx == segments.length - 1;

          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected
                      ? HuddlColors.primary              // warm orange fill
                      : Colors.transparent,
                  borderRadius: BorderRadius.horizontal(
                    left: isFirst ? const Radius.circular(11) : Radius.zero,
                    right: isLast ? const Radius.circular(11) : Radius.zero,
                  ),
                  border: !isFirst
                      ? Border(
                          left: BorderSide(
                            color: isSelected
                                ? HuddlColors.primary
                                : HuddlColors.divider,
                            width: 0.5,
                          ),
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: HuddlText.body(),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── _FilterChip (kept as alias → _FilterToggleRow) ──────────────────────────
// Replaced pill design with a clean full-width row toggle.
// Shows label left-aligned + check icon right when selected.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isSelected
              ? HuddlColors.primary.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? HuddlColors.primary.withValues(alpha: 0.5)
                : HuddlColors.divider,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: HuddlText.body(),
              ),
            ),
            if (isSelected)
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: HuddlColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    size: 14, color: Colors.white),
              )
            else
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: HuddlColors.divider, width: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── _MultiSelectChip ─────────────────────────────────────────────────────────
// Same visual style as _FilterChip but uses a square checkbox tick instead of
// a radio dot — signals multi-select semantics to the user.
class _MultiSelectChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MultiSelectChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isSelected
              ? HuddlColors.primary.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? HuddlColors.primary.withValues(alpha: 0.5)
                : HuddlColors.divider,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: HuddlText.body(),
              ),
            ),
            // Square checkbox — visually distinct from radio-style _FilterChip
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected ? HuddlColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isSelected ? HuddlColors.primary : HuddlColors.divider,
                  width: isSelected ? 0 : 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── _PriceHistogram ──────────────────────────────────────────────────────────
// Price distribution histogram shown above the range slider.
// Bars inside the selected range are nearBlack; outside are light grey.
class _PriceHistogram extends StatelessWidget {
  final double low;
  final double high;
  final double maxPrice;

  const _PriceHistogram({
    required this.low,
    required this.high,
    required this.maxPrice,
  });

  // Simulated price distribution curve (bell-ish, weighted toward lower prices)
  static const List<double> _distribution = [
    0.10, 0.18, 0.32, 0.55, 0.72, 0.88, 1.00, 0.95, 0.85, 0.78,
    0.70, 0.62, 0.55, 0.50, 0.46, 0.42, 0.38, 0.35, 0.32, 0.29,
    0.27, 0.25, 0.23, 0.21, 0.20, 0.18, 0.17, 0.16, 0.15, 0.14,
    0.13, 0.12, 0.11, 0.11, 0.10, 0.09, 0.09, 0.08, 0.08, 0.07,
    0.07, 0.06, 0.06, 0.06, 0.05, 0.05, 0.04, 0.04, 0.03, 0.03,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: CustomPaint(
        size: const Size(double.infinity, 48),
        painter: _PriceHistogramPainter(
          low: low,
          high: high,
          maxPrice: maxPrice,
          distribution: _distribution,
        ),
      ),
    );
  }
}

class _PriceHistogramPainter extends CustomPainter {
  final double low;
  final double high;
  final double maxPrice;
  final List<double> distribution;

  const _PriceHistogramPainter({
    required this.low,
    required this.high,
    required this.maxPrice,
    required this.distribution,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = distribution.length;
    final barW = size.width / barCount;
    final lowIdx = ((low / maxPrice) * barCount).floor().clamp(0, barCount - 1);
    final highIdx = ((high / maxPrice) * barCount).ceil().clamp(0, barCount);

    for (int i = 0; i < barCount; i++) {
      final barH = size.height * distribution[i];
      final rect = Rect.fromLTWH(
        i * barW + 1,
        size.height - barH,
        barW - 2,
        barH,
      );
      final isActive = i >= lowIdx && i < highIdx;
      final paint = Paint()
        ..color = isActive
            ? const Color(0xFFFF965C) // Huddl orange — selected range
            : const Color(0xFFD5D5D5) // divider — outside range
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PriceHistogramPainter old) =>
      old.low != low || old.high != high;
}

