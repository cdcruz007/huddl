import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'browser_storage.dart';
import 'clearable_user_state.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'default_group_service.dart';
import 'borough_scope_guard.dart';
import '../utils/safe_parse.dart';

/// Feed item types for the home screen.
enum FeedItemType {
  newGroup,
  newEvent,
  newMarketplaceItem,
  newParent,
  milestone,
  partnerPromoted, // Promoted card from a verified Partner business
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
/// BOROUGH-AWARE: The feed is primarily local \u2014 groups, meetups,
/// marketplace items, and parent joins are scoped to the user's borough.
/// Events are the exception: they appear from any borough (UK-wide).
///
/// The feed is seeded with realistic sample data on first run and
/// persisted via BrowserStorage. It reads from DefaultGroupService and
/// OnboardingDataService to reflect the user's actual borough context.
class CommunityFeedService implements ClearableUserState {
  static final CommunityFeedService _instance =
      CommunityFeedService._internal();
  factory CommunityFeedService() => _instance;
  CommunityFeedService._internal() {
    UserStateRegistry.register(this);
  }

  // v3: bumped to purge any cached dummy/seed data from previous versions.
  static const String _storageKey = 'community_feed_v3';
  static const String _lastLoginKey = 'last_login_timestamp';

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();
  final DefaultGroupService _groupService = DefaultGroupService();
  final BoroughScopeGuard _guard = BoroughScopeGuard();

  List<FeedItem> _feedItems = [];
  bool _isInitialized = false;
  String? _userBorough;
  DateTime? _lastLogin;

  /// Current user's borough, resolved via BoroughScopeGuard (single source of truth).
  String? get userBorough => _guard.currentBorough ?? _userBorough;
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
    final borough = (_userBorough?.isNotEmpty == true) ? _userBorough! : '';
    return _buildUpcomingEvents(borough);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    await _groupService.initialize();
    _resolveBorough();
    await _loadLastLogin();
    await _loadFeed();
    // Production: never seed dummy data.
    // The feed starts empty and fills with real user activity only.
    // Update last-login to NOW
    await _saveLastLogin();
    _isInitialized = true;
  }

  void _resolveBorough() {
    // 3-tier: BoroughScopeGuard → persisted API result → sync cache
    _userBorough = _guard.currentBorough;
    if (_userBorough == null || _userBorough!.isEmpty) {
      _userBorough = _onboarding.borough;
    }
    if (_userBorough == null || _userBorough!.isEmpty) {
      final pc = _onboarding.postcode;
      if (pc != null) {
        _userBorough = _postcode.getBoroughFromPostcode(pc);
      }
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

  // _seedFeed() removed — production build shows real user activity only.

  // ── Persistence ─────────────────────────────────────────────────────────
  Future<void> _loadFeed() async {
    try {
      final raw = await BrowserStorage.getString(_storageKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _feedItems = safeParseList<FeedItem>(
            decoded, FeedItem.fromJson,
            context: 'CommunityFeedService.feedItems');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CommunityFeedService load error: $e');
    }
  }

  // ignore: unused_element  (will be called when real feed posts are persisted)
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

  /// Fetch active Partner-promoted cards for the borough home feed.
  /// Returns max 3 items, ordered newest first. Silent on error.
  Future<List<FeedItem>> fetchPromotedFeedItems(String borough) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('borough_feed')
          .doc(borough)
          .collection('promoted')
          .where('isActive', isEqualTo: true)
          .orderBy('promotedAt', descending: true)
          .limit(3)
          .get().timeout(const Duration(seconds: 15)); // TIMEOUT-1
      return snap.docs.map((d) {
        final data = d.data();
        return FeedItem(
          id: d.id,
          type: FeedItemType.partnerPromoted,
          title: data['title'] as String? ?? '',
          subtitle: data['subtitle'] as String? ?? '',
          createdAt:
              (data['promotedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          meta: {
            'partnerName': data['partnerName'],
            'partnerUid':  data['partnerUid'],
            'externalUrl': data['externalUrl'],
            'ctaLabel':    data['ctaLabel'] ?? 'Find out more',
            'isVerified':  data['isVerified'] ?? false, // FEED-2: absent field → NOT verified (fail-closed)
          },
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// [ClearableUserState] — wipes feed state on sign-out.
  @override
  Future<void> clearUserState() async {
    _feedItems.clear();
    await BrowserStorage.remove(_storageKey);
    await BrowserStorage.remove(_lastLoginKey);
  }
}
