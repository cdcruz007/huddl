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
    _loadSampleItems();
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

  // ── Sample data ─────────────────────────────────────────────────────────

  void _loadSampleItems() {
    final now = DateTime.now();
    _items.addAll([
      // ── NEWBORN ─────────────────────
      RehomeItem(
        id: 'rh_01',
        title: 'Newborn Baby Clothes Bundle (0\u20133m)',
        description:
            'Beautiful bundle of 15+ newborn outfits including sleepsuits, vests, and hats. All from Next and M&S. Washed in non-bio, smoke-free home. Perfect starter pack for your little one.',
        ageStage: AgeStage.newborn,
        category: ItemCategory.boysClothes,
        condition: ItemCondition.likeNew,
        price: 25,
        imageUrls: [
          'https://images.pexels.com/photos/6849570/pexels-photo-6849570.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Sophie M.',
        sellerId: 'mem_sophie',
        sellerLocation: 'Islington, 1.2km',
        listedAt: now.subtract(const Duration(hours: 3)),
        borough: 'Cambridge',
        viewCount: 34,
        offerCount: 2,
      ),
      RehomeItem(
        id: 'rh_02',
        title: 'Ergobaby Embrace Newborn Carrier',
        description:
            'Barely used Ergobaby Embrace carrier in soft navy. Perfect for newborns from day one \u2014 no insert needed. Machine washable. Comes with original box and instructions.',
        ageStage: AgeStage.newborn,
        category: ItemCategory.babyCareAndAccessories,
        condition: ItemCondition.likeNew,
        price: 45,
        imageUrls: [
          'https://images.pexels.com/photos/3845456/pexels-photo-3845456.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Emma W.',
        sellerId: 'mem_emma',
        sellerLocation: 'Camden, 0.8km',
        listedAt: now.subtract(const Duration(hours: 5)),
        borough: 'Cambridge',
        viewCount: 21,
      ),
      RehomeItem(
        id: 'rh_03',
        title: 'Tommee Tippee Complete Feeding Set',
        description:
            'Brand new Tommee Tippee closer to nature feeding set. Includes 6 bottles, steriliser, bottle warmer, and milk storage pots. Never opened \u2014 received as duplicate gift.',
        ageStage: AgeStage.newborn,
        category: ItemCategory.babyCareAndAccessories,
        condition: ItemCondition.brandNew,
        price: 35,
        imageUrls: [
          'https://images.pexels.com/photos/3875089/pexels-photo-3875089.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Anna K.',
        sellerId: 'mem_anna',
        sellerLocation: 'Hackney, 2.1km',
        listedAt: now.subtract(const Duration(hours: 8)),
        borough: 'Cambridge',
        viewCount: 47,
        offerCount: 1,
      ),
      RehomeItem(
        id: 'rh_17',
        title: 'Snuzpod 4 Bedside Crib',
        description:
            'Snuzpod 4 in white. Includes mattress, fitted sheets x2, and rocking stand. Mesh sides for airflow. Can be used as standalone crib or attached to bed. Immaculate condition.',
        ageStage: AgeStage.newborn,
        category: ItemCategory.furniture,
        condition: ItemCondition.likeNew,
        price: 95,
        imageUrls: [
          'https://images.pexels.com/photos/6393361/pexels-photo-6393361.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Lucy R.',
        sellerId: 'mem_lucy',
        sellerLocation: 'Stoke Newington, 1.8km',
        listedAt: now.subtract(const Duration(hours: 18)),
        borough: 'Cambridge',
        viewCount: 56,
        offerCount: 3,
      ),
      RehomeItem(
        id: 'rh_18',
        title: 'Baby Bath & Changing Mat Bundle',
        description:
            'Shnuggle baby bath in white/grey plus matching changing mat with raised sides. Both in great condition. Bath has built-in bum support. Sold together only.',
        ageStage: AgeStage.newborn,
        category: ItemCategory.babyCareAndAccessories,
        condition: ItemCondition.good,
        price: 18,
        imageUrls: [
          'https://images.pexels.com/photos/3875089/pexels-photo-3875089.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Sarah T.',
        sellerId: 'mem_sarah',
        sellerLocation: 'Highbury, 1.9km',
        listedAt: now.subtract(const Duration(days: 1, hours: 2)),
        borough: 'Cambridge',
        viewCount: 18,
      ),

      // ── BABY 0\u201312 MONTHS ─────────────────────
      RehomeItem(
        id: 'rh_04',
        title: 'Baby Walker Activity Centre',
        description:
            'Bright Starts 3-in-1 Around We Go activity centre. Adjustable height, 360 rotating seat. Loads of activities and toys built in. Battery compartment clean. Great condition.',
        ageStage: AgeStage.baby0to12,
        category: ItemCategory.toysAndGames,
        condition: ItemCondition.good,
        price: 30,
        imageUrls: [
          'https://images.pexels.com/photos/3661452/pexels-photo-3661452.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'James D.',
        sellerId: 'mem_james',
        sellerLocation: 'Shoreditch, 1.5km',
        listedAt: now.subtract(const Duration(hours: 12)),
        borough: 'Cambridge',
        viewCount: 28,
      ),
      RehomeItem(
        id: 'rh_05',
        title: 'Stokke Tripp Trapp High Chair',
        description:
            'Classic Stokke Tripp Trapp in natural beech. Includes baby set and harness for smaller ones. A few scuff marks on the legs but solid as a rock. Grows with your child.',
        ageStage: AgeStage.baby0to12,
        category: ItemCategory.furniture,
        condition: ItemCondition.good,
        price: 85,
        imageUrls: [
          'https://images.pexels.com/photos/5694873/pexels-photo-5694873.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Kate P.',
        sellerId: 'mem_kate',
        sellerLocation: 'Dalston, 2.5km',
        listedAt: now.subtract(const Duration(days: 1)),
        borough: 'Cambridge',
        viewCount: 63,
        offerCount: 2,
      ),
      RehomeItem(
        id: 'rh_06',
        title: 'Baby Shoes \u2013 Soft Sole Bundle',
        description:
            'Collection of 5 pairs of soft-sole baby shoes, sizes 3\u20134.5. Mix of leather and fabric. Brands include Dotty Fish and Inch Blue. Perfect for early walkers.',
        ageStage: AgeStage.baby0to12,
        category: ItemCategory.boysClothes,
        condition: ItemCondition.good,
        price: 15,
        imageUrls: [
          'https://images.pexels.com/photos/1566435/pexels-photo-1566435.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Lucy R.',
        sellerId: 'mem_lucy',
        sellerLocation: 'Stoke Newington, 1.8km',
        listedAt: now.subtract(const Duration(days: 1, hours: 6)),
        borough: 'Cambridge',
        viewCount: 19,
      ),

      // ── BABY 1\u20132 YEARS ─────────────────────
      RehomeItem(
        id: 'rh_07',
        title: 'Silver Cross Pioneer Pram',
        description:
            'Silver Cross Pioneer complete travel system in silver/black. Includes bassinet, pushchair seat, rain cover and cup holder. Used for 18 months, excellent condition. Recently cleaned.',
        ageStage: AgeStage.baby1to2,
        category: ItemCategory.pushchairsAndPrams,
        condition: ItemCondition.good,
        price: 180,
        imageUrls: [
          'https://images.pexels.com/photos/4560136/pexels-photo-4560136.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Sarah T.',
        sellerId: 'mem_sarah',
        sellerLocation: 'Highbury, 1.9km',
        listedAt: now.subtract(const Duration(days: 2)),
        borough: 'Cambridge',
        viewCount: 89,
        offerCount: 4,
      ),
      RehomeItem(
        id: 'rh_08',
        title: 'Board Books Collection (20 books)',
        description:
            'Lovely collection of 20 board books for toddlers. Includes classics like Dear Zoo, That\'s Not My..., and Peppa Pig titles. All in great shape \u2014 just outgrown!',
        ageStage: AgeStage.baby1to2,
        category: ItemCategory.books,
        condition: ItemCondition.good,
        price: 0,
        imageUrls: [
          'https://images.pexels.com/photos/3661193/pexels-photo-3661193.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Olivia L.',
        sellerId: 'mem_olivia',
        sellerLocation: 'Angel, 3.2km',
        listedAt: now.subtract(const Duration(days: 2, hours: 4)),
        borough: 'Cambridge',
        viewCount: 72,
        offerCount: 0,
      ),

      // ── TODDLER 2\u20134 ─────────────────────
      RehomeItem(
        id: 'rh_09',
        title: 'DUPLO Zoo Animals Mega Set',
        description:
            'LEGO DUPLO Town Animals of the World set plus extra animal packs. Over 100 pieces including all the animals, trees, and base plates. Hours of entertainment. Complete set.',
        ageStage: AgeStage.toddler,
        category: ItemCategory.toysAndGames,
        condition: ItemCondition.likeNew,
        price: 40,
        imageUrls: [
          'https://images.pexels.com/photos/298825/pexels-photo-298825.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Mark T.',
        sellerId: 'mem_mark',
        sellerLocation: 'Bethnal Green, 2.8km',
        listedAt: now.subtract(const Duration(days: 3)),
        borough: 'Cambridge',
        viewCount: 45,
        offerCount: 1,
      ),
      RehomeItem(
        id: 'rh_10',
        title: 'Toddler Raincoat & Wellies Set',
        description:
            'Matching JoJo Maman Bebe raincoat and Hunter First Classic wellies. Size 2\u20133 years and size 6. Both in excellent condition \u2014 barely worn last winter. Bright yellow.',
        ageStage: AgeStage.toddler,
        category: ItemCategory.boysClothes,
        condition: ItemCondition.likeNew,
        price: 20,
        imageUrls: [
          'https://images.pexels.com/photos/36029/aroni-arsa-children-little.jpg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'David S.',
        sellerId: 'mem_david',
        sellerLocation: 'Clerkenwell, 4.1km',
        listedAt: now.subtract(const Duration(days: 3, hours: 8)),
        borough: 'Cambridge',
        viewCount: 31,
      ),
      RehomeItem(
        id: 'rh_11',
        title: 'Toddler Balance Bike \u2013 Strider',
        description:
            'Strider 12 Sport balance bike in red. Adjustable seat and handlebars. Lightweight aluminium frame. Teaches balance naturally before pedal bikes. Small scratch on frame.',
        ageStage: AgeStage.toddler,
        category: ItemCategory.toysAndGames,
        condition: ItemCondition.good,
        price: 35,
        imageUrls: [
          'https://images.pexels.com/photos/5623066/pexels-photo-5623066.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Tom R.',
        sellerId: 'mem_tom',
        sellerLocation: 'Finsbury Park, 3.5km',
        listedAt: now.subtract(const Duration(days: 4)),
        borough: 'Cambridge',
        viewCount: 22,
      ),

      // ── EARLY YEARS 4\u20136 ─────────────────────
      RehomeItem(
        id: 'rh_12',
        title: 'School Uniform Bundle \u2013 Age 4\u20135',
        description:
            'Full school uniform bundle for age 4\u20135. Includes 3 polo shirts, 2 jumpers, 2 trousers, and PE kit. All labelled but name easily removed. John Lewis quality.',
        ageStage: AgeStage.earlyYears,
        category: ItemCategory.girlsClothes,
        condition: ItemCondition.good,
        price: 15,
        imageUrls: [
          'https://images.pexels.com/photos/5905857/pexels-photo-5905857.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Sophie M.',
        sellerId: 'mem_sophie',
        sellerLocation: 'Islington, 1.2km',
        listedAt: now.subtract(const Duration(days: 5)),
        borough: 'Cambridge',
        viewCount: 38,
        offerCount: 1,
      ),

      // ── KIDS 6\u201310 ─────────────────────
      RehomeItem(
        id: 'rh_13',
        title: 'Kids Bike with Stabilisers',
        description:
            'Frog 48 kids bike with stabilisers included. Lightweight aluminium frame. Suit age 6\u20138. Serviced recently \u2014 new brake pads and tyres pumped. Ready to ride!',
        ageStage: AgeStage.kids,
        category: ItemCategory.toysAndGames,
        condition: ItemCondition.good,
        price: 65,
        imageUrls: [
          'https://images.pexels.com/photos/5623066/pexels-photo-5623066.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Luke W.',
        sellerId: 'mem_luke',
        sellerLocation: 'Holloway, 5.0km',
        listedAt: now.subtract(const Duration(days: 5, hours: 12)),
        borough: 'Cambridge',
        viewCount: 54,
        offerCount: 2,
      ),

      // ── ALL AGES ─────────────────────
      RehomeItem(
        id: 'rh_14',
        title: 'IKEA Kallax Nursery Shelving Unit',
        description:
            'White IKEA Kallax 4x2 shelving unit. Perfect for nursery or kids room storage. Comes with 4 fabric inserts in grey. Good condition \u2014 a few minor marks. Collection only.',
        ageStage: AgeStage.allAges,
        category: ItemCategory.furniture,
        condition: ItemCondition.good,
        price: 40,
        imageUrls: [
          'https://images.pexels.com/photos/1148955/pexels-photo-1148955.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Emma W.',
        sellerId: 'mem_emma',
        sellerLocation: 'Camden, 0.8km',
        listedAt: now.subtract(const Duration(days: 6)),
        borough: 'Cambridge',
        viewCount: 41,
      ),
      RehomeItem(
        id: 'rh_15',
        title: 'Maxi-Cosi Pebble Car Seat',
        description:
            'Maxi-Cosi Pebble Plus i-Size car seat in black. ISOFIX base included. No accidents. Expiry date 2028. Clean, non-smoking home. All padding washable and freshly cleaned.',
        ageStage: AgeStage.allAges,
        category: ItemCategory.forTheCar,
        condition: ItemCondition.good,
        price: 75,
        imageUrls: [
          'https://images.pexels.com/photos/3845456/pexels-photo-3845456.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Anna K.',
        sellerId: 'mem_anna',
        sellerLocation: 'Hackney, 2.1km',
        listedAt: now.subtract(const Duration(days: 7)),
        borough: 'Cambridge',
        viewCount: 66,
        offerCount: 3,
      ),

      // ── MATERNITY ─────────────────────
      RehomeItem(
        id: 'rh_16',
        title: 'Maternity Jeans & Tops Bundle',
        description:
            'Bundle of maternity clothes: 2 pairs of over-bump jeans (size 10), 3 nursing-friendly tops, and 1 dress. All from ASOS and H&M. Worn for one pregnancy only.',
        ageStage: AgeStage.maternity,
        category: ItemCategory.maternity,
        condition: ItemCondition.good,
        price: 0,
        imageUrls: [
          'https://images.pexels.com/photos/6849570/pexels-photo-6849570.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'Kate P.',
        sellerId: 'mem_kate',
        sellerLocation: 'Dalston, 2.5km',
        listedAt: now.subtract(const Duration(days: 4, hours: 6)),
        borough: 'Cambridge',
        viewCount: 29,
      ),
    ]);

    // Pre-populate "my listings"
    _myListings.addAll([
      RehomeItem(
        id: 'my_01',
        title: 'Bugaboo Fox 3 Complete',
        description:
            'Bugaboo Fox 3 in midnight black. Includes bassinet, seat, rain cover, and car seat adaptors. Used for 14 months. Recently serviced. Small mark on hood fabric.',
        ageStage: AgeStage.newborn,
        category: ItemCategory.pushchairsAndPrams,
        condition: ItemCondition.good,
        price: 350,
        imageUrls: [
          'https://images.pexels.com/photos/4560136/pexels-photo-4560136.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'You',
        sellerId: 'current_user',
        sellerLocation: 'Your area',
        listedAt: now.subtract(const Duration(days: 3)),
        borough: 'Cambridge',
        viewCount: 87,
        offerCount: 3,
      ),
      RehomeItem(
        id: 'my_02',
        title: 'Wooden Kitchen Play Set',
        description:
            'Beautiful wooden play kitchen from Kidkraft. Includes all accessories \u2014 pots, pans, utensils, and play food. Assembly intact. One hinge slightly loose but still works.',
        ageStage: AgeStage.toddler,
        category: ItemCategory.toysAndGames,
        condition: ItemCondition.good,
        price: 55,
        imageUrls: [
          'https://images.pexels.com/photos/3661452/pexels-photo-3661452.jpeg?auto=compress&cs=tinysrgb&w=600',
        ],
        sellerName: 'You',
        sellerId: 'current_user',
        sellerLocation: 'Your area',
        listedAt: now.subtract(const Duration(days: 5)),
        borough: 'Cambridge',
        viewCount: 43,
        offerCount: 1,
      ),
    ]);

    // Sample offers
    _offers.addAll([
      RehomeOffer(
        id: 'off_01',
        itemId: 'my_01',
        itemTitle: 'Bugaboo Fox 3 Complete',
        buyerName: 'Emma J.',
        buyerId: 'mem_emma_j',
        amount: 300,
        createdAt: now.subtract(const Duration(hours: 6)),
      ),
      RehomeOffer(
        id: 'off_02',
        itemId: 'my_01',
        itemTitle: 'Bugaboo Fox 3 Complete',
        buyerName: 'Sophie B.',
        buyerId: 'mem_sophie_b',
        amount: 320,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      RehomeOffer(
        id: 'off_03',
        itemId: 'my_02',
        itemTitle: 'Wooden Kitchen Play Set',
        buyerName: 'Lucy W.',
        buyerId: 'mem_lucy_w',
        amount: 45,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ]);
  }
}
