import 'dart:convert';
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
import '../main_shell.dart';

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

  bool _isLoading = true;

  String _name = '';
  String _borough = '';
  String? _photoUrl;
  List<Group> _userGroups = [];
  List<Announcement> _announcements = [];
  List<FeedItem> _feedItems = [];
  List<UpcomingEvent> _upcomingEvents = [];

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

      String borough = '';
      final pc = _onboarding.postcode;
      if (pc != null) {
        borough = _postcodeService.getBoroughFromPostcode(pc) ?? '';
      }

      final groups = await _groupService.getUserGroups('current_user');

      setState(() {
        _name = _onboarding.name ?? 'there';
        _borough = borough;
        _photoUrl = _onboarding.profilePhotoObjectUrl;
        _userGroups = groups;
        _announcements = _announcementService.boroughAnnouncements;
        _feedItems = _feedService.feedItems;
        _upcomingEvents = _feedService.upcomingEvents;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
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
    Clipboard.setData(ClipboardData(
      text:
          '${announcement.authorName}: "${announcement.content}" - via Huddl Connect',
    ));
    setState(() {
      _announcements = _announcementService.boroughAnnouncements;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: HuddlColors.white, size: 18),
            const SizedBox(width: 8),
            Text('Post copied to clipboard!',
                style: GoogleFonts.poppins(fontSize: 13)),
          ],
        ),
        backgroundColor: HuddlColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
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
      ),
    );
  }

  // ── Profile avatar tap ────────────────────────────────────────────────────
  void _onAvatarTap() {
    _switchToTab(4); // Navigate to Profile tab
  }

  // ── Feed item tap ─────────────────────────────────────────────────────────
  void _onFeedItemTap(FeedItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActivityDetailSheet(item: item, borough: _borough),
    );
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
    _switchToTab(2); // Go to Mingle tab
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
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: HuddlColors.peachLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            'H',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'huddl',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.primary,
                        ),
                      ),
                      const Spacer(),
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
                      colors: [Color(0xFFFFF3ED), Color(0xFFFFF8F0)],
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

              // ── Quick actions ────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _QuickAction(
                        icon: Icons.people,
                        label: 'My Groups',
                        color: HuddlColors.primary,
                        bgColor: HuddlColors.peachLight,
                        onTap: () => _switchToTab(1),
                      ),
                      const SizedBox(width: 12),
                      _QuickAction(
                        icon: Icons.event,
                        label: 'Events',
                        color: HuddlColors.blue,
                        bgColor: HuddlColors.blueBackground,
                        onTap: () => _switchToTab(2),
                      ),
                      const SizedBox(width: 12),
                      _QuickAction(
                        icon: Icons.storefront,
                        label: 'Rehome',
                        color: HuddlColors.teal,
                        bgColor: const Color(0xFFE6F5F3),
                        onTap: () => _switchToTab(3),
                      ),
                    ],
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

              // ── Upcoming Events ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: HuddlSectionHeader(
                    title: 'Upcoming events',
                    actionText: 'See all',
                    onAction: _openAllEvents,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _upcomingEvents.length,
                    itemBuilder: (context, index) {
                      return Container(
                        width: 240,
                        margin: EdgeInsets.only(
                            right:
                                index < _upcomingEvents.length - 1 ? 12 : 0),
                        child: GestureDetector(
                          onTap: () => _switchToTab(2),
                          child:
                              _EventCard(event: _upcomingEvents[index]),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // ── Your Groups (real) ───────────────────────────────────
              if (_userGroups.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: HuddlSectionHeader(
                      title: 'Your groups',
                      actionText: 'See all',
                      onAction: _openAllGroups,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 86,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _userGroups.length,
                      itemBuilder: (context, index) {
                        final g = _userGroups[index];
                        return Container(
                          width: 70,
                          margin: EdgeInsets.only(
                              right:
                                  index < _userGroups.length - 1 ? 14 : 0),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(context).pushNamed(
                                '/group_chat',
                                arguments: {
                                  'groupId': g.id,
                                  'groupName': g.name,
                                  'groupImageUrl': g.imageUrl,
                                },
                              );
                            },
                            child: Column(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: HuddlColors.primary
                                            .withValues(alpha: 0.25),
                                        width: 1.5),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _buildGroupImage(g.imageUrl),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  g.name,
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: HuddlColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
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

  // ── Group image helper (supports data-uri, http, assets) ──────────────
  Widget _buildGroupImage(String imageUrl) {
    if (imageUrl.startsWith('data:')) {
      try {
        final dataUri = imageUrl.split(',');
        if (dataUri.length > 1) {
          final bytes = base64Decode(dataUri[1]);
          return Image.memory(bytes, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _groupFallback());
        }
      } catch (_) {}
      return _groupFallback();
    }
    if (imageUrl.startsWith('http')) {
      return Image.network(imageUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _groupFallback());
    }
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(imageUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _groupFallback());
    }
    return _groupFallback();
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

  Widget _groupFallback() {
    return Container(
      color: HuddlColors.peachLight,
      child: const Center(
          child: Icon(Icons.people, size: 22, color: HuddlColors.primary)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUBWIDGETS
// ═══════════════════════════════════════════════════════════════════════════

// ── Quick action tile ─────────────────────────────────────────────────────
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Event card ────────────────────────────────────────────────────────────
class _EventCard extends StatelessWidget {
  final UpcomingEvent event;

  const _EventCard({required this.event});

  Color get _categoryColor {
    switch (event.category) {
      case 'Baby':
        return HuddlColors.primary;
      case 'Social':
        return HuddlColors.blue;
      case 'Toddler':
        return HuddlColors.teal;
      case 'Outdoors':
        return HuddlColors.purple;
      default:
        return HuddlColors.primary;
    }
  }

  IconData get _categoryIcon {
    switch (event.category) {
      case 'Baby':
        return Icons.child_care;
      case 'Social':
        return Icons.coffee;
      case 'Toddler':
        return Icons.music_note;
      case 'Outdoors':
        return Icons.directions_walk;
      default:
        return Icons.event;
    }
  }

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
          Container(
            height: 100,
            width: double.infinity,
            color: _categoryColor,
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    _categoryIcon,
                    size: 40,
                    color: HuddlColors.white.withValues(alpha: 0.7),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: HuddlColors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      event.date,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _categoryColor,
                      ),
                    ),
                  ),
                ),
                if (!event.isFree)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: HuddlColors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        event.price ?? '',
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
                  event.title,
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
                    Text(
                      event.time,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textHint,
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
                      '${event.attendees} going',
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

// ── Community feed card ───────────────────────────────────────────────────
class _FeedCard extends StatelessWidget {
  final FeedItem item;

  const _FeedCard({required this.item});

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

  Color get _iconColor {
    switch (item.type) {
      case FeedItemType.newParent:
        return HuddlColors.teal;
      case FeedItemType.newGroup:
        return HuddlColors.primary;
      case FeedItemType.newEvent:
        return HuddlColors.blue;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.purple;
      case FeedItemType.milestone:
        return const Color(0xFFE8A838);
    }
  }

  Color get _iconBg {
    switch (item.type) {
      case FeedItemType.newParent:
        return const Color(0xFFE6F5F3);
      case FeedItemType.newGroup:
        return HuddlColors.peachLight;
      case FeedItemType.newEvent:
        return HuddlColors.blueBackground;
      case FeedItemType.newMarketplaceItem:
        return const Color(0xFFF5F0FF);
      case FeedItemType.milestone:
        return HuddlColors.yellowLight;
    }
  }

  String get _typeLabel {
    switch (item.type) {
      case FeedItemType.newParent:
        return 'New Parent';
      case FeedItemType.newGroup:
        return 'New Group';
      case FeedItemType.newEvent:
        return 'New Event';
      case FeedItemType.newMarketplaceItem:
        return 'Rehome';
      case FeedItemType.milestone:
        return 'Milestone';
    }
  }

  @override
  Widget build(BuildContext context) {
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
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon, color: _iconColor, size: 24),
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
class _NotificationsSheet extends StatelessWidget {
  final List<FeedItem> feedItems;
  final List<Announcement> announcements;
  final String borough;

  const _NotificationsSheet({
    required this.feedItems,
    required this.announcements,
    required this.borough,
  });

  @override
  Widget build(BuildContext context) {
    // Build notification items from feed and announcement activity
    final List<_NotifItem> notifs = [];

    // Recent community activity as notifications
    for (final f in feedItems.take(5)) {
      notifs.add(_NotifItem(
        icon: _iconForType(f.type),
        color: _colorForType(f.type),
        bgColor: _bgForType(f.type),
        title: f.title,
        subtitle: f.subtitle,
        timeAgo: f.timeAgo,
      ));
    }

    // Announcement interactions as notifications
    for (final a in announcements.where((a) => a.likes > 0).take(3)) {
      notifs.add(_NotifItem(
        icon: Icons.favorite,
        color: HuddlColors.primary,
        bgColor: HuddlColors.peachLight,
        title: '${a.authorName}\'s post',
        subtitle: '${a.likes} people liked this post',
        timeAgo: a.timeAgo,
      ));
    }

    // Sort by time
    notifs.sort((a, b) => a.timeAgo.compareTo(b.timeAgo));

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
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Mark all read',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: HuddlColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: HuddlColors.divider),
          Flexible(
            child: notifs.isEmpty
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
                    itemCount: notifs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72, color: HuddlColors.divider),
                    itemBuilder: (_, index) {
                      final n = notifs[index];
                      return ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: n.bgColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(n.icon, color: n.color, size: 22),
                        ),
                        title: Text(
                          n.title,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          n.subtitle,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: HuddlColors.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          n.timeAgo,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: HuddlColors.textHint,
                          ),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      );
                    },
                  ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
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
        return HuddlColors.teal;
      case FeedItemType.newGroup:
        return HuddlColors.primary;
      case FeedItemType.newEvent:
        return HuddlColors.blue;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.purple;
      case FeedItemType.milestone:
        return const Color(0xFFE8A838);
    }
  }

  Color _bgForType(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return const Color(0xFFE6F5F3);
      case FeedItemType.newGroup:
        return HuddlColors.peachLight;
      case FeedItemType.newEvent:
        return HuddlColors.blueBackground;
      case FeedItemType.newMarketplaceItem:
        return const Color(0xFFF5F0FF);
      case FeedItemType.milestone:
        return HuddlColors.yellowLight;
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

  const _NotifItem({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.timeAgo,
  });
}

// ── Activity Detail Sheet ─────────────────────────────────────────────────
class _ActivityDetailSheet extends StatelessWidget {
  final FeedItem item;
  final String borough;

  const _ActivityDetailSheet({required this.item, required this.borough});

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
        return 'View in Rehome';
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
        return HuddlColors.blue;
      case FeedItemType.newMarketplaceItem:
        return HuddlColors.purple;
      case FeedItemType.milestone:
        return const Color(0xFFE8A838);
    }
  }

  Color _bgForType(FeedItemType t) {
    switch (t) {
      case FeedItemType.newParent:
        return const Color(0xFFE6F5F3);
      case FeedItemType.newGroup:
        return HuddlColors.peachLight;
      case FeedItemType.newEvent:
        return HuddlColors.blueBackground;
      case FeedItemType.newMarketplaceItem:
        return const Color(0xFFF5F0FF);
      case FeedItemType.milestone:
        return HuddlColors.yellowLight;
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
        return 'Rehome';
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
