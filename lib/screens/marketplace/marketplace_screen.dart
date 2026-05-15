import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/rehome_service.dart';
import '../../services/firestore_service.dart';
import '../../services/huddl_notification_service.dart';
import '../../services/backend_api_service.dart';
import 'item_detail_screen.dart';
import '../rehome/create_listing_screen.dart';
import '../../widgets/borough_badge.dart';
import '../../services/borough_scope_guard.dart';
import '../../widgets/common/huddl_empty_state.dart';



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
  final bool isApple =
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);
  if (isApple) {
    return TextStyle(
      fontFamily: '.SF Pro Text',
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
  bool _showSuggestions = false;
  bool _isLoadingItems = false;

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
    _searchFocus.addListener(() {
      if (mounted) setState(() => _showSuggestions = _searchFocus.hasFocus);
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

      // ── 1. Listings ────────────────────────────────────────────────────────
      final docs = await FirestoreService().getMarketplaceListings();
      for (final d in docs) {
        final item = RehomeItem.fromFirestore(d);
        if (item.id.isEmpty) continue;
        // Avoid duplicates (item already added by a local create action)
        if (_service.allItems.any((i) => i.id == item.id)) continue;
        _service.addListing(item);
        // Track own listings
        if (uid != null && item.sellerId == uid) {
          _service.addMyListing(item);
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
    HapticFeedback.lightImpact();
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
    HapticFeedback.selectionClick();

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
                HapticFeedback.selectionClick();
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
                                    color: HuddlColors.primary,
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
    HapticFeedback.mediumImpact();
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
                            HapticFeedback.mediumImpact();
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
        child: Column(
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
      ),
      floatingActionButton: _buildFAB(context, hc),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            ],
          ),
          const SizedBox(height: 8),
          // Borough scope context for marketplace (Buy/Sell and Offers = borough-only)
          const BoroughHeader(
            feature: HuddlFeature.marketplace,  // Buy/Sell/Offers all borough-only
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Buy'),
              Tab(text: 'Sell'),
              Tab(text: 'Saved'),
            ],
            labelColor: HuddlColors.primary,
            unselectedLabelColor: hc.textTertiary,
            labelStyle: _adaptiveText(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: _adaptiveText(
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            indicatorColor: HuddlColors.yellow,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: hc.divider,
          ),
        ],
      ),
    );
  }

  // == FILTER BAR ============================================================

  Widget _buildFilterBar(HuddlContextColors hc) {
    return Container(
      color: hc.surface,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _FilterChip(
              label: _selectedAge?.shortLabel ?? 'For age',
              icon: Icons.child_care,
              isActive: _selectedAge != null,
              onTap: () => _showAgeSheet(hc),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: _selectedCategory?.label ?? 'Category',
              icon: Icons.category_outlined,
              isActive: _selectedCategory != null,
              onTap: () => _showCategorySheet(hc),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: _selectedPriceType == PriceType.free
                  ? 'Free'
                  : _selectedPriceType == PriceType.paid
                      ? 'Paid'
                      : 'Price',
              icon: Icons.sell_outlined,
              isActive: _selectedPriceType != null,
              onTap: () => _showPriceSheet(hc),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: _selectedCondition?.label ?? 'Condition',
              icon: Icons.star_outline,
              isActive: _selectedCondition != null,
              onTap: () => _showConditionSheet(hc),
            ),
          ],
        ),
      ),
    );
  }

  // == FILTER BOTTOM SHEETS ==================================================

  void _showAgeSheet(HuddlContextColors hc) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AgeFilterSheet(
        selected: _selectedAge,
        onSelect: (age) {
          HapticFeedback.selectionClick();
          setState(() => _selectedAge = age);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showCategorySheet(HuddlContextColors hc) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategoryFilterSheet(
        selected: _selectedCategory,
        onSelect: (cat) {
          HapticFeedback.selectionClick();
          setState(() => _selectedCategory = cat);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showPriceSheet(HuddlContextColors hc) {
    HapticFeedback.selectionClick();
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Price',
                  style: _adaptiveText(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: hc.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _sheetOption('All prices', _selectedPriceType == null, hc, () {
                HapticFeedback.selectionClick();
                setState(() => _selectedPriceType = null);
                Navigator.pop(context);
              }),
              _sheetOption(
                  'Free only', _selectedPriceType == PriceType.free, hc, () {
                HapticFeedback.selectionClick();
                setState(() => _selectedPriceType = PriceType.free);
                Navigator.pop(context);
              }),
              _sheetOption('Paid only', _selectedPriceType == PriceType.paid,
                  hc, () {
                HapticFeedback.selectionClick();
                setState(() => _selectedPriceType = PriceType.paid);
                Navigator.pop(context);
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showConditionSheet(HuddlContextColors hc) {
    HapticFeedback.selectionClick();
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
              Text(
                'Condition',
                style: _adaptiveText(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: hc.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _sheetOption('All conditions', _selectedCondition == null, hc,
                  () {
                HapticFeedback.selectionClick();
                setState(() => _selectedCondition = null);
                Navigator.pop(context);
              }),
              ...ItemCondition.values.map((c) => _sheetOption(
                    c.label,
                    _selectedCondition == c,
                    hc,
                    () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedCondition = c);
                      Navigator.pop(context);
                    },
                  )),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetOption(
      String label, bool isSelected, HuddlContextColors hc, VoidCallback onTap) {
    return Semantics(
      label: '$label filter option${isSelected ? ", currently selected" : ""}',
      button: true,
      child: ListTile(
        title: Text(
          label,
          style: _adaptiveText(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? HuddlColors.primary : hc.textPrimary,
          ),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle,
                color: HuddlColors.primary, size: 22)
            : null,
        onTap: onTap,
        minTileHeight: 48,
      ),
    );
  }

  // == BUY TAB — clean, uncluttered ==========================================
  // No AI badges, no thumbs up/down, no smart ranking toggle.
  // AI works silently: ranking results, adapting search placeholder.

  Widget _buildBuyTab(HuddlContextColors hc) {
    final items = _filteredItems;
    final suggestions = _ai.searchSuggestions(_searchQuery);

    return Column(
      children: [
        // ── Unified search + filter bar ───────────────────────────
        Container(
          color: hc.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  // Search pill
                  Expanded(
                    child: Semantics(
                      label: 'Search market items',
                      textField: true,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: hc.inputBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          textAlignVertical: TextAlignVertical.center,
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                              _showSuggestions = val.isEmpty && _searchFocus.hasFocus;
                            });
                          },
                          onSubmitted: (val) {
                            _ai.recordSearch(val);
                            _searchFocus.unfocus();
                          },
                          style: _adaptiveText(fontSize: 13, color: hc.textPrimary),
                          decoration: InputDecoration(
                            hintText: _ai.smartPlaceholder(),
                            hintStyle: _adaptiveText(fontSize: 13, color: hc.textTertiary),
                            prefixIcon: Icon(Icons.search, size: 18,
                                color: hc.textTertiary.withValues(alpha: 0.7)),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? Semantics(
                                    label: 'Clear search',
                                    button: true,
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        _searchController.clear();
                                        setState(() {
                                          _searchQuery = '';
                                          _showSuggestions = false;
                                        });
                                      },
                                      child: Icon(Icons.close, size: 16,
                                          color: hc.textTertiary),
                                    ),
                                  )
                                : null,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Filter pill button
                  Semantics(
                    label: _hasActiveFilters ? 'Filters active. Tap to change.' : 'Filter items',
                    button: true,
                    child: GestureDetector(
                      onTap: () => _showAllFiltersSheet(hc),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: _hasActiveFilters
                              ? HuddlColors.primary.withValues(alpha: 0.12)
                              : hc.inputBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _hasActiveFilters
                                ? HuddlColors.primary.withValues(alpha: 0.4)
                                : Colors.transparent,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 16,
                              color: _hasActiveFilters
                                  ? HuddlColors.primary
                                  : hc.textTertiary,
                            ),
                            if (_hasActiveFilters) ...[
                              const SizedBox(width: 4),
                              Text(
                                _activeFilterCount > 1
                                    ? '$_activeFilterCount'
                                    : _activeFilterLabel,
                                style: _adaptiveText(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.primary,
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
              // Search suggestions
              if (_showSuggestions && suggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: suggestions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final isRecent = _ai._recentSearches.contains(suggestions[i]);
                      return Semantics(
                        label: 'Search for ${suggestions[i]}',
                        button: true,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _searchController.text = suggestions[i];
                            setState(() {
                              _searchQuery = suggestions[i];
                              _showSuggestions = false;
                              _searchFocus.unfocus();
                            });
                            _ai.recordSearch(suggestions[i]);
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: hc.inputBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: hc.divider),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isRecent)
                                  Icon(Icons.history, size: 12,
                                      color: hc.textTertiary),
                                if (isRecent) const SizedBox(width: 4),
                                Text(
                                  suggestions[i],
                                  style: _adaptiveText(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: hc.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        // ── Filter chips row (always visible) ────────────────────
        _buildFilterBar(hc),
        // Item count
        Semantics(
          liveRegion: true,
          child: Container(
            color: hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Row(
              children: [
                Text(
                  '${items.length} item${items.length == 1 ? '' : 's'}${_hasActiveFilters ? ' (filtered)' : ''}',
                  style: _adaptiveText(fontSize: 11, color: hc.textTertiary),
                ),
                const Spacer(),
                if (_hasActiveFilters)
                  GestureDetector(
                    onTap: _clearAllFilters,
                    child: Text(
                      'Clear all',
                      style: _adaptiveText(
                        fontSize: 11,
                        color: HuddlColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Grid or empty state
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState(
                  hc: hc,
                  illustration: HuddlIllustration.marketplaceEmpty,
                  title: 'No items found',
                  subtitle: _hasActiveFilters
                      ? 'Try adjusting your filters to see more results.'
                      : 'Nothing listed yet. Check back soon!',
                  action: _hasActiveFilters
                      ? Semantics(
                          label: 'Clear all filters',
                          button: true,
                          child: TextButton.icon(
                            onPressed: _clearAllFilters,
                            icon: const Icon(Icons.filter_list_off, size: 18),
                            label: Text('Clear filters',
                                style: _adaptiveText(
                                    fontWeight: FontWeight.w500)),
                          ),
                        )
                      : null,
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _ProductCard(
                    item: items[index],
                    onTap: () => _openItemDetail(items[index]),
                    onToggleSave: () {
                      HapticFeedback.lightImpact();
                      final item = items[index];
                      if (!item.isSaved) {
                        _ai.recordSave(item);
                      } else {
                        _ai.recordUnsave(item);
                      }
                      _service.toggleSaved(item.id);
                    },
                    onDismiss: () {
                      // Long-press "not interested" — feeds negative signal
                      HapticFeedback.mediumImpact();
                      _ai.recordDismiss(items[index]);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                              'Got it. You\'ll see fewer like this.'),
                          backgroundColor: hc.textSecondary,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
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

    // Separate active vs sold for adaptive display
    final active = myListings.where((i) => !i.isSold).toList();
    final sold = myListings.where((i) => i.isSold).toList();
    // Auto-collapse: only show recently-sold (within 48h)
    final recentlySold = sold.where((i) {
      return DateTime.now().difference(i.listedAt).inHours < 48;
    }).toList();

    return RefreshIndicator(
      color: HuddlColors.primary,
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          // ── Single-tap listing prompt — AI adapts the copy ──
          _buildSellCTA(hc),

          // ── Quick sell suggestions — trending categories ──
          _buildQuickSellChips(hc),

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
          if (active.isEmpty && offers.isEmpty && recentlySold.isEmpty)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: _buildEmptyState(
                  hc: hc,
                  illustration: HuddlIllustration.marketplaceEmpty,
                  title: 'No listings yet',
                  subtitle: 'Tap above to snap a photo and list your first item.',
                ),
              ),
            ),

          // ── AI transparency note (subtle, non-intrusive) ──
          if (active.isNotEmpty || offers.isNotEmpty)
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

  // ── Sell CTA Card — one tappable surface, AI-adapted copy ──
  Widget _buildSellCTA(HuddlContextColors hc) {
    return Semantics(
      label: 'Create a new listing',
      hint: 'Opens listing form. AI will pre-fill details from your photo.',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _openCreateListing,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(16),
              border: hc.cardBorder,
              boxShadow: [
                BoxShadow(color: hc.shadow, blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: HuddlColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _ai.sellPrompt(),
                        style: _adaptiveText(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: hc.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _ai.sellSubtitle(),
                        style: _adaptiveText(fontSize: 12, color: hc.textTertiary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 14, color: hc.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Quick sell suggestion chips — AI-driven trending categories ──
  // Progressive disclosure: only appears after first use.
  // Contextual intelligence: categories adapt based on community demand.
  Widget _buildQuickSellChips(HuddlContextColors hc) {
    final suggestions = _ai.quickSellSuggestions();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            return Semantics(
              label: 'Quick list ${suggestions[i]}',
              button: true,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _openCreateListing();
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: hc.surfaceAlt,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: hc.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 14, color: HuddlColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        suggestions[i],
                        style: _adaptiveText(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: hc.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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
                HapticFeedback.mediumImpact();
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
            'Recently sold',
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
                    color: HuddlColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${offers.length}',
                    style: _adaptiveText(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.primary,
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
    HapticFeedback.mediumImpact();
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
                            HapticFeedback.selectionClick();
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
    HapticFeedback.mediumImpact();
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
                            color: HuddlColors.primary.withValues(alpha: 0.08),
                            child: Icon(item.category.icon, size: 22, color: HuddlColors.primary),
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
                            style: _adaptiveText(fontSize: 13, color: HuddlColors.primary, fontWeight: FontWeight.w500)),
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
                  HapticFeedback.mediumImpact();
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
                  HapticFeedback.mediumImpact();
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
    final saved = _service.savedItems;
    if (saved.isEmpty) {
      // liveRegion: screen readers announce when saved list becomes empty
      return Semantics(
        liveRegion: true,
        child: _buildEmptyState(
          hc: hc,
          illustration: HuddlIllustration.saved,
          title: 'No saved items',
          subtitle: 'Tap the heart on items you love\nto save them here.',
        ),
      );
    }

    return Column(
      children: [
        // liveRegion: screen readers announce saved-item count changes
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${saved.length} saved item${saved.length == 1 ? '' : 's'}',
                style: _adaptiveText(
                  fontSize: 11,
                  color: hc.textTertiary,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.62,
            ),
            itemCount: saved.length,
            itemBuilder: (context, index) => _ProductCard(
              item: saved[index],
              onTap: () => _openItemDetail(saved[index]),
              onToggleSave: () {
                HapticFeedback.lightImpact();
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
    required HuddlContextColors hc,
    required String illustration,
    required String title,
    required String subtitle,
    Widget? action,
    // Legacy icon param kept for call-sites that use action widgets inline
    IconData? icon,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              illustration,
              height: 160,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  icon ?? Icons.storefront_outlined,
                  size: 40,
                  color: HuddlColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: _adaptiveText(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: hc.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: _adaptiveText(
                fontSize: 14,
                color: hc.textTertiary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }

  // == FAB =================================================================
  // Material You: FAB on both Buy and Sell tabs (Android pattern).
  // On Buy: "+" for new listing. On Sell: "+" for new listing (contextual).

  Widget? _buildFAB(BuildContext context, HuddlContextColors hc) {
    // Show FAB on Buy (0) and Sell (1) tabs
    if (_tabController.index > 1) return null;

    final bool isSellTab = _tabController.index == 1;

    // Compute how far above the bottom edge the FAB must sit so it clears
    // the floating bottom nav bar:
    //   • safeArea.bottom  → iPhone home-indicator inset (~34 pt on modern iPhones)
    //   • + 12 pt          → bottom padding applied to the nav bar container
    //   • + 70 pt          → nav bar container height
    //   • + 12 pt          → breathing room between FAB and nav bar
    final double bottomInset = MediaQuery.of(context).padding.bottom + 12 + 70 + 12;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Semantics(
        label: isSellTab ? 'Create new listing' : 'Create new listing',
        hint: 'Opens the listing creation form',
        button: true,
        child: Material(
          elevation: 6,
          shadowColor: HuddlColors.primary.withValues(alpha: 0.4),
          shape: const CircleBorder(),
          color: HuddlColors.primary,
          child: InkWell(
            onTap: _openCreateListing,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// AI ASSISTANT BOTTOM SHEET — progressive disclosure entry point v2
//
// Accessed via the subtle sparkle icon. Context-aware:
// - On Buy tab: search, voice search, chat
// =============================================================================
// FILTER CHIP -- 48dp minimum touch target, accessible, dark-mode aware
// =============================================================================

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final Color bgColor = isActive
            ? HuddlColors.primary.withValues(alpha: 0.1)
            : hc.inputBg;
    final Color fgColor = isActive
            ? HuddlColors.primary
            : hc.textSecondary;

    return Semantics(
      label: '$label filter${isActive ? ", active" : ""}',
      button: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? HuddlColors.primary.withValues(alpha: 0.3)
                  : hc.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fgColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: _adaptiveText(
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: fgColor,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 3),
                Icon(Icons.keyboard_arrow_down, size: 16, color: fgColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SHARED IMAGE HELPER — handles data:URI (base64), http, and empty URLs
// =============================================================================

Widget _buildItemImage(String url, RehomeItem item) {
  final fallback = Container(
    color: HuddlColors.primary.withValues(alpha: 0.08),
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
    return Image.network(url, fit: BoxFit.cover, width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => fallback);
  }
  return fallback;
}

// =============================================================================
// PRODUCT CARD — clean, no AI badges, no thumbs up/down
// Long-press triggers "not interested" feedback (invisible AI signal)
// =============================================================================

class _ProductCard extends StatefulWidget {
  final RehomeItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;
  final VoidCallback? onDismiss;

  const _ProductCard({
    required this.item,
    required this.onTap,
    required this.onToggleSave,
    this.onDismiss,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartAnim;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _heartScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _heartAnim, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _heartAnim.dispose();
    super.dispose();
  }

  void _onSaveTap() {
    _heartAnim.forward(from: 0);
    widget.onToggleSave();
  }

  void _onLongPress() {
    if (widget.onDismiss != null) {
      widget.onDismiss!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hc = context.hc;

    return Semantics(
      label: '${item.title}, ${item.priceDisplay}, ${item.condition.label}, '
          '${item.ageStage.shortLabel}, ${item.sellerLocation}. '
          'Long press to dismiss.',
      button: true,
      child: GestureDetector(
        onLongPress: _onLongPress,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(16),
              border: hc.cardBorder,
              boxShadow: [
                BoxShadow(
                  color: hc.shadow,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image — clean, no AI match badge
                Expanded(
                  flex: 5,
                  child: Stack(
                    children: [
                      SizedBox.expand(
                        child: _buildItemImage(
                          item.imageUrls.isNotEmpty ? item.imageUrls.first : '',
                          item,
                        ),
                      ),
                      // Save button — animated heart, 48dp touch target
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Semantics(
                          label: item.isSaved
                              ? 'Remove ${item.title} from saved'
                              : 'Save ${item.title}',
                          button: true,
                          child: InkWell(
                            onTap: _onSaveTap,
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              child: AnimatedBuilder(
                                animation: _heartScale,
                                builder: (_, __) => Transform.scale(
                                  scale: _heartScale.value,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: HuddlColors.white
                                          .withValues(alpha: 0.92),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.08),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      item.isSaved
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 18,
                                      color: item.isSaved
                                          ? HuddlColors.error
                                          : HuddlColors.textHint,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Free badge
                      if (item.isFree)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: HuddlColors.accentAmber,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Free',
                              style: _adaptiveText(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      // Condition badge — subtle, bottom-left
                      if (!item.isFree)
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.condition.label,
                              style: _adaptiveText(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Details — clean, no AI feedback row
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: _adaptiveText(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: hc.textPrimary,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Text(
                          item.priceDisplay,
                          style: _adaptiveText(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: item.isFree
                                ? HuddlColors.blue
                                : HuddlColors.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.child_care,
                                size: 12, color: hc.textTertiary),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                '${item.ageStage.shortLabel} \u2022 ${item.sellerLocation}',
                                style: _adaptiveText(
                                  fontSize: 10,
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
      'photos' => HuddlColors.blue,
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
              HapticFeedback.mediumImpact();
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
                                            ? HuddlColors.blue
                                            : HuddlColors.primary,
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
                      // More actions hint (progressive disclosure affordance)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.more_vert, size: 18, color: hc.textTertiary),
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
                                      HapticFeedback.selectionClick();
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
                                      HapticFeedback.selectionClick();
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
          HapticFeedback.mediumImpact();
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

// =============================================================================
// AGE FILTER SHEET
// =============================================================================

class _AgeFilterSheet extends StatelessWidget {
  final AgeStage? selected;
  final ValueChanged<AgeStage?> onSelect;

  const _AgeFilterSheet({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HuddlBottomSheetHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.child_care,
                    color: HuddlColors.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Who is this for?',
                  style: _adaptiveText(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: hc.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Choose an age group to see items suited for that stage.',
              style: _adaptiveText(
                  fontSize: 13, color: hc.textTertiary),
            ),
          ),
          const SizedBox(height: 12),
          _sheetOptionTile(
            label: 'All ages',
            emoji: '\u{2B50}',
            isSelected: selected == null,
            onTap: () => onSelect(null),
            hc: hc,
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: AgeStage.values.map((age) {
                  return _sheetOptionTile(
                    label: age.label,
                    emoji: age.emoji,
                    isSelected: selected == age,
                    onTap: () => onSelect(age),
                    hc: hc,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

Widget _sheetOptionTile({
  required String label,
  required String emoji,
  required bool isSelected,
  required VoidCallback onTap,
  required HuddlContextColors hc,
}) {
  return Semantics(
    label: '$label${isSelected ? ", selected" : ""}',
    button: true,
    child: ListTile(
      leading: Text(emoji, style: const TextStyle(fontSize: 22)),
      title: Text(
        label,
        style: _adaptiveText(
          fontSize: 15,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? HuddlColors.primary : hc.textPrimary,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle,
              color: HuddlColors.primary, size: 22)
          : null,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      minTileHeight: 48,
    ),
  );
}

// =============================================================================
// CATEGORY FILTER SHEET
// =============================================================================

class _CategoryFilterSheet extends StatelessWidget {
  final ItemCategory? selected;
  final ValueChanged<ItemCategory?> onSelect;

  const _CategoryFilterSheet({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HuddlBottomSheetHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.category_outlined,
                    color: HuddlColors.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Category',
                  style: _adaptiveText(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: hc.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'All categories${selected == null ? ", selected" : ""}',
            button: true,
            child: ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.grid_view,
                    size: 18, color: HuddlColors.primary),
              ),
              title: Text(
                'All categories',
                style: _adaptiveText(
                  fontSize: 15,
                  fontWeight:
                      selected == null ? FontWeight.w600 : FontWeight.w400,
                  color:
                      selected == null ? HuddlColors.primary : hc.textPrimary,
                ),
              ),
              trailing: selected == null
                  ? const Icon(Icons.check_circle,
                      color: HuddlColors.primary, size: 22)
                  : null,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(null);
              },
              minTileHeight: 48,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: ItemCategory.values.map((cat) {
                  final isActive = selected == cat;
                  return Semantics(
                    label: '${cat.label}${isActive ? ", selected" : ""}',
                    button: true,
                    child: ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cat.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(cat.icon, size: 18, color: cat.color),
                      ),
                      title: Text(
                        cat.label,
                        style: _adaptiveText(
                          fontSize: 15,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w400,
                          color:
                              isActive ? HuddlColors.primary : hc.textPrimary,
                        ),
                      ),
                      trailing: isActive
                          ? const Icon(Icons.check_circle,
                              color: HuddlColors.primary, size: 22)
                          : null,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onSelect(cat);
                      },
                      minTileHeight: 48,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
