import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';
import 'borough_scope_guard.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AGE STAGE — the primary filter dimension ("Who is this for?")
// ═══════════════════════════════════════════════════════════════════════════════

enum AgeStage {
  newborn,
  baby0to12,
  baby1to2,
  toddler,
  earlyYears,
  kids,
  olderKids,
  maternity,
  allAges,
}

extension AgeStageExt on AgeStage {
  String get label {
    switch (this) {
      case AgeStage.newborn:
        return 'Newborn';
      case AgeStage.baby0to12:
        return 'Baby 0\u201312 months';
      case AgeStage.baby1to2:
        return 'Baby 1\u20132 years';
      case AgeStage.toddler:
        return 'Toddler 2\u20134 years';
      case AgeStage.earlyYears:
        return 'Early Years 4\u20136';
      case AgeStage.kids:
        return 'Kids 6\u201310';
      case AgeStage.olderKids:
        return 'Older Kids 10+';
      case AgeStage.maternity:
        return 'Maternity';
      case AgeStage.allAges:
        return 'All Ages';
    }
  }

  String get shortLabel {
    switch (this) {
      case AgeStage.newborn:
        return 'Newborn';
      case AgeStage.baby0to12:
        return 'Baby 0\u201312m';
      case AgeStage.baby1to2:
        return 'Baby 1\u20132y';
      case AgeStage.toddler:
        return 'Toddler';
      case AgeStage.earlyYears:
        return 'Early Years';
      case AgeStage.kids:
        return 'Kids';
      case AgeStage.olderKids:
        return 'Older 10+';
      case AgeStage.maternity:
        return 'Maternity';
      case AgeStage.allAges:
        return 'All Ages';
    }
  }

  String get emoji {
    switch (this) {
      case AgeStage.newborn:
        return '\u{1F476}';
      case AgeStage.baby0to12:
        return '\u{1F9D2}';
      case AgeStage.baby1to2:
        return '\u{1F6B6}';
      case AgeStage.toddler:
        return '\u{1F9D1}';
      case AgeStage.earlyYears:
        return '\u{1F466}';
      case AgeStage.kids:
        return '\u{1F9D2}';
      case AgeStage.olderKids:
        return '\u{1F393}';
      case AgeStage.maternity:
        return '\u{1F930}';
      case AgeStage.allAges:
        return '\u{2B50}';
    }
  }

  IconData get icon {
    switch (this) {
      case AgeStage.newborn:
        return Icons.child_friendly;
      case AgeStage.baby0to12:
        return Icons.baby_changing_station;
      case AgeStage.baby1to2:
        return Icons.directions_walk;
      case AgeStage.toddler:
        return Icons.toys;
      case AgeStage.earlyYears:
        return Icons.school;
      case AgeStage.kids:
        return Icons.sports_soccer;
      case AgeStage.olderKids:
        return Icons.backpack;
      case AgeStage.maternity:
        return Icons.pregnant_woman;
      case AgeStage.allAges:
        return Icons.all_inclusive;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ITEM CATEGORY — secondary filter ("What are you looking for?")
// ═══════════════════════════════════════════════════════════════════════════════

enum ItemCategory {
  boysClothes,
  girlsClothes,
  toysAndGames,
  pushchairsAndPrams,
  forTheCar,
  furniture,
  books,
  maternity,
  babyCareAndAccessories,
  other,
}

extension ItemCategoryExt on ItemCategory {
  String get label {
    switch (this) {
      case ItemCategory.boysClothes:
        return 'Boys clothes';
      case ItemCategory.girlsClothes:
        return 'Girls clothes';
      case ItemCategory.toysAndGames:
        return 'Toys & games';
      case ItemCategory.pushchairsAndPrams:
        return 'Pushchairs & prams';
      case ItemCategory.forTheCar:
        return 'For the car';
      case ItemCategory.furniture:
        return 'Furniture';
      case ItemCategory.books:
        return 'Books';
      case ItemCategory.maternity:
        return 'Maternity';
      case ItemCategory.babyCareAndAccessories:
        return 'Baby care & accessories';
      case ItemCategory.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case ItemCategory.boysClothes:
        return Icons.checkroom;
      case ItemCategory.girlsClothes:
        return Icons.checkroom;
      case ItemCategory.toysAndGames:
        return Icons.extension;
      case ItemCategory.pushchairsAndPrams:
        return Icons.child_friendly;
      case ItemCategory.forTheCar:
        return Icons.directions_car;
      case ItemCategory.furniture:
        return Icons.chair;
      case ItemCategory.books:
        return Icons.auto_stories;
      case ItemCategory.maternity:
        return Icons.pregnant_woman;
      case ItemCategory.babyCareAndAccessories:
        return Icons.baby_changing_station;
      case ItemCategory.other:
        return Icons.more_horiz;
    }
  }

  Color get color {
    switch (this) {
      case ItemCategory.boysClothes:
        return HuddlColors.blue;
      case ItemCategory.girlsClothes:
        return HuddlColors.pinkSoft;
      case ItemCategory.toysAndGames:
        return HuddlColors.primary;
      case ItemCategory.pushchairsAndPrams:
        return HuddlColors.amberWarm;
      case ItemCategory.forTheCar:
        return HuddlColors.textSecondary;
      case ItemCategory.furniture:
        return HuddlColors.purpleAccent;
      case ItemCategory.books:
        return HuddlColors.teal;
      case ItemCategory.maternity:
        return HuddlColors.pinkSoft;
      case ItemCategory.babyCareAndAccessories:
        return HuddlColors.actionGreen;
      case ItemCategory.other:
        return HuddlColors.textHint;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONDITION
// ═══════════════════════════════════════════════════════════════════════════════

enum ItemCondition { brandNew, likeNew, good, wellUsed }

extension ItemConditionExt on ItemCondition {
  String get label {
    switch (this) {
      case ItemCondition.brandNew:
        return 'New';
      case ItemCondition.likeNew:
        return 'Like New';
      case ItemCondition.good:
        return 'Good';
      case ItemCondition.wellUsed:
        return 'Well Used';
    }
  }

  Color get color {
    switch (this) {
      case ItemCondition.brandNew:
        return HuddlColors.teal;
      case ItemCondition.likeNew:
        return HuddlColors.blue;
      case ItemCondition.good:
        return HuddlColors.amberWarm;
      case ItemCondition.wellUsed:
        return HuddlColors.textHint;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRICE TYPE
// ═══════════════════════════════════════════════════════════════════════════════

enum PriceType { free, paid }

// ═══════════════════════════════════════════════════════════════════════════════
// REHOME ITEM MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class RehomeItem {
  final String id;
  final String title;
  final String description;
  final AgeStage ageStage;
  final ItemCategory category;
  final ItemCondition condition;
  final double price; // 0 = free
  final List<String> imageUrls;
  final String sellerName;
  final String sellerId;
  final String sellerLocation;
  final DateTime listedAt;
  bool isSaved;
  bool isSold;
  int viewCount;
  int offerCount;
  final String? borough; // Borough this item belongs to for hyperlocal visibility

  RehomeItem({
    required this.id,
    required this.title,
    required this.description,
    required this.ageStage,
    required this.category,
    required this.condition,
    required this.price,
    required this.imageUrls,
    required this.sellerName,
    this.sellerId = 'seller_unknown',
    required this.sellerLocation,
    required this.listedAt,
    this.isSaved = false,
    this.isSold = false,
    this.viewCount = 0,
    this.offerCount = 0,
    this.borough,
  });

  bool get isFree => price == 0;

  String get priceDisplay =>
      isFree ? 'Free' : '\u00A3${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)}';

  String get timeAgo {
    final diff = DateTime.now().difference(listedAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OFFER MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class RehomeOffer {
  final String id;
  final String itemId;
  final String itemTitle;
  final String buyerName;
  final String buyerId;
  final double amount;
  final DateTime createdAt;
  String status; // 'pending', 'accepted', 'declined'
  String? responseMessage; // optional message sent back to buyer

  RehomeOffer({
    required this.id,
    required this.itemId,
    required this.itemTitle,
    required this.buyerName,
    this.buyerId = '',
    required this.amount,
    required this.createdAt,
    this.status = 'pending',
    this.responseMessage,
  });

  String get amountDisplay =>
      '\u00A3${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}';
}

// ═══════════════════════════════════════════════════════════════════════════════
// REHOME SERVICE — singleton with sample data
// ═══════════════════════════════════════════════════════════════════════════════

/// HYPERLOCAL RULE: Marketplace is borough-only.
/// Listings are only visible to parents in the same borough as the seller.
/// Users cannot browse or buy from outside their home borough.
class RehomeService extends ChangeNotifier {
  static final RehomeService _instance = RehomeService._internal();
  factory RehomeService() => _instance;
  RehomeService._internal() {
    // Demo sample items removed — app is production-only.
  }

  final List<RehomeItem> _items = [];
  final List<RehomeItem> _myListings = [];
  final List<RehomeOffer> _offers = [];
  final BoroughScopeGuard _guard = BoroughScopeGuard();

  /// All items (unfiltered) — used internally by AI services.
  List<RehomeItem> get allItems => List.unmodifiable(_items);

  /// Items visible to the current user (borough-filtered).
  ///
  /// HYPERLOCAL: Only returns items in the user's home borough.
  /// If borough is not set, falls back to showing all (graceful degradation).
  List<RehomeItem> get items {
    final borough = _guard.currentBorough;
    if (borough == null || borough.isEmpty) return List.unmodifiable(_items);
    return List.unmodifiable(
      _guard.filterByUserBorough<RehomeItem>(
        _items,
        (item) => item.borough,
      ),
    );
  }

  List<RehomeItem> get myListings => List.unmodifiable(_myListings);
  List<RehomeItem> get savedItems =>
      items.where((i) => i.isSaved).toList();
  List<RehomeOffer> get offers => List.unmodifiable(_offers);
  List<RehomeOffer> get pendingOffers =>
      _offers.where((o) => o.status == 'pending').toList();

  /// Filter items by age stage and optionally by category, condition, price.
  ///
  /// HYPERLOCAL: Always filters by the user's borough first, then applies
  /// the additional category/condition/price/query filters on top.
  List<RehomeItem> filter({
    AgeStage? ageStage,
    ItemCategory? category,
    ItemCondition? condition,
    PriceType? priceType,
    String? query,
  }) {
    // Start from borough-filtered items
    final boroughItems = items; // uses the borough-filtered getter
    return boroughItems.where((item) {
      if (item.isSold) return false;
      if (ageStage != null &&
          ageStage != AgeStage.allAges &&
          item.ageStage != ageStage &&
          item.ageStage != AgeStage.allAges) {
        return false;
      }
      if (category != null && item.category != category) return false;
      if (condition != null && item.condition != condition) return false;
      if (priceType == PriceType.free && !item.isFree) return false;
      if (priceType == PriceType.paid && item.isFree) return false;
      if (query != null && query.isNotEmpty) {
        final q = query.toLowerCase();
        if (!item.title.toLowerCase().contains(q) &&
            !item.description.toLowerCase().contains(q) &&
            !item.category.label.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void toggleSaved(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      _items[idx].isSaved = !_items[idx].isSaved;
      notifyListeners();
    }
  }

  /// Add a new listing. Auto-tags with user's borough if not set.
  ///
  /// HYPERLOCAL: Items without a borough tag will be invisible in
  /// borough-filtered views, so we ensure one is always set.
  void addListing(RehomeItem item) {
    final toAdd = (item.borough == null || item.borough!.isEmpty)
        ? RehomeItem(
            id: item.id,
            title: item.title,
            description: item.description,
            ageStage: item.ageStage,
            category: item.category,
            condition: item.condition,
            price: item.price,
            imageUrls: item.imageUrls,
            sellerName: item.sellerName,
            sellerId: item.sellerId,
            sellerLocation: item.sellerLocation,
            listedAt: item.listedAt,
            isSaved: item.isSaved,
            isSold: item.isSold,
            viewCount: item.viewCount,
            offerCount: item.offerCount,
            borough: _guard.currentBorough,
          )
        : item;
    _items.insert(0, toAdd);
    _myListings.insert(0, toAdd);
    notifyListeners();
  }

  void markSold(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      _items[idx].isSold = true;
      notifyListeners();
    }
    final myIdx = _myListings.indexWhere((i) => i.id == id);
    if (myIdx >= 0) {
      _myListings[myIdx].isSold = true;
    }
  }

  void relistItem(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      _items[idx].isSold = false;
      notifyListeners();
    }
    final myIdx = _myListings.indexWhere((i) => i.id == id);
    if (myIdx >= 0) {
      _myListings[myIdx].isSold = false;
    }
  }

  void deleteListing(String id) {
    _items.removeWhere((i) => i.id == id);
    _myListings.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  void updateListing(RehomeItem updated) {
    final idx = _items.indexWhere((i) => i.id == updated.id);
    if (idx >= 0) _items[idx] = updated;
    final myIdx = _myListings.indexWhere((i) => i.id == updated.id);
    if (myIdx >= 0) _myListings[myIdx] = updated;
    notifyListeners();
  }

  /// Called when a buyer submits an offer from the Item Detail screen.
  /// Inserts the offer at the top of [_offers] and increments the item's
  /// [offerCount] so the seller sees the new offer in their Sell tab.
  void addOffer(RehomeOffer offer) {
    _offers.insert(0, offer);
    // Bump offerCount on the matching item
    final idx = _items.indexWhere((i) => i.id == offer.itemId);
    if (idx >= 0) _items[idx].offerCount++;
    final myIdx = _myListings.indexWhere((i) => i.id == offer.itemId);
    if (myIdx >= 0) _myListings[myIdx].offerCount++;
    notifyListeners();
  }

  void acceptOffer(String offerId, {String? message}) {
    final idx = _offers.indexWhere((o) => o.id == offerId);
    if (idx >= 0) {
      _offers[idx].status = 'accepted';
      if (message != null && message.trim().isNotEmpty) {
        _offers[idx].responseMessage = message.trim();
      }
      notifyListeners();
    }
  }

  void declineOffer(String offerId, {String? message}) {
    final idx = _offers.indexWhere((o) => o.id == offerId);
    if (idx >= 0) {
      _offers[idx].status = 'declined';
      if (message != null && message.trim().isNotEmpty) {
        _offers[idx].responseMessage = message.trim();
      }
      notifyListeners();
    }
  }

  /// Restore a previously responded-to offer back to pending (undo support).
  void restoreOfferToPending(String offerId) {
    final idx = _offers.indexWhere((o) => o.id == offerId);
    if (idx >= 0) {
      _offers[idx].status = 'pending';
      _offers[idx].responseMessage = null;
      notifyListeners();
    }
  }

  RehomeItem? getItemById(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) return _items[idx];
    final myIdx = _myListings.indexWhere((i) => i.id == id);
    if (myIdx >= 0) return _myListings[myIdx];
    return null;
  }

}
