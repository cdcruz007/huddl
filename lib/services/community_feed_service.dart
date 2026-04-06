import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'default_group_service.dart';

/// Feed item types for the home screen.
enum FeedItemType {
  newGroup,
  newEvent,
  newMarketplaceItem,
  newParent,
  milestone,
}

/// A single feed item shown on the Home screen.
class FeedItem {
  final String id;
  final FeedItemType type;
  final String title;
  final String subtitle;
  final String? imageAsset; // local asset or null
  final String? iconName;
  final DateTime createdAt;
  final Map<String, dynamic> meta; // type-specific data

  FeedItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.imageAsset,
    this.iconName,
    required this.createdAt,
    this.meta = const {},
  });

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'title': title,
        'subtitle': subtitle,
        'imageAsset': imageAsset,
        'iconName': iconName,
        'createdAt': createdAt.toIso8601String(),
        'meta': meta,
      };

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
        id: j['id'] as String,
        type: FeedItemType.values[j['type'] as int],
        title: j['title'] as String,
        subtitle: j['subtitle'] as String,
        imageAsset: j['imageAsset'] as String?,
        iconName: j['iconName'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        meta: Map<String, dynamic>.from(j['meta'] as Map? ?? {}),
      );
}

/// Upcoming event model used by the Home screen.
class UpcomingEvent {
  final String id;
  final String title;
  final String date;
  final String time;
  final String location;
  final int attendees;
  final bool isFree;
  final String? price;
  final String category;

  const UpcomingEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.time,
    required this.location,
    required this.attendees,
    this.isFree = true,
    this.price,
    required this.category,
  });
}

/// Singleton that aggregates community activity into a single feed.
///
/// The feed is seeded with realistic sample data on first run and
/// persisted via BrowserStorage. It reads from DefaultGroupService and
/// OnboardingDataService to reflect the user's actual borough context.
class CommunityFeedService {
  static final CommunityFeedService _instance =
      CommunityFeedService._internal();
  factory CommunityFeedService() => _instance;
  CommunityFeedService._internal();

  static const String _storageKey = 'community_feed_v2';
  static const String _lastLoginKey = 'last_login_timestamp';

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();
  final DefaultGroupService _groupService = DefaultGroupService();

  List<FeedItem> _feedItems = [];
  bool _isInitialized = false;
  String? _userBorough;
  DateTime? _lastLogin;

  String? get userBorough => _userBorough;
  DateTime? get lastLogin => _lastLogin;

  /// All feed items, newest first.
  List<FeedItem> get feedItems {
    final sorted = List<FeedItem>.from(_feedItems)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  /// Count of new items since last login.
  int get newItemsSinceLastLogin {
    if (_lastLogin == null) return _feedItems.length;
    return _feedItems.where((f) => f.createdAt.isAfter(_lastLogin!)).length;
  }

  /// Upcoming events for the borough (hard-coded but borough-aware).
  List<UpcomingEvent> get upcomingEvents {
    final borough = _userBorough ?? 'Cambridge';
    return _buildUpcomingEvents(borough);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    await _groupService.initialize();
    _resolveBorough();
    await _loadLastLogin();
    await _loadFeed();
    if (_feedItems.isEmpty) {
      _seedFeed();
    }
    // Update last-login to NOW
    await _saveLastLogin();
    _isInitialized = true;
  }

  void _resolveBorough() {
    final pc = _onboarding.postcode;
    if (pc != null) {
      _userBorough = _postcode.getBoroughFromPostcode(pc);
    }
  }

  // ── Upcoming Events ─────────────────────────────────────────────────────
  List<UpcomingEvent> _buildUpcomingEvents(String borough) {
    final now = DateTime.now();
    return [
      UpcomingEvent(
        id: 'evt_1',
        title: 'Baby Sensory Play',
        date: _formatDate(now.add(const Duration(days: 2))),
        time: '10:00 AM',
        location: 'Community Centre, $borough',
        attendees: 24,
        category: 'Baby',
      ),
      UpcomingEvent(
        id: 'evt_2',
        title: 'Parents Coffee Morning',
        date: _formatDate(now.add(const Duration(days: 4))),
        time: '9:30 AM',
        location: 'Little Bean Cafe, $borough',
        attendees: 12,
        isFree: true,
        category: 'Social',
      ),
      UpcomingEvent(
        id: 'evt_3',
        title: 'Toddler Music & Movement',
        date: _formatDate(now.add(const Duration(days: 6))),
        time: '2:00 PM',
        location: 'Music Room, $borough',
        attendees: 18,
        isFree: false,
        price: '\u00a315',
        category: 'Toddler',
      ),
      UpcomingEvent(
        id: 'evt_4',
        title: 'Pram Walk & Picnic',
        date: _formatDate(now.add(const Duration(days: 8))),
        time: '10:00 AM',
        location: 'Midsummer Common, $borough',
        attendees: 32,
        category: 'Outdoors',
      ),
    ];
  }

  String _formatDate(DateTime d) {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  // ── Feed Seed ───────────────────────────────────────────────────────────
  void _seedFeed() {
    final borough = _userBorough ?? 'Cambridge';
    final now = DateTime.now();
    final rng = Random(42);

    // New parents who joined recently
    final parentNames = [
      'Sophie Andrews',
      'Oliver Chen',
      'Priya Sharma',
      'Liam O\'Brien',
      'Fatima Hassan',
    ];
    for (var i = 0; i < parentNames.length; i++) {
      _feedItems.add(FeedItem(
        id: 'fp_$i',
        type: FeedItemType.newParent,
        title: parentNames[i],
        subtitle: 'Joined the $borough community',
        iconName: 'person_add',
        createdAt: now.subtract(Duration(hours: rng.nextInt(48) + 1)),
      ));
    }

    // New groups
    final groupService = DefaultGroupService();
    final allGroups = groupService.getAllDefaultGroups();
    for (var i = 0; i < allGroups.length && i < 3; i++) {
      _feedItems.add(FeedItem(
        id: 'fg_$i',
        type: FeedItemType.newGroup,
        title: allGroups[i].name,
        subtitle: '${allGroups[i].memberCount} members joined',
        imageAsset: allGroups[i].imageUrl,
        createdAt: now.subtract(Duration(hours: rng.nextInt(24) + 1)),
        meta: {'groupId': allGroups[i].id},
      ));
    }

    // Sample marketplace items (with image URLs)
    final items = [
      {
        'title': 'Baby Jogger City Mini',
        'price': '\u00a3180',
        'seller': 'Emma J.',
        'image': 'https://images.pexels.com/photos/3933096/pexels-photo-3933096.jpeg?auto=compress&cs=tinysrgb&w=400',
      },
      {
        'title': 'Wooden Toy Set',
        'price': '\u00a325',
        'seller': 'David L.',
        'image': 'https://images.pexels.com/photos/3661452/pexels-photo-3661452.jpeg?auto=compress&cs=tinysrgb&w=400',
      },
      {
        'title': 'Ergobaby Carrier',
        'price': '\u00a395',
        'seller': 'Anna K.',
        'image': 'https://images.pexels.com/photos/3845459/pexels-photo-3845459.jpeg?auto=compress&cs=tinysrgb&w=400',
      },
    ];
    for (var i = 0; i < items.length; i++) {
      _feedItems.add(FeedItem(
        id: 'fm_$i',
        type: FeedItemType.newMarketplaceItem,
        title: items[i]['title']!,
        subtitle: '${items[i]['price']} by ${items[i]['seller']}',
        imageAsset: items[i]['image'],
        iconName: 'storefront',
        createdAt: now.subtract(Duration(hours: rng.nextInt(36) + 1)),
        meta: items[i],
      ));
    }

    // New events (with image URLs matching meetup images)
    final eventData = [
      {
        'title': 'Baby Sensory Play',
        'image': 'https://images.pexels.com/photos/296301/pexels-photo-296301.jpeg?auto=compress&cs=tinysrgb&w=400',
      },
      {
        'title': 'Parents Coffee Morning',
        'image': 'https://images.pexels.com/photos/302899/pexels-photo-302899.jpeg?auto=compress&cs=tinysrgb&w=400',
      },
      {
        'title': 'Toddler Music & Movement',
        'image': 'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=400',
      },
    ];
    for (var i = 0; i < eventData.length; i++) {
      _feedItems.add(FeedItem(
        id: 'fe_$i',
        type: FeedItemType.newEvent,
        title: eventData[i]['title']!,
        subtitle: 'New meetup in $borough',
        imageAsset: eventData[i]['image'],
        iconName: 'event',
        createdAt: now.subtract(Duration(hours: rng.nextInt(72) + 1)),
      ));
    }

    _saveFeed();
  }

  // ── Persistence ─────────────────────────────────────────────────────────
  Future<void> _loadFeed() async {
    try {
      final raw = await BrowserStorage.getString(_storageKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _feedItems =
            decoded.map((e) => FeedItem.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CommunityFeedService load error: $e');
    }
  }

  Future<void> _saveFeed() async {
    try {
      final encoded = json.encode(_feedItems.map((f) => f.toJson()).toList());
      await BrowserStorage.setString(_storageKey, encoded);
    } catch (e) {
      if (kDebugMode) debugPrint('CommunityFeedService save error: $e');
    }
  }

  Future<void> _loadLastLogin() async {
    try {
      final raw = await BrowserStorage.getString(_lastLoginKey);
      if (raw != null) {
        _lastLogin = DateTime.parse(raw);
      }
    } catch (_) {}
  }

  Future<void> _saveLastLogin() async {
    await BrowserStorage.setString(
        _lastLoginKey, DateTime.now().toIso8601String());
  }

  /// Clear all community feed data — used for GDPR account deletion.
  Future<void> clearAll() async {
    await BrowserStorage.remove(_storageKey);
    await BrowserStorage.remove(_lastLoginKey);
  }
}
