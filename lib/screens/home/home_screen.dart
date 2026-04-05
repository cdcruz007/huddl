import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
import '../../services/invitation_service.dart';
import '../ai/ai_copilot_screen.dart';
import '../../services/dm_service.dart';
import '../../services/browser_storage.dart';
import '../main_shell.dart';
import '../events/meetup_detail_screen.dart';
import '../../services/subscription_service.dart';
import '../../widgets/upgrade_prompt.dart';
import '../../services/ai_feed_service.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OnboardingDataService _onboarding = OnboardingDataService();
  final DefaultGroupService _groupService = DefaultGroupService();
  final PostcodeService _postcodeService = PostcodeService();
  final AnnouncementService _announcementService = AnnouncementService();
  final CommunityFeedService _feedService = CommunityFeedService();
  final MeetupService _meetupService = MeetupService();
  final InvitationService _invitationService = InvitationService();
  final DMService _dmService = DMService();
  final AiFeedService _aiFeedService = AiFeedService();


  bool _isLoading = true;

  String _name = '';
  String _borough = '';
  String? _photoUrl;
  List<Group> _userGroups = [];
  List<Announcement> _announcements = [];
  List<FeedItem> _feedItems = [];
  List<Meetup> _upcomingMeetups = [];
  List<Group> _newPublicGroups = [];
  List<BoroughMember> _boroughMembers = [];

  // Announcement compose
  final TextEditingController _postController = TextEditingController();
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

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

      String borough = '';
      final pc = _onboarding.postcode;
      if (pc != null) {
        borough = _postcodeService.getBoroughFromPostcode(pc) ?? '';
      }

      final groups = await _groupService.getUserGroups('current_user');

      // Get upcoming meetups (sorted by date, future only)
      final allMeetups = _meetupService.meetups;
      final upcomingMeetups = allMeetups.take(5).toList();

      // Get new public groups (user-created ones loaded from storage)
      final newGroups = await _loadNewPublicGroups();

      // Get borough members for Welcome DM
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
        _newPublicGroups = newGroups;
        _boroughMembers = boroughMembers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<List<Group>> _loadNewPublicGroups() async {
    // Load ONLY user-created public groups from same borough (exclude defaults)
    final List<Group> result = [];
    try {
      final raw = await BrowserStorage.getString('user_created_groups_v1');
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        for (final j in decoded) {
          final g = Group.fromJson(j as Map<String, dynamic>);
          if (!g.isPrivate) {
            // Only show groups from the same borough or without borough info
            if (g.creatorBorough == null ||
                g.creatorBorough!.isEmpty ||
                g.creatorBorough == 'Unknown Borough' ||
                g.creatorBorough == _borough) {
              result.add(g);
            }
          }
        }
      }
    } catch (_) {}
    // Do NOT include default groups — only user-created ones
    return result.take(6).toList();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ── Tab switching helper ──────────────────────────────────────────────────
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
    await _announcementService.post(text);
    _postController.clear();
    setState(() {
      _announcements = _announcementService.boroughAnnouncements;
      _isPosting = false;
    });
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

  /// Shows a bottom sheet letting the user choose a group or individual to share with.
  void _showShareTargetSheet(Announcement announcement) {
    final shareText = '${announcement.authorName}: "${announcement.content}" - via Huddl Connect';

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
                    const Icon(Icons.check_circle, color: HuddlColors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Shared with $targetName',
                          style: GoogleFonts.poppins(fontSize: 13)),
                    ),
                  ],
                ),
                backgroundColor: HuddlColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        );
      },
    );
  }

  /// Send a welcome DM to a new parent in the same borough
  Future<void> _sendWelcomeDM(FeedItem item) async {
    final recipientName = item.title; // The person's name is in title
    final recipientId = 'mem_${recipientName.toLowerCase().replaceAll(' ', '_').replaceAll("'", '')}';
    final senderName = _name.isNotEmpty ? _name : 'You';

    final conv = await _dmService.getOrCreateConversation(
      recipientId: recipientId,
      recipientName: recipientName,
    );

    await _dmService.sendMessage(
      conversationId: conv.id,
      message: 'Welcome to the $_borough community! Great to have you here. If you need any tips or recommendations for the area, don\'t hesitate to ask!',
      senderName: senderName,
    );

    if (mounted) {
      // Switch to Messages tab
      _switchToTab(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: HuddlColors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Welcome message sent to $recipientName!',
                    style: GoogleFonts.poppins(fontSize: 13)),
              ),
            ],
          ),
          backgroundColor: HuddlColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        decoration: const BoxDecoration(
          color: HuddlColors.white,
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
      leading: Icon(icon, color: color ?? HuddlColors.textDark, size: 22),
      title: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: color ?? HuddlColors.textDark,
        ),
      ),
      onTap: onTap,
    );
  }

  void _confirmDeletePost(Announcement announcement) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete post?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text('This action cannot be undone.',
            style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: HuddlColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _announcementService.delete(announcement.id);
              setState(() {
                _announcements = _announcementService.boroughAnnouncements;
              });
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

  // ── Notification bell ─────────────────────────────────────────────────────
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
        onNavigateToGroupChat: (String groupId, String groupName, String groupImageUrl) {
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
          // Clear the badge count on the bell icon
          setState(() {});
        },
      ),
    );
  }

  // ── Profile avatar tap ────────────────────────────────────────────────────
  void _onAvatarTap() {
    _switchToTab(4); // Navigate to Profile tab
  }

  // ── Feed item tap ─────────────────────────────────────────────────────────
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
        _switchToTab(1);
        break;
      case FeedItemType.newEvent:
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
        _switchToTab(3);
        break;
      case FeedItemType.milestone:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ActivityDetailSheet(item: item, borough: _borough),
        );
        break;
    }
  }

  // ── See All: Community Activity ───────────────────────────────────────────
  void _openAllCommunityActivity() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AllCommunityActivityScreen(
          feedItems: _feedItems,
          borough: _borough,
          onItemTap: _onFeedItemTap,
        ),
      ),
    );
  }

  // ── See All: Your Groups ──────────────────────────────────────────────────
  void _openAllGroups() {
    _switchToTab(1); // Go to MyHuddl tab which shows all groups
  }

  // ── See All: Upcoming Events ──────────────────────────────────────────────
  void _openAllEvents() {
    _switchToTab(2); // Go to Meetups tab
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: HuddlColors.background,
        body: Center(
            child: CircularProgressIndicator(color: HuddlColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: HuddlColors.primary,
          onRefresh: _loadData,
          child: CustomScrollView(
            slivers: [
              // ── App bar ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  color: HuddlColors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/images/logo_huddl.png',
                        height: 28,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Text(
                          'huddl',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AiCopilotScreen(),
                          ),
                        ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: HuddlColors.aiGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: HuddlColors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      HuddlBadge(
                        count: _feedService.newItemsSinceLastLogin
                            .clamp(0, 9),
                        child: IconButton(
                          icon: const Icon(Icons.notifications_outlined),
                          color: HuddlColors.textDark,
                          onPressed: _openNotifications,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: _onAvatarTap,
                        child: _buildSmallAvatar(),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Greeting card ────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [HuddlColors.peachLight, HuddlColors.peachVeryLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_greeting, $_name!',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _borough.isNotEmpty
                            ? 'Here\'s what\'s happening in $_borough today.'
                            : 'Here\'s what\'s happening in your community today.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: HuddlColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Subscription upgrade banner (free users) ─────────────
              if (SubscriptionService().isFree)
                SliverToBoxAdapter(
                  child: UpgradeBanner(
                    message: 'Unlock more groups, meetups & private features',
                    onTap: () => Navigator.pushNamed(context, '/subscription_plans'),
                  ),
                ),

              // ── AI Nudge Cards ───────────────────────────────────
              if (_aiFeedService.activeNudges.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildNudgeCarousel(),
                ),

              // ── Meetups I'm Going ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: HuddlSectionHeader(
                    title: "Meetups I'm Going",
                    actionText: 'See all',
                    onAction: _openAllEvents,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: _upcomingMeetups.where((m) => m.isGoing).isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: HuddlColors.blueBackground,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(
                                  color: HuddlColors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.event_available,
                                    color: HuddlColors.blue, size: 24),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'No upcoming meetups yet',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Browse meetups and mark yourself as going!',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: HuddlColors.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _switchToTab(2),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: HuddlColors.blue,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Browse',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: HuddlColors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SizedBox(
                        height: 210,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _upcomingMeetups.where((m) => m.isGoing).length,
                          itemBuilder: (context, index) {
                            final goingMeetups = _upcomingMeetups.where((m) => m.isGoing).toList();
                            final meetup = goingMeetups[index];
                            return Container(
                              width: 240,
                              margin: EdgeInsets.only(
                                  right: index < goingMeetups.length - 1 ? 12 : 0),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          MeetupDetailScreen(meetup: meetup),
                                    ),
                                  );
                                },
                                child: _MeetupCard(meetup: meetup),
                              ),
                            );
                          },
                        ),
                      ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // ── Borough notice board ─────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_outlined,
                          size: 20, color: HuddlColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        _borough.isNotEmpty
                            ? '$_borough Notice Board'
                            : 'Community Notice Board',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── Post composer ────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: HuddlColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _buildTinyAvatar(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _postController,
                          decoration: InputDecoration(
                            hintText:
                                'Post to your $_borough neighbours...',
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 14,
                              color: HuddlColors.textHint,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: HuddlColors.textDark,
                          ),
                          maxLines: 3,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _postAnnouncement(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _isPosting ? null : _postAnnouncement,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: _isPosting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: HuddlColors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded,
                                  size: 18, color: HuddlColors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── Announcements list ───────────────────────────────────
              if (_announcements.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= _announcements.length) return null;
                      final a = _announcements[index];
                      return _AnnouncementCard(
                        announcement: a,
                        onLike: () => _toggleLike(a.id),
                        onComment: () => _openComments(a),
                        onShare: () => _sharePost(a),
                        onMenu: () => _showPostMenu(a),
                      );
                    },
                    childCount: _announcements.length.clamp(0, 5),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // ── Upcoming Meetups ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: HuddlSectionHeader(
                    title: 'Upcoming Meetups',
                    actionText: 'See all',
                    onAction: _openAllEvents,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 210,
                  child: _upcomingMeetups.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('No upcoming meetups',
                                style: GoogleFonts.poppins(
                                    fontSize: 14, color: HuddlColors.textHint)),
                          ),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _upcomingMeetups.length,
                          itemBuilder: (context, index) {
                            final meetup = _upcomingMeetups[index];
                            return Container(
                              width: 240,
                              margin: EdgeInsets.only(
                                  right: index < _upcomingMeetups.length - 1
                                      ? 12
                                      : 0),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          MeetupDetailScreen(meetup: meetup),
                                    ),
                                  );
                                },
                                child: _MeetupCard(meetup: meetup),
                              ),
                            );
                          },
                        ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // ── New Groups ──────────────────────────────────────────
              if (_newPublicGroups.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: HuddlSectionHeader(
                      title: 'New Groups',
                      actionText: 'See all',
                      onAction: _openAllGroups,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 210,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _newPublicGroups.length,
                      itemBuilder: (context, index) {
                        final g = _newPublicGroups[index];
                        return Container(
                          width: 240,
                          margin: EdgeInsets.only(
                              right: index < _newPublicGroups.length - 1
                                  ? 12
                                  : 0),
                          child: GestureDetector(
                            onTap: () {
                              // Navigate to Discover tab in Chat
                              _switchToTab(1);
                            },
                            child: _NewGroupCard(group: g),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],

              // ── Community activity feed ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: HuddlSectionHeader(
                    title: 'Community activity',
                    actionText: 'See all',
                    onAction: _openAllCommunityActivity,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= _feedItems.length) return null;
                    return GestureDetector(
                      onTap: () => _onFeedItemTap(_feedItems[index]),
                      child: _FeedCard(item: _feedItems[index]),
                    );
                  },
                  childCount: _feedItems.length.clamp(0, 10),
                ),
              ),

              // Bottom padding for nav bar
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  // ── AI Nudge Carousel ────────────────────────────────────────────────
  Widget _buildNudgeCarousel() {
    final nudges = _aiFeedService.activeNudges.take(3).toList();
    if (nudges.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.auto_awesome, size: 14, color: HuddlColors.white),
              ),
              const SizedBox(width: 8),
              Text(
                'AI Insights for You',
                style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: nudges.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _buildNudgeCard(nudges[i]),
          ),
        ),
      ],
    );
  }

  void _handleNudgeTap(NudgeCard nudge) {
    // Map nudge route strings to MainShell tab indices
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

  Widget _buildNudgeCard(NudgeCard nudge) {
    return GestureDetector(
      onTap: () => _handleNudgeTap(nudge),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              nudge.type == NudgeType.nearbyMeetup
                  ? const Color(0xFFFFF0E6)
                  : nudge.type == NudgeType.milestone
                      ? const Color(0xFFE6F5F3)
                      : nudge.type == NudgeType.weatherActivity
                          ? const Color(0xFFEDF4FF)
                          : const Color(0xFFFFF7C9),
              HuddlColors.white,
            ],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HuddlColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(nudge.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nudge.title,
                    style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: HuddlColors.textDark,
                    ),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _aiFeedService.dismissNudge(nudge.id);
                    setState(() {});
                  },
                  child: const Icon(Icons.close, size: 16, color: HuddlColors.textHint),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              nudge.subtitle,
              style: GoogleFonts.poppins(
                fontSize: 11, color: HuddlColors.textSecondary, height: 1.3,
              ),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            if (nudge.actionLabel != null)
              GestureDetector(
                onTap: () => _handleNudgeTap(nudge),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    nudge.actionLabel!,
                    style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: HuddlColors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallAvatar() {
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      if (_photoUrl!.startsWith('data:')) {
        try {
          final parts = _photoUrl!.split(',');
          if (parts.length > 1) {
            final bytes = base64Decode(parts[1]);
            return ClipOval(
              child: Image.memory(bytes,
                  width: 32, height: 32, fit: BoxFit.cover),
            );
          }
        } catch (_) {}
      }
      return ClipOval(
        child: Image.network(
          _photoUrl!,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(32),
        ),
      );
    }
    return _avatarFallback(32);
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
                  width: 36, height: 36, fit: BoxFit.cover),
            );
          }
        } catch (_) {}
      }
      return ClipOval(
        child: Image.network(
          _photoUrl!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(36),
        ),
      );
    }
    return _avatarFallback(36);
  }

  Widget _avatarFallback(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HuddlColors.peachLight,
        border: Border.all(color: HuddlColors.primary, width: 1.5),
      ),
      child: Center(
        child: Text(
          _name.isNotEmpty ? _name[0].toUpperCase() : 'U',
          style: GoogleFonts.poppins(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
            color: HuddlColors.primary,
          ),
        ),
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// SUBWIDGETS
// ═══════════════════════════════════════════════════════════════════════════

// ── Meetup card (with real image) ─────────────────────────────────────────
class _MeetupCard extends StatelessWidget {
  final Meetup meetup;

  const _MeetupCard({required this.meetup});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meetup image
          SizedBox(
            height: 110,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                meetup.imageUrl.isNotEmpty
                    ? Image.network(
                        meetup.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: HuddlColors.primary,
                          child: const Center(
                            child: Icon(Icons.groups,
                                size: 40, color: HuddlColors.white),
                          ),
                        ),
                      )
                    : Container(
                        color: HuddlColors.primary,
                        child: const Center(
                          child: Icon(Icons.groups,
                              size: 40, color: HuddlColors.white),
                        ),
                      ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: HuddlColors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      meetup.dateDisplay,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.primary,
                      ),
                    ),
                  ),
                ),
                if (!meetup.isFree)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: HuddlColors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        meetup.price != null
                            ? '\u00a3${meetup.price!.toStringAsFixed(0)}'
                            : '',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meetup.title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 14, color: HuddlColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        meetup.timeDisplay,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.textHint,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.people_outline,
                        size: 14, color: HuddlColors.textHint),
                    const SizedBox(width: 4),
                    Text(
                      '${meetup.attendeeCount} going',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textHint,
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
  }
}

// ── New Group card (matching meetup card style) ──────────────────────────
class _NewGroupCard extends StatelessWidget {
  final Group group;

  const _NewGroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 110,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildGroupImage(group.imageUrl),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: HuddlColors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people,
                            size: 12, color: HuddlColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${group.memberCount} members',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  group.description,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.textHint,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildGroupImage(String imageUrl) {
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(imageUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imageFallback());
    }
    if (imageUrl.startsWith('http')) {
      return Image.network(imageUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imageFallback());
    }
    if (imageUrl.startsWith('data:')) {
      try {
        final parts = imageUrl.split(',');
        if (parts.length > 1) {
          final bytes = base64Decode(parts[1]);
          return Image.memory(bytes, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _imageFallback());
        }
      } catch (_) {}
    }
    return _imageFallback();
  }

  static Widget _imageFallback() {
    return Container(
      color: HuddlColors.peachLight,
      child: const Center(
        child: Icon(Icons.people, size: 40, color: HuddlColors.primary),
      ),
    );
  }
}

// ── Announcement card (town-hall notice) ──────────────────────────────────
class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onMenu;

  const _AnnouncementCard({
    required this.announcement,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: announcement.isPinned
            ? Border.all(
                color: HuddlColors.primary.withValues(alpha: 0.3), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Author avatar with profile photo
              MemberAvatar(
                name: announcement.authorName,
                imageUrl: announcement.authorPhotoUrl,
                size: 40,
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
                            announcement.authorName,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.textDark,
                            ),
                          ),
                        ),
                        if (announcement.isPinned)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: HuddlColors.peachLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.push_pin,
                                    size: 10, color: HuddlColors.primary),
                                const SizedBox(width: 2),
                                Text(
                                  'Pinned',
                                  style: GoogleFonts.poppins(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                    color: HuddlColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    Text(
                      announcement.timeAgo,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onMenu,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.more_horiz, color: HuddlColors.textHint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            announcement.content,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: HuddlColors.textDark,
              height: 1.5,
            ),
          ),
          // Borough tag
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: HuddlColors.peachLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on,
                    size: 12, color: HuddlColors.primary),
                const SizedBox(width: 4),
                Text(
                  announcement.borough,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Actions row
          Row(
            children: [
              // Love / Like
              GestureDetector(
                onTap: onLike,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: announcement.isLiked
                        ? HuddlColors.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        announcement.isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 18,
                        color: announcement.isLiked
                            ? HuddlColors.primary
                            : HuddlColors.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${announcement.likes}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: announcement.isLiked
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: announcement.isLiked
                              ? HuddlColors.primary
                              : HuddlColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Comment
              GestureDetector(
                onTap: onComment,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline,
                          size: 18, color: HuddlColors.textHint),
                      const SizedBox(width: 4),
                      Text(
                        '${announcement.comments}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Share
              GestureDetector(
                onTap: onShare,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.share_outlined,
                          size: 18, color: HuddlColors.textHint),
                      const SizedBox(width: 4),
                      Text(
                        announcement.shares > 0
                            ? '${announcement.shares}'
                            : 'Share',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Community feed card (with images) ─────────────────────────────────────
class _FeedCard extends StatelessWidget {
  final FeedItem item;

  const _FeedCard({required this.item});

  String? get _imageUrl {
    // Resolve image based on type
    switch (item.type) {
      case FeedItemType.newParent:
        return MemberPhotoService.getPhotoByName(item.title);
      case FeedItemType.newGroup:
      case FeedItemType.newEvent:
      case FeedItemType.newMarketplaceItem:
        return item.imageAsset; // image URL stored in imageAsset field
      case FeedItemType.milestone:
        return null;
    }
  }

  Color get _iconColor {
    switch (item.type) {
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

  Color get _iconBg {
    switch (item.type) {
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

  IconData get _icon {
    switch (item.type) {
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

  String get _typeLabel {
    switch (item.type) {
      case FeedItemType.newParent:
        return 'New Parent';
      case FeedItemType.newGroup:
        return 'New Group';
      case FeedItemType.newEvent:
        return 'New Meetup';
      case FeedItemType.newMarketplaceItem:
        return 'Preloved';
      case FeedItemType.milestone:
        return 'Milestone';
    }
  }

  Widget _buildFeedImage(String url, IconData fallbackIcon, Color fallbackColor) {
    if (url.startsWith('data:')) {
      try {
        final parts = url.split(',');
        if (parts.length > 1) {
          final bytes = base64Decode(parts[1]);
          return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover,
              width: 52, height: 52,
              errorBuilder: (_, __, ___) =>
                  Center(child: Icon(fallbackIcon, color: fallbackColor, size: 24)));
        }
      } catch (_) {}
    }
    if (url.startsWith('assets/')) {
      return Image.asset(url, fit: BoxFit.cover,
          width: 52, height: 52,
          errorBuilder: (_, __, ___) =>
              Center(child: Icon(fallbackIcon, color: fallbackColor, size: 24)));
    }
    if (url.startsWith('http')) {
      return Image.network(url, fit: BoxFit.cover,
          width: 52, height: 52,
          errorBuilder: (_, __, ___) =>
              Center(child: Icon(fallbackIcon, color: fallbackColor, size: 24)));
    }
    return Center(child: Icon(fallbackIcon, color: fallbackColor, size: 24));
  }

  @override
  Widget build(BuildContext context) {
    final imgUrl = _imageUrl;
    final hasImage = imgUrl != null && imgUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.white,
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
          // Image or icon
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _iconBg,
              borderRadius: item.type == FeedItemType.newParent
                  ? BorderRadius.circular(26)
                  : BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasImage
                ? _buildFeedImage(imgUrl, _icon, _iconColor)
                : Center(child: Icon(_icon, color: _iconColor, size: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.textHint,
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _typeLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _iconColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.timeAgo,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: HuddlColors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: HuddlColors.textHint),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BOTTOM SHEETS & FULL-SCREEN PAGES
// ═══════════════════════════════════════════════════════════════════════════

// ── Comments Sheet ────────────────────────────────────────────────────────
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
      decoration: const BoxDecoration(
        color: HuddlColors.white,
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
                      color: HuddlColors.textDark,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${_comments.length})',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: HuddlColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: HuddlColors.divider),
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
                                color:
                                    HuddlColors.textHint.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            Text(
                              'No comments yet',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: HuddlColors.textHint,
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
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        c.authorName,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: HuddlColors.textDark,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        c.timeAgo,
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: HuddlColors.textHint,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.content,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: HuddlColors.textDark,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            c.isLiked = !c.isLiked;
                                            c.likes += c.isLiked ? 1 : -1;
                                          });
                                        },
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
                                      const SizedBox(width: 16),
                                      Text(
                                        'Reply',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: HuddlColors.textHint,
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
            const Divider(height: 1, color: HuddlColors.divider),
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
                            fontSize: 14, color: HuddlColors.textHint),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide:
                              const BorderSide(color: HuddlColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide:
                              const BorderSide(color: HuddlColors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide:
                              const BorderSide(color: HuddlColors.primary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: HuddlColors.textDark),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sending ? null : _send,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: HuddlColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: HuddlColors.white),
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

// ── Notifications Sheet ───────────────────────────────────────────────────
class _NotificationsSheet extends StatefulWidget {
  final List<FeedItem> feedItems;
  final List<Announcement> announcements;
  final String borough;
  final List<Meetup> meetups;
  final void Function(int tabIndex) onNavigate;
  final void Function(String groupId, String groupName, String groupImageUrl) onNavigateToGroupChat;
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
  late List<_NotifItem> _notifs;

  @override
  void initState() {
    super.initState();
    _notifs = _buildNotifications();
  }

  List<_NotifItem> _buildNotifications() {
    final List<_NotifItem> notifs = [];

    // Recent community activity as notifications
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
        personName: f.type == FeedItemType.newParent ? f.title : null,
        meta: f.meta,
        isRead: false,
      ));
    }

    // Announcement interactions as notifications
    for (final a in widget.announcements.where((a) => a.likes > 0).take(3)) {
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

    // Sort by time (newest first)
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
    // Mark as read
    setState(() => n.isRead = true);

    // Navigate based on type
    if (n.feedType == null) {
      // Announcement like - go to home (notice board)
      widget.onNavigate(0);
      return;
    }
    switch (n.feedType!) {
      case FeedItemType.newGroup:
        final groupId = n.meta['groupId'] as String?;
        if (groupId != null) {
          final groupName = n.title;
          final groupImage = n.imageUrl ?? '';
          widget.onNavigateToGroupChat(groupId, groupName, groupImage);
        } else {
          widget.onNavigate(1);
        }
        break;
      case FeedItemType.newEvent:
        // Try to find the exact meetup and navigate to its detail screen
        final match = widget.meetups
            .where((m) => m.title == n.title)
            .toList();
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
      decoration: const BoxDecoration(
        color: HuddlColors.white,
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
                    color: HuddlColors.textDark,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: HuddlColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unreadCount',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.white,
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
          const Divider(height: 1, color: HuddlColors.divider),
          Flexible(
            child: _notifs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none,
                              size: 48,
                              color:
                                  HuddlColors.textHint.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          Text(
                            'No new notifications',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: HuddlColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'You\'re all caught up!',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: HuddlColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: _notifs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72, color: HuddlColors.divider),
                    itemBuilder: (_, index) {
                      final n = _notifs[index];
                      return _buildNotifTile(n);
                    },
                  ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _buildNotifTile(_NotifItem n) {
    // Resolve photo: personName lookup > imageUrl > icon fallback
    final resolvedPhoto = n.personName != null
        ? MemberPhotoService.getPhotoByName(n.personName!)
        : null;
    final photoUrl = resolvedPhoto ?? n.imageUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Material(
      color: n.isRead ? HuddlColors.white : HuddlColors.peachLight.withValues(alpha: 0.3),
      child: InkWell(
        onTap: () => _onNotifTap(n),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Leading: Photo or icon
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
                        child: Icon(n.icon, color: n.color, size: 24),
                      ),
                    // Small type badge at bottom-right
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: n.bgColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: HuddlColors.white, width: 1.5),
                        ),
                        child: Icon(n.icon, size: 11, color: n.color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600,
                        color: HuddlColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textHint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Time + unread dot
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    n.timeAgo,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: n.isRead ? HuddlColors.textHint : HuddlColors.primary,
                      fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600,
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
          return Image.memory(bytes, width: 48, height: 48, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _notifImageFallback());
        }
      } catch (_) {}
      return _notifImageFallback();
    }
    if (url.startsWith('http') || url.startsWith('blob:')) {
      return Image.network(url, width: 48, height: 48, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _notifImageFallback());
    }
    if (url.startsWith('assets/')) {
      return Image.asset(url, width: 48, height: 48, fit: BoxFit.cover,
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
      child: const Icon(Icons.person, color: HuddlColors.primary, size: 24),
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

// ── Share Post Sheet ─────────────────────────────────────────────────────
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
    // Simulate sharing the post to the group chat
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
      decoration: const BoxDecoration(
        color: HuddlColors.white,
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
                const Icon(Icons.share, color: HuddlColors.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Share with...',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search groups or people...',
                hintStyle: GoogleFonts.poppins(
                    fontSize: 14, color: HuddlColors.textHint),
                prefixIcon: const Icon(Icons.search,
                    size: 20, color: HuddlColors.textHint),
                filled: true,
                fillColor: HuddlColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              style: GoogleFonts.poppins(
                  fontSize: 14, color: HuddlColors.textDark),
            ),
          ),
          const SizedBox(height: 12),
          // Tab bar: Groups | People
          TabBar(
            controller: _tabCtrl,
            labelColor: HuddlColors.primary,
            unselectedLabelColor: HuddlColors.textHint,
            indicatorColor: HuddlColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400),
            tabs: const [Tab(text: 'My Groups'), Tab(text: 'People')],
          ),
          const Divider(height: 1, color: HuddlColors.divider),
          // Tab views
          Flexible(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // Groups tab
                _filteredGroups.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No groups to share with',
                            style: GoogleFonts.poppins(
                                fontSize: 14, color: HuddlColors.textHint),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _filteredGroups.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 72,
                            color: HuddlColors.divider),
                        itemBuilder: (_, i) {
                          final g = _filteredGroups[i];
                          return ListTile(
                            leading: SizedBox(
                              width: 44,
                              height: 44,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _buildShareImage(g.imageUrl),
                              ),
                            ),
                            title: Text(
                              g.name,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${g.memberCount} members',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: HuddlColors.textHint),
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: HuddlColors.primary,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Share',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.white,
                                      ),
                                    ),
                                  ),
                            onTap: _sending ? null : () => _shareToGroup(g),
                          );
                        },
                      ),
                // People tab
                _filteredMembers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No people in ${widget.borough} to share with',
                            style: GoogleFonts.poppins(
                                fontSize: 14, color: HuddlColors.textHint),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _filteredMembers.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 72,
                            color: HuddlColors.divider),
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
                                color: HuddlColors.textDark,
                              ),
                            ),
                            subtitle: Text(
                              widget.borough,
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: HuddlColors.textHint),
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: HuddlColors.primary,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Send',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.white,
                                      ),
                                    ),
                                  ),
                            onTap: _sending ? null : () => _shareToMember(m),
                          );
                        },
                      ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _buildShareImage(String imageUrl) {
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(imageUrl, width: 44, height: 44, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _shareFallback());
    }
    if (imageUrl.startsWith('http')) {
      return Image.network(imageUrl, width: 44, height: 44, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _shareFallback());
    }
    if (imageUrl.startsWith('data:')) {
      try {
        final parts = imageUrl.split(',');
        if (parts.length > 1) {
          final bytes = base64Decode(parts[1]);
          return Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover,
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
      child: const Icon(Icons.people, size: 22, color: HuddlColors.primary),
    );
  }
}

// ── Activity Detail Sheet ─────────────────────────────────────────────────
class _ActivityDetailSheet extends StatelessWidget {
  final FeedItem item;
  final String borough;
  final VoidCallback? onAction;

  const _ActivityDetailSheet({required this.item, required this.borough, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: const BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HuddlBottomSheetHandle(),
          // Header
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
                  child:
                      Icon(_iconForType(item.type), color: _colorForType(item.type), size: 26),
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
                          color: HuddlColors.textDark,
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
          const Divider(height: 1, color: HuddlColors.divider),
          // Details
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow(Icons.info_outline, 'Details', item.subtitle),
                  const SizedBox(height: 16),
                  _detailRow(Icons.access_time, 'When', item.timeAgo),
                  const SizedBox(height: 16),
                  _detailRow(Icons.location_on_outlined, 'Location',
                      borough.isNotEmpty ? borough : 'Your Community'),
                  if (item.meta.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ...item.meta.entries
                        .where((e) =>
                            e.key != 'groupId' && e.value is String)
                        .map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _detailRow(
                                  Icons.label_outline, e.key, e.value.toString()),
                            )),
                  ],
                  const SizedBox(height: 24),
                  // Action button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.primary,
                        foregroundColor: HuddlColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        if (onAction != null) {
                          onAction!();
                        } else {
                          Navigator.pop(context);
                          // Navigate based on type
                          final shell = MainShell.shellKey.currentState;
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
                              // Stay on home
                              break;
                          }
                        }
                      },
                      child: Text(
                        _actionLabel(item.type),
                        style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w600),
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
        Icon(icon, size: 18, color: HuddlColors.textHint),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: HuddlColors.textHint,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: HuddlColors.textDark,
                ),
              ),
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
        return 'View in Preloved';
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
        return 'Preloved';
      case FeedItemType.milestone:
        return 'Milestone';
    }
  }
}

// ── All Community Activity Screen ─────────────────────────────────────────
class _AllCommunityActivityScreen extends StatelessWidget {
  final List<FeedItem> feedItems;
  final String borough;
  final void Function(FeedItem) onItemTap;

  const _AllCommunityActivityScreen({
    required this.feedItems,
    required this.borough,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: HuddlColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Community Activity',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        centerTitle: true,
      ),
      body: feedItems.isEmpty
          ? Center(
              child: Text(
                'No activity yet',
                style: GoogleFonts.poppins(
                    fontSize: 15, color: HuddlColors.textHint),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: feedItems.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => onItemTap(feedItems[index]),
                  child: _FeedCard(item: feedItems[index]),
                );
              },
            ),
    );
  }
}
