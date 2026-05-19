import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/huddl_colors.dart';
import 'borough_scope_guard.dart';
import 'firestore_service.dart';
import 'huddl_notification_service.dart';

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
        return HuddlColors.teal;
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
        return HuddlColors.teal;
      case ItemCondition.good:
        return HuddlColors.amberWarm;
      case ItemCondition.wellUsed:
        return HuddlColors.textHint;
    }
  }

  IconData get icon {
    switch (this) {
      case ItemCondition.brandNew:
        return Icons.auto_awesome;
      case ItemCondition.likeNew:
        return Icons.star_outline;
      case ItemCondition.good:
        return Icons.thumb_up_outlined;
      case ItemCondition.wellUsed:
        return Icons.replay_outlined;
    }
  }

  String get description {
    switch (this) {
      case ItemCondition.brandNew:
        return 'Unused, with or without original packaging';
      case ItemCondition.likeNew:
        return 'Barely used, in excellent condition';
      case ItemCondition.good:
        return 'Some signs of use, fully functional';
      case ItemCondition.wellUsed:
        return 'Visible wear but still works well';
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

  /// Build a RehomeItem from a Firestore document map.
  factory RehomeItem.fromFirestore(Map<String, dynamic> d) {
    // Parse AgeStage from stored label string
    AgeStage parseAge(String? s) {
      if (s == null) return AgeStage.allAges;
      return AgeStage.values.firstWhere(
        (e) => e.label == s || e.name == s,
        orElse: () => AgeStage.allAges,
      );
    }
    // Parse ItemCategory from stored label string
    ItemCategory parseCat(String? s) {
      if (s == null) return ItemCategory.other;
      return ItemCategory.values.firstWhere(
        (e) => e.label == s || e.name == s,
        orElse: () => ItemCategory.other,
      );
    }
    // Parse ItemCondition from stored label string
    ItemCondition parseCond(String? s) {
      if (s == null) return ItemCondition.good;
      return ItemCondition.values.firstWhere(
        (e) => e.label == s || e.name == s,
        orElse: () => ItemCondition.good,
      );
    }
    // Parse DateTime from either Timestamp or ISO string
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }
    // imageUrls may be stored as List or single string
    List<String> parseImages(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String && v.isNotEmpty) return [v];
      return [];
    }

    return RehomeItem(
      id: d['id'] as String? ?? '',
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      ageStage: parseAge(d['ageStage'] as String?),
      category: parseCat(d['category'] as String?),
      condition: parseCond(d['condition'] as String?),
      price: (d['price'] as num?)?.toDouble() ?? 0,
      imageUrls: parseImages(d['imageUrls'] ?? d['images']),
      sellerName: d['sellerName'] as String? ?? '',
      sellerId: d['sellerId'] as String? ?? 'seller_unknown',
      sellerLocation:
          d['sellerLocation'] as String? ?? d['sellerBorough'] as String? ?? '',
      listedAt: parseDate(d['createdAt'] ?? d['listedAt']),
      isSold: d['status'] == 'sold' || d['isSold'] == true,
      viewCount: (d['viewCount'] as num?)?.toInt() ?? 0,
      offerCount: (d['offerCount'] as num?)?.toInt() ?? 0,
      borough:
          d['borough'] as String? ?? d['sellerBorough'] as String?,
    );
  }

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
      // ── Persist to Firestore (fire-and-forget) ──────────────────────────
      FirestoreService().toggleSavedItem(id).catchError((Object e) {
        if (kDebugMode) debugPrint('[RehomeService] toggleSaved FS error: $e');
        return false;
      });
    }
  }

  /// Silently mark an item as saved without triggering a Firestore write.
  /// Used when restoring saved state from Firestore on app launch so we
  /// don't immediately toggle the state back off.
  void setSaved(String id, {required bool saved}) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0 && _items[idx].isSaved != saved) {
      _items[idx].isSaved = saved;
      notifyListeners();
    }
  }

  /// Silently insert an offer loaded from Firestore without triggering
  /// another Firestore write (avoids the double-write ping-pong).
  void loadOffer(RehomeOffer offer) {
    if (_offers.any((o) => o.id == offer.id)) return;
    _offers.insert(0, offer);
    // Keep offerCount in sync on the matching item
    final idx = _items.indexWhere((i) => i.id == offer.itemId);
    if (idx >= 0) _items[idx].offerCount++;
    final myIdx = _myListings.indexWhere((i) => i.id == offer.itemId);
    if (myIdx >= 0) _myListings[myIdx].offerCount++;
    notifyListeners();
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

  /// Add an item that belongs to the current user's listings without
  /// duplicating it in the global browse list (called when loading from
  /// Firestore where the item was already inserted via addListing).
  void addMyListing(RehomeItem item) {
    if (_myListings.any((i) => i.id == item.id)) return;
    _myListings.insert(0, item);
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
    // ── Persist to Firestore (fire-and-forget) ──────────────────────────
    FirestoreService().markListingSold(id).catchError((e) {
      if (kDebugMode) debugPrint('[RehomeService] markSold FS error: $e');
    });

    // ── Notify seller + saved users (fire-and-forget) ─────────────────────
    final item = getItemById(id);
    if (item != null) {
      final me = FirebaseAuth.instance.currentUser;
      final myId = me?.uid ?? '';
      // Find the accepted offer's buyer name (if any)
      final acceptedOffer = _offers
          .where((o) => o.itemId == id && o.status == 'accepted')
          .isNotEmpty
          ? _offers.firstWhere((o) => o.itemId == id && o.status == 'accepted')
          : null;
      // Notify seller if seller ≠ current user (they marked it sold themselves)
      if (item.sellerId.isNotEmpty && item.sellerId != myId) {
        HuddlNotificationService().itemSold(
          sellerId: item.sellerId,
          itemTitle: item.title,
          itemId: item.id,
          buyerName: acceptedOffer?.buyerName ?? 'a buyer',
          itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
        ).catchError((e) {
          if (kDebugMode) debugPrint('[RehomeService] itemSold notif error: $e');
        });
      }
      // Prefetch saved-by cache, then notify those users once data is ready
      FirestoreService().getSavedByUserIds(id).then((freshIds) {
        _savedByCache[id] = freshIds;
        final savedIds = freshIds
            .where((uid) => uid != myId && uid != item.sellerId)
            .toList();
        for (final uid in savedIds) {
          HuddlNotificationService().savedItemSold(
            savedByUserId: uid,
            itemTitle: item.title,
            itemId: item.id,
            itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
          ).catchError((Object e) {
            if (kDebugMode) debugPrint('[RehomeService] savedItemSold notif error: $e');
            return;
          });
        }
      }).catchError((Object e) {
        if (kDebugMode) debugPrint('[RehomeService] markSold savedByUserIds error: $e');
        return;
      });
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
    // ── Persist to Firestore (fire-and-forget) ──────────────────────────
    FirestoreService().relistListing(id).catchError((e) {
      if (kDebugMode) debugPrint('[RehomeService] relistItem FS error: $e');
    });

    // ── Notify saved users this item is available again (fire-and-forget) ──
    final item = getItemById(id);
    if (item != null) {
      final myId = FirebaseAuth.instance.currentUser?.uid ?? '';
      // Prefetch saved-by cache, then notify those users once data is ready
      FirestoreService().getSavedByUserIds(id).then((freshIds) {
        _savedByCache[id] = freshIds;
        final savedIds = freshIds
            .where((uid) => uid != myId && uid != item.sellerId)
            .toList();
        for (final uid in savedIds) {
          HuddlNotificationService().itemRelisted(
            savedByUserId: uid,
            itemTitle: item.title,
            itemId: item.id,
            itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
          ).catchError((Object e) {
            if (kDebugMode) debugPrint('[RehomeService] itemRelisted notif error: $e');
            return;
          });
        }
      }).catchError((Object e) {
        if (kDebugMode) debugPrint('[RehomeService] relistItem savedByUserIds error: $e');
        return;
      });
    }
  }

  void deleteListing(String id) {
    _items.removeWhere((i) => i.id == id);
    _myListings.removeWhere((i) => i.id == id);
    notifyListeners();
    // ── Persist to Firestore (fire-and-forget) ──────────────────────────
    FirestoreService().deleteListing(id).catchError((e) {
      if (kDebugMode) debugPrint('[RehomeService] deleteListing FS error: $e');
    });
  }

  void updateListing(RehomeItem updated) {
    final idx = _items.indexWhere((i) => i.id == updated.id);
    if (idx >= 0) _items[idx] = updated;
    final myIdx = _myListings.indexWhere((i) => i.id == updated.id);
    if (myIdx >= 0) _myListings[myIdx] = updated;
    notifyListeners();
    // ── Persist to Firestore (fire-and-forget) ──────────────────────────
    FirestoreService().updateListing(updated.id, {
      'title': updated.title,
      'description': updated.description,
      'price': updated.price,
      'ageStage': updated.ageStage.label,
      'category': updated.category.label,
      'condition': updated.condition.label,
      'imageUrls': updated.imageUrls,
    }).catchError((e) {
      if (kDebugMode) debugPrint('[RehomeService] updateListing FS error: $e');
    });
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
    // ── Persist to Firestore (fire-and-forget) ──────────────────────────
    FirestoreService().submitOffer(
      listingId: offer.itemId,
      offerId: offer.id,
      itemTitle: offer.itemTitle,
      buyerId: offer.buyerId,
      buyerName: offer.buyerName,
      amount: offer.amount,
      note: offer.responseMessage,
    ).catchError((e) {
      if (kDebugMode) debugPrint('[RehomeService] addOffer FS error: $e');
    });

    // ── Notify seller of new offer (fire-and-forget) ─────────────────────
    final item = getItemById(offer.itemId);
    if (item != null && item.sellerId.isNotEmpty) {
      final me = FirebaseAuth.instance.currentUser;
      final myId = me?.uid ?? '';
      // Only notify if the buyer ≠ the seller
      if (myId != item.sellerId) {
        HuddlNotificationService().offerReceived(
          sellerId: item.sellerId,
          buyerName: offer.buyerName,
          itemTitle: offer.itemTitle,
          itemId: offer.itemId,
          offerId: offer.id,
          offerAmount: offer.amountDisplay,
          itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
        ).catchError((e) {
          if (kDebugMode) debugPrint('[RehomeService] offerReceived notif error: $e');
        });
      }
    }
  }

  void acceptOffer(String offerId, {String? message}) {
    final idx = _offers.indexWhere((o) => o.id == offerId);
    if (idx >= 0) {
      _offers[idx].status = 'accepted';
      if (message != null && message.trim().isNotEmpty) {
        _offers[idx].responseMessage = message.trim();
      }
      notifyListeners();
      // ── Persist to Firestore + notify buyer (fire-and-forget) ──────────
      final offer = _offers[idx];
      FirestoreService().updateOfferStatus(
        offer.itemId,
        offerId,
        status: 'accepted',
        responseMessage: message,
      ).catchError((Object e) {
        if (kDebugMode) debugPrint('[RehomeService] acceptOffer FS error: $e');
        return;
      });
      final item = getItemById(offer.itemId);
      if (item != null && offer.buyerId.isNotEmpty) {
        final me = FirebaseAuth.instance.currentUser;
        HuddlNotificationService().offerAccepted(
          buyerId: offer.buyerId,
          sellerName: item.sellerName,
          itemTitle: offer.itemTitle,
          itemId: offer.itemId,
          sellerId: item.sellerId,
          offerAmount: offer.amountDisplay,
          responseMessage: message,
          itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
        ).catchError((e) {
          if (kDebugMode) debugPrint('[RehomeService] offerAccepted notif error: $e');
        });
        // Notify other pending buyers this item is sold
        final otherBuyers = _offers
            .where((o) => o.itemId == offer.itemId && o.id != offerId && o.buyerId.isNotEmpty && o.buyerId != (me?.uid ?? ''))
            .map((o) => o.buyerId)
            .toSet()
            .toList();
        if (otherBuyers.isNotEmpty) {
          HuddlNotificationService().offerOnOtherBuyerDeclined(
            otherBuyerIds: otherBuyers,
            itemTitle: offer.itemTitle,
            itemId: offer.itemId,
            itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
          ).catchError((e) {
            if (kDebugMode) debugPrint('[RehomeService] offerOnOtherBuyer notif error: $e');
          });
        }
      }
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
      // ── Persist to Firestore + notify buyer (fire-and-forget) ──────────
      final offer = _offers[idx];
      FirestoreService().updateOfferStatus(
        offer.itemId,
        offerId,
        status: 'declined',
        responseMessage: message,
      ).catchError((Object e) {
        if (kDebugMode) debugPrint('[RehomeService] declineOffer FS error: $e');
        return;
      });
      final item = getItemById(offer.itemId);
      if (item != null && offer.buyerId.isNotEmpty) {
        HuddlNotificationService().offerDeclined(
          buyerId: offer.buyerId,
          sellerName: item.sellerName,
          itemTitle: offer.itemTitle,
          itemId: offer.itemId,
          responseMessage: message,
          itemImageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : null,
        ).catchError((e) {
          if (kDebugMode) debugPrint('[RehomeService] offerDeclined notif error: $e');
        });
      }
    }
  }

  /// Restore a previously responded-to offer back to pending (undo support).
  void restoreOfferToPending(String offerId) {
    final idx = _offers.indexWhere((o) => o.id == offerId);
    if (idx >= 0) {
      _offers[idx].status = 'pending';
      _offers[idx].responseMessage = null;
      notifyListeners();
      // ── Persist undo to Firestore (fire-and-forget) ──────────────────────
      final offer = _offers[idx];
      FirestoreService().updateOfferStatus(
        offer.itemId,
        offerId,
        status: 'pending',
      ).catchError((Object e) {
        if (kDebugMode) debugPrint('[RehomeService] restoreOffer FS error: $e');
        return;
      });
    }
  }

  RehomeItem? getItemById(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) return _items[idx];
    final myIdx = _myListings.indexWhere((i) => i.id == id);
    if (myIdx >= 0) return _myListings[myIdx];
    return null;
  }

  /// Returns user IDs of everyone who has saved a given item.
  /// Queries the real Firestore `saved_items` subcollections via a collectionGroup
  /// query and caches the result in [_savedByCache] keyed by itemId.
  ///
  /// Callers that need the list synchronously (e.g. notification dispatch) should
  /// call [prefetchSavedByUserIds] first; this getter then returns the cached value.
  List<String> savedByUserIds(String itemId) {
    return _savedByCache[itemId] ?? [];
  }

  /// In-memory cache: itemId → list of uids that saved it.
  final Map<String, List<String>> _savedByCache = {};

  /// Fire-and-forget: fetch userIds who saved [itemId] from Firestore and
  /// cache them so [savedByUserIds] returns up-to-date results.
  void prefetchSavedByUserIds(String itemId) {
    FirestoreService().getSavedByUserIds(itemId).then((ids) {
      _savedByCache[itemId] = ids;
    }).catchError((Object e) {
      if (kDebugMode) debugPrint('[RehomeService] savedByUserIds error: $e');
    });
  }


}
