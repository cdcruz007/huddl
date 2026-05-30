import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/common/huddl_button.dart';
import '../../widgets/common/huddl_card.dart';
// import 'package:flutter/services.dart'; // removed — provided by material.dart
import '../../widgets/cards/huddl_photo_card.dart';
import '../../widgets/common/huddl_network_image.dart';
import '../../widgets/common/huddl_logo.dart';
import '../../widgets/animations/huddl_spring_animations.dart';
import '../../widgets/animations/huddl_loading_states.dart';
import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';
import '../../widgets/huddl_widgets.dart';
import '../../models/group.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';
import '../../services/postcode_service.dart';
import '../../services/announcement_service.dart';
import '../../services/community_feed_service.dart';
import '../../services/member_photo_service.dart';
import '../../services/meetup_service.dart';
import '../../services/event_service.dart';
import '../../services/invitation_service.dart';
import '../../services/dm_service.dart';
import '../../services/browser_storage.dart';
import '../main_shell.dart';
import '../events/meetup_detail_screen.dart';
import '../events/event_detail_screen.dart';
import '../../services/subscription_service.dart';
import '../../widgets/upgrade_prompt.dart';
import '../../services/ai_feed_service.dart';
import '../../widgets/borough_badge.dart';
import '../../services/borough_scope_guard.dart';
import '../../services/daily_ai_refresh_service.dart';
import '../../widgets/huddl_character.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/huddl_notification_service.dart';
import '../../services/rehome_service.dart';
import '../../services/local_services_service.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_event_discovery_service.dart';
import '../../screens/marketplace/item_detail_screen.dart';
import '../../screens/groups/group_chat_screen.dart';
import '../../screens/groups/dm_chat_screen.dart';
import '../../screens/search/unified_search_screen.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


// =============================================================================
// Home — "Invisible AI" Redesign
// =============================================================================
// Design principles:
//   1. LESS IS MORE — unified smart feed replaces 10 separate sections
//   2. INVISIBLE AI — predictive pre-fill, contextual intelligence,
//      auto-summarisation, adaptive reordering
//   3. PROGRESSIVE DISCLOSURE — sparkle entry → AI assistant bottom sheet
//   4. TRANSPARENT AI — subtle labels, thumbs feedback, user override
// =============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────
  final OnboardingDataService _onboarding = OnboardingDataService();
  final DefaultGroupService _groupService = DefaultGroupService();
  final PostcodeService _postcodeService = PostcodeService();
  final AnnouncementService _announcementService = AnnouncementService();
  final CommunityFeedService _feedService = CommunityFeedService();
  final MeetupService _meetupService = MeetupService();
  final EventService _eventService = EventService();
  final InvitationService _invitationService = InvitationService();
  final DMService _dmService = DMService();
  final AiFeedService _aiFeedService = AiFeedService();
  final LocalServicesService _servicesService = LocalServicesService();
  final RehomeService _rehomeService = RehomeService();

  bool _isLoading = true;
  bool _isFirstRun = false;

  // ── User state ────────────────────────────────────────────────────────────
  String _name = '';
  String _borough = '';
  String? _photoUrl;
  List<Group> _userGroups = [];
  List<Announcement> _announcements = [];
  List<FeedItem> _feedItems = [];
  List<Meetup> _upcomingMeetups = [];
  List<Event> _goingEvents = []; // Events the user is attending
  List<Group> _newPublicGroups = [];
  List<BoroughMember> _boroughMembers = [];
  List<ServiceListing> _featuredServices = [];

  // ── Unified smart-feed items ──────────────────────────────────────────────
  List<_SmartFeedItem> _smartFeed = [];

  // ── Feed preference toggles (persisted via BrowserStorage) ────────────────
  Map<String, bool> _feedPrefs = {
    'meetups': true,
    'events': true,
    'announcements': true,
    'suggestions': true,
    'tips': true,
  };

  // ── AI catch-up card state ──────────────────────────────────────────────
  bool _catchUpDismissed = false;

  // ── Notification state ───────────────────────────────────────────────────
  bool _notificationsRead = false;
  int _realUnreadNotifCount = 0;           // live count from Firestore
  StreamSubscription<List<Map<String, dynamic>>>? _notifStreamSub;
  StreamSubscription<User?>? _authStateSub;  // watches auth ready before subscribing

  int get _notifBadgeCount {
    if (_notificationsRead) return 0;
    // Prefer the real Firestore unread count when available
    if (_realUnreadNotifCount > 0) return _realUnreadNotifCount.clamp(0, 9);
    // Fallback: local feed heuristic
    final feedCount = _feedItems.take(5).length;
    final annCount = _announcements.where((a) => a.likes > 0).take(3).length;
    final total = feedCount + annCount;
    final meetupNotifs = _upcomingMeetups.isNotEmpty ? 1 : 0;
    return (total > 0 ? total : meetupNotifs).clamp(0, 9);
  }

  // ── Post composer / assistant launcher ─────────────────────────────────────
  final TextEditingController _postController = TextEditingController();
  String _aiPostHint = '';

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _greetingAnimCtrl;
  late Animation<double> _greetingFade;
  late Animation<Offset> _greetingSlide;
  // ── AI feedback tracking ──────────────────────────────────────────────────


  // ── Feed filter chip — 'all' | 'meetups' | 'events' | 'noticeboard' | 'tips'
  // Filter chips removed — feed always shows all content.
  final String _activeFeedFilter = 'all';

  // ── Adaptive: track which sections user interacts with ────────────────────
  int _meetupTaps = 0;
  int _groupTaps = 0;
  int _marketTaps = 0;

  // ── Hero parallax scroll ──────────────────────────────────────────────────
  final ScrollController _heroScrollCtrl = ScrollController();
  double _heroScrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _heroScrollCtrl.addListener(() {
      final offset = _heroScrollCtrl.offset;
      if ((offset - _heroScrollOffset).abs() > 1.0) {
        setState(() => _heroScrollOffset = offset.clamp(0.0, 300.0));
      }
    });
    _greetingAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _greetingFade = CurvedAnimation(
      parent: _greetingAnimCtrl,
      curve: Curves.easeOut,
    );
    _greetingSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _greetingAnimCtrl,
      curve: Curves.easeOutCubic,
    ));
    // Defer _initHome() until after the first frame is fully built.
    // Calling setState() inside initState() (via _loadFeedPrefs / _loadData)
    // before the widget tree is drawn triggers:
    // "setState() or markNeedsBuild() called during build"
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initHome();
    });
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    _notifStreamSub?.cancel();
    _heroScrollCtrl.dispose();
    _greetingAnimCtrl.dispose();
    _postController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load feed preferences FIRST, then data, so _buildSmartFeed sees prefs.
  Future<void> _initHome() async {
    await _loadFeedPrefs();
    await _loadData();
    _subscribeToNotifications();
  }

  /// Subscribe to real-time Firestore notifications so the bell badge
  /// reflects the true unread count even when the app is in the foreground.
  /// If new unread notifications arrive after the user already opened the
  /// sheet, reset _notificationsRead so the badge lights up again.
  ///
  /// Uses authStateChanges to guard against the cold-start race where
  /// FirebaseAuth.currentUser is still null when the widget first mounts,
  /// causing stream() to return Stream.value([]) and the badge/list to
  /// appear empty even though notifications exist in Firestore.
  void _subscribeToNotifications() {
    _authStateSub?.cancel();
    // If already signed in, start immediately; otherwise wait for auth.
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      _startNotifStream();
    } else {
      _authStateSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null && mounted) {
          _authStateSub?.cancel();
          _authStateSub = null;
          _startNotifStream();
        }
      });
    }
  }

  void _startNotifStream() {
    try {
      _notifStreamSub?.cancel();
      _notifStreamSub = HuddlNotificationService()
          .stream()
          .listen((notifs) {
        if (!mounted) return;
        final unread = notifs.where((n) => n['read'] != true).length;
        setState(() {
          // If new unread items arrive, un-silence the badge so it shows.
          if (unread > _realUnreadNotifCount) _notificationsRead = false;
          _realUnreadNotifCount = unread;
        });
      }, onError: (_) {
        // Silent — bell will fall back to heuristic count
      });
    } catch (_) {
      // Firestore not available (e.g. demo mode) — fall back gracefully
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Force-reload from storage so we always pick up values written by
      // syncCurrentUserProfile / restoreProfile even if the singleton was
      // already initialised earlier with stale empty data.
      await _onboarding.initialize(forceReload: true);

      // If name is still empty after storage reload, restore directly from
      // Firestore — this covers the case where storage was cleared but
      // Firestore has the correct name.
      if (_onboarding.name == null || _onboarding.name!.trim().isEmpty) {
        try {
          await FirebaseAuthService().restoreProfileFromFirestore()
              .timeout(const Duration(seconds: 5));
          await _onboarding.initialize(forceReload: true);
        } catch (_) {}
      }

      // ── First-run detection ──────────────────────────────────────────
      try {
        final countStr = await BrowserStorage.getString('huddl_interaction_count');
        final count = int.tryParse(countStr ?? '') ?? 0;
        _isFirstRun = count < 3;
      } catch (_) {}

      await _groupService.initialize();
      await _announcementService.initialize();
      await _feedService.initialize();
      await _invitationService.initialize();
      await _dmService.initialize();
      await _aiFeedService.initialize();

      // Step 14: Trigger daily AI refresh cycle if due
      DailyAiRefreshService().initialize().then((_) {
        DailyAiRefreshService().runRefreshCycle();
      });

      String borough = '';
      final pc = _onboarding.postcode;
      if (pc != null) {
        borough = _postcodeService.getBoroughFromPostcode(pc) ?? '';
      }

      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
      final groups = await _groupService.getUserGroups(uid);

      // ── Load Meetups from Firestore ──────────────────────────────────────
      // The MeetupService singleton only contains locally-created meetups
      // until loadFromFirestore() is called. Call it here so the home feed
      // shows real Firestore meetups even when the user hasn't opened the
      // Discover tab yet (which is where events_screen.dart normally calls it).
      await _meetupService.loadFromFirestore().catchError((_) {});
      await _meetupService.syncRsvpsFromFirestore().catchError((_) {});

      final allMeetups = _meetupService.meetups;
      final upcomingMeetups = allMeetups
          .where((m) => m.dateTime.isAfter(DateTime.now()))
          .toList()
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
      final upcomingMeetupsList = upcomingMeetups.take(8).toList();

      // ── Load Events via AI Discovery ─────────────────────────────────────
      // EventService._events is empty until AiEventDiscoveryService populates it.
      // Call runDailyDiscovery() here so home feed shows events immediately.
      try {
        await AiEventDiscoveryService()
            .runDailyDiscovery()
            .timeout(const Duration(seconds: 6));
      } catch (_) {}
      await _eventService.syncRsvpsFromFirestore().catchError((_) {});
      final goingEvents = _eventService.goingEvents;

      // ── Load Groups: merge BrowserStorage + Firestore ──────────────────────
      // Always pull Firestore public groups so community/seeded groups appear
      // even if the user has no locally-stored groups.
      List<Group> newGroups = await _loadNewPublicGroups(borough);
      try {
        final firestoreGroups = await FirestoreService()
            .getDiscoverGroups()
            .timeout(const Duration(seconds: 5));
        // Filter system/onboarding groups and deduplicate by id
        final existingIds = newGroups.map((g) => g.id).toSet();
        final filtered = firestoreGroups
            .where((g) => !_isDefaultOnboardingGroup(g) && !existingIds.contains(g.id))
            .toList();
        newGroups = [...newGroups, ...filtered];
      } catch (_) {}

      List<BoroughMember> boroughMembers = [];
      if (pc != null) {
        boroughMembers = InvitationService.getBoroughMembers(pc);
      }

      // Load services for carousel (non-blocking)
      List<ServiceListing> featuredServices = [];
      try {
        featuredServices = await _servicesService
            .topEndorsedStream(limit: 8)
            .first
            .timeout(const Duration(seconds: 4));
      } catch (_) {}

      // ── Load Marketplace items from Firestore ────────────────────────────
      // RehomeService._items is populated by the marketplace screen, but may
      // be empty when the user lands on Home first.  Fetch from Firestore and
      // insert into the service singleton so _rehomeService.allItems is populated.
      if (_rehomeService.allItems.isEmpty) {
        try {
          final rawListings = await FirestoreService()
              .getMarketplaceListings()
              .timeout(const Duration(seconds: 5));
          for (final map in rawListings) {
            try {
              final item = RehomeItem.fromFirestore(map);
              _rehomeService.silentInsert(item);
            } catch (_) {}
          }
        } catch (_) {}
      }

      setState(() {
        _name = _onboarding.name ?? 'there';
        _borough = borough;
        _photoUrl = (_onboarding.profilePhotoObjectUrl?.isNotEmpty == true)
            ? _onboarding.profilePhotoObjectUrl
            : (_onboarding.profilePhotoPath?.isNotEmpty == true &&
                   _onboarding.profilePhotoPath!.startsWith('http'))
                ? _onboarding.profilePhotoPath
                : _onboarding.profilePhotoObjectUrl;
        _userGroups = groups;
        _announcements = _announcementService.boroughAnnouncements;
        _feedItems = _feedService.feedItems;
        _upcomingMeetups = upcomingMeetupsList;
        _goingEvents = goingEvents;
        _newPublicGroups = newGroups;
        _boroughMembers = boroughMembers;
        _featuredServices = featuredServices;
        _isLoading = false;
      });

      _buildSmartFeed();
      _generateAiPostHint();

      _greetingAnimCtrl.forward();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // ── Feed preferences persistence ────────────────────────────────────────
  // §1C: Preferences are persisted to BrowserStorage (local) AND
  //      Firestore users/{userId}.feedPreferences (cloud) per spec.
  Future<void> _loadFeedPrefs() async {
    try {
      // 1. Try Firestore first (authoritative, cross-device)
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final fsPrefs = doc.data()?['feedPreferences'] as Map<String, dynamic>?;
        if (fsPrefs != null) {
          final loaded = fsPrefs.map((k, v) => MapEntry(k, v as bool));
          final merged = Map<String, bool>.from(_feedPrefs)..addAll(loaded);
          // Sync to local cache
          await BrowserStorage.setString('feed_preferences_v1', json.encode(merged));
          if (mounted) setState(() => _feedPrefs = merged);
          return;
        }
      }
      // 2. Fall back to local BrowserStorage
      final raw = await BrowserStorage.getString('feed_preferences_v1');
      if (raw != null) {
        final Map<String, dynamic> decoded = json.decode(raw);
        final loaded = decoded.map((k, v) => MapEntry(k, v as bool));
        // Merge with defaults so new keys added later are never null
        final merged = Map<String, bool>.from(_feedPrefs)..addAll(loaded);
        if (mounted) setState(() => _feedPrefs = merged);
      }
    } catch (_) {}
  }

  Future<void> _saveFeedPrefs() async {
    // Save to local BrowserStorage (always, for offline resilience)
    await BrowserStorage.setString(
        'feed_preferences_v1', json.encode(_feedPrefs));
    // Save to Firestore users/{userId}.feedPreferences (§1C spec)
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'feedPreferences': _feedPrefs}, SetOptions(merge: true));
      }
    } catch (_) {
      // Non-fatal: local storage already saved, Firestore is best-effort
    }
  }

  /// Returns true when [g] should be hidden from the home feed's suggested
  /// groups section.  Excludes:
  ///   1. isImageLocked == true (all default borough groups)
  ///   2. ID pattern meetup_group_* or event_group_* (auto-created chats)
  ///   3. Name starts with a 4-digit year (e.g. "2024 Cambridge Parents")
  ///   4. Category is "Default Community", "MEETUP" or "EVENT"
  ///   5. Name contains any onboarding keyword (aspiring / expecting / SEN…)
  ///   6. Privacy is private (these are invite-only chats, not suggestions)
  static bool _isDefaultOnboardingGroup(Group g) {
    if (g.isImageLocked) return true;
    if (g.id.startsWith('meetup_group_') || g.id.startsWith('event_group_')) return true;
    if (RegExp(r'^\d{4}\s+\S').hasMatch(g.name)) return true;
    if (g.category == 'Default Community') return true;
    if (g.category == 'MEETUP' || g.category == 'EVENT') return true;
    if (g.isPrivate) return true;
    final lower = g.name.toLowerCase();
    const onboardingKeywords = [
      'aspiring parents',
      'expecting parents',
      'sen parents',
      'sen support',
      'dads connect',
      'toddler adventures',
      'new parents',
      'parents group',
      'mums group',
      'dads group',
      'parenting group',
    ];
    for (final kw in onboardingKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }

  Future<List<Group>> _loadNewPublicGroups(String borough) async {
    final List<Group> result = [];
    try {
      // v2 key: clears any stale default/onboarding groups that were
      // incorrectly written to the old key by earlier app versions.
      final raw = await BrowserStorage.getString('user_created_groups_v2');
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        for (final j in decoded) {
          final g = Group.fromJson(j as Map<String, dynamic>);
          // Multi-signal defence-in-depth: skip any default/system group
          // regardless of whether isImageLocked was written correctly.
          if (_isDefaultOnboardingGroup(g)) continue;
          if (!g.isPrivate) {
            if (g.creatorBorough == null ||
                g.creatorBorough!.isEmpty ||
                g.creatorBorough == 'Unknown Borough' ||
                g.creatorBorough == borough) {
              result.add(g);
            }
          }
        }
      }
    } catch (_) {}
    return result.take(6).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INVISIBLE AI: UNIFIED SMART FEED
  // ═══════════════════════════════════════════════════════════════════════════
  // Merges announcements, meetups, groups, and community feed
  // into a single AI-ranked stream. Each item type is wrapped in a
  // _SmartFeedItem with a relevance score and AI-generated reason.

  Future<void> _buildSmartFeed() async {
    final List<_SmartFeedItem> items = [];

    // 1. AI nudge is shown in the Noticeboard section above the smart feed,
    //    so we intentionally skip adding it here to avoid duplication.
    //    (topNudge is read by _buildNoticeboardSection directly.)

    // 2. isGoing meetups and goingEvents are now exclusively shown in the
    //    "Don't Forget" pinned carousel above — do NOT add them to the smart
    //    feed list or they will appear twice on screen.

    // 3. Announcements are already rendered inside the Noticeboard section
    //    (see _buildNoticeboardSection → topAnnouncements) so we do NOT add
    //    them here again — doing so caused every post to appear twice on screen.

    // 4 & 5. Meetups and groups are already shown in dedicated horizontal
    //         carousels above the smart feed — adding them here again causes
    //         duplication. Skipped intentionally.

    // 6. Community activity feed (AI-ranked — max 4)
    final ranked = _aiFeedService.rankFeedItems(_feedItems);
    for (var i = 0; i < ranked.length && i < 4; i++) {
      items.add(_SmartFeedItem(
        type: _SmartFeedType.communityActivity,
        relevanceScore: ranked[i].score * 0.85,
        reason: ranked[i].reason,
        feedItem: ranked[i].item,
      ));
    }

    // ── Apply feed preference filters ─────────────────────────────────────
    items.removeWhere((item) {
      switch (item.type) {
        case _SmartFeedType.meetup:
          return !(_feedPrefs['meetups'] ?? true);
        case _SmartFeedType.goingEvent:
          return !(_feedPrefs['events'] ?? true);
        case _SmartFeedType.announcement:
          return !(_feedPrefs['announcements'] ?? true);
        case _SmartFeedType.suggestedMeetup:
        case _SmartFeedType.group:
          return !(_feedPrefs['suggestions'] ?? true);
        case _SmartFeedType.aiNudge:
        case _SmartFeedType.communityActivity:
          return !(_feedPrefs['tips'] ?? true);
        case _SmartFeedType.partnerPromoted:
          return false; // always shown — Partner paid for placement
      }
    });

    // ── Fixed section order (score only breaks ties within each section) ──
    // Note: announcements live in the Noticeboard; meetups/groups in carousels;
    //       AI nudge in the Noticeboard tip row — none duplicated here.
    // 1. Upcoming meetups & events the user is going to  (soonest first)
    // 2. Community activity feed  (AI-ranked)
    const sectionOrder = {
      _SmartFeedType.announcement:       0,
      _SmartFeedType.meetup:             1,
      _SmartFeedType.goingEvent:         1,
      _SmartFeedType.suggestedMeetup:    2,
      _SmartFeedType.group:              2,
      _SmartFeedType.communityActivity:  3,
      _SmartFeedType.aiNudge:            4,
      _SmartFeedType.partnerPromoted:    5, // below organic; woven in separately
    };
    items.sort((a, b) {
      final sA = sectionOrder[a.type] ?? 99;
      final sB = sectionOrder[b.type] ?? 99;
      if (sA != sB) return sA.compareTo(sB);
      // Within the same section, higher score first
      return b.relevanceScore.compareTo(a.relevanceScore);
    });

    setState(() => _smartFeed = items);

    // ── Fetch and interleave Partner promoted cards at 1:7 ratio ─────────
    // Positions: 2, 9, 16... (3rd, 10th, 17th organic item)
    // Source: Firestore borough_feed/{borough}/promoted — non-blocking
    if (_borough.isNotEmpty) {
      try {
        final promoted = await _feedService.fetchPromotedFeedItems(_borough);
        if (!mounted) return;
        int offset = 0;
        for (int i = 0; i < promoted.length; i++) {
          final pos = 2 + (i * 7) + offset;
          if (pos <= _smartFeed.length) {
            _smartFeed.insert(
              pos,
              _SmartFeedItem(
                type: _SmartFeedType.partnerPromoted,
                feedItem: promoted[i],
                relevanceScore: 0,
                reason: 'Partner',
              ),
            );
            offset++;
          }
        }
        if (promoted.isNotEmpty && mounted) setState(() {});
      } catch (_) {
        // Silently ignore — promoted cards are non-critical
      }
    }
  }

  // ── AI: Generate contextual assistant hint ────────────────────────────────
  void _generateAiPostHint() {
    final hour = DateTime.now().hour;
    final hints = <String>[];
    if (hour < 12) {
      hints.addAll([
        'Ask about morning activities in $_borough...',
        'Find play spots open this morning...',
        'Ask for local breakfast recommendations...',
      ]);
    } else if (hour < 17) {
      hints.addAll([
        'Find after-school activities near you...',
        'Ask about soft play spots nearby...',
        'What\'s on this afternoon in $_borough?',
      ]);
    } else {
      hints.addAll([
        'Ask about evening family events nearby...',
        'Find a family-friendly spot tonight...',
        'Ask for bedtime tips for new parents...',
      ]);
    }
    // Mix in meetup-aware hint
    if (_upcomingMeetups.isNotEmpty) {
      hints.add('Ask about ${_upcomingMeetups.first.title}...');
    }
    setState(() {
      _aiPostHint = hints[Random().nextInt(hints.length)];
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _switchToTab(int index) {
    final shellState = MainShell.shellKey.currentState;
    if (shellState != null) {
      shellState.switchTab(index);
    }
  }

  /// Switch to the Discover tab and jump directly to a sub-tab.
  /// subIndex: 0=Groups, 1=Meetups, 2=Events, 3=Services
  void _switchToDiscover(int subIndex) {
    final shellState = MainShell.shellKey.currentState;
    if (shellState != null) {
      shellState.switchDiscoverTab(subIndex);
    }
  }

  Future<void> _toggleLike(String id) async {
    await _announcementService.toggleLike(id);
    setState(() {
      _announcements = _announcementService.boroughAnnouncements;
    });
  }

  void _openComments(Announcement announcement) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(
        announcement: announcement,
        service: _announcementService,
        onUpdate: () {
          setState(() {
            _announcements = _announcementService.boroughAnnouncements;
          });
          _buildSmartFeed();
        },
      ),
    );
  }

  void _sharePost(Announcement announcement) {
    _announcementService.share(announcement.id);
    setState(() {
      _announcements = _announcementService.boroughAnnouncements;
    });
    _showShareTargetSheet(announcement);
  }

  void _showShareTargetSheet(Announcement announcement) {
    final shareText =
        '${announcement.authorName}: "${announcement.content}" - via Huddl';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _SharePostSheet(
          shareText: shareText,
          userGroups: _userGroups,
          boroughMembers: _boroughMembers,
          borough: _borough,
          currentUserName: _name,
          dmService: _dmService,
          onShared: (String targetName) {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: context.hc.surface, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Shared with $targetName',
                          style: HuddlText.body()),
                    ),
                  ],
                ),
                backgroundColor: HuddlColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendWelcomeDM(FeedItem item) async {
    final recipientName = item.title;
    final recipientId =
        'mem_${recipientName.toLowerCase().replaceAll(' ', '_').replaceAll("'", '')}';
    final senderName = _name.isNotEmpty ? _name : 'You';
    final conv = await _dmService.getOrCreateConversation(
      recipientId: recipientId,
      recipientName: recipientName,
    );
    await _dmService.sendMessage(
      conversationId: conv.id,
      message:
          'Welcome to the $_borough community! Great to have you here. If you need any tips or recommendations for the area, don\'t hesitate to ask!',
      senderName: senderName,
    );
    if (mounted) {
      _switchToTab(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle,
                  color: context.hc.surface, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Welcome message sent to $recipientName!',
                    style: HuddlText.body()),
              ),
            ],
          ),
          backgroundColor: HuddlColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showPostMenu(Announcement announcement) {
    final isOwnPost =
        announcement.authorName == (_announcementService.currentUserName);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HuddlBottomSheetHandle(),
              _menuItem(
                icon: announcement.isPinned
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                label: announcement.isPinned ? 'Unpin post' : 'Pin post',
                onTap: () {
                  Navigator.pop(ctx);
                  _announcementService.togglePin(announcement.id);
                  setState(() {
                    _announcements =
                        _announcementService.boroughAnnouncements;
                  });
                  _buildSmartFeed();
                },
              ),
              _menuItem(
                icon: announcement.isBookmarked
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                label: announcement.isBookmarked
                    ? 'Remove bookmark'
                    : 'Bookmark post',
                onTap: () {
                  Navigator.pop(ctx);
                  _announcementService.toggleBookmark(announcement.id);
                  setState(() {
                    _announcements =
                        _announcementService.boroughAnnouncements;
                  });
                },
              ),
              _menuItem(
                icon: Icons.share_outlined,
                label: 'Share post',
                onTap: () {
                  Navigator.pop(ctx);
                  _sharePost(announcement);
                },
              ),
              if (isOwnPost)
                _menuItem(
                  icon: Icons.delete_outline,
                  label: 'Delete post',
                  color: HuddlColors.error,
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeletePost(announcement);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? context.hc.textPrimary, size: 22),
      title: Text(
        label,
        style: HuddlText.body(),
      ),
      onTap: onTap,
    );
  }

  void _confirmDeletePost(Announcement announcement) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete post?',
            style: HuddlText.body(weight: FontWeight.w600)),
        content: Text('This action cannot be undone.',
            style: HuddlText.body()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                    HuddlText.body(color: context.hc.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _announcementService.delete(announcement.id);
              setState(() {
                _announcements =
                    _announcementService.boroughAnnouncements;
              });
              _buildSmartFeed();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Post deleted',
                      style: HuddlText.body()),
                  backgroundColor: HuddlColors.textDark,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Text('Delete',
                style: HuddlText.body(color: HuddlColors.error)),
          ),
        ],
      ),
    );
  }

  void _dismissAnnouncement(Announcement announcement) {
    final index = _announcements.indexOf(announcement);
    setState(() {
      _announcements.remove(announcement);
    });
    HuddlAnimations.mediumTap();
    _buildSmartFeed();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Post hidden',
            style: HuddlText.body()),
        backgroundColor: HuddlColors.textDark,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          textColor: HuddlColors.textTertiary,
          onPressed: () {
            setState(() {
              _announcements.insert(
                index.clamp(0, _announcements.length),
                announcement,
              );
            });
            _buildSmartFeed();
          },
        ),
      ),
    );
  }

  void _openNotifications() {
    // The badge will clear naturally once markAllRead / markOneRead runs.
    // We don't pre-clear here so tapping the bell always shows the live list.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsSheet(
        feedItems: _feedItems,
        announcements: _announcements,
        borough: _borough,
        meetups: _meetupService.meetups,
        onNavigate: (int tabIndex) {
          // Sheet closes itself before calling onNavigate
          _switchToTab(tabIndex);
        },
        onNavigateToGroupChat:
            (String groupId, String groupName, String groupImageUrl) {
          Navigator.of(context).pushNamed(
            '/group_chat',
            arguments: {
              'groupId': groupId,
              'groupName': groupName,
              'groupImageUrl': groupImageUrl,
            },
          );
        },
        onNavigateToMeetup: (Meetup meetup) {
          Navigator.of(context).push(
            HuddlSpringPageRoute(page: MeetupDetailScreen(meetup: meetup)),
          );
        },
        onMarkAllRead: () {
          // Badge will auto-update via Firestore stream
          setState(() => _realUnreadNotifCount = 0);
        },
      ),
    );
  }

  void _onAvatarTap() {
    _switchToTab(4); // Profile tab
  }

  void _onFeedItemTap(FeedItem item) {
    switch (item.type) {
      case FeedItemType.newParent:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ActivityDetailSheet(
            item: item,
            borough: _borough,
            onAction: () {
              Navigator.pop(context);
              _sendWelcomeDM(item);
            },
          ),
        );
        break;
      case FeedItemType.newGroup:
        setState(() => _groupTaps++);
        _switchToTab(1);
        break;
      case FeedItemType.newEvent:
        setState(() => _meetupTaps++);
        final match = _meetupService.meetups
            .where((m) => m.title == item.title)
            .toList();
        if (match.isNotEmpty) {
          Navigator.of(context).push(
            HuddlSpringPageRoute(page: MeetupDetailScreen(meetup: match.first)),
          );
        } else {
          _switchToTab(2);
        }
        break;
      case FeedItemType.newMarketplaceItem:
        setState(() => _marketTaps++);
        _switchToTab(3);
        break;
      case FeedItemType.milestone:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              _ActivityDetailSheet(item: item, borough: _borough),
        );
        break;
      case FeedItemType.partnerPromoted:
        // Tap navigates to the listing detail or services screen
        final listingId = item.meta['listingId'] as String?;
        if (listingId != null && listingId.isNotEmpty) {
          Navigator.pushNamed(context, '/services',
              arguments: {'listingId': listingId});
        } else {
          Navigator.pushNamed(context, '/services');
        }
        break;
    }
  }

  // AI assistant removed from header — AI works invisibly now.

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show skeleton shimmer while loading — no full-screen "finding parents" block
    if (_isLoading) {
      return Scaffold(
        backgroundColor: hc.scaffold,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: HuddlSkeletonFeed(cardCount: 4),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: hc.scaffold,
      body: SafeArea(
        child: RefreshIndicator(
          color: HuddlColors.textTertiary,
          onRefresh: _loadData,
          child: CustomScrollView(
            controller: _heroScrollCtrl,
            slivers: [
              // ── Pinned App Bar + Feed Header ─────────────────────
              // SliverPersistentHeader with a fixed-height delegate gives
              // reliable pinning without the PreferredSize clipping issue
              // that SliverAppBar(bottom:) caused.
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyHeaderDelegate(
                  child: _buildStickyHeader(hc, isDark),
                  // Logo row:   top(10) + icon(40) + bottom(4) = 54px
                  // Feed header: outer(4+10) + inner(6) + title(32) + bottom(10) = 62px
                  // total = 116px — subtitle removed from pinned header
                  height: 116,
                ),
              ),

              // Search pill removed — filter chips in feed header handle discovery

              // ── Compact greeting row — hidden when filtered ──────────
              if (_activeFeedFilter == 'all')
                SliverToBoxAdapter(
                  child: SlideTransition(
                    position: _greetingSlide,
                    child: FadeTransition(
                      opacity: _greetingFade,
                      child: _buildCompactGreeting(hc, isDark),
                    ),
                  ),
                ),

              // ── Hero Meetup Card — next upcoming meetup, 'all' only ──
              if (!_isLoading &&
                  _activeFeedFilter == 'all' &&
                  _upcomingMeetups.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildHeroMeetupCard(_upcomingMeetups.first, hc, isDark),
                ),

              // ── AI Catch-Up Summary Card — 'all' only ─────────────
              if (!_isLoading && _activeFeedFilter == 'all')
                SliverToBoxAdapter(
                  child: _buildAiCatchUpCard(hc, isDark),
                ),

              // ── First-run onboarding card ──────────────────────────
              if (_isFirstRun && _activeFeedFilter == 'all')
                SliverToBoxAdapter(
                  child: _buildFirstRunCard(hc, isDark),
                ),

              // ── Noticeboard composer + feed ────────────────────────
              // Shown on 'all' and 'noticeboard' filter tabs
              if (_activeFeedFilter == 'all' || _activeFeedFilter == 'noticeboard') ...[
                SliverToBoxAdapter(
                  child: _buildNoticeboardComposer(hc, isDark),
                ),
                SliverToBoxAdapter(
                  child: _buildNoticeboardSection(hc, isDark),
                ),
              ],

              // ── "Don't Forget" — confirmed-attending items ────────
              // Always shown (with an empty state CTA when no RSVPs yet).
              // Pulls from: meetups where isGoing==true + _goingEvents.
              // Sorted soonest first.
              if (_activeFeedFilter == 'all' ||
                  _activeFeedFilter == 'meetups' ||
                  _activeFeedFilter == 'events') ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    hc: hc,
                    icon: Icons.notifications_active_outlined,
                    iconColor: HuddlColors.nearBlack,
                    title: "Don't Forget",
                    subtitle: 'Your confirmed upcoming meetups & events',
                    onSeeAll: () => _switchToTab(2),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildDontForgetCarousel(hc, isDark),
                ),
              ],

              // ── Discover New Listings — unified carousel ──────────
              // Groups + Meetups + Events + Market items, last 7 days
              // (or since last login if < 7 days), newest → oldest
              if (_activeFeedFilter == 'all' ||
                  _activeFeedFilter == 'meetups' ||
                  _activeFeedFilter == 'events') ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    hc: hc,
                    icon: Icons.auto_awesome,
                    iconColor: HuddlColors.yellow,
                    title: 'Discover New Listings',
                    subtitle: 'New groups, meetups, events & items this week',
                    onSeeAll: () => _switchToTab(2),
                  ),
                ),
                SliverToBoxAdapter(
                    child: _buildDiscoverNewListingsCarousel(hc, isDark)),
              ],

              // ── Smart feed items — filtered per tab ───────────────
              // UX-03: Spring physics on feed cards
              if (_activeFeedFilter != 'noticeboard') ...[
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final feed = _filteredSmartFeed(hc, isDark);
                      if (index >= feed.length) return null;
                      final item = feed[index];
                      return HuddlSpringMount(
                        delay: Duration(milliseconds: index * 55),
                        child: _buildSmartFeedCard(item, hc, isDark),
                      );
                    },
                    childCount: _filteredSmartFeed(hc, isDark).length,
                  ),
                ),
              ],

              // ── Upgrade banner — shown at the bottom ──────────────
              if (_activeFeedFilter == 'all' && SubscriptionService().isFree)
                SliverToBoxAdapter(
                  child: UpgradeBanner(
                    message: 'Unlock more groups, meetups & private features',
                    onTap: () => Navigator.pushNamed(context, '/subscription_plans'),
                  ),
                ),

              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UI BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Adaptive logo:
  ///   Light mode → logo_huddl.png       (orange H + dark-grey wordmark, transparent bg)
  ///   Dark mode  → logo_huddl_dark.png  (orange H + white wordmark, transparent bg)
  /// Both assets have white background removed at build time.
  /// RichText fallback is used if either asset is missing.
  Widget _buildAdaptiveLogo(bool isDark) {
    final fallback = RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'h',
            style: HuddlText.display(),
          ),
          TextSpan(
            text: 'uddl',
            style: HuddlText.display(),
          ),
        ],
      ),
    );

    return const HuddlAppBarLogo(height: 28);
  }



  // ── Sticky header (app bar row + feed header + filter chips) ─────────────
  // Rendered as the `bottom:` of SliverAppBar(pinned:true) so the entire
  // block stays pinned while the feed content scrolls beneath it.
  Widget _buildStickyHeader(dynamic hc, bool isDark) {
    return Container(
      color: hc.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Logo row ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
            child: Row(
              children: [
                Semantics(
                  label: 'Huddl home',
                  child: _buildAdaptiveLogo(isDark),
                ),
                const Spacer(),
                // Search — opens unified search across all content types
                Semantics(
                  label: 'Search everything',
                  button: true,
                  child: Tooltip(
                    message: 'Search groups, meetups, services & market',
                    child: IconButton(
                      icon: const Icon(Icons.search),
                      color: hc.textPrimary,
                      onPressed: () {
                        HuddlAnimations.lightTap();
                        Navigator.of(context).push(HuddlSpringPageRoute(
                          page: const UnifiedSearchScreen(),
                        ));
                      },
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                  ),
                ),
                // Notification bell
                Semantics(
                  label: 'Notifications, $_notifBadgeCount new',
                  button: true,
                  child: HuddlBadge(
                    count: _notifBadgeCount,
                    child: IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      color: hc.textPrimary,
                      onPressed: () {
                        HuddlAnimations.lightTap();
                        _openNotifications();
                      },
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                  ),
                ),
                // Profile avatar
                Semantics(
                  label: 'Your profile',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      HuddlAnimations.lightTap();
                      _onAvatarTap();
                    },
                    child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(child: _buildSmallAvatar())),
                  ),
                ),
              ],
            ),
          ),
          // ── "Your Feed" title + subtitle + tune icon ─────────────
          _buildFeedFilterHeader(hc, isDark),
        ],
      ),
    );
  }

  // ── Feed filter header ────────────────────────────────────────────────────
  // Shows the screen title "Your Feed" with the settings gear on the right,
  // and a horizontally scrollable row of filter chips below it.
  Widget _buildFeedFilterHeader(dynamic hc, bool isDark) {
    // Filter chips removed — all content is shown at once.
    return Container(
      color: hc.surface,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Feed',
                    style: HuddlText.display(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Customise your feed',
              child: GestureDetector(
                onTap: () {
                  HuddlAnimations.lightTap();
                  _showFeedPreferences();
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: hc.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.tune_rounded,
                      size: 18, color: hc.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the smart feed items filtered by [_activeFeedFilter].
  List<_SmartFeedItem> _filteredSmartFeed(dynamic hc, bool isDark) {
    switch (_activeFeedFilter) {
      case 'meetups':
        return _smartFeed
            .where((i) =>
                i.type == _SmartFeedType.meetup ||
                i.type == _SmartFeedType.goingEvent ||
                i.type == _SmartFeedType.suggestedMeetup)
            .toList();
      case 'events':
        return _smartFeed
            .where((i) =>
                i.type == _SmartFeedType.goingEvent ||
                i.type == _SmartFeedType.meetup)
            .toList();
      case 'noticeboard':
        return []; // Noticeboard renders its own section above
      case 'tips':
        return _smartFeed
            .where((i) =>
                i.type == _SmartFeedType.aiNudge ||
                i.type == _SmartFeedType.communityActivity)
            .toList();
      case 'all':
      default:
        return _smartFeed;
    }
  }

  /// Greeting row: time-based greeting + bold name.
  /// Location shown as inline text line (no pill bubble).
  Widget _buildCompactGreeting(dynamic hc, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting + name — two separate Text widgets so the name
          // wraps to a second line rather than being cut off mid-word.
          Semantics(
            header: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_greeting,',
                  style: HuddlText.display(),
                ),
                Text(
                  _name.isNotEmpty ? _name : 'there',
                  style: HuddlText.display(color: hc.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Location + member count — single inline row, no pill
          Row(
            children: [
              Icon(Icons.location_on_rounded,
                  size: 13,
                  color: _borough.isNotEmpty
                      ? HuddlColors.primary
                      : hc.textTertiary),
              const SizedBox(width: 4),
              if (_borough.isNotEmpty)
                Text(
                  _borough,
                  style: HuddlText.caption(weight: FontWeight.w600),
                ),
              if (_borough.isNotEmpty && _boroughMembers.isNotEmpty)
                Text(
                  ' · ',
                  style: HuddlText.caption(color: hc.textTertiary),
                ),
              Expanded(
                child: Text(
                  _boroughMembers.isNotEmpty
                      ? '${_boroughMembers.length}+ parents here'
                      : _borough.isNotEmpty
                          ? 'Your local community'
                          : 'Your area',
                  overflow: TextOverflow.ellipsis,
                  style: HuddlText.caption(color: hc.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── UX-06: Section header — bare icon (no container), neutral 'See all' ──
  Widget _buildSectionHeader({
    required dynamic hc,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Coloured icon container — saturated Figma palette per section
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: HuddlText.body(weight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: HuddlText.caption(),
                ),
              ],
            ),
          ),
          // Orange 'See all' link
          Semantics(
            label: 'See all $title',
            button: true,
            child: GestureDetector(
              onTap: () { HuddlAnimations.selectionClick(); onSeeAll(); },
              child: Text(
                'See all',
                style: HuddlText.body(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── §4 Noticeboard section ────────────────────────────────────────────────
  // Uses a StreamBuilder on AnnouncementService.boroughStream so posts from
  // ALL users in the same borough appear in real-time without a manual refresh.
  // Shows up to 2 posts as compact tap-to-expand rows.
  // Pin / like / comment / share actions are preserved.
  Widget _buildNoticeboardSection(dynamic hc, bool isDark) {
    final topNudge = _aiFeedService.activeNudges.isNotEmpty
        ? _aiFeedService.activeNudges.first
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ───────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: hc.textPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.campaign_rounded,
                    size: 18, color: hc.textPrimary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Noticeboard',
                      style: HuddlText.body(weight: FontWeight.w700, color: hc.textPrimary),
                    ),
                    Text(
                      '${_borough.isNotEmpty ? _borough : 'Your borough'} community board',
                      style: HuddlText.caption(color: hc.textTertiary),
                    ),
                  ],
                ),
              ),
              // See all -> noticeboard full screen
              GestureDetector(
                onTap: () {
                  HuddlAnimations.selectionClick();
                  Navigator.pushNamed(context, '/noticeboard');
                },
                child: Text(
                  'See all',
                  style: HuddlText.caption(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── AI nudge row (if any) ────────────────────────────────────────
          if (topNudge != null) ...[
            GestureDetector(
              onTap: () {
                HuddlAnimations.selectionClick();
                _handleNudgeTap(topNudge);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: hc.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: hc.divider),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.push_pin_outlined,
                        size: 15, color: hc.textTertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        topNudge.title,
                        style: HuddlText.body(color: hc.textSecondary).copyWith(height: 1.35),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: hc.textTertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Live StreamBuilder — top 2 posts from Firestore ──────────────
          StreamBuilder<List<Announcement>>(
            stream: _announcementService.boroughStream,
            // initialData from the cache so there's no flash of empty state
            initialData: _announcementService.boroughAnnouncements,
            builder: (context, snapshot) {
              // Keep _announcements state in sync for badge counts etc.
              final live = snapshot.data ?? [];
              if (live.isNotEmpty && live != _announcements) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && live != _announcements) {
                    setState(() {
                      _announcements = live;
                    });
                    _buildSmartFeed();
                  }
                });
              }

              final topTwo = live.take(2).toList();

              if (topTwo.isEmpty) {
                // Empty state
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: hc.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: hc.divider),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.campaign_outlined,
                          size: 15, color: hc.textTertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No posts yet — be the first to share something with '
                          '${_borough.isNotEmpty ? _borough : 'your'} neighbours.',
                          style: HuddlText.caption(color: hc.textTertiary).copyWith(height: 1.4),
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Render up to 2 compact tap-to-expand rows
              return Column(
                children: topTwo
                    .map((ann) => _buildNoticeboardRow(ann, hc, isDark))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  /// A compact noticeboard row that expands to show full post + actions.
  Widget _buildNoticeboardRow(
      Announcement ann, dynamic hc, bool isDark) {
    return _NoticeboardRow(
      key: ValueKey(ann.id),
      announcement: ann,
      hc: hc,
      isDark: isDark,
      onLike: () async {
        await _toggleLike(ann.id);
      },
      onComment: () => _openComments(ann),
      onShare: () => _sharePost(ann),
      onMenu: () => _showPostMenu(ann),
    );
  }

  // ── AI Catch-Up Summary Card ──────────────────────────────────────────────
  // Always-visible card that surfaces what the user missed since last login:
  // new meetups, events, groups, market items. Dismissible per session.
  Widget _buildAiCatchUpCard(dynamic hc, bool isDark) {
    if (_catchUpDismissed) return const SizedBox.shrink();

    final lastLogin = _feedService.lastLogin;
    final now = DateTime.now();

    // Compute counts of new items since last login
    final sinceTime = lastLogin ?? now.subtract(const Duration(days: 7));
    final newMeetups = _upcomingMeetups
        .where((m) => m.dateTime.isAfter(sinceTime))
        .length;
    final newEvents = _eventService.events
        .where((e) => e.dateTime.isAfter(sinceTime))
        .length;
    final newGroupCount = _newPublicGroups
        .where((g) => !_isDefaultOnboardingGroup(g))
        .length;
    final newMarket = _rehomeService.allItems
        .where((i) => i.listedAt.isAfter(sinceTime))
        .length;

    // Friendly "last seen" label
    String lastSeenLabel;
    if (lastLogin == null) {
      lastSeenLabel = 'since you joined';
    } else {
      final days = now.difference(lastLogin).inDays;
      if (days == 0) {
        lastSeenLabel = 'since earlier today';
      } else if (days == 1) {
        lastSeenLabel = 'since yesterday';
      } else {
        lastSeenLabel = 'in the last $days days';
      }
    }

    // Build individual activity pills
    final List<_CatchUpItem> items = [];
    if (newMeetups > 0) {
      items.add(_CatchUpItem(
        icon: Icons.place_rounded,
        color: HuddlColors.nearBlack,
        label: '$newMeetups new meetup${newMeetups == 1 ? '' : 's'}',
        onTap: () => _switchToDiscover(1), // Meetups sub-tab
      ));
    }
    if (newEvents > 0) {
      items.add(_CatchUpItem(
        icon: Icons.event_rounded,
        color: HuddlColors.nearBlack,
        label: '$newEvents new event${newEvents == 1 ? '' : 's'}',
        onTap: () => _switchToDiscover(2), // Events sub-tab
      ));
    }
    if (newGroupCount > 0) {
      items.add(_CatchUpItem(
        icon: Icons.people_rounded,
        color: HuddlColors.nearBlack,
        label: '$newGroupCount group${newGroupCount == 1 ? '' : 's'} nearby',
        onTap: () => _switchToDiscover(0), // Groups sub-tab
      ));
    }
    if (newMarket > 0) {
      items.add(_CatchUpItem(
        icon: Icons.storefront_rounded,
        color: HuddlColors.nearBlack,
        label: '$newMarket item${newMarket == 1 ? '' : 's'} for sale',
        onTap: () => _switchToTab(3),
      ));
    }

    // When no new items, show a light "you're all caught up" state
    // so the card is always visible (matches the home screen mockup design).

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hc.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 0),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: HuddlColors.nearBlack.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Here's what you missed",
                          style: HuddlText.body(weight: FontWeight.w700),
                        ),
                        Text(
                          lastSeenLabel,
                          style: HuddlText.label(),
                        ),
                      ],
                    ),
                  ),
                  // Dismiss button
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(Icons.close, size: 16, color: hc.textTertiary),
                    onPressed: () {
                      HuddlAnimations.lightTap();
                      setState(() => _catchUpDismissed = true);
                    },
                  ),
                ],
              ),
            ),

            // Activity rows — card-style, no pills
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                child: Column(
                  children: items.asMap().entries.map((entry) {
                    final item = entry.value;
                    return InkWell(
                      onTap: () {
                        HuddlAnimations.selectionClick();
                        item.onTap();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            // Coloured icon square
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: item.color.withValues(
                                    alpha: isDark ? 0.20 : 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(item.icon,
                                  size: 18,
                                  color: isDark
                                      ? item.color.withValues(alpha: 0.85)
                                      : item.color),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.label,
                                style: HuddlText.body(),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 18, color: hc.textTertiary),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 14, color: HuddlColors.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      "You're all caught up! Scroll down to explore.",
                      style: HuddlText.caption(color: hc.textSecondary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }



  // ── "Don't Forget" carousel ──────────────────────────────────────────────
  // Shows only confirmed-attending items (isGoing meetups + goingEvents).
  // Sorted soonest first. Each card shows a countdown "in X days" chip.
  Widget _buildDontForgetCarousel(dynamic hc, bool isDark) {
    final now = DateTime.now();
    final items = <_DiscoverItem>[];

    // Going meetups — isGoing == true and still in the future
    for (final m in _upcomingMeetups
        .where((m) => m.isGoing && m.dateTime.isAfter(now))) {
      items.add(_DiscoverItem(
        type: _DiscoverType.meetup,
        sortDate: m.dateTime,
        title: m.title,
        subtitle: '${m.dateDisplay} · ${m.location.isNotEmpty ? m.location : m.category}',
        imageUrl: m.imageUrl.isNotEmpty ? m.imageUrl : _meetupCategoryImage(m.category),
        badge: _daysAwayLabel(m.dateTime),
        onTap: () {
          HuddlAnimations.selectionClick();
          setState(() => _meetupTaps++);
          Navigator.of(context)
              .push(HuddlSpringPageRoute(page: MeetupDetailScreen(meetup: m)));
        },
      ));
    }

    // Going events — in _goingEvents and still in the future
    for (final e in _goingEvents.where((e) => e.dateTime.isAfter(now))) {
      final eMap = e.toMap();
      items.add(_DiscoverItem(
        type: _DiscoverType.event,
        sortDate: e.dateTime,
        title: e.title,
        subtitle: '${e.dateDisplay} · ${e.location.isNotEmpty ? e.location : e.category}',
        imageUrl: e.imageUrl,
        badge: _daysAwayLabel(e.dateTime),
        onTap: () {
          HuddlAnimations.selectionClick();
          Navigator.of(context)
              .push(HuddlSpringPageRoute(page: EventDetailScreen(event: eMap)));
        },
      ));
    }

    // Sort soonest first
    items.sort((a, b) => a.sortDate.compareTo(b.sortDate));

    if (items.isEmpty) {
      return _buildDontForgetEmptyState(hc, isDark);
    }

    return SizedBox(
      height: 252,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) =>
            _buildDontForgetCard(items[index], hc, isDark),
      ),
    );
  }

  /// Returns "Today", "Tomorrow", or "in N days" countdown label.
  String _daysAwayLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (diff == 0) return 'Today!';
    if (diff == 1) return 'Tomorrow';
    return 'In $diff days';
  }

  /// Empty state shown in the "Don't Forget" section when the user has no RSVPs.
  /// Amber-tinted, with a dashed border and a CTA that navigates to Connect tab.
  Widget _buildDontForgetEmptyState(dynamic hc, bool isDark) {
    return Container(
      height: 120,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? hc.surface : const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: HuddlColors.divider,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Left neutral accent bar
          Container(
            width: 5,
            decoration: BoxDecoration(
              color: HuddlColors.nearBlack.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Bell icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: HuddlColors.nearBlack.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active_outlined,
              size: 20,
              color: HuddlColors.nearBlack.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 12),
          // Text + CTA
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Nothing confirmed yet",
                  style: HuddlText.body(weight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  "RSVP to a meetup or event and it'll appear here with a countdown.",
                  style: HuddlText.caption(color: hc.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    HuddlAnimations.lightTap();
                    _switchToTab(2); // Discover tab
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: HuddlColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Browse events →',
                      style: HuddlText.caption(weight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// Specialised "Don't Forget" card — identical hero/body to _buildDiscoverCard
  /// but renders the countdown badge prominently in amber + a "Going ✓" strip.
  Widget _buildDontForgetCard(_DiscoverItem item, dynamic hc, bool isDark) {
    // Design rule: all type pills nearBlack — no per-type colour coding
    final pillLabel = switch (item.type) {
      _DiscoverType.meetup  => 'MEETUP',
      _DiscoverType.event   => 'EVENT',
      _DiscoverType.group   => 'GROUP',
      _DiscoverType.sale    => 'SALE',
    };
    const pillColor = HuddlColors.nearBlack;

    Widget imageWidget = item.imageUrl.isNotEmpty
        ? HuddlNetworkImage(
            url: item.imageUrl,
            width: double.infinity,
            height: double.infinity,
            fallbackWidget: _discoverImageFallback(item.type, hc),
          )
        : _discoverImageFallback(item.type, hc);

    return ScaleOnPress(
      scale: 0.97,
      onTap: item.onTap,
      child: SizedBox(
        width: 200,
        child: HuddlCard(
        variant: HuddlCardVariant.standard,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero image ──────────────────────────────────────────
            SizedBox(
              height: 115,
              width: 200,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageWidget,
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x55000000)],
                        stops: [0.45, 1.0],
                      ),
                    ),
                  ),
                  // Type pill — top-left
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: pillColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(pillLabel,
                          style: HuddlText.label(color: Colors.white).copyWith(letterSpacing: 0.4)),
                    ),
                  ),
                  // Countdown badge — top-right, outlined pill
                  if (item.badge != null)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: item.badge == 'Today!'
                                ? Colors.redAccent
                                : HuddlColors.primary,
                            width: 1.5,
                          ),
                        ),
                        child: Text(item.badge!,
                            style: HuddlText.label().copyWith(letterSpacing: 0.2)),
                      ),
                    ),
                ],
              ),
            ),
            // ── Going confirmation strip — neutral, not orange-tinted
            Container(
              width: double.infinity,
              color: const Color(0xFFF7F7F7),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 11,
                      color: Color(0xFF4CAF50)),
                  const SizedBox(width: 4),
                  Text(
                    "You're going!",
                    style: HuddlText.label(),
                  ),
                ],
              ),
            ),
            // ── Card body ────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      item.title,
                      style: HuddlText.body(weight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    // Date / location subtitle
                    Text(
                      item.subtitle,
                      style: HuddlText.label(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    // ── Prominent countdown row ──────────────────────
                    // Outlined pill: white bg + orange border (not filled orange)
                    if (item.badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: item.badge == 'Today!'
                                ? Colors.redAccent
                                : HuddlColors.primary,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time_outlined,
                              size: 12,
                              color: item.badge == 'Today!'
                                  ? Colors.redAccent
                                  : HuddlColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.badge!,
                              style: HuddlText.caption(weight: FontWeight.w600),
                            ),
                          ],
                        ),
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

  // ignore: unused_element
  Widget _buildUpcomingMeetupsEventsCarousel(dynamic hc, bool isDark) =>
      _buildDontForgetCarousel(hc, isDark);

  // ── Discover New Listings carousel ───────────────────────────────────────
  // Merges Groups + Meetups + Events + Market items created in the last 7 days
  // (or since last login if more recent). Sorted newest → oldest.
  // Each card has a type pill badge so users know what they're tapping.
  Widget _buildDiscoverNewListingsCarousel(dynamic hc, bool isDark) {
    final now = DateTime.now();
    final lastLogin = _feedService.lastLogin;
    // Use whichever is more recent: last login or 7 days ago
    final cutoff = lastLogin != null && now.difference(lastLogin).inDays < 7
        ? lastLogin
        : now.subtract(const Duration(days: 7));

    // Build a unified list of _DiscoverItem wrappers
    final items = <_DiscoverItem>[];

    // Groups — use lastMessageTime as proxy; fallback to cutoff so they're included
    for (final g in _newPublicGroups.where((g) => !_isDefaultOnboardingGroup(g))) {
      items.add(_DiscoverItem(
        type: _DiscoverType.group,
        sortDate: g.lastMessageTime ?? cutoff.add(const Duration(seconds: 1)),
        title: g.name,
        subtitle: '${g.memberCount} member${g.memberCount == 1 ? '' : 's'} · ${g.category}',
        imageUrl: g.imageUrl.isNotEmpty ? g.imageUrl : _groupMosaicImages(g)[0],
        badge: g.isPrivate ? 'Members only' : null,
        onTap: () { HuddlAnimations.selectionClick(); setState(() => _groupTaps++); _switchToTab(2); },
      ));
    }

    // Meetups — use createdAt; include if created within cutoff window
    for (final m in _upcomingMeetups.where((m) => m.createdAt.isAfter(cutoff))) {
      items.add(_DiscoverItem(
        type: _DiscoverType.meetup,
        sortDate: m.createdAt,
        title: m.title,
        subtitle: '${m.dateDisplay} · ${m.location.isNotEmpty ? m.location : m.category}',
        imageUrl: m.imageUrl.isNotEmpty ? m.imageUrl : _meetupCategoryImage(m.category),
        badge: m.isGoing ? 'Going ✓' : null,
        onTap: () {
          HuddlAnimations.selectionClick();
          setState(() => _meetupTaps++);
          Navigator.of(context).push(HuddlSpringPageRoute(page: MeetupDetailScreen(meetup: m)));
        },
      ));
    }

    // Events — use dateTime as created proxy; include future events within cutoff
    for (final e in _eventService.events.where((e) => e.dateTime.isAfter(cutoff))) {
      final eMap = e.toMap();
      items.add(_DiscoverItem(
        type: _DiscoverType.event,
        sortDate: e.dateTime,
        title: e.title,
        subtitle: '${e.dateDisplay} · ${e.location}',
        imageUrl: e.imageUrl,
        badge: _goingEvents.any((ge) => ge.id == e.id) ? 'Going ✓' : null,
        onTap: () {
          HuddlAnimations.selectionClick();
          Navigator.of(context).push(HuddlSpringPageRoute(page: EventDetailScreen(event: eMap)));
        },
      ));
    }

    // Market items — use listedAt; include if listed within cutoff
    for (final item in _rehomeService.allItems.where((i) => i.listedAt.isAfter(cutoff))) {
      final priceStr = item.isFree
          ? 'Free'
          : '£${item.price % 1 == 0 ? item.price.toInt() : item.price.toStringAsFixed(2)}';
      items.add(_DiscoverItem(
        type: _DiscoverType.sale,
        sortDate: item.listedAt,
        title: item.title,
        subtitle: '$priceStr · ${item.condition.label}',
        imageUrl: item.imageUrls.isNotEmpty ? item.imageUrls.first : '',
        badge: item.isFree ? 'Free' : null,
        onTap: () {
          HuddlAnimations.selectionClick();
          setState(() => _marketTaps++);
          Navigator.of(context).push(HuddlSpringPageRoute(page: ItemDetailScreen(item: item)));
        },
      ));
    }

    // Sort newest → oldest
    items.sort((a, b) => b.sortDate.compareTo(a.sortDate));

    if (items.isEmpty) {
      return _buildCarouselEmpty(hc, 'No new listings this week', Icons.explore_outlined);
    }

    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildDiscoverCard(item, hc, isDark);
        },
      ),
    );
  }

  /// A single unified Discover card — image hero + type pill + title + subtitle.
  Widget _buildDiscoverCard(_DiscoverItem item, dynamic hc, bool isDark) {
    // Type pill colour + label
    // Design rule: GROUP/MEETUP/EVENT badges are informational category labels
    // → infoBluePale bg with infoBlue text. FOR SALE stays dark (commerce action).
    final (pillLabel, pillBg, pillText) = switch (item.type) {
      _DiscoverType.group   => ('GROUP',    HuddlColors.infoBluePale, HuddlColors.infoBlue),
      _DiscoverType.meetup  => ('MEETUP',   HuddlColors.infoBluePale, HuddlColors.infoBlue),
      _DiscoverType.event   => ('EVENT',    HuddlColors.infoBluePale, HuddlColors.infoBlue),
      _DiscoverType.sale    => ('FOR SALE', HuddlColors.nearBlack,    Colors.white),
    };

    // Image widget — network, fallback icon
    Widget imageWidget;
    if (item.imageUrl.isNotEmpty) {
      imageWidget = HuddlNetworkImage(
        url: item.imageUrl,
        width: double.infinity,
        height: double.infinity,
        fallbackWidget: _discoverImageFallback(item.type, hc),
      );
    } else {
      imageWidget = _discoverImageFallback(item.type, hc);
    }

    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        width: 190,
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark
              ? null
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12, offset: const Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero image with type pill ─────────────────────────
            SizedBox(
              height: 120,
              width: 190,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageWidget,
                  // Subtle bottom gradient
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x44000000)],
                        stops: [0.5, 1.0],
                      ),
                    ),
                  ),
                  // Type pill — top-left
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 4)],
                      ),
                      child: Text(
                        pillLabel,
                        style: HuddlText.label(color: pillText).copyWith(letterSpacing: 0.4),
                      ),
                    ),
                  ),
                  // Optional badge — top-right (Going / Free / Members only)
                  if (item.badge != null)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.badge!,
                          style: HuddlText.label(color: HuddlColors.nearBlack),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ── Card body ─────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.title,
                      style: HuddlText.body(weight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.subtitle,
                      style: HuddlText.caption(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _discoverImageFallback(_DiscoverType type, dynamic hc) {
    // Design rule: fallback icon colours all nearBlack
    final (icon, color) = switch (type) {
      _DiscoverType.group  => (Icons.people_outline,     HuddlColors.nearBlack),
      _DiscoverType.meetup => (Icons.place_outlined,     HuddlColors.nearBlack),
      _DiscoverType.event  => (Icons.event_outlined,     HuddlColors.nearBlack),
      _DiscoverType.sale   => (Icons.storefront_outlined,HuddlColors.nearBlack),
    };
    return Container(
      color: color.withValues(alpha: 0.08),
      child: Center(child: Icon(icon, size: 36, color: color.withValues(alpha: 0.5))),
    );
  }

  // ── Groups carousel ───────────────────────────────────────────────────────
  // ── UX-02: Groups carousel — HuddlMosaicPhotoCard
  //
  // Group model only has a single imageUrl, so we compose a 4-image mosaic by
  // pairing the group's own photo with 3 category-matched Pexels stock images.
  // Mosaic collage layout without requiring extra data
  // model to be changed.
  // ignore: unused_element
  Widget _buildGroupsCarousel(dynamic hc) {
    final groups = _newPublicGroups.where((g) => !_isDefaultOnboardingGroup(g)).take(8).toList();
    if (groups.isEmpty) {
      return _buildCarouselEmpty(hc, 'No new groups yet', Icons.people_outline);
    }
    return SizedBox(
      height: 280,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final g = groups[index];
          return SizedBox(
            width: 210,
            child: HuddlMosaicPhotoCard(
              images: _groupMosaicImages(g),
              title: g.name,
              subtitle: '${g.memberCount} members · ${g.category}',
              badge: g.isPrivate ? 'Members only' : null,
              stat: '${g.memberCount} ★',
              showSaveButton: false,
              onTap: () {
                HuddlAnimations.selectionClick();
                setState(() => _groupTaps++);
                _switchToTab(2);
              },
            ),
          );
        },
      ),
    );
  }

  /// Builds a 4-image list for [HuddlMosaicPhotoCard] from a [Group].
  ///
  /// The group's own [imageUrl] fills slot 0.  Slots 1–3 are filled with
  /// category-themed Pexels stock photos so the mosaic always looks complete
  /// even when the group only has one image.
  static List<String> _groupMosaicImages(Group g) {
    final stock = _groupCategoryStockImages(g.category);
    return [
      g.imageUrl.isNotEmpty ? g.imageUrl : stock[0],
      stock[0],
      stock[1],
      stock[2],
    ];
  }

  /// Returns 3 Pexels stock image URLs that match a group category.
  /// Used as mosaic fill images alongside the group's own photo.
  static List<String> _groupCategoryStockImages(String category) {
    switch (category.toLowerCase()) {
      case 'fitness':
      case 'sport':
      case 'exercise':
        return [
          'https://images.pexels.com/photos/3822864/pexels-photo-3822864.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/1552242/pexels-photo-1552242.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/4056723/pexels-photo-4056723.jpeg?auto=compress&cs=tinysrgb&w=300',
        ];
      case 'arts':
      case 'crafts':
      case 'creative':
        return [
          'https://images.pexels.com/photos/1266808/pexels-photo-1266808.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/102127/pexels-photo-102127.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/374074/pexels-photo-374074.jpeg?auto=compress&cs=tinysrgb&w=300',
        ];
      case 'food':
      case 'cooking':
      case 'dining':
        return [
          'https://images.pexels.com/photos/1640777/pexels-photo-1640777.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/1640772/pexels-photo-1640772.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/2097090/pexels-photo-2097090.jpeg?auto=compress&cs=tinysrgb&w=300',
        ];
      case 'music':
        return [
          'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/1751731/pexels-photo-1751731.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/210922/pexels-photo-210922.jpeg?auto=compress&cs=tinysrgb&w=300',
        ];
      case 'outdoor':
      case 'nature':
      case 'walk':
        return [
          'https://images.pexels.com/photos/1325735/pexels-photo-1325735.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/1761279/pexels-photo-1761279.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/2258536/pexels-photo-2258536.jpeg?auto=compress&cs=tinysrgb&w=300',
        ];
      case 'tech':
      case 'technology':
      case 'coding':
        return [
          'https://images.pexels.com/photos/3861969/pexels-photo-3861969.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/1181671/pexels-photo-1181671.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/574071/pexels-photo-574071.jpeg?auto=compress&cs=tinysrgb&w=300',
        ];
      case 'parenting':
      case 'family':
      case 'kids':
        return [
          'https://images.pexels.com/photos/3933239/pexels-photo-3933239.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/1741231/pexels-photo-1741231.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/3662852/pexels-photo-3662852.jpeg?auto=compress&cs=tinysrgb&w=300',
        ];
      case 'books':
      case 'reading':
      case 'book club':
        return [
          'https://images.pexels.com/photos/1148399/pexels-photo-1148399.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/159866/books-book-pages-read-literature-159866.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/904616/pexels-photo-904616.jpeg?auto=compress&cs=tinysrgb&w=300',
        ];
      case 'default community':
      default:
        return [
          'https://images.pexels.com/photos/3933250/pexels-photo-3933250.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/1128318/pexels-photo-1128318.jpeg?auto=compress&cs=tinysrgb&w=300',
          'https://images.pexels.com/photos/1266808/pexels-photo-1266808.jpeg?auto=compress&cs=tinysrgb&w=300',
        ];
    }
  }

  // ── UX-02: Meetups carousel — HuddlSinglePhotoCard ───────────────────────
  // ignore: unused_element
  Widget _buildMeetupsCarousel(dynamic hc) {
    final meetups = _upcomingMeetups.take(8).toList();
    if (meetups.isEmpty) {
      return _buildCarouselEmpty(hc, 'No upcoming meetups', Icons.place);
    }
    return SizedBox(
      height: 280,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: meetups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final m = meetups[index];
          final isGoing = m.isGoing;
          return SizedBox(
            width: 200,
            child: HuddlSinglePhotoCard(
              imageUrl: m.imageUrl.isNotEmpty ? m.imageUrl : _meetupCategoryImage(m.category),
              title: m.title,
              subtitle: '${m.dateDisplay} · ${m.location.isNotEmpty ? m.location : m.category}',
              badge: isGoing ? 'Going ✓' : null,
              stat: '${m.attendeeCount} attending',
              statIcon: Icons.people_outline,
              isSaved: isGoing,
              showSaveButton: false,
              aspectRatio: 1.1,
              onTap: () {
                HuddlAnimations.selectionClick();
                setState(() => _meetupTaps++);
                Navigator.of(context).push(HuddlSpringPageRoute(page: MeetupDetailScreen(meetup: m)));
              },
            ),
          );
        },
      ),
    );
  }

  // ── Events carousel ───────────────────────────────────────────────────────
  // ignore: unused_element
  Widget _buildEventsCarousel(dynamic hc) {
    final events = _eventService.events.take(8).toList();
    if (events.isEmpty) {
      return _buildCarouselEmpty(hc, 'No events listed yet', Icons.event_outlined);
    }
    return SizedBox(
      height: 320,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final e = events[index];
          final isGoing = _goingEvents.any((ge) => ge.id == e.id);
          final eMap = e.toMap();
          final hasImage = e.imageUrl.isNotEmpty;
          return GestureDetector(
            onTap: () {
              HuddlAnimations.selectionClick();
              Navigator.of(context).push(HuddlSpringPageRoute(page: EventDetailScreen(event: eMap)));
            },
            child: Container(
              width: 220,
              decoration: BoxDecoration(
                color: hc.surface,
                borderRadius: BorderRadius.circular(16),
                border: isGoing ? Border.all(color: HuddlColors.divider, width: 1) : null,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero photo
                  SizedBox(
                    height: 150, width: 220,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        hasImage
                            ? HuddlNetworkImage(
                                url: e.imageUrl,
                                width: double.infinity,
                                height: double.infinity,
                                fallbackWidget: _eventImageFallback(),
                              )
                            : _eventImageFallback(),
                        // Date badge — bottom-left
                        Positioned(
                          bottom: 8, left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: HuddlColors.nearBlack,
                              borderRadius: BorderRadius.circular(7),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                            ),
                            child: Text(e.dateDisplay,
                              style: HuddlText.label(color: Colors.white)),
                          ),
                        ),
                        // Going badge — top-right
                        if (isGoing)
                          Positioned(
                            top: 8, right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: HuddlColors.success,  // teal — confirmed attendance
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.check_circle, size: 10, color: Colors.white),
                                const SizedBox(width: 3),
                                Text('Going', style: HuddlText.label(color: Colors.white)),
                              ]),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Card body
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.category.toUpperCase(),
                          style: HuddlText.label(color: hc.textTertiary).copyWith(letterSpacing: 0.5),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(e.title,
                          style: HuddlText.body(weight: FontWeight.w600, color: hc.textPrimary),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (e.location.isNotEmpty) ...[  
                          const SizedBox(height: 3),
                          Row(children: [
                            Icon(Icons.location_on_outlined, size: 11, color: hc.textTertiary),
                            const SizedBox(width: 2),
                            Expanded(child: Text(e.location,
                              style: HuddlText.caption(color: hc.textTertiary).copyWith(fontStyle: FontStyle.italic),
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ]),
                        ],
                        const SizedBox(height: 10),
                        Row(children: [
                          _buildAvatarStack(e.id.hashCode, hc),
                          const SizedBox(width: 5),
                          Expanded(child: Text('${e.attendees} attending',
                            style: HuddlText.label(color: hc.textTertiary))),
                          _buildActionPill(
                            isGoing ? 'Going ✓' : 'Book',
                            isGoing ? HuddlColors.nearBlack : HuddlColors.primary,
                            hc,
                            isActive: isGoing,
                          ),
                        ]),
                      ],
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

  Widget _eventImageFallback() {
    return Container(
      color: const Color(0xFFF7F7F7),
      child: Center(
        child: Icon(Icons.event_outlined, size: 32,
            color: HuddlColors.nearBlack.withValues(alpha: 0.3)),
      ),
    );
  }

  // ── Services carousel ─────────────────────────────────────────────────────
  // ignore: unused_element
  Widget _buildServicesCarousel(dynamic hc) {
    final services = _featuredServices.take(8).toList();
    if (services.isEmpty) {
      return _buildCarouselEmpty(hc, 'No services listed yet', Icons.handshake_outlined);
    }
    return SizedBox(
      height: 320,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: services.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final s = services[index];
          final hasImage = s.imageUrl != null && s.imageUrl!.isNotEmpty;
          return GestureDetector(
            onTap: () { HuddlAnimations.selectionClick(); _switchToTab(2); },
            child: Container(
              width: 220,
              decoration: BoxDecoration(
                color: hc.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero photo with category badge
                  SizedBox(
                    height: 150, width: 220,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        hasImage
                            ? HuddlNetworkImage(
                                url: s.imageUrl!,
                                width: double.infinity,
                                height: double.infinity,
                                fallbackWidget: _serviceImageFallback(s.category.emoji),
                              )
                            : _serviceImageFallback(s.category.emoji),
                        // Category badge — top-right
                        Positioned(
                          top: 8, right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: HuddlColors.nearBlack,
                              borderRadius: BorderRadius.circular(7),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                            ),
                            child: Text(s.category.displayName,
                              style: HuddlText.label(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Card body
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.category.displayName.toUpperCase(),
                          style: HuddlText.label(color: hc.textTertiary).copyWith(letterSpacing: 0.5),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(s.name,
                          style: HuddlText.body(weight: FontWeight.w600, color: hc.textPrimary),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (s.tagline.isNotEmpty) ...[  
                          const SizedBox(height: 3),
                          Text(s.tagline,
                            style: HuddlText.caption(color: hc.textTertiary).copyWith(fontStyle: FontStyle.italic),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 10),
                        Row(children: [
                          _buildAvatarStack(s.id.hashCode, hc),
                          const SizedBox(width: 5),
                          Expanded(child: Text(
                            s.endorsementCount > 0 ? '${s.endorsementCount} endorsed' : 'Recommended',
                            style: HuddlText.label(color: hc.textTertiary))),
                          _buildActionPill('View', HuddlColors.primary, hc),
                        ]),
                      ],
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

  Widget _serviceImageFallback(String emoji) {
    return Container(
      color: const Color(0xFFF7F7F7),
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 32)),
      ),
    );
  }

  // ── Market carousel — horizontal scroll matching Groups/Meetups style ────
  // ignore: unused_element
  Widget _buildMarketCarousel(dynamic hc) {
    final items = _rehomeService.allItems.take(8).toList();
    if (items.isEmpty) {
      return _buildCarouselEmpty(hc, 'No items listed yet', Icons.storefront_outlined);
    }
    return SizedBox(
      height: 320,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final hasImage = item.imageUrls.isNotEmpty;
          final priceStr = item.isFree
              ? 'Free'
              : '£${item.price % 1 == 0 ? item.price.toInt() : item.price.toStringAsFixed(2)}';
          final priceColor = item.isFree ? HuddlColors.success : HuddlColors.textDark;
          return GestureDetector(
            onTap: () {
              HuddlAnimations.selectionClick();
              setState(() => _marketTaps++);
              Navigator.of(context).push(HuddlSpringPageRoute(page: ItemDetailScreen(item: item)));
            },
            child: Container(
              width: 220,
              decoration: BoxDecoration(
                color: hc.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero photo with condition badge overlay
                  SizedBox(
                    height: 150, width: 220,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        hasImage
                            ? HuddlNetworkImage(
                                url: item.imageUrls.first,
                                width: double.infinity,
                                height: double.infinity,
                                fallbackWidget: _marketImageFallback(item),
                              )
                            : _marketImageFallback(item),
                        // Subtle gradient
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
                          top: 8, right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: item.condition.color,
                              borderRadius: BorderRadius.circular(7),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                            ),
                            child: Text(item.condition.label,
                              style: HuddlText.label(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Card body
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.category.label.toUpperCase(),
                          style: HuddlText.label(color: hc.textTertiary).copyWith(letterSpacing: 0.5),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(item.title,
                          style: HuddlText.body(weight: FontWeight.w600, color: hc.textPrimary),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (item.sellerLocation.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(children: [
                            Icon(Icons.location_on_outlined, size: 11, color: hc.textTertiary),
                            const SizedBox(width: 2),
                            Expanded(child: Text(item.sellerLocation,
                              style: HuddlText.caption(color: hc.textTertiary).copyWith(fontStyle: FontStyle.italic),
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ]),
                        ],
                        const SizedBox(height: 10),
                        Row(children: [
                          _buildAvatarStack(item.id.hashCode, hc),
                          const SizedBox(width: 5),
                          Expanded(child: Text('Near you',
                            style: HuddlText.label(color: hc.textTertiary))),
                          // Price pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: item.isFree
                                  ? HuddlColors.nearBlack.withValues(alpha: 0.10)
                                  : const Color(0xFFF2F2F2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(priceStr,
                              style: HuddlText.caption(weight: FontWeight.w700, color: priceColor)),
                          ),
                        ]),
                      ],
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

  // ── Shared carousel card helpers ──────────────────────────────────────────

  /// 3 overlapping deterministic avatar circles (Groups-card pattern).
  Widget _buildAvatarStack(int seed, dynamic hc, [Color borderColor = Colors.white]) {  // ignore: unused_element_parameter
    const avatars = [
      'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=48&q=70',
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=48&q=70',
      'https://images.unsplash.com/photo-1527980965255-d3b416303d12?w=48&q=70',
      'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=48&q=70',
      'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=48&q=70',
      'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=48&q=70',
    ];
    return SizedBox(
      width: 56, height: 22,
      child: Stack(
        children: [
          for (int i = 0; i < 3; i++)
            Positioned(
              left: i * 16.0,
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: ClipOval(
                  child: Image.network(
                    avatars[(seed + i) % avatars.length],
                    width: 22, height: 22, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: HuddlColors.gray100,
                      child: const Icon(Icons.person, size: 11, color: HuddlColors.textHint),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// UX-06: Rounded pill action button — textDark always, no accent colour.
  Widget _buildActionPill(String label, Color accentColor, dynamic hc, {bool isActive = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isActive
            ? HuddlColors.textDark.withValues(alpha: 0.08)
            : const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HuddlColors.divider, width: 0.5),
      ),
      child: Text(
        label,
        style: HuddlText.caption(),
      ),
    );
  }

  Widget _marketImageFallback(RehomeItem item) {
    return Container(
      color: HuddlColors.gray100,
      child: Center(
        child: Icon(item.category.icon, size: 28, color: HuddlColors.textHint),
      ),
    );
  }

  Widget _buildCarouselEmpty(dynamic hc, String message, IconData icon) {
    return Container(
      height: 110,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hc.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: hc.textTertiary),
            const SizedBox(height: 6),
            Text(message,
                style: HuddlText.body(color: hc.textTertiary)),
          ],
        ),
      ),
    );
  }

  /// Smart post composer with AI-generated contextual hints
  /// Opens the Huddl Assistant screen, optionally passing any text the user
  /// has typed in the composer as an initial message.
  void _openAssistant() {
    HuddlAnimations.mediumTap();
    final text = _postController.text.trim();
    _postController.clear();
    Navigator.pushNamed(
      context,
      '/copilot',
      arguments: text.isNotEmpty
          ? {'initialMessage': text, 'autoSend': false}
          : null,
    );
  }

  // ignore: unused_element
  Widget _buildSmartPostComposer(dynamic hc, bool isDark) {
    return Semantics(
      label: 'Ask the huddl assistant',
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
          border: isDark ? Border.all(color: hc.divider) : null,
        ),
        child: Row(
          children: [
            _buildTinyAvatar(),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _postController,
                decoration: InputDecoration(
                  hintText: _aiPostHint.isNotEmpty
                      ? _aiPostHint
                      : 'Ask huddl assistant anything...',
                  hintStyle: HuddlText.body(),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                style: HuddlText.body(),
                textAlignVertical: TextAlignVertical.center,
                maxLines: 2,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _openAssistant(),
              ),
            ),
            const SizedBox(width: 6),
            Semantics(
              label: 'Open huddl assistant',
              button: true,
              child: GestureDetector(
                onTap: _openAssistant,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: HuddlColors.primary,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.arrow_forward_rounded,
                          size: 16, color: HuddlColors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Noticeboard composer bar ─────────────────────────────────────────────
  // Tappable row that opens a bottom sheet to post to the borough noticeboard.
  Widget _buildNoticeboardComposer(dynamic hc, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GestureDetector(
        onTap: () => _openNoticeboardComposerSheet(hc, isDark),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hc.divider),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Icon(Icons.campaign_outlined, size: 20, color: hc.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Post something to ${_borough.isNotEmpty ? _borough : 'your community'}...',
                  style: HuddlText.body(color: hc.textTertiary),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: HuddlColors.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.send_rounded, size: 14, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openNoticeboardComposerSheet(dynamic hc, bool isDark) {
    final controller = TextEditingController();
    HuddlAnimations.lightTap();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: hc.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HuddlBottomSheetHandle(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Post to ${_borough.isNotEmpty ? _borough : 'community'}',
                        style: HuddlText.body(weight: FontWeight.w700, color: hc.textPrimary),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        maxLength: 280,
                        maxLines: 5,
                        minLines: 3,
                        decoration: InputDecoration(
                          hintText:
                              "Share something with your ${_borough.isNotEmpty ? _borough : 'community'} neighbours...",
                          hintStyle: HuddlText.body(color: hc.textTertiary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: hc.divider),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: hc.divider),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: HuddlColors.primary),
                          ),
                          filled: true,
                          fillColor: hc.scaffold,
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        style: HuddlText.body(color: hc.textPrimary),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: HuddlButton(
                        label: 'Post to ${_borough.isNotEmpty ? _borough : 'community'}',
                        onPressed: controller.text.trim().isEmpty
                            ? null
                            : () {
                                final content = controller.text.trim();
                                Navigator.pop(ctx);
                                _postToBoroughNoticeboard(content);
                              },
                        variant: HuddlButtonVariant.primary,
                        fullWidth: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _postToBoroughNoticeboard(String content) async {
    if (content.trim().isEmpty) return;
    try {
      await _announcementService.post(content.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: context.hc.surface, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Posted to ${_borough.isNotEmpty ? _borough : 'community'} community',
                    style: HuddlText.body(),
                  ),
                ),
              ],
            ),
            backgroundColor: HuddlColors.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
        // Increment interaction count
        try {
          final countStr =
              await BrowserStorage.getString('huddl_interaction_count');
          final count = (int.tryParse(countStr ?? '') ?? 0) + 1;
          await BrowserStorage.setString(
              'huddl_interaction_count', count.toString());
          if (count >= 3 && _isFirstRun) {
            setState(() => _isFirstRun = false);
          }
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post. Please try again.',
                style: HuddlText.body()),
            backgroundColor: HuddlColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // ── First-run onboarding card ──────────────────────────────────────────────
  Widget _buildFirstRunCard(dynamic hc, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hc.divider),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome to ${_borough.isNotEmpty ? _borough : 'Huddl'}!',
                          style: HuddlText.body(weight: FontWeight.w700, color: hc.textPrimary),
                        ),
                        Text(
                          "Here's how to get the most out of huddl",
                          style: HuddlText.caption(color: hc.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  // Dismiss X
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon:
                        Icon(Icons.close, size: 18, color: hc.textTertiary),
                    onPressed: () async {
                      HuddlAnimations.lightTap();
                      await BrowserStorage.setString(
                          'huddl_interaction_count', '3');
                      setState(() => _isFirstRun = false);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Action rows
            _buildFirstRunRow(
              hc: hc,
              icon: Icons.people_outline,
              title: 'Join a group near you',
              ctaLabel: 'Browse groups',
              onTap: () async {
                HuddlAnimations.selectionClick();
                _switchToTab(1);
                await _incrementInteractionCount();
              },
            ),
            Divider(height: 1, thickness: 0.5, color: hc.divider, indent: 44),
            _buildFirstRunRow(
              hc: hc,
              icon: Icons.place,
              title: 'Find a local meetup',
              ctaLabel: 'See meetups',
              onTap: () async {
                HuddlAnimations.selectionClick();
                _switchToTab(2);
                await _incrementInteractionCount();
              },
            ),
            Divider(height: 1, thickness: 0.5, color: hc.divider, indent: 44),
            _buildFirstRunRow(
              hc: hc,
              icon: Icons.campaign_outlined,
              title: 'Say hello to your neighbours',
              ctaLabel: 'Post now',
              onTap: () async {
                HuddlAnimations.selectionClick();
                final isDarkMode =
                    Theme.of(context).brightness == Brightness.dark;
                _openNoticeboardComposerSheet(hc, isDarkMode);
                await _incrementInteractionCount();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildFirstRunRow({
    required dynamic hc,
    required IconData icon,
    required String title,
    required String ctaLabel,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: hc.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: HuddlText.body(color: hc.textPrimary)),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: HuddlColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                ctaLabel,
                style: HuddlText.caption(weight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _incrementInteractionCount() async {
    try {
      final countStr =
          await BrowserStorage.getString('huddl_interaction_count');
      final count = (int.tryParse(countStr ?? '') ?? 0) + 1;
      await BrowserStorage.setString(
          'huddl_interaction_count', count.toString());
      if (count >= 3 && mounted) {
        setState(() => _isFirstRun = false);
      }
    } catch (_) {}
  }

  // ── §3 "Today for you" — kept as fallback, superseded by Upcoming carousel ──
  // ignore: unused_element
  Widget? _buildTodayForYouCard(dynamic hc, bool isDark) {
    // ── Personalised candidate selection ─────────────────────────────────────
    // Priority 1: soonest meetup the user has already RSVP'd (isGoing == true)
    // Priority 2: meetup in user's borough matching their stage-of-life category
    // Priority 3: any upcoming meetup (first in list)
    // Priority 4: event, then service as fallback
    dynamic candidate;
    String candidateType = '';
    String ctaLabel = 'View';
    IconData candidateIcon = Icons.event_rounded;
    Color candidateColor = HuddlColors.primary;   // warm orange default
    // ignore: no_leading_underscores_for_local_identifiers
    String _reasonTag = '';   // shown as a pill below the category tag

    if (_upcomingMeetups.isNotEmpty) {
      // Priority 1: RSVP'd meetup — user is already committed
      final goingMeetup = _upcomingMeetups
          .where((m) => m.isGoing)
          .toList()
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

      if (goingMeetup.isNotEmpty) {
        candidate = goingMeetup.first;
        _reasonTag = "You're going!";
      } else {
        // Priority 2: stage-of-life match in user's borough
        final stages = _onboarding.stagesOfLife
            .map((s) => s.toLowerCase())
            .toList();
        // Map stages → preferred category keywords
        final stageKeywords = <String>[];
        for (final s in stages) {
          if (s.contains('expect') || s.contains('pregnan') || s.contains('due')) {
            stageKeywords.addAll(['antenatal', 'pregnancy', 'social']);
          }
          if (s.contains('baby') || s.contains('newborn') || s.contains('infant')) {
            stageKeywords.addAll(['baby', 'social', 'coffee']);
          }
          if (s.contains('toddler') || s.contains('1') || s.contains('2') || s.contains('3')) {
            stageKeywords.addAll(['playdate', 'walk', 'sport']);
          }
        }

        Meetup? stageMatch;
        if (stageKeywords.isNotEmpty) {
          stageMatch = _upcomingMeetups.cast<Meetup?>().firstWhere(
            (m) => m != null &&
                stageKeywords.any((kw) => m.category.toLowerCase().contains(kw)),
            orElse: () => null,
          );
        }

        if (stageMatch != null) {
          candidate = stageMatch;
          _reasonTag = 'Near you in $_borough';
        } else {
          // Priority 3: soonest meetup regardless
          candidate = _upcomingMeetups.first;
          _reasonTag = 'New in ${(_upcomingMeetups.first.category)}';
        }
      }

      candidateType = 'MEETUP';
      ctaLabel = (candidate as Meetup).isGoing ? 'View' : 'Join';
      candidateIcon = Icons.place_rounded;
      candidateColor = HuddlColors.primary;         // warm orange meetup CTA

    } else if (_eventService.events.isNotEmpty) {
      candidate = _eventService.events.first;
      candidateType = 'EVENT';
      ctaLabel = 'Book';
      candidateIcon = Icons.event_rounded;
      candidateColor = HuddlColors.primary;
      _reasonTag = 'New in ${_borough.isNotEmpty ? _borough : 'your area'}';
    } else if (_featuredServices.isNotEmpty) {
      candidate = _featuredServices.first;
      candidateType = 'SERVICE';
      ctaLabel = 'View';
      candidateIcon = Icons.handshake_rounded;
      candidateColor = HuddlColors.success;         // teal — services
    }

    if (candidate == null) return null;

    // Extract fields from candidate dynamically
    final title = (candidate.title as String?) ?? '';
    final location = (candidate.location as String?) ??
        (candidate.address as String?) ?? '';
    final imageUrl = (candidate.imageUrl as String?) ?? '';
    final category = (candidate.category as String?) ?? candidateType;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: hc.textTertiary),
              const SizedBox(width: 8),
              Text(
                'Today for you',
                style: HuddlText.body(weight: FontWeight.w700),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () { HuddlAnimations.selectionClick(); _switchToTab(2); },
                child: Text(
                  'See all',
                  style: HuddlText.body(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Full-width card
          ScaleOnPress(
            scale: 0.98,
            onTap: () { HuddlAnimations.selectionClick(); _switchToTab(2); },
            child: Container(
              decoration: BoxDecoration(
                color: hc.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isDark
                    ? null
                    : [
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
                  // Hero image
                  if (imageUrl.isNotEmpty)
                    SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: HuddlNetworkImage(
                        url: imageUrl,
                        width: double.infinity,
                        height: 160,
                        fallbackWidget: Container(
                          color: candidateColor.withValues(alpha: 0.12),
                          child: Center(
                            child: Icon(candidateIcon,
                                size: 48, color: candidateColor.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 120,
                      color: candidateColor.withValues(alpha: 0.1),
                      child: Center(
                        child: Icon(candidateIcon,
                            size: 48, color: candidateColor.withValues(alpha: 0.4)),
                      ),
                    ),
                  // Card body
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: candidateColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            category.toUpperCase(),
                            style: HuddlText.label(color: candidateColor),
                          ),
                        ),
                        // Reason tag pill — personalisation signal
                        if (_reasonTag.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: hc.surfaceAlt,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _reasonTag,
                              style: HuddlText.label(),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: HuddlText.body(weight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 13, color: hc.textTertiary),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  location,
                                  style: HuddlText.caption(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        // CTA button
                        HuddlButton(
                          label: ctaLabel,
                          onPressed: () {
                            HuddlAnimations.mediumTap();
                            _switchToTab(2);
                          },
                          variant: HuddlButtonVariant.primary,
                          fullWidth: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Feed preferences sheet (interactive + persisted) ─────────────────────
  void _showFeedPreferences() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FeedPreferencesSheet(
        initialPrefs: Map<String, bool>.from(_feedPrefs),
        onSaved: (updatedPrefs) {
          setState(() => _feedPrefs = updatedPrefs);
          _saveFeedPrefs();
          _buildSmartFeed();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Preferences saved',
                  style: HuddlText.body()),
              backgroundColor: HuddlColors.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  // ── Smart feed card router ────────────────────────────────────────────────
  Widget _buildSmartFeedCard(
      _SmartFeedItem item, dynamic hc, bool isDark) {
    switch (item.type) {
      case _SmartFeedType.aiNudge:
        return _buildInlineNudge(item, hc);
      case _SmartFeedType.meetup:
        return _buildMeetupFeedCard(item, hc);
      case _SmartFeedType.goingEvent:
        return _buildGoingEventFeedCard(item, hc);
      case _SmartFeedType.suggestedMeetup:
        return _buildSuggestedMeetupCard(item, hc);
      case _SmartFeedType.announcement:
        return _buildAnnouncementFeedCard(item, hc, isDark);
      case _SmartFeedType.group:
        return _buildGroupFeedCard(item, hc);
      case _SmartFeedType.communityActivity:
        return _buildCommunityFeedCard(item, hc);
      case _SmartFeedType.partnerPromoted:
        return _buildPartnerPromotedCard(item, hc);
    }
  }

  /// Returns a short, plain-English category label for each nudge type so
  /// users always know at a glance what kind of content they are seeing.
  String _nudgeCategoryLabel(NudgeType type) {
    switch (type) {
      case NudgeType.knowledgeNudge:
        return 'Parenting tip';
      case NudgeType.vaccinationReminder:
        return 'Health reminder';
      case NudgeType.seasonalActivity:
        return 'Activity idea';
      case NudgeType.dadSpecific:
        return 'For dads';
      case NudgeType.digitalSafetyTip:
        return 'Online safety';
      case NudgeType.charityEvent:
        return 'Charity event';
      case NudgeType.emotionalIntelligence:
        return 'Wellbeing';
      case NudgeType.ecoParenting:
        return 'Eco parenting';
      case NudgeType.schoolReadiness:
        return 'School readiness';
      case NudgeType.siblingSupport:
        return 'Sibling support';
      case NudgeType.separationSupport:
        return 'Family support';
      case NudgeType.nearbyMeetup:
        return 'Nearby meetup';
      case NudgeType.groupSuggestion:
        return 'Suggested group';
      case NudgeType.weatherActivity:
        return 'Today\'s activity';
      case NudgeType.weeklyDigest:
        return 'Weekly digest';
      case NudgeType.communityWelcome:
        return 'Welcome';
      case NudgeType.trendingItem:
        return 'Trending nearby';
      case NudgeType.reengagement:
        return 'Back in the loop';
      case NudgeType.milestone:
        return 'Milestone';
    }
  }

  /// Inline AI nudge — compact, not a carousel.
  /// Uses dark-mode-aware colours so the card remains readable regardless of
  /// the system brightness.
  Widget _buildInlineNudge(_SmartFeedItem item, dynamic hc) {
    final nudge = item.nudge!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Card colours
    final borderColor = isDark
        ? HuddlColors.darkDivider
        : HuddlColors.gray200;
    final subtitleColor = isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;
    final labelColor = isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;

    final categoryLabel = _nudgeCategoryLabel(nudge.type).toUpperCase();

    return ScaleOnPress(
      scale: 0.98,
      onTap: () => _handleNudgeTap(nudge),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
          boxShadow: isDark ? null : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(nudge.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category label — tells the user what this card is
                  Text(
                    categoryLabel,
                    style: HuddlText.label(color: labelColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nudge.title,
                    style: HuddlText.body(weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    nudge.subtitle,
                    style: HuddlText.caption(color: subtitleColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: subtitleColor),
          ],
        ),
      ),
    );
  }

  /// Full-width hero card for the next upcoming meetup the user is attending.
  /// Sits between the greeting row and the AI catch-up card — high-impact,
  /// photography-first card layout.
  Widget _buildHeroMeetupCard(Meetup meetup, dynamic hc, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: HuddlParallaxPhotoCard(
        imageUrl: meetup.imageUrl,
        title: meetup.title,
        subtitle: '${meetup.dateDisplay} · ${meetup.timeDisplay}',
        badge: meetup.isGoing ? 'Going ✓' : null,
        stat: meetup.attendeeCount > 0 ? '${meetup.attendeeCount} going' : null,
        statIcon: Icons.people_outline,
        scrollOffset: _heroScrollOffset,
        aspectRatio: 1.65,
        onTap: () => Navigator.of(context).push(
          HuddlSpringPageRoute(page: MeetupDetailScreen(meetup: meetup)),
        ),
      ),
    );
  }

  /// Meetup the user is attending
  Widget _buildMeetupFeedCard(_SmartFeedItem item, dynamic hc) {
    final meetup = item.meetup!;
    return ScaleOnPress(
      scale: 0.98,
      onTap: () {
        setState(() => _meetupTaps++);
        Navigator.of(context).push(
          HuddlSpringPageRoute(page: MeetupDetailScreen(meetup: meetup)),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.hc.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Meetup image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: _buildMeetupImage(meetup.imageUrl, meetup.category),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.hc.surfaceAlt,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.reason,
                          style: HuddlText.label(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      BoroughBadge(
                        borough: meetup.borough,
                        feature: HuddlFeature.meetups,
                      ),
                      const Spacer(),
                      const Icon(Icons.check_circle,
                          size: 14, color: HuddlColors.success),  // teal
                      const SizedBox(width: 3),
                      Text('Going',
                          style: HuddlText.label()),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meetup.title,
                    style: HuddlText.body(weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${meetup.timeDisplay} \u00B7 ${meetup.attendeeCount} going',
                    style: HuddlText.caption(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Going event feed card — mirrors meetup card style with event accent
  Widget _buildGoingEventFeedCard(_SmartFeedItem item, dynamic hc) {
    final event = item.event!;
    final eventMap = event.toMap();
    return ScaleOnPress(
      scale: 0.98,
      onTap: () {
        Navigator.of(context).push(
          HuddlSpringPageRoute(page: EventDetailScreen(event: eventMap)),
        );
      },
      child: HuddlCard(
        variant: HuddlCardVariant.standard,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Event image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: event.imageUrl.isNotEmpty
                    ? HuddlNetworkImage(
                        url: event.imageUrl,
                        width: 56,
                        height: 56,
                        fallbackWidget: Container(
                              color: HuddlColors.nearBlack
                                  .withValues(alpha: 0.15),
                              child: const Center(
                                child: Icon(Icons.event,
                                    size: 22,
                                    color: HuddlColors.nearBlack),
                              ),
                            ))
                    : Container(
                        color:
                            HuddlColors.nearBlack.withValues(alpha: 0.15),
                        child: const Center(
                          child: Icon(Icons.event,
                              size: 22, color: HuddlColors.nearBlack),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: HuddlColors.nearBlack
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.reason,
                          style: HuddlText.label(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const BoroughBadge(
                        feature: HuddlFeature.events,
                        forceUkWide: true,
                      ),
                      const Spacer(),
                      Icon(Icons.check_circle,
                          size: 14, color: HuddlColors.success),  // teal
                      const SizedBox(width: 3),
                      Text('Going',
                          style: HuddlText.label()),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.title,
                    style: HuddlText.body(weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 11,
                          color: context.hc.textTertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${event.dateDisplay} \u00B7 ${event.timeDisplay}',
                          style: HuddlText.caption(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (event.location.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 11,
                            color: context.hc.textTertiary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location,
                            style: HuddlText.label(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Suggested meetup (not yet attending)
  Widget _buildSuggestedMeetupCard(
      _SmartFeedItem item, dynamic hc) {
    final meetup = item.meetup!;
    return ScaleOnPress(
      scale: 0.98,
      onTap: () {
        setState(() => _meetupTaps++);
        Navigator.of(context).push(
          HuddlSpringPageRoute(page: MeetupDetailScreen(meetup: meetup)),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: _buildMeetupImage(meetup.imageUrl, meetup.category),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meetup.title,
                    style: HuddlText.body(weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${meetup.dateDisplay} \u00B7 ${item.reason}',
                          style: HuddlText.caption(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      BoroughBadge(
                        borough: meetup.borough,
                        feature: HuddlFeature.meetups,
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

  /// Announcement card — streamlined
  Widget _buildAnnouncementFeedCard(
      _SmartFeedItem item, dynamic hc, bool isDark) {
    final a = item.announcement!;
    return Dismissible(
      key: ValueKey('sf_ann_${a.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: context.hc.textTertiary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_off_outlined,
                color: context.hc.textSecondary, size: 20),
            const SizedBox(height: 2),
            Text('Hide',
                style: HuddlText.label()),
          ],
        ),
      ),
      onDismissed: (_) => _dismissAnnouncement(a),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: BorderRadius.circular(14),
          border: a.isPinned
              ? Border.all(color: context.hc.divider)
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI reason tag + author
            Row(
              children: [
                MemberAvatar(
                  name: a.authorName,
                  imageUrl: a.authorPhotoUrl,
                  size: 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.authorName,
                              style: HuddlText.body(weight: FontWeight.w600),
                            ),
                          ),
                          if (a.isPinned)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: context.hc.surfaceAlt,
                                borderRadius:
                                    BorderRadius.circular(5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.push_pin,
                                      size: 9,
                                      color: context.hc.textTertiary),
                                  const SizedBox(width: 2),
                                  Text('Pinned',
                                      style: HuddlText.label()),
                                ],
                              ),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            a.timeAgo,
                            style: HuddlText.caption(),
                          ),
                          const SizedBox(width: 6),
                          // AI reason
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: context.hc.surfaceAlt,
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lightbulb_outline,
                                    size: 8,
                                    color: context.hc.textTertiary),
                                const SizedBox(width: 3),
                                Text(
                                  item.reason,
                                  style: HuddlText.label(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: 'Post options menu',
                  button: true,
                  child: GestureDetector(
                    onTap: () => _showPostMenu(a),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Icon(Icons.more_horiz,
                            color: context.hc.textTertiary, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Content (truncated with AI summarisation for long posts)
            Text(
              a.content.length > 120
                  ? '${a.content.substring(0, 120)}...'
                  : a.content,
              style: HuddlText.body(color: context.hc.textPrimary),
            ),
            const SizedBox(height: 8),
            // Compact action row
            Row(
              children: [
                _compactAction(
                  icon: a.isLiked
                      ? Icons.favorite
                      : Icons.favorite_border,
                  label: '${a.likes}',
                  isActive: a.isLiked,
                  semantics:
                      '${a.isLiked ? "Unlike" : "Like"}, ${a.likes} likes',
                  onTap: () => _toggleLike(a.id),
                ),
                const SizedBox(width: 12),
                _compactAction(
                  icon: Icons.chat_bubble_outline,
                  label: '${a.comments}',
                  semantics: '${a.comments} comments',
                  onTap: () => _openComments(a),
                ),
                const SizedBox(width: 12),
                _compactAction(
                  icon: Icons.share_outlined,
                  label:
                      a.shares > 0 ? '${a.shares}' : '',
                  semantics: 'Share post',
                  onTap: () => _sharePost(a),
                ),
                const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Group suggestion card
  Widget _buildGroupFeedCard(_SmartFeedItem item, dynamic hc) {
    final g = item.group!;
    return ScaleOnPress(
      scale: 0.98,
      onTap: () {
        setState(() => _groupTaps++);
        _switchToTab(1);
      },
      child: HuddlCard(
        variant: HuddlCardVariant.standard,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: _buildGroupImage(g.imageUrl),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.name,
                    style: HuddlText.body(weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Icon(Icons.people_outline,
                          size: 12, color: context.hc.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        item.reason,
                        style: HuddlText.caption(),
                      ),
                      const SizedBox(width: 6),
                      BoroughBadge(
                        borough: g.creatorBorough ?? _borough,
                        feature: HuddlFeature.groups,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('View',
                  style: HuddlText.caption(weight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  /// Community activity card
  Widget _buildCommunityFeedCard(_SmartFeedItem item, dynamic hc) {
    final f = item.feedItem!;
    return ScaleOnPress(
      scale: 0.98,
      onTap: () => _onFeedItemTap(f),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _feedIconBg(f.type),
                borderRadius: f.type == FeedItemType.newParent
                    ? BorderRadius.circular(21)
                    : BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildFeedImage(f),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.title,
                    style: HuddlText.body(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        f.timeAgo,
                        style: HuddlText.label(),
                      ),
                      if (item.reason.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: context.hc.textTertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            item.reason,
                            style: HuddlText.label(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(maxWidth: 72),
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: _feedIconBg(f.type),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _feedTypeLabel(f.type),
                style: HuddlText.label(color: _feedIconColor(f.type)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Partner promoted card (1:7 ratio in smart feed) ──────────────────────
  Widget _buildPartnerPromotedCard(_SmartFeedItem item, dynamic hc) {
    final meta        = item.feedItem?.meta ?? {};
    final partnerName = meta['partnerName'] as String? ?? '';
    final externalUrl = meta['externalUrl'] as String? ?? '';
    final ctaLabel    = meta['ctaLabel']    as String? ?? 'Find out more';
    final isVerified  = meta['isVerified']  as bool?   ?? false;
    final title       = item.feedItem?.title   ?? '';
    final subtitle    = item.feedItem?.subtitle ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: HuddlColors.primary.withValues(alpha: 0.20),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: hc.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: partner name + verified tick + "Promoted" pill
            Row(
              children: [
                if (isVerified) ...[
                  Icon(Icons.verified_rounded,
                      size: 14, color: HuddlColors.primary),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    partnerName,
                    style: HuddlText.caption(weight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Promoted',
                    style: HuddlText.label(color: HuddlColors.warningDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              title,
              style: HuddlText.body(weight: FontWeight.w600),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: HuddlText.caption(color: hc.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            // CTA button
            if (externalUrl.isNotEmpty)
              HuddlButton(
                label: ctaLabel,
                onPressed: () => launchUrl(
                  Uri.parse(externalUrl),
                  mode: LaunchMode.externalApplication,
                ),
                variant: HuddlButtonVariant.secondary,
                fullWidth: true,
              ),
          ],
        ),
      ),
    );
  }

  // ── Compact action button ─────────────────────────────────────────────────
  Widget _compactAction({
    required IconData icon,
    required String label,
    bool isActive = false,
    required String semantics,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semantics,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? HuddlColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: isActive
                      ? HuddlColors.primary
                      : HuddlColors.textHint),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: HuddlText.caption(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }



  // ── Nudge tap handler ─────────────────────────────────────────────────────
  void _handleNudgeTap(NudgeCard nudge) {
    final tabRoutes = <String, int>{
      '/meetups': 2,
      '/groups': 1,
      '/marketplace': 3,
      '/create_meetup': 2,
    };
    final route = nudge.actionRoute;
    if (route != null && tabRoutes.containsKey(route)) {
      final shellState = MainShell.shellKey.currentState;
      if (shellState != null) {
        shellState.switchTab(tabRoutes[route]!);
      }
    } else if (route != null && route.startsWith('/')) {
      Navigator.pushNamed(context, route);
    }
  }

  // ── Feed item helpers ─────────────────────────────────────────────────────
  Widget _buildFeedImage(FeedItem item) {
    final imgUrl = item.type == FeedItemType.newParent
        ? MemberPhotoService.getPhotoByName(item.title)
        : item.imageAsset;

    if (imgUrl != null && imgUrl.isNotEmpty) {
      if (imgUrl.startsWith('data:')) {
        try {
          final parts = imgUrl.split(',');
          if (parts.length > 1) {
            final bytes = base64Decode(parts[1]);
            return Image.memory(bytes,
                fit: BoxFit.cover, width: 42, height: 42);
          }
        } catch (_) {}
      }
      if (imgUrl.startsWith('http')) {
        return Image.network(imgUrl,
            fit: BoxFit.cover,
            width: 42,
            height: 42,
            errorBuilder: (_, __, ___) =>
                Center(child: Icon(_feedIcon(item.type),
                    color: _feedIconColor(item.type), size: 20)));
      }
      if (imgUrl.startsWith('assets/')) {
        return Image.asset(imgUrl,
            fit: BoxFit.cover,
            width: 42,
            height: 42,
            errorBuilder: (_, __, ___) =>
                Center(child: Icon(_feedIcon(item.type),
                    color: _feedIconColor(item.type), size: 20)));
      }
    }
    return Center(child: Icon(_feedIcon(item.type),
        color: _feedIconColor(item.type), size: 20));
  }

  IconData _feedIcon(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return Icons.person_add;
      case FeedItemType.newGroup:
        return Icons.people;
      case FeedItemType.newEvent:
        return Icons.event;
      case FeedItemType.newMarketplaceItem:
        return Icons.storefront;
      case FeedItemType.milestone:
        return Icons.emoji_events;
      case FeedItemType.partnerPromoted:
        return Icons.campaign_outlined;
    }
  }

  Color _feedIconColor(FeedItemType t) {
    // Design rule: no per-type colour coding — all nearBlack for visual calm
    return HuddlColors.nearBlack;
  }

  Color _feedIconBg(FeedItemType t) {
    // Design rule: uniform neutral grey — no tinted/coloured icon containers
    return const Color(0xFFF7F7F7);
  }

  String _feedTypeLabel(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return 'New Parent';
      case FeedItemType.newGroup:
        return 'New Group';
      case FeedItemType.newEvent:
        return 'Meetup';
      case FeedItemType.newMarketplaceItem:
        return 'Market';
      case FeedItemType.milestone:
        return 'Milestone';
      case FeedItemType.partnerPromoted:
        return 'Partner';
    }
  }

  /// Returns a Pexels placeholder image based on meetup category.
  static String _meetupCategoryImage(String category) {
    switch (category.toLowerCase()) {
      case 'coffee':
      case 'coffee & chat':
        return 'https://images.pexels.com/photos/302899/pexels-photo-302899.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'playdate':
      case 'play':
        return 'https://images.pexels.com/photos/3933239/pexels-photo-3933239.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'walk':
      case 'outdoor':
        return 'https://images.pexels.com/photos/1325735/pexels-photo-1325735.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'fitness':
      case 'exercise':
        return 'https://images.pexels.com/photos/3822864/pexels-photo-3822864.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'class':
      case 'workshop':
        return 'https://images.pexels.com/photos/3662667/pexels-photo-3662667.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'music':
        return 'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=300';
      default:
        return 'https://images.pexels.com/photos/3933250/pexels-photo-3933250.jpeg?auto=compress&cs=tinysrgb&w=300';
    }
  }

  Widget _buildMeetupImage(String imageUrl, String category) {
    // If imageUrl is a data URI, try to decode it
    if (imageUrl.startsWith('data:')) {
      try {
        final parts = imageUrl.split(',');
        if (parts.length > 1) {
          final bytes = base64Decode(parts[1]);
          return Image.memory(bytes, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _meetupIconFallback(category));
        }
      } catch (_) {}
    }
    // If imageUrl is a valid HTTP URL, use it
    if (imageUrl.startsWith('http') && imageUrl.isNotEmpty) {
      return HuddlNetworkImage(
        url: imageUrl,
        width: double.infinity,
        height: double.infinity,
        fallbackWidget: _meetupIconFallback(category),
      );
    }
    // Fallback to category-based placeholder
    return _meetupIconFallback(category);
  }

  Widget _meetupIconFallback([String category = '']) {
    final fallbackUrl = _meetupCategoryImage(category);
    return Image.network(
      fallbackUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: HuddlColors.gray100,
        child: const Center(
          child: Icon(Icons.groups, size: 22, color: HuddlColors.textHint),
        ),
      ),
    );
  }

  Widget _buildGroupImage(String imageUrl) {
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(imageUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _groupImageFallback());
    }
    if (imageUrl.startsWith('http')) {
      return HuddlNetworkImage(
        url: imageUrl,
        width: double.infinity,
        height: double.infinity,
        fallbackWidget: _groupImageFallback(),
      );
    }
    if (imageUrl.startsWith('data:')) {
      try {
        final parts = imageUrl.split(',');
        if (parts.length > 1) {
          final bytes = base64Decode(parts[1]);
          return Image.memory(bytes, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _groupImageFallback());
        }
      } catch (_) {}
    }
    return _groupImageFallback();
  }

  Widget _groupImageFallback() {
    return Container(
      color: HuddlColors.gray100,
      child: const Center(
        child: Icon(Icons.people, size: 22, color: HuddlColors.textHint),
      ),
    );
  }

  // ── Avatars ───────────────────────────────────────────────────────────────
  Widget _buildSmallAvatar() {
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      if (_photoUrl!.startsWith('data:')) {
        try {
          final parts = _photoUrl!.split(',');
          if (parts.length > 1) {
            final bytes = base64Decode(parts[1]);
            return ClipOval(
              child: Image.memory(bytes,
                  width: 30, height: 30, fit: BoxFit.cover),
            );
          }
        } catch (_) {}
      }
      return ClipOval(
        child: Image.network(
          _photoUrl!,
          width: 30,
          height: 30,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(30),
        ),
      );
    }
    return _avatarFallback(30);
  }

  Widget _buildTinyAvatar() {
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      if (_photoUrl!.startsWith('data:')) {
        try {
          final parts = _photoUrl!.split(',');
          if (parts.length > 1) {
            final bytes = base64Decode(parts[1]);
            return ClipOval(
              child: Image.memory(bytes,
                  width: 34, height: 34, fit: BoxFit.cover),
            );
          }
        } catch (_) {}
      }
      return ClipOval(
        child: Image.network(
          _photoUrl!,
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(34),
        ),
      );
    }
    return _avatarFallback(34);
  }

  Widget _avatarFallback(double size) {
    // Show gender-appropriate illustrated avatar: John.png for dads, Emma.png for mums.
    final asset = MemberPhotoService.currentUserAvatarAsset;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HuddlColors.primary.withValues(alpha: 0.08),
        border: Border.all(
          color: HuddlColors.primary.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.person,
            size: size * 0.5,
            color: HuddlColors.primary,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _NoticeboardRow — compact tap-to-expand noticeboard post row
// ═══════════════════════════════════════════════════════════════════════════════

class _NoticeboardRow extends StatefulWidget {
  final Announcement announcement;
  final dynamic hc;
  final bool isDark;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onMenu;

  const _NoticeboardRow({
    super.key,
    required this.announcement,
    required this.hc,
    required this.isDark,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onMenu,
  });

  @override
  State<_NoticeboardRow> createState() => _NoticeboardRowState();
}

class _NoticeboardRowState extends State<_NoticeboardRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ann = widget.announcement;
    final hc = widget.hc;
    final isDark = widget.isDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hc.divider,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Compact header row ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pin / campaign icon
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        ann.isPinned
                            ? Icons.push_pin
                            : Icons.campaign_outlined,
                        size: 15,
                        color: hc.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Author + content preview
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Author name + time
                          Row(
                            children: [
                              Text(
                                ann.authorName,
                                style: HuddlText.caption(weight: FontWeight.w600),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                ann.timeAgo,
                                style: HuddlText.label(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          // Content — truncated when collapsed
                          Text(
                            ann.content,
                            style: HuddlText.body(color: hc.textSecondary),
                            maxLines: _expanded ? null : 2,
                            overflow: _expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Chevron + overflow menu
                    Column(
                      children: [
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 18,
                          color: hc.textTertiary,
                        ),
                        GestureDetector(
                          onTap: widget.onMenu,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Icon(Icons.more_horiz,
                                size: 18, color: hc.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Expanded action bar ───────────────────────────────────
              if (_expanded) ...[
                Divider(height: 1, color: hc.divider),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      // Like
                      _ActionButton(
                        icon: ann.isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: ann.isLiked
                            ? HuddlColors.error
                            : hc.textTertiary,
                        label: ann.likes > 0
                            ? '${ann.likes}'
                            : '',
                        onTap: widget.onLike,
                      ),
                      // Comment
                      _ActionButton(
                        icon: Icons.chat_bubble_outline,
                        color: hc.textTertiary,
                        label: ann.comments > 0
                            ? '${ann.comments}'
                            : '',
                        onTap: widget.onComment,
                      ),
                      // Share
                      _ActionButton(
                        icon: Icons.share_outlined,
                        color: hc.textTertiary,
                        label: ann.shares > 0
                            ? '${ann.shares}'
                            : '',
                        onTap: widget.onShare,
                      ),
                      const Spacer(),
                      // Bookmark indicator
                      if (ann.isBookmarked)
                        Icon(Icons.bookmark,
                            size: 16, color: HuddlColors.primary),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimal icon + label action button used in the noticeboard row action bar.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HuddlAnimations.lightTap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: HuddlText.caption(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART FEED DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

// ── Sticky header delegate ────────────────────────────────────────────────
/// Used by SliverPersistentHeader(pinned:true) to keep the app-bar row +
/// "Your Feed" title pinned at the top of the home screen while content
/// scrolls beneath it. A fixed [height] is supplied by the caller.
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _StickyHeaderDelegate({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

// ── AI Catch-Up card helper ───────────────────────────────────────────────
class _CatchUpItem {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CatchUpItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
}

enum _SmartFeedType {
  aiNudge,
  meetup,
  goingEvent,
  suggestedMeetup,
  announcement,
  group,
  communityActivity,
  partnerPromoted, // Promoted card from a verified Partner business (1:7 ratio)
}

// ── Discover New Listings types ───────────────────────────────────────────
enum _DiscoverType { group, meetup, event, sale }

class _DiscoverItem {
  final _DiscoverType type;
  final DateTime sortDate;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String? badge;
  final VoidCallback onTap;

  const _DiscoverItem({
    required this.type,
    required this.sortDate,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.badge,
    required this.onTap,
  });
}

class _SmartFeedItem {
  final _SmartFeedType type;
  final double relevanceScore;
  final String reason;
  final NudgeCard? nudge;
  final Meetup? meetup;
  final Event? event;
  final Announcement? announcement;
  final Group? group;
  final FeedItem? feedItem;
  final ServiceListing? promotedListing; // for partnerPromoted cards

  _SmartFeedItem({
    required this.type,
    required this.relevanceScore,
    required this.reason,
    // ignore: unused_element_parameter
    this.nudge,
    // ignore: unused_element_parameter
    this.meetup,
    // ignore: unused_element_parameter
    this.event,
    // ignore: unused_element_parameter
    this.announcement,
    // ignore: unused_element_parameter
    this.group,
    this.feedItem,
    // ignore: unused_element_parameter
    this.promotedListing,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// AI ASSISTANT BOTTOM SHEET (Progressive Disclosure)
// ═══════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEETS & FULL-SCREEN PAGES
// (Retained from previous implementation — comments, notifications, share, etc.)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Feed Preferences Sheet (interactive toggles) ───────────────────────────
class _FeedPreferencesSheet extends StatefulWidget {
  final Map<String, bool> initialPrefs;
  final ValueChanged<Map<String, bool>> onSaved;

  const _FeedPreferencesSheet({
    required this.initialPrefs,
    required this.onSaved,
  });

  @override
  State<_FeedPreferencesSheet> createState() => _FeedPreferencesSheetState();
}

class _FeedPreferencesSheetState extends State<_FeedPreferencesSheet> {
  late Map<String, bool> _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = Map<String, bool>.from(widget.initialPrefs);
  }

  void _toggle(String key) {
    HuddlAnimations.selectionClick();
    setState(() => _prefs[key] = !(_prefs[key] ?? true));
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        // Clip so rounded corners show properly
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HuddlBottomSheetHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.tune, color: hc.textTertiary, size: 20),
                  const SizedBox(width: 8),
                  Text('Feed Preferences',
                      style: HuddlText.heading(color: hc.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Choose which content appears in your feed.',
                style: HuddlText.caption(color: hc.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            _tile('meetups', Icons.groups, 'Meetups I\'m going to',
                'High priority \u2014 shown at the top'),
            _tile('events', Icons.event, 'Events I\'m attending',
                'Reminders as the date approaches'),
            _tile('announcements', Icons.campaign_outlined,
                'Community announcements', 'Pinned posts and popular activity'),
            _tile('suggestions', Icons.group_add,
                'Suggested meetups & groups', 'New meetups and groups near you'),
            _tile('tips', Icons.lightbulb_outline, 'Tips & suggestions',
                'Personalised suggestions based on your activity'),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: HuddlButton(
                label: 'Save Preferences',
                onPressed: () {
                  Navigator.pop(context);
                  widget.onSaved(_prefs);
                },
                variant: HuddlButtonVariant.primary,
                fullWidth: true,
              ),
            ),
            SizedBox(height: bottomInset > 0 ? bottomInset : 16),
          ],
        ),
      ),
    );
  }

  Widget _tile(String key, IconData icon, String title, String subtitle) {
    final enabled = _prefs[key] ?? true;
    final hc = context.hc;
    return InkWell(
      onTap: () => _toggle(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 22,
                color: enabled ? HuddlColors.primary : hc.textTertiary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: HuddlText.body(color: enabled ? hc.textPrimary : hc.textTertiary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: HuddlText.caption(color: hc.textTertiary)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                enabled ? Icons.check_circle : Icons.circle_outlined,
                key: ValueKey(enabled),
                size: 24,
                color: enabled ? HuddlColors.textDark : hc.textTertiary,  // Phase 1: feed-pref toggle → textDark
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Comments Sheet ──────────────────────────────────────────────────────────
class _CommentsSheet extends StatefulWidget {
  final Announcement announcement;
  final AnnouncementService service;
  final VoidCallback onUpdate;

  const _CommentsSheet({
    required this.announcement,
    required this.service,
    required this.onUpdate,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  late List<AnnouncementComment> _comments;

  /// When non-null the input bar is in "reply" mode for this author name.
  String? _replyingTo;

  @override
  void initState() {
    super.initState();
    _comments = List.from(widget.announcement.commentsList);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Begin replying to [authorName]: pre-fills @mention and focuses input.
  void _startReply(String authorName) {
    HuddlAnimations.selectionClick();
    setState(() {
      _replyingTo = authorName;
      _ctrl.text = '@$authorName ';
      _ctrl.selection =
          TextSelection.collapsed(offset: _ctrl.text.length);
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
      _ctrl.clear();
    });
    _focusNode.unfocus();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);

    final AnnouncementComment result;
    if (_replyingTo != null) {
      // Strip the leading @mention from the persisted content
      // so we don't double-render it (the UI already shows the @mention pill).
      final strippedText =
          text.startsWith('@$_replyingTo ') && text.length > '@$_replyingTo '.length
              ? text.substring('@$_replyingTo '.length).trim()
              : text;
      result = await widget.service.addReply(
        announcementId: widget.announcement.id,
        replyToName: _replyingTo!,
        content: strippedText,
      );
    } else {
      result = await widget.service
          .addComment(widget.announcement.id, text);
    }

    _ctrl.clear();
    setState(() {
      _comments.add(result);
      _replyingTo = null;
      _sending = false;
    });
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HuddlBottomSheetHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Comments',
                    style: HuddlText.heading(),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${_comments.length})',
                    style: HuddlText.body(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: hc.divider),
            // ── Comment list ────────────────────────────────────────────────
            Flexible(
              child: _comments.isEmpty
                  ? const HuddlEmptyState(
                      mood: HuddlMood.waving,
                      title: 'No comments yet',
                      subtitle: 'Be the first to comment!',
                      characterSize: 100,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      shrinkWrap: true,
                      itemCount: _comments.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 16),
                      itemBuilder: (_, index) {
                        final c = _comments[index];
                        final isReply = c.replyToName != null;
                        return Padding(
                          // Indent replies slightly
                          padding: EdgeInsets.only(left: isReply ? 20.0 : 0.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Vertical reply line for threaded feel
                              if (isReply) ...[
                                Container(
                                  width: 2,
                                  height: 36,
                                  margin: const EdgeInsets.only(right: 8, top: 4),
                                  decoration: BoxDecoration(
                                    color: HuddlColors.gray200,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ],
                              MemberAvatar(
                                name: c.authorName,
                                imageUrl: c.authorPhotoUrl,
                                size: isReply ? 28 : 36,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          c.authorName,
                                          style: HuddlText.caption(weight: FontWeight.w600, color: hc.textPrimary),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          c.timeAgo,
                                          style: HuddlText.caption(),
                                        ),
                                      ],
                                    ),
                                    // @mention chip for replies
                                    if (isReply) ...[
                                      const SizedBox(height: 2),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: HuddlColors.gray100,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '@${c.replyToName}',
                                          style: HuddlText.caption(weight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      c.content,
                                      style: HuddlText.caption(color: hc.textPrimary).copyWith(height: 1.4),
                                    ),
                                    const SizedBox(height: 6),
                                    // Like + Reply row
                                    Row(
                                      children: [
                                        // Like
                                        Semantics(
                                          label: c.isLiked
                                              ? 'Unlike comment'
                                              : 'Like comment',
                                          button: true,
                                          child: GestureDetector(
                                            onTap: () {
                                              HuddlAnimations.lightTap();
                                              setState(() {
                                                c.isLiked = !c.isLiked;
                                                c.likes +=
                                                    c.isLiked ? 1 : -1;
                                              });
                                            },
                                            child: SizedBox(
                                              height: 40,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    c.isLiked
                                                        ? Icons.favorite
                                                        : Icons.favorite_border,
                                                    size: 14,
                                                    color: c.isLiked
                                                        ? HuddlColors.accentCoral
                                                        : HuddlColors.textHint,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${c.likes}',
                                                    style: HuddlText.caption(),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Reply — now fully wired
                                        Semantics(
                                          label: 'Reply to ${c.authorName}',
                                          button: true,
                                          child: GestureDetector(
                                            onTap: () =>
                                                _startReply(c.authorName),
                                            child: SizedBox(
                                              height: 40,
                                              child: Center(
                                                child: Text(
                                                  'Reply',
                                                  style: HuddlText.caption(),
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
                            ],
                          ),
                        );
                      },
                    ),
            ),
            // ── "Replying to @name" banner ──────────────────────────────────
            if (_replyingTo != null)
              Container(
                color: HuddlColors.gray100,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.reply_rounded,
                        size: 14, color: HuddlColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Replying to @$_replyingTo',
                        style: HuddlText.caption(color: HuddlColors.textSecondary),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelReply,
                      child: Icon(Icons.close_rounded,
                          size: 16, color: HuddlColors.textHint),
                    ),
                  ],
                ),
              ),
            Divider(height: 1, color: hc.divider),
            // ── Input bar ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: _replyingTo != null
                            ? 'Reply to @$_replyingTo…'
                            : 'Write a comment…',
                        hintStyle: HuddlText.body(color: hc.textTertiary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: hc.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: hc.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: _replyingTo != null
                                ? HuddlColors.primary
                                : HuddlColors.primary,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                      style: HuddlText.body(color: hc.textPrimary),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sending ? null : _send,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: HuddlColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: HuddlColors.white),
                            )
                          : const Icon(Icons.send_rounded,
                              size: 18, color: HuddlColors.white),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

// ── Notifications Sheet ─────────────────────────────────────────────────────
// Streams all notification types from Firestore in real-time.
// Tapping a notification deep-links directly to the related screen.
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationsSheet extends StatefulWidget {
  // Legacy feed/meetup params kept so _openNotifications() call-site compiles
  // without changes. They are only used as a secondary fallback when Firestore
  // has no notifications yet.
  final List<FeedItem> feedItems;
  final List<Announcement> announcements;
  final String borough;
  final List<Meetup> meetups;
  final void Function(int tabIndex) onNavigate;
  final void Function(String groupId, String groupName, String groupImageUrl)
      onNavigateToGroupChat;
  final void Function(Meetup meetup) onNavigateToMeetup;
  final VoidCallback onMarkAllRead;

  const _NotificationsSheet({
    required this.feedItems,
    required this.announcements,
    required this.borough,
    required this.meetups,
    required this.onNavigate,
    required this.onNavigateToGroupChat,
    required this.onNavigateToMeetup,
    required this.onMarkAllRead,
  });

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  late Stream<List<Map<String, dynamic>>> _stream;
  bool _showUnreadOnly = false;

  @override
  void initState() {
    super.initState();
    // Guard against the auth race: if the user is already signed in use the
    // stream directly; otherwise fall back to an auth-state stream that
    // switches over once a UID becomes available.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _stream = HuddlNotificationService().stream();
    } else {
      _stream = FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
        if (user == null) return const Stream.empty();
        return HuddlNotificationService().stream();
      });
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  IconData _iconFor(String type) {
    switch (type) {
      // Messaging
      case 'new_dm':            return Icons.chat_bubble_outline;
      case 'new_group_message': return Icons.group;
      case 'voice_message_dm':  return Icons.mic;
      case 'voice_message_group': return Icons.mic;
      case 'message_reaction':  return Icons.favorite;
      case 'thread_reply':      return Icons.reply;
      // Groups & social
      case 'group_invitation':    return Icons.group_add;
      case 'invitation_accepted': return Icons.check_circle_outline;
      case 'group_member_joined': return Icons.person_add;
      case 'post_liked':          return Icons.favorite;
      case 'post_commented':      return Icons.comment_outlined;
      case 'comment_replied':     return Icons.reply;
      case 'poll_created':        return Icons.poll_outlined;
      // Events
      case 'meetup_rsvp':         return Icons.event_available;
      case 'meetup_reminder':     return Icons.alarm;
      case 'new_meetup_nearby':   return Icons.location_on_outlined;
      case 'event_update':        return Icons.update;
      // Marketplace
      case 'offer_received':      return Icons.local_offer_outlined;
      case 'offer_accepted':      return Icons.handshake_outlined;
      case 'offer_declined':      return Icons.cancel_outlined;
      case 'item_sold':           return Icons.sell_outlined;
      case 'saved_item_sold':     return Icons.bookmark_remove_outlined;
      case 'item_relisted':       return Icons.refresh;
      // System
      case 'subscription_activated': return Icons.star_outline;
      case 'payment_failed':         return Icons.payment;
      case 'welcome':                return Icons.waving_hand;
      default:                       return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'new_dm':
      case 'new_group_message':
      case 'voice_message_dm':
      case 'voice_message_group':
      case 'thread_reply':
        return HuddlColors.primary;
      case 'message_reaction':
      case 'post_liked':
        return HuddlColors.accentCoral;
      case 'group_invitation':
      case 'invitation_accepted':
      case 'group_member_joined':
        return HuddlColors.nearBlack;
      case 'post_commented':
      case 'comment_replied':
      case 'poll_created':
        return HuddlColors.primary;
      case 'meetup_rsvp':
      case 'meetup_reminder':
      case 'new_meetup_nearby':
      case 'event_update':
        return HuddlColors.nearBlack;
      case 'offer_received':
      case 'offer_accepted':
        return HuddlColors.success;
      case 'offer_declined':
      case 'item_sold':
      case 'saved_item_sold':
        return HuddlColors.primaryDark;
      case 'item_relisted':
        return HuddlColors.primary;
      case 'subscription_activated':
        return HuddlColors.primary;
      case 'payment_failed':
        return HuddlColors.error;
      default:
        return HuddlColors.primary;
    }
  }

  Color _bgFor(String type) {
    final c = _colorFor(type);
    return c.withValues(alpha: 0.12);
  }

  String _timeAgo(Map<String, dynamic> n) {
    final raw = n['createdAt'];
    if (raw == null) return 'just now';
    DateTime? dt;
    if (raw is String) dt = DateTime.tryParse(raw);
    if (dt == null) return 'just now';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  // ── Deep-link routing ─────────────────────────────────────────────────────

  void _onTap(Map<String, dynamic> n) {
    // Mark as read
    final id = n['id'] as String? ?? '';
    if (id.isNotEmpty && n['read'] != true) {
      HuddlNotificationService().markOneRead(id);
    }

    final type = n['type'] as String? ?? '';
    final data = (n['data'] as Map<String, dynamic>?) ?? {};

    Navigator.pop(context); // Close sheet first

    switch (type) {
      // ── DM / Voice DM ──────────────────────────────────────────────────
      case 'new_dm':
      case 'voice_message_dm':
        {
          final convId = data['conversationId'] as String? ?? '';
          final recipientId = data['recipientId'] as String? ?? '';
          final senderName = n['senderName'] as String? ?? 'Chat';
          Navigator.of(context).push(HuddlSpringPageRoute(page: DMChatScreen(
              recipientId: recipientId,
              recipientName: senderName,
              recipientAvatarColor: '#FF975C',
              conversationId: convId.isEmpty ? null : convId,
            )));
        }
        break;

      // ── Group messages / voice / reaction / thread ─────────────────────
      case 'new_group_message':
      case 'voice_message_group':
      case 'message_reaction':
      case 'thread_reply':
      case 'group_invitation':
      case 'invitation_accepted':
      case 'group_member_joined':
      case 'poll_created':
        {
          final groupId = data['groupId'] as String? ?? '';
          final groupName = data['groupName'] as String? ?? 'Group';
          final groupImageUrl = data['groupImageUrl'] as String? ?? '';
          if (groupId.isNotEmpty) {
            Navigator.of(context).push(HuddlSpringPageRoute(page: GroupChatScreen(
                groupId: groupId,
                groupName: groupName,
                groupImageUrl: groupImageUrl,
              )));
          } else {
            widget.onNavigate(1); // Groups tab
          }
        }
        break;

      // ── Meetup events ──────────────────────────────────────────────────
      case 'meetup_rsvp':
      case 'meetup_reminder':
      case 'new_meetup_nearby':
      case 'event_update':
        {
          final meetupId = data['meetupId'] as String? ?? '';
          final meetupTitle = data['meetupTitle'] as String? ?? '';
          // Try to find matching meetup in local list
          final match = widget.meetups
              .where((m) => m.id == meetupId || m.title == meetupTitle)
              .toList();
          if (match.isNotEmpty) {
            widget.onNavigateToMeetup(match.first);
          } else {
            widget.onNavigate(2); // Events tab
          }
        }
        break;

      // ── offer_accepted → auto-open DM with the seller ─────────────────
      case 'offer_accepted':
        {
          final sellerId   = data['sellerId']   as String? ?? '';
          final sellerName = data['sellerName'] as String?
              ?? n['senderName'] as String?
              ?? 'Seller';
          final itemId = data['itemId'] as String? ?? '';
          if (sellerId.isNotEmpty) {
            // Open (or create) a DM conversation with the seller so the
            // buyer can arrange the handover immediately.
            Navigator.of(context).push(HuddlSpringPageRoute(page: DMChatScreen(
                recipientId: sellerId,
                recipientName: sellerName,
                recipientAvatarColor: '#FF975C',
                conversationId: null, // getOrCreate on first send
              )));
          } else {
            // Fallback: open the item detail if we have it
            final item = itemId.isNotEmpty
                ? RehomeService().getItemById(itemId)
                : null;
            if (item != null) {
              Navigator.of(context).push(HuddlSpringPageRoute(page: ItemDetailScreen(item: item)));
            } else {
              widget.onNavigate(3);
            }
          }
        }
        break;

      // ── Marketplace: other offer/sold/relisted notifications ───────────
      case 'offer_received':
      case 'offer_declined':
      case 'item_sold':
      case 'saved_item_sold':
      case 'item_relisted':
        {
          final itemId = data['itemId'] as String? ?? '';
          // Try to find item in RehomeService
          final item = itemId.isNotEmpty
              ? RehomeService().getItemById(itemId)
              : null;
          if (item != null) {
            Navigator.of(context).push(HuddlSpringPageRoute(page: ItemDetailScreen(item: item)));
          } else {
            widget.onNavigate(3); // Marketplace tab
          }
        }
        break;

      // ── System / subscription ──────────────────────────────────────────
      case 'subscription_activated':
      case 'payment_failed':
        widget.onNavigate(4); // Profile tab (where subscription lives)
        break;

      // ── Fallback ───────────────────────────────────────────────────────
      default:
        widget.onNavigate(0);
        break;
    }
  }

  Future<void> _markAllRead(List<Map<String, dynamic>> notifs) async {
    await HuddlNotificationService().markAllRead();
    widget.onMarkAllRead();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final allNotifs = snapshot.data ?? [];
        final unread = allNotifs.where((n) => n['read'] != true).length;
        final displayed = _showUnreadOnly
            ? allNotifs.where((n) => n['read'] != true).toList()
            : allNotifs;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          decoration: BoxDecoration(
            color: context.hc.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HuddlBottomSheetHandle(),
              // ── Header row ──────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.notifications,
                        size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Notifications',
                      style: HuddlText.heading(),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: HuddlColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unread',
                          style: HuddlText.caption(weight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const Spacer(),
                    TextButton(
                      onPressed: unread > 0
                          ? () => _markAllRead(allNotifs)
                          : null,
                      child: Text(
                        'Mark all read',
                        style: HuddlText.body(),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.hc.divider),
              // ── Filter chips ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    _filterChip('All', !_showUnreadOnly, () {
                      setState(() => _showUnreadOnly = false);
                    }),
                    const SizedBox(width: 8),
                    _filterChip(
                      'Unread${unread > 0 ? ' ($unread)' : ''}',
                      _showUnreadOnly,
                      () => setState(() => _showUnreadOnly = true),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.hc.divider),
              // ── List ────────────────────────────────────────────────
              Flexible(
                child: snapshot.connectionState ==
                            ConnectionState.waiting &&
                        allNotifs.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : displayed.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.notifications_none,
                                      size: 48,
                                      color: context.hc.textTertiary
                                          .withValues(alpha: 0.4)),
                                  const SizedBox(height: 12),
                                  Text(
                                    _showUnreadOnly
                                        ? 'No unread notifications'
                                        : 'No notifications yet',
                                    style: HuddlText.body(),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "You're all caught up!",
                                    style: HuddlText.body(),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            shrinkWrap: true,
                            itemCount: displayed.length,
                            separatorBuilder: (_, __) => Divider(
                                height: 1,
                                indent: 72,
                                color: context.hc.divider),
                            itemBuilder: (_, i) =>
                                _buildTile(displayed[i]),
                          ),
              ),
              SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  Widget _filterChip(
      String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? HuddlColors.primary.withValues(alpha: 0.12)
              : context.hc.scaffold,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? HuddlColors.primary.withValues(alpha: 0.3)
                : HuddlColors.divider,
          ),
        ),
        child: Text(
          label,
          style: HuddlText.caption(),
        ),
      ),
    );
  }

  Widget _buildTile(Map<String, dynamic> n) {
    final type = n['type'] as String? ?? '';
    final title = n['title'] as String? ?? '';
    final body = n['body'] as String? ?? '';
    final isRead = n['read'] == true;
    final photoUrl = n['senderPhotoUrl'] as String? ??
        n['imageUrl'] as String? ?? '';
    final icon = _iconFor(type);
    final color = _colorFor(type);
    final bg = _bgFor(type);
    final timeAgo = _timeAgo(n);

    return Material(
      color: isRead
          ? context.hc.surface
          : HuddlColors.primary.withValues(alpha: 0.04),
      child: InkWell(
        onTap: () => _onTap(n),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar / icon badge
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: photoUrl.isNotEmpty
                          ? _buildPhoto(photoUrl, bg)
                          : Container(
                              width: 48,
                              height: 48,
                              color: bg,
                              child: Icon(icon, color: color, size: 24),
                            ),
                    ),
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: bg,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: context.hc.surface, width: 1.5),
                        ),
                        child: Icon(icon, size: 11, color: color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: HuddlText.body(weight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: HuddlText.caption(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Time + unread dot
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeAgo,
                    style: HuddlText.label(color: HuddlColors.primary),
                  ),
                  const SizedBox(height: 4),
                  if (!isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: HuddlColors.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(width: 8, height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto(String url, Color fallbackBg) {
    if (url.startsWith('http')) {
      return Image.network(url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(width: 48, height: 48, color: fallbackBg));
    }
    if (url.startsWith('assets/')) {
      return Image.asset(url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(width: 48, height: 48, color: fallbackBg));
    }
    return Container(width: 48, height: 48, color: fallbackBg);
  }
}
// ── Share Post Sheet ────────────────────────────────────────────────────────
class _SharePostSheet extends StatefulWidget {
  final String shareText;
  final List<Group> userGroups;
  final List<BoroughMember> boroughMembers;
  final String borough;
  final String currentUserName;
  final DMService dmService;
  final void Function(String targetName) onShared;

  const _SharePostSheet({
    required this.shareText,
    required this.userGroups,
    required this.boroughMembers,
    required this.borough,
    required this.currentUserName,
    required this.dmService,
    required this.onShared,
  });

  @override
  State<_SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<_SharePostSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _search = '';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  List<Group> get _filteredGroups {
    if (_search.isEmpty) return widget.userGroups;
    final q = _search.toLowerCase();
    return widget.userGroups
        .where((g) => g.name.toLowerCase().contains(q))
        .toList();
  }

  List<BoroughMember> get _filteredMembers {
    if (_search.isEmpty) return widget.boroughMembers;
    final q = _search.toLowerCase();
    return widget.boroughMembers
        .where((m) => m.name.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _shareToGroup(Group group) async {
    setState(() => _sending = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() => _sending = false);
      widget.onShared(group.name);
    }
  }

  Future<void> _shareToMember(BoroughMember member) async {
    setState(() => _sending = true);
    final recipientId = member.id;
    final conv = await widget.dmService.getOrCreateConversation(
      recipientId: recipientId,
      recipientName: member.name,
    );
    await widget.dmService.sendMessage(
      conversationId: conv.id,
      message: widget.shareText,
      senderName: widget.currentUserName,
    );
    if (mounted) {
      setState(() => _sending = false);
      widget.onShared(member.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HuddlBottomSheetHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.share,
                    size: 22),
                const SizedBox(width: 8),
                Text(
                  'Share with...',
                  style: HuddlText.heading(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search groups or members...',
                hintStyle: HuddlText.body(color: context.hc.textTertiary),
                prefixIcon: Icon(Icons.search,
                    size: 20, color: context.hc.textTertiary),
                filled: true,
                fillColor: context.hc.scaffold,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                isDense: true,
              ),
              style: HuddlText.body(color: context.hc.textPrimary),
            ),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabCtrl,
            labelColor: HuddlColors.textDark,
            unselectedLabelColor: HuddlColors.textHint,
            indicatorColor: HuddlColors.textDark,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: HuddlText.caption(weight: FontWeight.w600),
            unselectedLabelStyle: HuddlText.caption(),
            tabs: const [Tab(text: 'Groups'), Tab(text: 'Members')],
          ),
          Divider(height: 1, color: context.hc.divider),
          Flexible(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _filteredGroups.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No groups to share with yet',
                            style: HuddlText.body(color: context.hc.textTertiary),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _filteredGroups.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 72,
                            color: context.hc.divider),
                        itemBuilder: (_, i) {
                          final g = _filteredGroups[i];
                          return ListTile(
                            leading: SizedBox(
                              width: 44,
                              height: 44,
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(12),
                                child: _buildShareImage(g.imageUrl),
                              ),
                            ),
                            title: Text(
                              g.name,
                              style: HuddlText.body(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${g.memberCount} members',
                              style: HuddlText.caption(color: context.hc.textTertiary),
                            ),
                            trailing: _sending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: HuddlColors.primary),
                                  )
                                : Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 6),
                                    decoration: BoxDecoration(
                                      color: HuddlColors.primary,
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Share',
                                      style: HuddlText.caption(weight: FontWeight.w600),
                                    ),
                                  ),
                            onTap: _sending
                                ? null
                                : () => _shareToGroup(g),
                          );
                        },
                      ),
                _filteredMembers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No members in ${widget.borough} to share with',
                            style: HuddlText.body(color: context.hc.textTertiary),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _filteredMembers.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 72,
                            color: context.hc.divider),
                        itemBuilder: (_, i) {
                          final m = _filteredMembers[i];
                          return ListTile(
                            leading: MemberAvatar(
                              name: m.name,
                              imageUrl: m.avatarUrl,
                              size: 44,
                            ),
                            title: Text(
                              m.name,
                              style: HuddlText.body(),
                            ),
                            subtitle: Text(
                              widget.borough,
                              style: HuddlText.caption(color: context.hc.textTertiary),
                            ),
                            trailing: _sending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: HuddlColors.primary),
                                  )
                                : Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 6),
                                    decoration: BoxDecoration(
                                      color: HuddlColors.primary,
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Send',
                                      style: HuddlText.caption(weight: FontWeight.w600),
                                    ),
                                  ),
                            onTap: _sending
                                ? null
                                : () => _shareToMember(m),
                          );
                        },
                      ),
              ],
            ),
          ),
          SizedBox(
              height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _buildShareImage(String imageUrl) {
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(imageUrl,
          width: 44, height: 44, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _shareFallback());
    }
    if (imageUrl.startsWith('http')) {
      return Image.network(imageUrl,
          width: 44, height: 44, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _shareFallback());
    }
    if (imageUrl.startsWith('data:')) {
      try {
        final parts = imageUrl.split(',');
        if (parts.length > 1) {
          final bytes = base64Decode(parts[1]);
          return Image.memory(bytes,
              width: 44, height: 44, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _shareFallback());
        }
      } catch (_) {}
    }
    return _shareFallback();
  }

  Widget _shareFallback() {
    return Container(
      width: 44,
      height: 44,
      color: HuddlColors.gray100,
      child: const Icon(Icons.people,
          size: 22, color: HuddlColors.textHint),
    );
  }
}

// ── Activity Detail Sheet ───────────────────────────────────────────────────
class _ActivityDetailSheet extends StatelessWidget {
  final FeedItem item;
  final String borough;
  final VoidCallback? onAction;

  const _ActivityDetailSheet(
      {required this.item, required this.borough, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HuddlBottomSheetHandle(),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _bgForType(item.type),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_iconForType(item.type),
                      color: _colorForType(item.type), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: HuddlText.heading(),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _typeLabelForType(item.type),
                        style: HuddlText.body(color: _colorForType(item.type)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.hc.divider),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow(
                      Icons.info_outline, 'Details', item.subtitle),
                  const SizedBox(height: 16),
                  _detailRow(
                      Icons.access_time, 'When', item.timeAgo),
                  const SizedBox(height: 16),
                  _detailRow(
                      Icons.location_on_outlined,
                      'Location',
                      borough.isNotEmpty
                          ? borough
                          : 'Your Community'),
                  if (item.meta.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ...item.meta.entries
                        .where((e) =>
                            e.key != 'groupId' &&
                            e.value is String)
                        .map((e) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 12),
                              child: _detailRow(Icons.label_outline,
                                  e.key, e.value.toString()),
                            )),
                  ],
                  const SizedBox(height: 24),
                  HuddlButton(
                    label: 'View',
                    variant: HuddlButtonVariant.primary,
                    fullWidth: true,
                    onPressed: () {
                        if (onAction != null) {
                          onAction!();
                        } else {
                          Navigator.pop(context);
                          final shell =
                              MainShell.shellKey.currentState;
                          if (shell == null) return;
                          switch (item.type) {
                            case FeedItemType.newGroup:
                              shell.switchTab(1);
                              break;
                            case FeedItemType.newEvent:
                              shell.switchTab(2);
                              break;
                            case FeedItemType.newMarketplaceItem:
                              shell.switchTab(3);
                              break;
                            case FeedItemType.newParent:
                            case FeedItemType.milestone:
                            case FeedItemType.partnerPromoted:
                              break;
                          }
                        }
                      },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: HuddlColors.textTertiary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: HuddlText.caption()),
              const SizedBox(height: 2),
              Text(value,
                  style: HuddlText.body()),
            ],
          ),
        ),
      ],
    );
  }


  IconData _iconForType(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return Icons.person_add;
      case FeedItemType.newGroup:
        return Icons.people;
      case FeedItemType.newEvent:
        return Icons.event;
      case FeedItemType.newMarketplaceItem:
        return Icons.storefront;
      case FeedItemType.milestone:
        return Icons.emoji_events;
      case FeedItemType.partnerPromoted:
        return Icons.campaign_outlined;
    }
  }

  Color _colorForType(FeedItemType t) {
    // Design rule: no per-type colour — all nearBlack
    return HuddlColors.nearBlack;
  }

  Color _bgForType(FeedItemType t) {
    // Design rule: uniform neutral grey — no tinted backgrounds
    return const Color(0xFFF7F7F7);
  }

  String _typeLabelForType(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return 'New Parent';
      case FeedItemType.newGroup:
        return 'New Group';
      case FeedItemType.newEvent:
        return 'New Event';
      case FeedItemType.newMarketplaceItem:
        return 'Market';
      case FeedItemType.milestone:
        return 'Milestone';
      case FeedItemType.partnerPromoted:
        return 'Partner';
    }
  }
}
