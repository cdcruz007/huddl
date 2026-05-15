import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
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
import '../../widgets/learning_maturity_indicator.dart';
import '../../services/daily_ai_refresh_service.dart';
import '../../widgets/common/huddl_empty_state.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/huddl_notification_service.dart';
import '../../services/rehome_service.dart';
import '../../screens/marketplace/item_detail_screen.dart';
import '../../screens/groups/group_chat_screen.dart';
import '../../screens/groups/dm_chat_screen.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';


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

  bool _isLoading = true;

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

  // ── Post composer ─────────────────────────────────────────────────────────
  final TextEditingController _postController = TextEditingController();
  bool _isPosting = false;
  String _aiPostHint = '';

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _greetingAnimCtrl;
  late Animation<double> _greetingFade;
  late Animation<Offset> _greetingSlide;
  late AnimationController _feedStaggerCtrl;

  // ── AI feedback tracking ──────────────────────────────────────────────────


  // ── Adaptive: track which sections user interacts with ────────────────────
  int _meetupTaps = 0;
  int _groupTaps = 0;
  int _marketTaps = 0;

  @override
  void initState() {
    super.initState();
    _greetingAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _feedStaggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
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
    _greetingAnimCtrl.dispose();
    _feedStaggerCtrl.dispose();
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

      final groups = await _groupService.getUserGroups('current_user');
      final allMeetups = _meetupService.meetups;
      final upcomingMeetups = allMeetups.take(5).toList();
      final goingEvents = _eventService.goingEvents;
      final newGroups = await _loadNewPublicGroups(borough);

      List<BoroughMember> boroughMembers = [];
      if (pc != null) {
        boroughMembers = InvitationService.getBoroughMembers(pc);
      }

      setState(() {
        _name = _onboarding.name ?? 'there';
        _borough = borough;
        _photoUrl = _onboarding.profilePhotoObjectUrl;
        _userGroups = groups;
        _announcements = _announcementService.boroughAnnouncements;
        _feedItems = _feedService.feedItems;
        _upcomingMeetups = upcomingMeetups;
        _goingEvents = goingEvents;
        _newPublicGroups = newGroups;
        _boroughMembers = boroughMembers;
        _isLoading = false;
      });

      _buildSmartFeed();
      _generateAiPostHint();

      _greetingAnimCtrl.forward();
      _feedStaggerCtrl.forward(from: 0.0);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // ── Feed preferences persistence ────────────────────────────────────────
  Future<void> _loadFeedPrefs() async {
    try {
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
    await BrowserStorage.setString(
        'feed_preferences_v1', json.encode(_feedPrefs));
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

  void _buildSmartFeed() {
    final List<_SmartFeedItem> items = [];
    final now = DateTime.now();

    // 1. Top AI nudge (only the single most relevant)
    final topNudge = _aiFeedService.activeNudges.isNotEmpty
        ? _aiFeedService.activeNudges.first
        : null;
    if (topNudge != null) {
      items.add(_SmartFeedItem(
        type: _SmartFeedType.aiNudge,
        score: topNudge.relevanceScore + 0.05,
        reason: 'Personalised for you',
        nudge: topNudge,
      ));
    }

    // 2. Upcoming meetups user is attending (high priority — max 2)
    final goingMeetups = _upcomingMeetups.where((m) => m.isGoing).take(2);
    for (final m in goingMeetups) {
      final daysUntil = m.dateTime.difference(now).inDays;
      items.add(_SmartFeedItem(
        type: _SmartFeedType.meetup,
        score: daysUntil <= 1 ? 0.95 : 0.82,
        reason: daysUntil == 0 ? 'Today' : daysUntil == 1 ? 'Tomorrow' : 'In $daysUntil days',
        meetup: m,
      ));
    }

    // 2b. Upcoming events user is attending (high priority — max 2)
    final upcomingGoingEvents = _goingEvents
        .where((e) => e.dateTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    for (final e in upcomingGoingEvents.take(2)) {
      final daysUntil = e.dateTime.difference(now).inDays;
      items.add(_SmartFeedItem(
        type: _SmartFeedType.goingEvent,
        score: daysUntil <= 1 ? 0.94 : 0.81,
        reason: daysUntil == 0 ? 'Today' : daysUntil == 1 ? 'Tomorrow' : 'In $daysUntil days',
        event: e,
      ));
    }

    // 3. Announcements (ranked: own posts always first, then pinned, then
    //    engagement + recency — max 4 so a user's new post is never buried)
    final currentUserName = _announcementService.currentUserName;
    final sortedAnn = List<Announcement>.from(_announcements)
      ..sort((a, b) {
        // Own posts always surface to the top
        final aIsOwn = a.authorName == currentUserName ? 1 : 0;
        final bIsOwn = b.authorName == currentUserName ? 1 : 0;
        if (aIsOwn != bIsOwn) return bIsOwn.compareTo(aIsOwn);
        // Then pinned
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        // Then recency-weighted engagement: each hour of age reduces score by 1
        final hoursAgeA = now.difference(a.createdAt).inHours;
        final hoursAgeB = now.difference(b.createdAt).inHours;
        final scoreA = a.likes * 2 + a.comments * 3 - hoursAgeA;
        final scoreB = b.likes * 2 + b.comments * 3 - hoursAgeB;
        return scoreB.compareTo(scoreA);
      });
    for (var i = 0; i < sortedAnn.length && i < 4; i++) {
      final a = sortedAnn[i];
      final isOwn = a.authorName == currentUserName;
      final isNew = now.difference(a.createdAt).inMinutes < 30;
      final score = 0.70 +
          (a.isPinned ? 0.15 : 0.0) +
          (a.likes > 3 ? 0.05 : 0.0) +
          (isOwn ? 0.10 : 0.0);
      items.add(_SmartFeedItem(
        type: _SmartFeedType.announcement,
        score: score.clamp(0.0, 1.0),
        reason: isOwn && isNew
            ? 'Just posted by you'
            : a.isPinned
                ? 'Pinned by community'
                : a.likes > 3
                    ? 'Popular in $_borough'
                    : 'Recent',
        announcement: a,
      ));
    }

    // 4. Nearby meetups not yet joined (max 2, adaptive)
    final suggestedMeetups = _upcomingMeetups
        .where((m) => !m.isGoing)
        .take(_meetupTaps > 2 ? 3 : 2);
    for (final m in suggestedMeetups) {
      items.add(_SmartFeedItem(
        type: _SmartFeedType.suggestedMeetup,
        score: 0.65 + (_meetupTaps > 2 ? 0.1 : 0.0),
        reason: '${m.attendeeCount} parents going',
        meetup: m,
      ));
    }

    // 5. New groups (max 2, adaptive)
    // FILTER: exclude ALL default onboarding groups using multi-signal check.
    // isImageLocked alone is insufficient for docs created before the field
    // existed — _isDefaultOnboardingGroup() adds name-pattern and category
    // guards as defence-in-depth.
    final userCreatedGroups = _newPublicGroups
        .where((g) => !_isDefaultOnboardingGroup(g))
        .toList();
    if (userCreatedGroups.isNotEmpty) {
      for (var i = 0; i < userCreatedGroups.length && i < (_groupTaps > 2 ? 3 : 2); i++) {
        final g = userCreatedGroups[i];
        items.add(_SmartFeedItem(
          type: _SmartFeedType.group,
          score: 0.55 + (_groupTaps > 2 ? 0.1 : 0.0),
          reason: '${g.memberCount} members',
          group: g,
        ));
      }
    }

    // 6. Community activity feed (AI-ranked — max 4)
    final ranked = _aiFeedService.rankFeedItems(_feedItems);
    for (var i = 0; i < ranked.length && i < 4; i++) {
      items.add(_SmartFeedItem(
        type: _SmartFeedType.communityActivity,
        score: ranked[i].score * 0.85,
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
      }
    });

    // ── Fixed section order (score only breaks ties within each section) ──
    // 0. Community posts / announcements  (own posts first, then recent)
    // 1. Upcoming meetups & events the user is going to  (soonest first)
    // 2. Suggested meetups & new groups  (by score within section)
    // 3. Community activity feed  (AI-ranked)
    // 4. AI nudge / Parenting tip  (always at the bottom of the feed)
    const sectionOrder = {
      _SmartFeedType.announcement:       0,
      _SmartFeedType.meetup:             1,
      _SmartFeedType.goingEvent:         1,
      _SmartFeedType.suggestedMeetup:    2,
      _SmartFeedType.group:              2,
      _SmartFeedType.communityActivity:  3,
      _SmartFeedType.aiNudge:            4,
    };
    items.sort((a, b) {
      final sA = sectionOrder[a.type] ?? 99;
      final sB = sectionOrder[b.type] ?? 99;
      if (sA != sB) return sA.compareTo(sB);
      // Within the same section, higher score first
      return b.score.compareTo(a.score);
    });

    setState(() => _smartFeed = items);
  }

  // ── AI: Generate contextual post hint ─────────────────────────────────────
  void _generateAiPostHint() {
    final hour = DateTime.now().hour;
    final hints = <String>[];
    if (hour < 12) {
      hints.addAll([
        'Share a morning tip with $_borough parents...',
        'Any good play spots this morning?',
        'Recommend a local breakfast spot?',
      ]);
    } else if (hour < 17) {
      hints.addAll([
        'What are your afternoon plans in $_borough?',
        'Any soft play recommendations nearby?',
        'Looking for after-school activity ideas?',
      ]);
    } else {
      hints.addAll([
        'How was your day in $_borough?',
        'Any evening family-friendly spots?',
        'Share a bedtime tip for new parents...',
      ]);
    }
    // Mix in meetup-aware hint
    if (_upcomingMeetups.isNotEmpty) {
      hints.add('Heading to ${_upcomingMeetups.first.title}? Share tips!');
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

  // ── Post actions ──────────────────────────────────────────────────────────
  Future<void> _postAnnouncement() async {
    final text = _postController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isPosting = true);
    try {
      await _announcementService.post(text);
      _postController.clear();
      FocusScope.of(context).unfocus();
      setState(() {
        _announcements = _announcementService.boroughAnnouncements;
        _isPosting = false;
      });
      _buildSmartFeed();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Posted to your community!',
                style: GoogleFonts.poppins(fontSize: 13)),
            backgroundColor: HuddlColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isPosting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post. Please try again.',
                style: GoogleFonts.poppins(fontSize: 13)),
            backgroundColor: HuddlColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
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
                          style: GoogleFonts.poppins(fontSize: 13)),
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
                    style: GoogleFonts.poppins(fontSize: 13)),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: color ?? context.hc.textPrimary,
        ),
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
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text('This action cannot be undone.',
            style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                    GoogleFonts.poppins(color: context.hc.textSecondary)),
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
                      style: GoogleFonts.poppins(fontSize: 13)),
                  backgroundColor: HuddlColors.textDark,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Text('Delete',
                style: GoogleFonts.poppins(color: HuddlColors.error)),
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
    HapticFeedback.mediumImpact();
    _buildSmartFeed();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Post hidden',
            style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: HuddlColors.textDark,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          textColor: HuddlColors.primary,
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
            MaterialPageRoute(
              builder: (_) => MeetupDetailScreen(meetup: meetup),
            ),
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
            MaterialPageRoute(
              builder: (_) => MeetupDetailScreen(meetup: match.first),
            ),
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

    if (_isLoading) {
      return Scaffold(
        backgroundColor: hc.scaffold,
        body: const Center(
            child: CircularProgressIndicator(color: HuddlColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: hc.scaffold,
      body: SafeArea(
        child: RefreshIndicator(
          color: HuddlColors.primary,
          onRefresh: _loadData,
          child: CustomScrollView(
            slivers: [
              // ── Streamlined App Bar ────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  color: hc.surface,
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                  child: Row(
                    children: [
                      Semantics(
                        label: 'Huddl home logo',
                        child: _buildAdaptiveLogo(isDark),
                      ),
                      const Spacer(),

                      // Notification bell
                      Semantics(
                        label:
                            'Notifications, $_notifBadgeCount new',
                        button: true,
                        child: HuddlBadge(
                          count: _notifBadgeCount,
                          child: IconButton(
                            icon:
                                const Icon(Icons.notifications_outlined),
                            color: hc.textPrimary,
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _openNotifications();
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                          ),
                        ),
                      ),
                      // Profile avatar
                      Semantics(
                        label: 'Your profile',
                        button: true,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _onAvatarTap();
                          },
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(child: _buildSmallAvatar()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Compact Greeting + Top Insight ─────────────────────
              SliverToBoxAdapter(
                child: SlideTransition(
                  position: _greetingSlide,
                  child: FadeTransition(
                    opacity: _greetingFade,
                    child: _buildContextualGreeting(hc, isDark),
                  ),
                ),
              ),

              // ── Subscription upgrade (free users only) ────────────
              if (SubscriptionService().isFree)
                SliverToBoxAdapter(
                  child: UpgradeBanner(
                    message:
                        'Unlock more groups, meetups & private features',
                    onTap: () => Navigator.pushNamed(
                        context, '/subscription_plans'),
                  ),
                ),

              // ── Step 14: Learning Maturity Indicator ─────────────────
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: LearningMaturityIndicator(compact: false),
                ),
              ),

              // ── Smart Post Composer (AI pre-fill) ──────────────────
              SliverToBoxAdapter(
                child: _buildSmartPostComposer(hc, isDark),
              ),

              // ── AI curation transparency note ──────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) =>
                              HuddlColors.yellowGradient.createShader(bounds),
                          child: const Icon(Icons.lightbulb_outline,
                              size: 14, color: HuddlColors.white),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Curated for you \u00B7 ${_smartFeed.length} updates',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: hc.textTertiary,
                            ),
                          ),
                        ),
                        // Feed preferences
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _showFeedPreferences();
                          },
                          child: SizedBox(
                            width: 48,
                            height: 32,
                            child: Center(
                              child: Icon(Icons.tune,
                                  size: 16,
                                  color: context.hc.textTertiary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Unified Smart Feed ─────────────────────────────────
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= _smartFeed.length) return null;
                    final item = _smartFeed[index];
                    // Staggered entry animation
                    return AnimatedBuilder(
                      animation: _feedStaggerCtrl,
                      builder: (context, child) {
                        final start = (index * 0.08).clamp(0.0, 0.7);
                        final end = (start + 0.5).clamp(0.0, 1.0);
                        final progress =
                            ((_feedStaggerCtrl.value - start) /
                                    (end - start))
                                .clamp(0.0, 1.0);
                        final curved =
                            Curves.easeOutCubic.transform(progress);
                        return Transform.translate(
                          offset: Offset(0, 20 * (1 - curved)),
                          child: Opacity(
                            opacity: curved,
                            child: _buildSmartFeedCard(item, hc, isDark),
                          ),
                        );
                      },
                    );
                  },
                  childCount: _smartFeed.length,
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

  /// Adaptive logo — in dark mode the dark-grey wordmark is tinted white for
  /// proper contrast against the dark surface.
  Widget _buildAdaptiveLogo(bool isDark) {
    final logo = Image.asset(
      'assets/images/logo_huddl.png',
      height: 26,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Text(
        'huddl',
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: HuddlColors.primary,
        ),
      ),
    );

    if (!isDark) return logo;

    // In dark mode, apply a colour filter that brightens the dark-grey wordmark
    // while keeping the orange H icon vibrant.  BlendMode.srcATop tints only
    // the opaque pixels; we use a very light grey so the orange still reads.
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        // R  G  B  A  offset
        2.0, 0, 0, 0, 60,   // boost red channel
        0, 2.0, 0, 0, 60,   // boost green channel
        0, 0, 2.0, 0, 60,   // boost blue channel
        0, 0, 0, 1.0, 0,    // keep alpha
      ]),
      child: logo,
    );
  }

  /// Compact greeting that merges greeting text + top AI insight into one card
  Widget _buildContextualGreeting(dynamic hc, bool isDark) {
    final topNudge = _aiFeedService.activeNudges.isNotEmpty
        ? _aiFeedService.activeNudges.first
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(color: HuddlColors.darkDivider, width: 0.5)
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting row
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    '$_greeting, $_name!',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: hc.textPrimary,
                    ),
                  ),
                ),
              ),
              BoroughBadge(
                borough: _borough,
                size: BoroughBadgeSize.medium,
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Contextual subtitle with AI nudge embedded
          if (topNudge != null)
            GestureDetector(
              onTap: () => _handleNudgeTap(topNudge),
              child: Row(
                children: [
                  Text(topNudge.emoji,
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      topNudge.title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: hc.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 16, color: context.hc.textTertiary),
                ],
              ),
            )
          else
            Text(
              _borough.isNotEmpty
                  ? 'Here\'s what\'s happening in $_borough'
                  : 'Here\'s what\'s happening in your community',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: hc.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  /// Smart post composer with AI-generated contextual hints
  Widget _buildSmartPostComposer(dynamic hc, bool isDark) {
    return Semantics(
      label: 'Post to your community notice board',
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
                      : 'Post to your $_borough neighbours...',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 13,
                    color: hc.textTertiary,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: hc.textPrimary,
                ),
                textAlignVertical: TextAlignVertical.center,
                maxLines: 2,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _postAnnouncement(),
              ),
            ),
            const SizedBox(width: 6),
            Semantics(
              label: 'Send post',
              button: true,
              child: GestureDetector(
                onTap: _isPosting
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        _postAnnouncement();
                      },
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
                      child: _isPosting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.hc.surface,
                              ),
                            )
                          : const Icon(Icons.send_rounded,
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
                  style: GoogleFonts.poppins(fontSize: 13)),
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
    final titleColor = isDark ? HuddlColors.darkTextPrimary : HuddlColors.textDark;
    final subtitleColor = isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;
    final labelColor = isDark ? HuddlColors.primary.withValues(alpha: 0.85) : HuddlColors.primary;

    final categoryLabel = _nudgeCategoryLabel(nudge.type).toUpperCase();

    return GestureDetector(
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
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nudge.title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    nudge.subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: subtitleColor,
                      height: 1.3,
                    ),
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

  /// Meetup the user is attending
  Widget _buildMeetupFeedCard(_SmartFeedItem item, dynamic hc) {
    final meetup = item.meetup!;
    return GestureDetector(
      onTap: () {
        setState(() => _meetupTaps++);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MeetupDetailScreen(meetup: meetup),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: HuddlColors.primary.withValues(alpha: 0.2)),
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
                          color: HuddlColors.primary.withValues(
                              alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.reason,
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      BoroughBadge(
                        borough: meetup.borough,
                        feature: HuddlFeature.meetups,
                      ),
                      const Spacer(),
                      const Icon(Icons.check_circle,
                          size: 14, color: HuddlColors.primary),
                      const SizedBox(width: 3),
                      Text('Going',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.primary,
                          )),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meetup.title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${meetup.timeDisplay} \u00B7 ${meetup.attendeeCount} going',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: context.hc.textTertiary,
                    ),
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
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(event: eventMap),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: HuddlColors.teal.withValues(alpha: 0.25)),
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
            // Event image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: event.imageUrl.isNotEmpty
                    ? Image.network(event.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                              color: HuddlColors.teal
                                  .withValues(alpha: 0.15),
                              child: const Center(
                                child: Icon(Icons.event,
                                    size: 22,
                                    color: HuddlColors.teal),
                              ),
                            ))
                    : Container(
                        color:
                            HuddlColors.teal.withValues(alpha: 0.15),
                        child: const Center(
                          child: Icon(Icons.event,
                              size: 22, color: HuddlColors.teal),
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
                          color: HuddlColors.teal
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.reason,
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.teal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const BoroughBadge(
                        feature: HuddlFeature.events,
                        forceUkWide: true,
                      ),
                      const Spacer(),
                      Icon(Icons.check_circle,
                          size: 14, color: HuddlColors.teal),
                      const SizedBox(width: 3),
                      Text('Going',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.teal,
                          )),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                    ),
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
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: context.hc.textTertiary,
                          ),
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
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: context.hc.textTertiary,
                            ),
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
    return GestureDetector(
      onTap: () {
        setState(() => _meetupTaps++);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MeetupDetailScreen(meetup: meetup),
          ),
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
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${meetup.dateDisplay} \u00B7 ${item.reason}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: context.hc.textTertiary,
                          ),
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
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: context.hc.textSecondary,
                )),
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
              ? Border.all(
                  color: HuddlColors.primary.withValues(alpha: 0.25))
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
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: context.hc.textPrimary,
                              ),
                            ),
                          ),
                          if (a.isPinned)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: HuddlColors.primary.withValues(alpha: 0.08),
                                borderRadius:
                                    BorderRadius.circular(5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.push_pin,
                                      size: 9,
                                      color: HuddlColors.primary),
                                  const SizedBox(width: 2),
                                  Text('Pinned',
                                      style: GoogleFonts.poppins(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w500,
                                        color: HuddlColors.primary,
                                      )),
                                ],
                              ),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            a.timeAgo,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: context.hc.textTertiary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // AI reason
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: HuddlColors.primary.withValues(alpha: 0.08),
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lightbulb_outline,
                                    size: 8,
                                    color: HuddlColors.primary),
                                const SizedBox(width: 3),
                                Text(
                                  item.reason,
                                  style: GoogleFonts.poppins(
                                    fontSize: 9,
                                    color: HuddlColors.accentAmber,
                                  ),
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
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: context.hc.textPrimary,
                height: 1.45,
              ),
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
    return GestureDetector(
      onTap: () {
        setState(() => _groupTaps++);
        _switchToTab(1);
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
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                    ),
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
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: context.hc.textTertiary,
                        ),
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
                color: HuddlColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('View',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primary,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  /// Community activity card
  Widget _buildCommunityFeedCard(_SmartFeedItem item, dynamic hc) {
    final f = item.feedItem!;
    return GestureDetector(
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
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        f.timeAgo,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: context.hc.textTertiary,
                        ),
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
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: context.hc.textTertiary,
                            ),
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
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: _feedIconColor(f.type),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? HuddlColors.primary
                        : HuddlColors.textHint,
                  ),
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
    }
  }

  Color _feedIconColor(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return HuddlColors.teal;
      case FeedItemType.newGroup:
        return HuddlColors.primary;
      case FeedItemType.newEvent:
        return HuddlColors.teal;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.accentAmber;
      case FeedItemType.milestone:
        return HuddlColors.accentAmber;
    }
  }

  Color _feedIconBg(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return HuddlColors.primary.withValues(alpha: 0.08);
      case FeedItemType.newGroup:
        return HuddlColors.primary.withValues(alpha: 0.08);
      case FeedItemType.newEvent:
        return HuddlColors.teal.withValues(alpha: 0.08);
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.teal.withValues(alpha: 0.08);
      case FeedItemType.milestone:
        return HuddlColors.primary.withValues(alpha: 0.08);
    }
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
      return Image.network(imageUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _meetupIconFallback(category));
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
        color: HuddlColors.primary.withValues(alpha: 0.15),
        child: const Center(
          child: Icon(Icons.groups, size: 22, color: HuddlColors.primary),
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
      return Image.network(imageUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _groupImageFallback());
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
      color: HuddlColors.primary.withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.people, size: 22, color: HuddlColors.primary),
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
    // Use local asset avatar as default when no profile photo
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: HuddlColors.primary, width: 1.5),
      ),
      child: ClipOval(
        child: Image.asset(
          _onboarding.parentType?.toLowerCase() == 'dad'
              ? 'assets/images/avatars/John.png'
              : 'assets/images/avatars/Emma.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: HuddlColors.primary.withValues(alpha: 0.08),
            child: Center(
              child: Icon(Icons.person, size: size * 0.5, color: HuddlColors.primary),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART FEED DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

enum _SmartFeedType {
  aiNudge,
  meetup,
  goingEvent,
  suggestedMeetup,
  announcement,
  group,
  communityActivity,
}

class _SmartFeedItem {
  final _SmartFeedType type;
  final double score;
  final String reason;
  final NudgeCard? nudge;
  final Meetup? meetup;
  final Event? event;
  final Announcement? announcement;
  final Group? group;
  final FeedItem? feedItem;

  _SmartFeedItem({
    required this.type,
    required this.score,
    required this.reason,
    this.nudge,
    this.meetup,
    this.event,
    this.announcement,
    this.group,
    this.feedItem,
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
    HapticFeedback.selectionClick();
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  const Icon(Icons.tune, color: HuddlColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Feed Preferences',
                      style: GoogleFonts.poppins(
                          fontSize: 17, fontWeight: FontWeight.w600,
                          color: hc.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Choose which content appears in your feed.',
                style: GoogleFonts.poppins(fontSize: 12, color: hc.textSecondary),
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
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onSaved(_prefs);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Save Preferences',
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
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
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w500,
                          color: enabled ? hc.textPrimary : hc.textTertiary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: hc.textTertiary)),
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
                color: enabled ? HuddlColors.primary : hc.textTertiary,
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
    HapticFeedback.selectionClick();
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: hc.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${_comments.length})',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: hc.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: hc.divider),
            // ── Comment list ────────────────────────────────────────────────
            Flexible(
              child: _comments.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              HuddlIllustration.chat,
                              height: 100,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.chat_bubble_outline,
                                size: 40,
                                color: hc.textTertiary.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No comments yet',
                              style: GoogleFonts.poppins(
                                  fontSize: 14, color: hc.textTertiary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Be the first to comment!',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: HuddlColors.textLight),
                            ),
                          ],
                        ),
                      ),
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
                                    color: HuddlColors.primary.withValues(alpha: 0.25),
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
                                          style: GoogleFonts.poppins(
                                            fontSize: isReply ? 12 : 13,
                                            fontWeight: FontWeight.w600,
                                            color: hc.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          c.timeAgo,
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: hc.textTertiary,
                                          ),
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
                                          color: HuddlColors.primary
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '@${c.replyToName}',
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: HuddlColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      c.content,
                                      style: GoogleFonts.poppins(
                                        fontSize: isReply ? 12 : 13,
                                        color: hc.textPrimary,
                                        height: 1.4,
                                      ),
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
                                              HapticFeedback.lightImpact();
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
                                                        ? HuddlColors.primary
                                                        : HuddlColors.textHint,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${c.likes}',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 11,
                                                      color: c.isLiked
                                                          ? HuddlColors.primary
                                                          : HuddlColors.textHint,
                                                    ),
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
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                    color: _replyingTo ==
                                                            c.authorName
                                                        ? HuddlColors.primary
                                                        : HuddlColors.textHint,
                                                  ),
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
                color: HuddlColors.primary.withValues(alpha: 0.06),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.reply_rounded,
                        size: 14, color: HuddlColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Replying to @$_replyingTo',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: HuddlColors.primary,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelReply,
                      child: Icon(Icons.close_rounded,
                          size: 16, color: HuddlColors.primary),
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
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 14, color: hc.textTertiary),
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
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: hc.textPrimary),
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
        return HuddlColors.teal;
      case 'post_commented':
      case 'comment_replied':
      case 'poll_created':
        return HuddlColors.primary;
      case 'meetup_rsvp':
      case 'meetup_reminder':
      case 'new_meetup_nearby':
      case 'event_update':
        return HuddlColors.teal;
      case 'offer_received':
      case 'offer_accepted':
        return HuddlColors.success;
      case 'offer_declined':
      case 'item_sold':
      case 'saved_item_sold':
        return HuddlColors.primaryDark;
      case 'item_relisted':
        return HuddlColors.accentAmber;
      case 'subscription_activated':
        return HuddlColors.accentAmber;
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
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DMChatScreen(
              recipientId: recipientId,
              recipientName: senderName,
              recipientAvatarColor: '#FF975C',
              conversationId: convId.isEmpty ? null : convId,
            ),
          ));
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
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupChatScreen(
                groupId: groupId,
                groupName: groupName,
                groupImageUrl: groupImageUrl,
              ),
            ));
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
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DMChatScreen(
                recipientId: sellerId,
                recipientName: sellerName,
                recipientAvatarColor: '#FF975C',
                conversationId: null, // getOrCreate on first send
              ),
            ));
          } else {
            // Fallback: open the item detail if we have it
            final item = itemId.isNotEmpty
                ? RehomeService().getItemById(itemId)
                : null;
            if (item != null) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ItemDetailScreen(item: item),
              ));
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
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ItemDetailScreen(item: item),
            ));
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
                const BorderRadius.vertical(top: Radius.circular(20)),
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
                        color: HuddlColors.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Notifications',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: context.hc.textPrimary,
                      ),
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
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
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
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: unread > 0
                              ? HuddlColors.primary
                              : HuddlColors.textHint,
                        ),
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
                                    style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: context.hc.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "You're all caught up!",
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: context.hc.textTertiary,
                                    ),
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
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? HuddlColors.primary
                : HuddlColors.textSecondary,
          ),
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
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: isRead
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: context.hc.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: context.hc.textTertiary,
                        ),
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
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: isRead
                          ? HuddlColors.textHint
                          : HuddlColors.primary,
                      fontWeight: isRead
                          ? FontWeight.w400
                          : FontWeight.w600,
                    ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: HuddlColors.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Share with...',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: context.hc.textPrimary,
                  ),
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
                hintStyle: GoogleFonts.poppins(
                    fontSize: 14, color: context.hc.textTertiary),
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
              style: GoogleFonts.poppins(
                  fontSize: 14, color: context.hc.textPrimary),
            ),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabCtrl,
            labelColor: HuddlColors.primary,
            unselectedLabelColor: HuddlColors.textHint,
            indicatorColor: HuddlColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w400),
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
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: context.hc.textTertiary),
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
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: context.hc.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${g.memberCount} members',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: context.hc.textTertiary),
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
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: context.hc.surface,
                                      ),
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
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: context.hc.textTertiary),
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
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: context.hc.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              widget.borough,
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: context.hc.textTertiary),
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
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: context.hc.surface,
                                      ),
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
      color: HuddlColors.primary.withValues(alpha: 0.08),
      child: const Icon(Icons.people,
          size: 22, color: HuddlColors.primary),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _typeLabelForType(item.type),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _colorForType(item.type),
                        ),
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.primary,
                        foregroundColor: HuddlColors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
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
                              break;
                          }
                        }
                      },
                      child: Text(
                        _actionLabel(item.type),
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
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
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.textTertiary,
                  )),
              const SizedBox(height: 2),
              Text(value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: HuddlColors.textDark,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  String _actionLabel(FeedItemType t) {
    switch (t) {
      case FeedItemType.newGroup:
        return 'View Groups';
      case FeedItemType.newEvent:
        return 'View Events';
      case FeedItemType.newMarketplaceItem:
        return 'View in Market';
      case FeedItemType.newParent:
        return 'Say Welcome';
      case FeedItemType.milestone:
        return 'Celebrate';
    }
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
    }
  }

  Color _colorForType(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return HuddlColors.teal;
      case FeedItemType.newGroup:
        return HuddlColors.primary;
      case FeedItemType.newEvent:
        return HuddlColors.teal;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.accentAmber;
      case FeedItemType.milestone:
        return HuddlColors.accentAmber;
    }
  }

  Color _bgForType(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return HuddlColors.successBg;
      case FeedItemType.newGroup:
        return HuddlColors.primary.withValues(alpha: 0.08);
      case FeedItemType.newEvent:
        return HuddlColors.blueBackground;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.primary.withValues(alpha: 0.06);
      case FeedItemType.milestone:
        return HuddlColors.primary.withValues(alpha: 0.08);
    }
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
    }
  }
}
