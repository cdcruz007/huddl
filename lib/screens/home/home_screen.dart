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

  // ── Notification state ───────────────────────────────────────────────────
  bool _notificationsRead = false;

  int get _notifBadgeCount {
    if (_notificationsRead) return 0;
    // Same logic as the notification sheet: feedItems.take(5) + liked announcements.take(3)
    final feedCount = _feedItems.take(5).length;
    final annCount = _announcements.where((a) => a.likes > 0).take(3).length;
    final total = feedCount + annCount;
    // Always show at least the count of meetups + events to ensure visibility
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
  final Set<String> _feedbackGiven = {};

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
    _loadData();
  }

  @override
  void dispose() {
    _greetingAnimCtrl.dispose();
    _feedStaggerCtrl.dispose();
    _postController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await _onboarding.initialize();
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

  Future<List<Group>> _loadNewPublicGroups(String borough) async {
    final List<Group> result = [];
    try {
      final raw = await BrowserStorage.getString('user_created_groups_v1');
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        for (final j in decoded) {
          final g = Group.fromJson(j as Map<String, dynamic>);
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

    // 3. Announcements (AI-ranked by engagement + recency — max 3)
    final sortedAnn = List<Announcement>.from(_announcements)
      ..sort((a, b) {
        final scoreA = a.likes * 2 + a.comments * 3 + (a.isPinned ? 10 : 0);
        final scoreB = b.likes * 2 + b.comments * 3 + (b.isPinned ? 10 : 0);
        return scoreB.compareTo(scoreA);
      });
    for (var i = 0; i < sortedAnn.length && i < 3; i++) {
      final a = sortedAnn[i];
      final score = 0.70 + (a.isPinned ? 0.15 : 0.0) +
          (a.likes > 3 ? 0.05 : 0.0);
      items.add(_SmartFeedItem(
        type: _SmartFeedType.announcement,
        score: score.clamp(0.0, 1.0),
        reason: a.isPinned
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
    if (_newPublicGroups.isNotEmpty) {
      for (var i = 0; i < _newPublicGroups.length && i < (_groupTaps > 2 ? 3 : 2); i++) {
        final g = _newPublicGroups[i];
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

    // Sort by score descending
    items.sort((a, b) => b.score.compareTo(a.score));

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
        '${announcement.authorName}: "${announcement.content}" - via Huddl Connect';
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
          Navigator.pop(context);
          _switchToTab(tabIndex);
        },
        onNavigateToGroupChat:
            (String groupId, String groupName, String groupImageUrl) {
          Navigator.pop(context);
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
          Navigator.pop(context);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MeetupDetailScreen(meetup: meetup),
            ),
          );
        },
        onMarkAllRead: () {
          setState(() => _notificationsRead = true);
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
                              HuddlColors.aiGradient.createShader(bounds),
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
        gradient: LinearGradient(
          colors: isDark
              ? [HuddlColors.darkSurface, HuddlColors.darkSurfaceVariant]
              : [HuddlColors.peachLight, HuddlColors.peachVeryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
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
                  contentPadding: EdgeInsets.zero,
                ),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: hc.textPrimary,
                ),
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

  // ── Feed preferences sheet ──────────────────────────────────────────────
  void _showFeedPreferences() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
                  const Icon(Icons.tune, color: HuddlColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Feed Preferences',
                      style: GoogleFonts.poppins(
                          fontSize: 17, fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Your feed is personalised based on your interests, activity, and local community.',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: context.hc.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            _feedPrefTile(Icons.groups, 'Meetups I\'m going to',
                'High priority — shown at the top', true),
            _feedPrefTile(Icons.event, 'Events I\'m attending',
                'Reminders as the date approaches', true),
            _feedPrefTile(Icons.campaign_outlined, 'Community announcements',
                'Pinned posts and popular activity', true),
            _feedPrefTile(Icons.group_add, 'Suggested meetups & groups',
                'New meetups and groups near you', true),
            _feedPrefTile(Icons.lightbulb_outline, 'Tips & suggestions',
                'Personalised suggestions based on your activity', true),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
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
                  child: Text('Done',
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: HuddlColors.primary)),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _feedPrefTile(
      IconData icon, String title, String subtitle, bool enabled) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: HuddlColors.primary),
      title: Text(title,
          style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w500,
              color: context.hc.textPrimary)),
      subtitle: Text(subtitle,
          style: GoogleFonts.poppins(
              fontSize: 11, color: context.hc.textTertiary)),
      trailing: Icon(
        enabled ? Icons.check_circle : Icons.circle_outlined,
        size: 20,
        color: enabled ? HuddlColors.primary : context.hc.textTertiary,
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

  /// Inline AI nudge — compact, not a carousel.
  /// Uses dark-mode-aware colours so the card remains readable regardless of
  /// the system brightness.
  Widget _buildInlineNudge(_SmartFeedItem item, dynamic hc) {
    final nudge = item.nudge!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Card colours — light gradient in light mode, dark elevated surface in dark mode
    final gradientColors = isDark
        ? [HuddlColors.darkSurfaceVariant, HuddlColors.darkSurface]
        : [HuddlColors.blueBackground, HuddlColors.white];
    final borderColor = isDark
        ? HuddlColors.darkDivider
        : HuddlColors.blue.withValues(alpha: 0.15);

    // Text colours — always contrast against their card background
    final titleColor = isDark ? HuddlColors.darkTextPrimary : HuddlColors.textDark;
    final subtitleColor = isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;

    return GestureDetector(
      onTap: () => _handleNudgeTap(nudge),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Text(nudge.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // AI feedback thumbs
            _buildAiFeedback('nudge_${nudge.id}'),
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
            _buildAiFeedback('meetup_${meetup.id}'),
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
                                color: HuddlColors.peachLight,
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
                              color: HuddlColors.blueBackground,
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lightbulb_outline,
                                    size: 8,
                                    color: HuddlColors.blue),
                                const SizedBox(width: 3),
                                Text(
                                  item.reason,
                                  style: GoogleFonts.poppins(
                                    fontSize: 9,
                                    color: HuddlColors.blue,
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
                // AI feedback
                _buildAiFeedback('ann_${a.id}'),
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
                        Text(
                          item.reason,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: context.hc.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
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

  // ── AI feedback thumbs (transparent AI) ───────────────────────────────────
  Widget _buildAiFeedback(String itemId) {
    if (_feedbackGiven.contains(itemId)) {
      return SizedBox(
        width: 48,
        height: 32,
        child: Center(
          child: Text('Thanks!',
              style: GoogleFonts.poppins(
                fontSize: 9,
                color: context.hc.textTertiary,
              )),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _feedbackGiven.add(itemId));
          },
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: Icon(Icons.thumb_up_alt_outlined,
                  size: 14, color: context.hc.textTertiary),
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _feedbackGiven.add(itemId));
            // Negative feedback — could inform AI to reduce similar
          },
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: Icon(Icons.thumb_down_alt_outlined,
                  size: 14, color: context.hc.textTertiary),
            ),
          ),
        ),
      ],
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
        return HuddlColors.blue;
      case FeedItemType.newGroup:
        return HuddlColors.primary;
      case FeedItemType.newEvent:
        return HuddlColors.blue;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.yellowDark;
      case FeedItemType.milestone:
        return HuddlColors.accentAmber;
    }
  }

  Color _feedIconBg(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return HuddlColors.successBg;
      case FeedItemType.newGroup:
        return HuddlColors.peachLight;
      case FeedItemType.newEvent:
        return HuddlColors.blueBackground;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.yellowBackground;
      case FeedItemType.milestone:
        return HuddlColors.yellowSoft;
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
      color: HuddlColors.peachLight,
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
            color: HuddlColors.peachLight,
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
  bool _sending = false;
  late List<AnnouncementComment> _comments;

  @override
  void initState() {
    super.initState();
    _comments = List.from(widget.announcement.commentsList);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final comment =
        await widget.service.addComment(widget.announcement.id, text);
    _ctrl.clear();
    setState(() {
      _comments.add(comment);
      _sending = false;
    });
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                      color: context.hc.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${_comments.length})',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: context.hc.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: context.hc.divider),
            Flexible(
              child: _comments.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                size: 40,
                                color: context.hc.textTertiary
                                    .withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            Text(
                              'No comments yet',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: context.hc.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Be the first to comment!',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: HuddlColors.textLight,
                              ),
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
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MemberAvatar(
                              name: c.authorName,
                              imageUrl: c.authorPhotoUrl,
                              size: 36,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        c.authorName,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: context.hc.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        c.timeAgo,
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: context.hc.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.content,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: context.hc.textPrimary,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
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
                                            height: 48,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  c.isLiked
                                                      ? Icons.favorite
                                                      : Icons
                                                          .favorite_border,
                                                  size: 14,
                                                  color: c.isLiked
                                                      ? HuddlColors
                                                          .primary
                                                      : HuddlColors
                                                          .textHint,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${c.likes}',
                                                  style:
                                                      GoogleFonts.poppins(
                                                    fontSize: 11,
                                                    color: c.isLiked
                                                        ? HuddlColors
                                                            .primary
                                                        : HuddlColors
                                                            .textHint,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Semantics(
                                        label: 'Reply to comment',
                                        button: true,
                                        child: GestureDetector(
                                          onTap: () {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: const Text('Reply feature coming soon'),
                                                behavior: SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                          child: SizedBox(
                                            height: 48,
                                            child: Center(
                                              child: Text(
                                                'Reply',
                                                style:
                                                    GoogleFonts.poppins(
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w500,
                                                  color:
                                                      HuddlColors.textHint,
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
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: context.hc.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration: InputDecoration(
                        hintText: 'Write a comment...',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 14, color: context.hc.textTertiary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                              color: context.hc.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                              color: context.hc.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                              color: HuddlColors.primary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: context.hc.textPrimary),
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
class _NotificationsSheet extends StatefulWidget {
  final List<FeedItem> feedItems;
  final List<Announcement> announcements;
  final String borough;
  final List<Meetup> meetups;
  final void Function(int tabIndex) onNavigate;
  final void Function(
          String groupId, String groupName, String groupImageUrl)
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
  State<_NotificationsSheet> createState() =>
      _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  late List<_NotifItem> _notifs;
  bool _showUnreadOnly = false;

  List<_NotifItem> get _displayedNotifs => _showUnreadOnly
      ? _notifs.where((n) => !n.isRead).toList()
      : _notifs;

  @override
  void initState() {
    super.initState();
    _notifs = _buildNotifications();
  }

  List<_NotifItem> _buildNotifications() {
    final List<_NotifItem> notifs = [];
    for (final f in widget.feedItems.take(5)) {
      notifs.add(_NotifItem(
        icon: _iconForType(f.type),
        color: _colorForType(f.type),
        bgColor: _bgForType(f.type),
        title: f.title,
        subtitle: f.subtitle,
        timeAgo: f.timeAgo,
        feedType: f.type,
        imageUrl: f.imageAsset,
        personName:
            f.type == FeedItemType.newParent ? f.title : null,
        meta: f.meta,
        isRead: false,
      ));
    }
    for (final a
        in widget.announcements.where((a) => a.likes > 0).take(3)) {
      notifs.add(_NotifItem(
        icon: Icons.favorite,
        color: HuddlColors.primary,
        bgColor: HuddlColors.peachLight,
        title: '${a.authorName}\'s post',
        subtitle: '${a.likes} people liked this post',
        timeAgo: a.timeAgo,
        feedType: null,
        personName: a.authorName,
        imageUrl: a.authorPhotoUrl,
        meta: const {},
        isRead: false,
      ));
    }
    notifs.sort((a, b) => a.timeAgo.compareTo(b.timeAgo));
    return notifs;
  }

  void _markAllRead() {
    setState(() {
      for (final n in _notifs) {
        n.isRead = true;
      }
    });
    widget.onMarkAllRead();
  }

  void _onNotifTap(_NotifItem n) {
    setState(() => n.isRead = true);
    if (n.feedType == null) {
      widget.onNavigate(0);
      return;
    }
    switch (n.feedType!) {
      case FeedItemType.newGroup:
        final groupId = n.meta['groupId'] as String?;
        if (groupId != null) {
          widget.onNavigateToGroupChat(
              groupId, n.title, n.imageUrl ?? '');
        } else {
          widget.onNavigate(1);
        }
        break;
      case FeedItemType.newEvent:
        final match =
            widget.meetups.where((m) => m.title == n.title).toList();
        if (match.isNotEmpty) {
          widget.onNavigateToMeetup(match.first);
        } else {
          widget.onNavigate(2);
        }
        break;
      case FeedItemType.newMarketplaceItem:
        widget.onNavigate(3);
        break;
      case FeedItemType.newParent:
      case FeedItemType.milestone:
        widget.onNavigate(0);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifs.where((n) => !n.isRead).length;
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
                if (unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: HuddlColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unreadCount',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.hc.surface,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: unreadCount > 0 ? _markAllRead : null,
                  child: Text(
                    'Mark all read',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: unreadCount > 0
                          ? HuddlColors.primary
                          : HuddlColors.textHint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.hc.divider),
          // Unread / All filter row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _notifFilterChip('All', !_showUnreadOnly, () {
                  setState(() => _showUnreadOnly = false);
                }),
                const SizedBox(width: 8),
                _notifFilterChip(
                  'Unread${unreadCount > 0 ? ' ($unreadCount)' : ''}',
                  _showUnreadOnly,
                  () {
                    setState(() => _showUnreadOnly = true);
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.hc.divider),
          Flexible(
            child: _displayedNotifs.isEmpty
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
                                : 'No new notifications',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: context.hc.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'You\'re all caught up!',
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
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: _displayedNotifs.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 72,
                        color: context.hc.divider),
                    itemBuilder: (_, index) {
                      final n = _displayedNotifs[index];
                      return _buildNotifTile(n);
                    },
                  ),
          ),
          SizedBox(
              height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _notifFilterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? HuddlColors.primary : HuddlColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildNotifTile(_NotifItem n) {
    final resolvedPhoto = n.personName != null
        ? MemberPhotoService.getPhotoByName(n.personName!)
        : null;
    final photoUrl = resolvedPhoto ?? n.imageUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    return Material(
      color: n.isRead
          ? HuddlColors.white
          : HuddlColors.peachLight.withValues(alpha: 0.3),
      child: InkWell(
        onTap: () => _onNotifTap(n),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (hasPhoto)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: _buildNotifImage(photoUrl),
                      )
                    else
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: n.bgColor,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child:
                            Icon(n.icon, color: n.color, size: 24),
                      ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: n.bgColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: context.hc.surface, width: 1.5),
                        ),
                        child:
                            Icon(n.icon, size: 11, color: n.color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: n.isRead
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: context.hc.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: context.hc.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    n.timeAgo,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: n.isRead
                          ? HuddlColors.textHint
                          : HuddlColors.primary,
                      fontWeight: n.isRead
                          ? FontWeight.w400
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (!n.isRead)
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

  Widget _buildNotifImage(String url) {
    if (url.startsWith('data:')) {
      try {
        final parts = url.split(',');
        if (parts.length > 1) {
          final bytes = base64Decode(parts[1]);
          return Image.memory(bytes,
              width: 48, height: 48, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _notifImageFallback());
        }
      } catch (_) {}
      return _notifImageFallback();
    }
    if (url.startsWith('http') || url.startsWith('blob:')) {
      return Image.network(url,
          width: 48, height: 48, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _notifImageFallback());
    }
    if (url.startsWith('assets/')) {
      return Image.asset(url,
          width: 48, height: 48, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _notifImageFallback());
    }
    return _notifImageFallback();
  }

  Widget _notifImageFallback() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: HuddlColors.peachLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Icon(Icons.person,
          color: HuddlColors.primary, size: 24),
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
    }
  }

  Color _colorForType(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return HuddlColors.blue;
      case FeedItemType.newGroup:
        return HuddlColors.primary;
      case FeedItemType.newEvent:
        return HuddlColors.blue;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.yellowDark;
      case FeedItemType.milestone:
        return HuddlColors.accentAmber;
    }
  }

  Color _bgForType(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return HuddlColors.successBg;
      case FeedItemType.newGroup:
        return HuddlColors.peachLight;
      case FeedItemType.newEvent:
        return HuddlColors.blueBackground;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.yellowBackground;
      case FeedItemType.milestone:
        return HuddlColors.yellowSoft;
    }
  }
}

class _NotifItem {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String title;
  final String subtitle;
  final String timeAgo;
  final FeedItemType? feedType;
  final String? imageUrl;
  final String? personName;
  final Map<String, dynamic> meta;
  bool isRead;

  _NotifItem({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.timeAgo,
    required this.feedType,
    this.imageUrl,
    this.personName,
    this.meta = const {},
    this.isRead = false,
  });
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
      color: HuddlColors.peachLight,
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
        return HuddlColors.blue;
      case FeedItemType.newGroup:
        return HuddlColors.primary;
      case FeedItemType.newEvent:
        return HuddlColors.blue;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.yellowDark;
      case FeedItemType.milestone:
        return HuddlColors.accentAmber;
    }
  }

  Color _bgForType(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return HuddlColors.successBg;
      case FeedItemType.newGroup:
        return HuddlColors.peachLight;
      case FeedItemType.newEvent:
        return HuddlColors.blueBackground;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.yellowBackground;
      case FeedItemType.milestone:
        return HuddlColors.yellowSoft;
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
