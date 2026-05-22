import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // removed — provided by material.dart
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';
import '../../widgets/huddl_widgets.dart';
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



// Marketplace price colour — near-black for a premium, neutral feel
const Color _kMarketBlue = HuddlColors.nearBlack;

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
// PLATFORM-ADAPTIVE TEXT HELPER  (SF Pro on iOS/macOS, Poppins elsewhere)
// =============================================================================
TextStyle _adaptiveText({
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w400,
  Color? color,
  double? height,
  FontStyle? fontStyle,
  double? letterSpacing,
  TextDecoration? decoration,
  Color? decorationColor,
}) {
  return GoogleFonts.poppins(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    fontStyle: fontStyle,
    letterSpacing: letterSpacing,
    decoration: decoration,
    decorationColor: decorationColor,
  );
}

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
  ItemCategory? _selectedCategory;
  PriceType? _selectedPriceType;
  ItemCondition? _selectedCondition;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  // UI state
  bool _isLoadingItems = false;
  bool _isSearchActive = false;

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
    final raw = _service.filter(
      ageStage: _selectedAge,
      category: _selectedCategory,
      condition: _selectedCondition,
      priceType: _selectedPriceType,
      query: _searchQuery,
    );
    // AI always ranks invisibly — no toggle needed
    return _ai.rankItems(raw);
  }

  bool get _hasActiveFilters =>
      _selectedAge != null ||
      _selectedCategory != null ||
      _selectedPriceType != null ||
      _selectedCondition != null;

  void _clearAllFilters() {
    HuddlAnimations.lightTap();
    setState(() {
      _selectedAge = null;
      _selectedCategory = null;
      _selectedPriceType = null;
      _selectedCondition = null;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  int get _activeFilterCount {
    int n = 0;
    if (_selectedAge != null) n++;
    if (_selectedCategory != null) n++;
    if (_selectedPriceType != null) n++;
    if (_selectedCondition != null) n++;
    return n;
  }

  /// Short label shown inside the filter pill when exactly one filter is active.
  String get _activeFilterLabel {
    if (_selectedAge != null) return _selectedAge!.shortLabel;
    if (_selectedCategory != null) return _selectedCategory!.label;
    if (_selectedPriceType == PriceType.free) return 'Free';
    if (_selectedPriceType == PriceType.paid) return 'Paid';
    if (_selectedCondition != null) return _selectedCondition!.label;
    return 'Filter';
  }

  /// Opens a combined filter bottom-sheet that consolidates all four filters.
  void _showAllFiltersSheet(HuddlContextColors hc) {
    HuddlAnimations.selectionClick();

    // Snapshot current values so the sheet StatefulBuilder can mutate locally
    // while also pushing changes back to the parent via setState immediately
    // (live filtering as the user taps — no "Apply" delay).
    AgeStage? sheetAge = _selectedAge;
    ItemCategory? sheetCat = _selectedCategory;
    PriceType? sheetPrice = _selectedPriceType;
    ItemCondition? sheetCond = _selectedCondition;

    showModalBottomSheet(
      context: context,
      backgroundColor: hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final shc = ctx.hc;
          final hasAny = sheetAge != null ||
              sheetCat != null ||
              sheetPrice != null ||
              sheetCond != null;

          // ── Helper: inline chip that selects/deselects on tap ──────────
          Widget chip<T>({
            required String label,
            required bool isSelected,
            required VoidCallback onTap,
            Color? activeColor,
          }) {
            final color = activeColor ?? HuddlColors.primary;
            return GestureDetector(
              onTap: () {
                HuddlAnimations.selectionClick();
                onTap();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.12)
                      : shc.inputBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? color.withValues(alpha: 0.45)
                        : shc.divider,
                    width: 1.2,
                  ),
                ),
                child: Text(
                  label,
                  style: _adaptiveText(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? color : shc.textSecondary,
                  ),
                ),
              ),
            );
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollController) => SafeArea(
              child: Column(
                children: [
                  // ── Fixed header ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const HuddlBottomSheetHandle(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Filters',
                              style: _adaptiveText(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: shc.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            if (hasAny)
                              TextButton(
                                onPressed: () {
                                  setSheetState(() {
                                    sheetAge = null;
                                    sheetCat = null;
                                    sheetPrice = null;
                                    sheetCond = null;
                                  });
                                  setState(() {
                                    _selectedAge = null;
                                    _selectedCategory = null;
                                    _selectedPriceType = null;
                                    _selectedCondition = null;
                                  });
                                },
                                style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap),
                                child: Text(
                                  'Clear all',
                                  style: _adaptiveText(
                                    fontSize: 13,
                                    color: HuddlColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),

                  // ── Scrollable filter sections ─────────────────────────
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      children: [
                        // ── AGE GROUP ──────────────────────────────────
                        Text(
                          'Age group',
                          style: _adaptiveText(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: shc.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // "Any age" clears the age selection
                            chip<void>(
                              label: 'Any age',
                              isSelected: sheetAge == null,
                              onTap: () {
                                setSheetState(() => sheetAge = null);
                                setState(() => _selectedAge = null);
                              },
                            ),
                            ...AgeStage.values.map((age) => chip<AgeStage>(
                                  label: age.shortLabel,
                                  isSelected: sheetAge == age,
                                  onTap: () {
                                    // Tap again to deselect
                                    final next =
                                        sheetAge == age ? null : age;
                                    setSheetState(() => sheetAge = next);
                                    setState(
                                        () => _selectedAge = next);
                                  },
                                )),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── CATEGORY ───────────────────────────────────
                        Text(
                          'Category',
                          style: _adaptiveText(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: shc.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chip<void>(
                              label: 'All',
                              isSelected: sheetCat == null,
                              onTap: () {
                                setSheetState(() => sheetCat = null);
                                setState(
                                    () => _selectedCategory = null);
                              },
                            ),
                            ...ItemCategory.values
                                .map((cat) => chip<ItemCategory>(
                                      label: cat.label,
                                      isSelected: sheetCat == cat,
                                      activeColor: cat.color,
                                      onTap: () {
                                        final next = sheetCat == cat
                                            ? null
                                            : cat;
                                        setSheetState(
                                            () => sheetCat = next);
                                        setState(() =>
                                            _selectedCategory = next);
                                      },
                                    )),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── PRICE ──────────────────────────────────────
                        Text(
                          'Price',
                          style: _adaptiveText(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: shc.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chip<void>(
                              label: 'All prices',
                              isSelected: sheetPrice == null,
                              onTap: () {
                                setSheetState(() => sheetPrice = null);
                                setState(
                                    () => _selectedPriceType = null);
                              },
                            ),
                            chip<PriceType>(
                              label: 'Free',
                              isSelected: sheetPrice == PriceType.free,
                              activeColor: HuddlColors.actionGreen,
                              onTap: () {
                                final next = sheetPrice == PriceType.free
                                    ? null
                                    : PriceType.free;
                                setSheetState(() => sheetPrice = next);
                                setState(
                                    () => _selectedPriceType = next);
                              },
                            ),
                            chip<PriceType>(
                              label: 'Paid',
                              isSelected: sheetPrice == PriceType.paid,
                              activeColor: HuddlColors.amberWarm,
                              onTap: () {
                                final next = sheetPrice == PriceType.paid
                                    ? null
                                    : PriceType.paid;
                                setSheetState(() => sheetPrice = next);
                                setState(
                                    () => _selectedPriceType = next);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── CONDITION ──────────────────────────────────
                        Text(
                          'Condition',
                          style: _adaptiveText(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: shc.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chip<void>(
                              label: 'Any condition',
                              isSelected: sheetCond == null,
                              onTap: () {
                                setSheetState(() => sheetCond = null);
                                setState(
                                    () => _selectedCondition = null);
                              },
                            ),
                            ...ItemCondition.values
                                .map((cond) => chip<ItemCondition>(
                                      label: cond.label,
                                      isSelected: sheetCond == cond,
                                      activeColor: cond.color,
                                      onTap: () {
                                        final next = sheetCond == cond
                                            ? null
                                            : cond;
                                        setSheetState(
                                            () => sheetCond = next);
                                        setState(() =>
                                            _selectedCondition = next);
                                      },
                                    )),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),

                  // ── Fixed "Show items" button ──────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.primary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          'Show items',
                          style: _adaptiveText(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
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
    final result = await Navigator.push<RehomeItem>(
      context,
      MaterialPageRoute(builder: (_) => const CreateListingScreen()),
    );
    if (result != null && mounted) {
      _tabController.animateTo(1);
    }
  }

  void _openItemDetail(RehomeItem item) {
    _ai.recordView(item);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
    );
  }

  void _openEditListing(RehomeItem item) async {
    final result = await Navigator.push<RehomeItem>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateListingScreen(existingItem: item),
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
                  style: _adaptiveText(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: hc.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to delist "${item.title}"? This will remove it from the marketplace.',
                  textAlign: TextAlign.center,
                  style: _adaptiveText(
                    fontSize: 14,
                    color: hc.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'Cancel delisting',
                        button: true,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: hc.divider),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(0, 48),
                          ),
                          child: Text(
                            'Cancel',
                            style: _adaptiveText(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: hc.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        label: 'Confirm delist ${item.title}',
                        button: true,
                        child: ElevatedButton(
                          onPressed: () {
                            HuddlAnimations.mediumTap();
                            Navigator.pop(ctx);
                            _service.deleteListing(item.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle,
                                        color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(
                                            '"${item.title}" has been delisted')),
                                  ],
                                ),
                                backgroundColor: HuddlColors.teal,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HuddlColors.error,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            minimumSize: const Size(0, 48),
                          ),
                          child: Text(
                            'Delist',
                            style: _adaptiveText(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
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
                bottom: 24,
                right: 16,
                child: GestureDetector(
                  onTap: _openCreateListing,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: HuddlColors.nearBlack,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: HuddlColors.nearBlack.withValues(alpha: 0.25),
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
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Market',
                    style: _adaptiveText(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: hc.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Borough scope chip — exactly matches Groups/Discover header chip
                const BoroughScopeChip(feature: HuddlFeature.marketplace),
                const Spacer(),
                // Search icon — top-right, like Discover
                Semantics(
                  label: 'Search market items',
                  button: true,
                  child: IconButton(
                    onPressed: () {
                      setState(() => _isSearchActive = true);
                      Future.microtask(() => _searchFocus.requestFocus());
                    },
                    icon: Icon(
                      Icons.search,
                      color: hc.textSecondary,
                      size: 22,
                    ),
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    tooltip: 'Search',
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
                              style: _adaptiveText(
                                  fontSize: 13, color: hc.textPrimary),
                              decoration: InputDecoration(
                                hintText: _ai.smartPlaceholder(),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isDense: true,
                                hintStyle: _adaptiveText(
                                    fontSize: 13,
                                    color: hc.textTertiary),
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
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Buy'),
              Tab(text: 'Sell'),
              Tab(text: 'Saved'),
            ],
            labelColor: HuddlColors.textDark,
            unselectedLabelColor: hc.textTertiary,
            labelStyle: _adaptiveText(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: _adaptiveText(
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            indicatorColor: HuddlColors.textDark,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: hc.divider,
          ),
        ],
      ),
    );
  }

  // == FILTER BOTTOM SHEETS ==================================================
  // Individual filter sheets are accessed via _showAllFiltersSheet (combined).

  // == BUY TAB — clean, uncluttered ==========================================
  // No AI badges, no thumbs up/down, no smart ranking toggle.
  // AI works silently: ranking results, adapting search placeholder.

  Widget _buildBuyTab(HuddlContextColors hc) {
    final items = _filteredItems;

    return Column(
      children: [
        // ── Filter and sort pill — Groups/Events style ────────────
        Container(
          color: hc.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Semantics(
                label: _hasActiveFilters ? 'Active filters. Tap to change.' : 'Filter and sort items',
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: _hasActiveFilters
                              ? HuddlColors.textDark
                              : hc.textPrimary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _hasActiveFilters && _activeFilterCount > 1
                              ? 'Filter and sort ($_activeFilterCount)'
                              : _hasActiveFilters
                                  ? 'Filter and sort · $_activeFilterLabel'
                                  : 'Filter and sort',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _hasActiveFilters
                                ? HuddlColors.textDark
                                : hc.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (_hasActiveFilters)
                GestureDetector(
                  onTap: _clearAllFilters,
                  child: Text(
                    'Clear all',
                    style: _adaptiveText(
                      fontSize: 12,
                      color: HuddlColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Item count row
        Semantics(
          liveRegion: true,
          child: Container(
            color: hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${items.length} item${items.length == 1 ? '' : 's'}${_hasActiveFilters ? ' (filtered)' : ''}${_searchQuery.isNotEmpty ? ' matching “$_searchQuery”' : ''}',
                style: _adaptiveText(fontSize: 11, color: hc.textTertiary),
              ),
            ),
          ),
        ),
        // 2-column grid (compact cards) — richer browse experience
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState(
                  hc: hc,
                  illustration: 'marketplace',
                  title: 'No items found',
                  subtitle: _hasActiveFilters || _searchQuery.isNotEmpty
                      ? 'Try adjusting your filters to see more results.'
                      : 'Nothing listed yet. Check back soon!',
                  action: (_hasActiveFilters || _searchQuery.isNotEmpty)
                      ? Semantics(
                          label: 'Clear all filters',
                          button: true,
                          child: TextButton.icon(
                            onPressed: () {
                              _clearAllFilters();
                              setState(() => _searchQuery = '');
                              _searchController.clear();
                            },
                            icon: const Icon(Icons.filter_list_off, size: 18),
                            label: Text('Clear filters',
                                style: _adaptiveText(
                                    fontWeight: FontWeight.w500)),
                          ),
                        )
                      : null,
                )
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
                  // ── 2-column grid ─────────────────────────────────────
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        final isOwn =
                            uid != null && items[index].sellerId == uid;
                        return _MarketGridCard(
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

    // Separate active vs sold — show full sold history, no time filter
    final active = myListings.where((i) => !i.isSold).toList();
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
                style: _adaptiveText(fontSize: 11, color: hc.textTertiary),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState(
                    hc: hc,
                    illustration: 'marketplace',
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
          // ── Single-tap listing prompt — AI adapts the copy ──
          _buildSellCTA(hc),

          // ── Adaptive section ordering ──
          if (offersFirst && offers.isNotEmpty) ...[
            _buildOffersSection(hc, offers),
            if (active.isNotEmpty) _buildListingsSection(hc, active, 'Active listings'),
            if (recentlySold.isNotEmpty) _buildSoldSection(hc, recentlySold),
          ] else ...[
            if (active.isNotEmpty) _buildListingsSection(hc, active, 'My listings'),
            if (offers.isNotEmpty) _buildOffersSection(hc, offers),
            if (recentlySold.isNotEmpty) _buildSoldSection(hc, recentlySold),
          ],

          // ── Empty state ──
          // liveRegion: screen readers announce when seller's listings become empty
          if (active.isEmpty && offers.isEmpty && sold.isEmpty)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: _buildEmptyState(
                  hc: hc,
                  illustration: 'marketplace',
                  title: 'No listings yet',
                  subtitle: 'Tap above to snap a photo and list your first item.',
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
                  style: _adaptiveText(fontSize: 11, color: hc.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
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
                        color: HuddlColors.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.camera_alt_rounded,
                          color: HuddlColors.textSecondary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _ai.sellPrompt(),
                        style: _adaptiveText(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: hc.textPrimary,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 13, color: hc.textTertiary),
                  ],
                ),
                // P12: listing usage indicator for capped tiers
                if (isCapped) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 48), // align under text
                      Text(
                        '$usedListings / $maxListings listings used',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: usedListings >= maxListings
                              ? Colors.red.shade400
                              : HuddlColors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
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
                  style: _adaptiveText(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: hc.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${listings.length}',
                  style: _adaptiveText(
                    fontSize: 12,
                    color: hc.textTertiary,
                  ),
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
            style: _adaptiveText(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: hc.textTertiary,
            ),
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
                  style: _adaptiveText(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: hc.textPrimary,
                  ),
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
                    style: _adaptiveText(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textSecondary,
                    ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                                style: _adaptiveText(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: shc.textPrimary,
                                ),
                              ),
                              Text(
                                '${offer.buyerName} · ${offer.amountDisplay} for ${offer.itemTitle}',
                                style: _adaptiveText(
                                  fontSize: 12,
                                  color: shc.textTertiary,
                                ),
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
                      style: _adaptiveText(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: shc.textSecondary,
                      ),
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
                        style: _adaptiveText(fontSize: 14, color: shc.textPrimary),
                        decoration: InputDecoration(
                          hintText: isAccept
                              ? 'e.g. "Great! Please get in touch to arrange pick-up."'
                              : 'e.g. "Sorry, I\'ve had another offer."',
                          hintStyle: _adaptiveText(
                              fontSize: 13, color: shc.textTertiary),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(14),
                          counterStyle: _adaptiveText(
                              fontSize: 11, color: shc.textTertiary),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Quick-reply suggestions ──────────────────────────
                    Text(
                      'Quick replies',
                      style: _adaptiveText(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: shc.textTertiary,
                      ),
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
                              style: _adaptiveText(
                                fontSize: 13,
                                color: msgController.text == reply
                                    ? accentColor
                                    : shc.textSecondary,
                              ),
                            ),
                          ),
                        )),
                    const SizedBox(height: 20),

                    // ── Action buttons ───────────────────────────────────
                    Row(
                      children: [
                        // Cancel
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: shc.divider),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              'Cancel',
                              style: _adaptiveText(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: shc.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Confirm action
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
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
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              actionLabel,
                              style: _adaptiveText(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                        child: Image.network(
                          item.imageUrls.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: HuddlColors.background,
                            child: Icon(item.category.icon, size: 22, color: HuddlColors.textHint),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title,
                            style: _adaptiveText(fontSize: 14, fontWeight: FontWeight.w600, color: hc.textPrimary),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(item.priceDisplay,
                            style: _adaptiveText(fontSize: 13, color: _kMarketBlue, fontWeight: FontWeight.w500)),
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
                      backgroundColor: HuddlColors.teal,
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
          style: _adaptiveText(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: isDestructive ? HuddlColors.error : hc.textPrimary,
          )),
        onTap: onTap,
        minTileHeight: 48,
      ),
    );
  }

  // == SAVED TAB =============================================================

  Widget _buildSavedTab(HuddlContextColors hc) {
    final allSaved = _service.savedItems;

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
        child: _buildEmptyState(
          hc: hc,
          illustration: 'saved',
          title: 'No saved items',
          subtitle: 'Tap the heart on items you love\nto save them here.',
        ),
      );
    }

    return Column(
      children: [
        // Count row
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${saved.length} saved item${saved.length == 1 ? '' : 's'}${q.isNotEmpty ? ' matching "$_searchQuery"' : ''}',
                style: _adaptiveText(fontSize: 11, color: hc.textTertiary),
              ),
            ),
          ),
        ),
        Expanded(
          child: saved.isEmpty
              ? _buildEmptyState(
                  hc: hc,
                  illustration: 'saved',
                  title: 'No saved items found',
                  subtitle: 'Try a different search term.',
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

  // == EMPTY STATE ===========================================================

  Widget _buildEmptyState({
    // hc kept for call-site compatibility — unused after migration
    required HuddlContextColors hc,
    // illustration kept for call-site compatibility — mood derived internally
    required String illustration,
    required String title,
    required String subtitle,
    Widget? action,
    // ignore: unused_element_parameter
    IconData? icon,
  }) {
    // Derive mood from the legacy illustration constant
    final mood = illustration.contains('saved')
        ? HuddlMood.neutral
        : illustration.contains('marketplace')
            ? HuddlMood.curious
            : HuddlMood.neutral;

    if (action != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              HuddlEmptyState(mood: mood, title: title, subtitle: subtitle),
              const SizedBox(height: 8),
              action,
            ],
          ),
        ),
      );
    }
    return HuddlEmptyState(mood: mood, title: title, subtitle: subtitle);
  }

  // == FAB removed — now rendered as Positioned inside Stack in build() ==
  // Matches Groups/Meetups pattern: Positioned(bottom:24, right:16).
}

// =============================================================================
// SHARED IMAGE HELPER — handles data:URI (base64), http, and empty URLs
// =============================================================================

// =============================================================================
// SHIMMER WIDGET — pure-Dart animated shimmer, no external package required.
// Used as a loading placeholder for all image areas in the Market module.
//
// Usage:
//   _ShimmerBox(width: double.infinity, height: double.infinity)
//   _ShimmerBox(width: 64, height: 64, radius: 10)
// =============================================================================
class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 0,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8);
    final highlight = isDark ? const Color(0xFF3D3D3D) : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value + 1, 0),
            colors: [base, highlight, base],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

Widget _buildItemImage(String url, RehomeItem item) {
  final fallback = Container(
    color: HuddlColors.background,
    child: Center(
      child: Icon(item.category.icon,
          size: 44, color: item.category.color.withValues(alpha: 0.5)),
    ),
  );
  if (url.isEmpty) return fallback;
  if (url.startsWith('data:')) {
    try {
      final comma = url.indexOf(',');
      if (comma >= 0) {
        final bytes = base64Decode(url.substring(comma + 1));
        return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => fallback);
      }
    } catch (_) {}
    return fallback;
  }
  if (url.startsWith('http')) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return const _ShimmerBox(width: double.infinity, height: double.infinity);
      },
    );
  }
  return fallback;
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
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
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
              // ── Image area (⅝ of card height) ────────────────────────────────
              // GridView.builder provides tight box constraints to each cell
              // so Expanded works correctly here.
              Expanded(
                flex: 5,
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
                                style: _adaptiveText(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Condition badge — top-right
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: item.isFree
                              ? HuddlColors.teal.withValues(alpha: 0.90)
                              : Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item.isFree ? 'Free' : item.condition.label,
                          style: _adaptiveText(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
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
                            color: Colors.white.withValues(alpha: 0.92),
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
              // ── Card body (⅗ of card height) ────────────────────────────────
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category row + price right-aligned
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              item.category.label.toUpperCase(),
                              style: _adaptiveText(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: hc.textTertiary,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            item.priceDisplay,
                            style: _adaptiveText(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: item.isFree ? HuddlColors.teal : _kMarketBlue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Title
                      Expanded(
                        child: Text(
                          item.title,
                          style: _adaptiveText(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: hc.textPrimary,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
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
                              style: _adaptiveText(
                                fontSize: 11,
                                color: hc.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ), // SizedBox.expand
    );
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
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: hc.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
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
                      // Free badge — top-left (teal, matches Services 'Parent Added')
                      if (item.isFree)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: _MarketBadgePill(
                            label: 'Free',
                            color: HuddlColors.teal,
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
                              color: Colors.white.withValues(alpha: 0.92),
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
                            style: _adaptiveText(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: hc.textTertiary,
                            ),
                          ),
                          const Spacer(),
                          // Price — right-aligned in category row
                          Text(
                            item.priceDisplay,
                            style: _adaptiveText(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: item.isFree
                                  ? HuddlColors.teal
                                  : _kMarketBlue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Title
                      Text(
                        item.title,
                        style: _adaptiveText(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: hc.textPrimary,
                        ),
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
                              style: _adaptiveText(
                                fontSize: 12,
                                color: hc.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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
                                      color: HuddlColors.background,
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
                          style: _adaptiveText(
                            fontSize: 12,
                            color: hc.textTertiary,
                          ),
                        ),
                      ),
                      // Action pill — matches Events "Join" pill exactly
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: HuddlColors.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Message',
                          style: _adaptiveText(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark,
                          ),
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
      case 'new':       return HuddlColors.teal;
      case 'like new':  return HuddlColors.blueDark;
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
    final priceColor = item.isFree ? HuddlColors.teal : _kMarketBlue;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
                    ? Image.network(
                        item.imageUrls.first,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _MarketPhotoFallback(item: item),
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return const _ShimmerBox(width: 64, height: 64, radius: 10);
                        },
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
                    style: _adaptiveText(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: hc.textTertiary,
                      letterSpacing: 0.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Title
                  Text(
                    item.title,
                    style: _adaptiveText(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: hc.textPrimary,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  // Location row
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: hc.textTertiary),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          item.sellerLocation.isNotEmpty
                              ? item.sellerLocation
                              : 'Near you',
                          style: _adaptiveText(
                              fontSize: 11,
                              color: hc.textTertiary,
                              fontStyle: FontStyle.italic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                      style: _adaptiveText(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: badgeFg,
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                // Price pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: item.isFree
                        ? HuddlColors.teal.withValues(alpha: 0.10)
                        : HuddlColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    priceStr,
                    style: _adaptiveText(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: priceColor,
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
      case 'new':       return HuddlColors.teal;
      case 'like new':  return HuddlColors.blueDark;
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
    final priceColor = item.isFree ? HuddlColors.teal : _kMarketBlue;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        // Full-width card — same shape/shadow as Groups discover card
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
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
                      ? Image.network(
                          item.imageUrls.first,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorBuilder: (_, __, ___) => _MarketPhotoFallback(item: item),
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return const _ShimmerBox(
                                width: double.infinity, height: 160);
                          },
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
                        style: _adaptiveText(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
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
                              style: _adaptiveText(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
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
                    style: _adaptiveText(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: hc.textTertiary,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Title — bold dark
                  Text(
                    item.title,
                    style: _adaptiveText(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: hc.textPrimary,
                      height: 1.3,
                    ),
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
                            style: _adaptiveText(
                              fontSize: 12,
                              color: hc.textTertiary,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),

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
                                        color: HuddlColors.background,
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
                      // "Near you" or empty space
                      Expanded(
                        child: Text(
                          'Near you',
                          style: _adaptiveText(fontSize: 11, color: hc.textTertiary),
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
                      // Price pill (Groups "Join" button pattern — grey pill)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: item.isFree
                              ? HuddlColors.teal.withValues(alpha: 0.10)
                              : HuddlColors.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          priceStr,
                          style: _adaptiveText(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: priceColor,
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
      color: HuddlColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.category.icon, size: 44, color: HuddlColors.textHint.withValues(alpha: 0.5)),
            const SizedBox(height: 6),
            Text(
              item.category.label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: HuddlColors.textHint,
              ),
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
    this.isOwn = false,
  });

  @override
  State<_MarketGridCard> createState() => _MarketGridCardState();
}

class _MarketGridCardState extends State<_MarketGridCard> {

  Color _conditionColor(String condition) {
    switch (condition.toLowerCase()) {
      case 'new':
        return HuddlColors.teal;
      case 'like new':
        return HuddlColors.blueDark;
      case 'good':
        return HuddlColors.primary;
      default:
        return HuddlColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hc = context.hc;
    final hasImage = item.imageUrls.isNotEmpty;
    final condColor = _conditionColor(item.condition.label);

    return Semantics(
      label:
          '${item.title}, £${item.price.toStringAsFixed(0)}, ${item.condition.label}',
      button: true,
      child: ScaleOnPress(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Product image ──────────────────────────────────────────
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: AspectRatio(
                  aspectRatio: 1.05,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Image or placeholder
                      hasImage
                          ? Image.network(
                              item.imageUrls.first,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _gridPlaceholder(hc, item),
                              loadingBuilder: (_, child, progress) =>
                                  progress == null
                                      ? child
                                      : Container(
                                          color: hc.surfaceAlt,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: HuddlColors.textTertiary,
                                            ),
                                          ),
                                        ),
                            )
                          : _gridPlaceholder(hc, item),

                      // Condition badge OR "Your listing" — top-left
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.isOwn
                                ? HuddlColors.textTertiary
                                : condColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.isOwn ? 'Your listing' : item.condition.label,
                            style: _adaptiveText(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      // Save / heart — top-right (hidden for own listings)
                      if (!widget.isOwn)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: hc.surface.withValues(alpha: 0.88),
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
                    ],
                  ),
                ),
              ),

              // ── Info area ──────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _adaptiveText(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: hc.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Price
                      Text(
                        '£${item.price % 1 == 0 ? item.price.toInt() : item.price.toStringAsFixed(2)}',
                        style: _adaptiveText(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _kMarketBlue,
                        ),
                      ),
                      const Spacer(),
                      // Location row
                      if (item.sellerLocation.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 11, color: hc.textTertiary),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                item.sellerLocation,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _adaptiveText(
                                  fontSize: 10.5,
                                  color: hc.textTertiary,
                                ),
                              ),
                            ),
                          ],
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
    return Container(
      color: hc.surfaceAlt,
      child: Center(
        child: Icon(Icons.child_care_outlined,
            size: 36, color: hc.textTertiary.withValues(alpha: 0.4)),
      ),
    );
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
        style: _adaptiveText(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
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
      'relist' => HuddlColors.teal,
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
                                  style: _adaptiveText(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
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
                                    style: _adaptiveText(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: widget.isSold
                                          ? hc.textTertiary
                                          : hc.textPrimary,
                                    ),
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
                                  style: _adaptiveText(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: widget.isSold
                                        ? hc.textTertiary
                                        : item.isFree
                                            ? HuddlColors.teal
                                            : _kMarketBlue,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ExcludeSemantics(
                                  child: Text(
                                    '${item.viewCount} views \u2022 ${item.timeAgo}',
                                    style: _adaptiveText(
                                      fontSize: 11,
                                      color: hc.textTertiary,
                                    ),
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
                                  style: _adaptiveText(
                                    fontSize: 12,
                                    color: _insightColor(insight.type),
                                    fontWeight: FontWeight.w500,
                                  ),
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
                style: _adaptiveText(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.error,
                ),
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
              style: _adaptiveText(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: HuddlColors.success,
              ),
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
              style: _adaptiveText(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: HuddlColors.error,
              ),
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
                            style: _adaptiveText(
                              fontSize: 13.5,
                              color: hc.textPrimary,
                            ),
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
                          style: _adaptiveText(fontSize: 12, color: hc.textTertiary),
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
                            style: _adaptiveText(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: sentColor,
                            ),
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
                          style: _adaptiveText(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: hc.textSecondary,
                          ),
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
                          style: _adaptiveText(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.success,
                          ),
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
                      style: _adaptiveText(
                        fontSize: 10,
                        color: hc.textTertiary,
                      ),
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


