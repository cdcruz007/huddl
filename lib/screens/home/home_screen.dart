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
                          onPressed: () {},
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildSmallAvatar(),
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
                        onTap: () {},
                      ),
                      const SizedBox(width: 12),
                      _QuickAction(
                        icon: Icons.event,
                        label: 'Events',
                        color: HuddlColors.blue,
                        bgColor: HuddlColors.blueBackground,
                        onTap: () {},
                      ),
                      const SizedBox(width: 12),
                      _QuickAction(
                        icon: Icons.storefront,
                        label: 'Marketplace',
                        color: HuddlColors.teal,
                        bgColor: const Color(0xFFE6F5F3),
                        onTap: () {},
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
                      return _AnnouncementCard(
                        announcement: _announcements[index],
                        onLike: () =>
                            _toggleLike(_announcements[index].id),
                      );
                    },
                    childCount:
                        _announcements.length.clamp(0, 5), // show max 5
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
                    onAction: () {},
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
                        child: _EventCard(event: _upcomingEvents[index]),
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
                      onAction: () {},
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
                                  child: g.imageUrl.startsWith('assets/')
                                      ? Image.asset(g.imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _groupFallback())
                                      : _groupFallback(),
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
                    onAction: () {},
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= _feedItems.length) return null;
                    return _FeedCard(item: _feedItems[index]);
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

  Widget _buildSmallAvatar() {
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
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

  const _AnnouncementCard({
    required this.announcement,
    required this.onLike,
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
              // Author avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HuddlColors.peachLight,
                ),
                child: Center(
                  child: Text(
                    announcement.authorName.isNotEmpty
                        ? announcement.authorName[0].toUpperCase()
                        : 'U',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.primary,
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
                          const Icon(Icons.push_pin,
                              size: 14, color: HuddlColors.primary),
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
              const Icon(Icons.more_horiz, color: HuddlColors.textHint),
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
              GestureDetector(
                onTap: onLike,
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
                        color: announcement.isLiked
                            ? HuddlColors.primary
                            : HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Row(
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
              const SizedBox(width: 20),
              Row(
                children: [
                  const Icon(Icons.share_outlined,
                      size: 18, color: HuddlColors.textHint),
                  const SizedBox(width: 4),
                  Text(
                    'Share',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.textHint,
                    ),
                  ),
                ],
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
        return 'Marketplace';
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
          // Icon or group image
          if (item.imageAsset != null && item.imageAsset!.startsWith('assets/'))
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                item.imageAsset!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: _iconBg,
                  child: Icon(_icon, color: _iconColor, size: 24),
                ),
              ),
            )
          else
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
        ],
      ),
    );
  }
}
