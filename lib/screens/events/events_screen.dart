import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';
import '../../services/event_service.dart';
import '../../services/default_group_service.dart';
import '../../services/browser_storage.dart';
import '../../models/group.dart';
import 'create_meetup_screen.dart';
import 'meetup_detail_screen.dart';
import 'event_detail_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DISCOVER SCREEN — main entry with 3 tabs: All · Meet-ups · Events
// ═══════════════════════════════════════════════════════════════════════════════

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MeetupService _meetupService = MeetupService();
  final EventService _eventService = EventService();
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _meetupService.addListener(_refresh);
    _eventService.addListener(_refresh);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _meetupService.removeListener(_refresh);
    _eventService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _navigateToCreateMeetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateMeetupScreen()),
    );
  }

  void _showNotificationsSheet() {
    final goingMeetups = _meetupService.meetups
        .where((m) => m.isGoing)
        .toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: HuddlColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Upcoming Reminders',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                if (goingMeetups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.notifications_off_outlined,
                              size: 48,
                              color: HuddlColors.textHint.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No upcoming reminders',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: HuddlColors.textHint,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'RSVP to meetups to receive reminders',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: HuddlColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...goingMeetups.take(5).map((meetup) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.event,
                              color: HuddlColors.primary, size: 22),
                        ),
                        title: Text(
                          meetup.title,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${meetup.dateDisplay} · ${meetup.timeDisplay}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: HuddlColors.textHint,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right,
                            color: HuddlColors.textHint, size: 20),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  MeetupDetailScreen(meetup: meetup),
                            ),
                          );
                        },
                      )),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Meetups",
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _isSearching ? Icons.close : Icons.search,
                              color: HuddlColors.textDark,
                            ),
                            onPressed: () {
                              setState(() {
                                _isSearching = !_isSearching;
                                if (!_isSearching) {
                                  _searchQuery = '';
                                  _searchController.clear();
                                } else {
                                  _searchFocusNode.requestFocus();
                                }
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.notifications_outlined,
                                color: HuddlColors.textDark),
                            onPressed: () {
                              _showNotificationsSheet();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  // ── Search bar (collapsible) ──────────────────────
                  if (_isSearching) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search meetups & events...',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 14, color: HuddlColors.textHint),
                        prefixIcon: const Icon(Icons.search,
                            color: HuddlColors.textHint, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: HuddlColors.background,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  // ── Tabs: Nearby | I'm Going ──────────────────────
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Nearby'),
                      Tab(text: "I'm Going"),
                    ],
                    labelColor: HuddlColors.primary,
                    unselectedLabelColor: HuddlColors.textHint,
                    labelStyle: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                    indicatorColor: HuddlColors.primary,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: HuddlColors.divider,
                  ),
                ],
              ),
            ),
            // ── Tab content ─────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MeetupsTab(
                    meetupService: _meetupService,
                    onCreateMeetup: _navigateToCreateMeetup,
                  ),
                  _ImGoingTab(
                    meetupService: _meetupService,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// _AllTab removed — no longer used (Meetups screen has only Nearby + I'm Going tabs)

// ═══════════════════════════════════════════════════════════════════════════════
// MEET-UPS TAB — parent-organized casual gatherings
// ═══════════════════════════════════════════════════════════════════════════════

class _MeetupsTab extends StatefulWidget {
  final MeetupService meetupService;
  final VoidCallback onCreateMeetup;

  const _MeetupsTab({required this.meetupService, required this.onCreateMeetup});

  @override
  State<_MeetupsTab> createState() => _MeetupsTabState();
}

class _MeetupsTabState extends State<_MeetupsTab> {
  String _filter = 'All';
  Set<String> _joinedGroupIds = {};

  @override
  void initState() {
    super.initState();
    _loadUserContext();
  }

  Future<void> _loadUserContext() async {
    // Load user groups
    final groupService = DefaultGroupService();
    await groupService.initialize();
    final defaultGroups = await groupService.getUserGroups('current_user');
    List<Group> discovered = [];
    try {
      final discoveredJson =
          await BrowserStorage.getString('user_created_groups_v1');
      if (discoveredJson != null) {
        final List<dynamic> decoded = json.decode(discoveredJson);
        discovered = decoded
            .map((e) => Group.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _joinedGroupIds = {...defaultGroups.map((g) => g.id), ...discovered.map((g) => g.id)};
      });
    }
  }

  /// Filter meetups by visibility rules:
  /// - Public: same borough, visible to all
  /// - Group: same borough, visible only to members of that group
  /// - Private: visible only to invited members (or organiser)
  /// - Past meetups are excluded
  List<Meetup> get _visibleMeetups {
    final now = DateTime.now();
    return widget.meetupService.meetups.where((m) {
      // Exclude past meetups from Nearby
      if (m.dateTime.isBefore(now)) return false;

      switch (m.privacy) {
        case MeetupPrivacy.public:
          // Public: visible to anyone in the same borough (or if no borough set)
          return true;
        case MeetupPrivacy.group:
          // Group: only visible to members of that group
          if (m.groupId == null) return false;
          return _joinedGroupIds.contains(m.groupId) || m.organiserId == 'current_user';
        case MeetupPrivacy.private_:
          // Private: only visible to invited members or organiser
          return m.invitedMemberIds.contains('current_user') || m.organiserId == 'current_user';
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleMeetups;
    final meetups = _filter == 'All'
        ? visible
        : visible.where((m) => m.category == _filter).toList();

    return Column(
      children: [
        // ── Filter chips ─────────────────────────────────────────
        Container(
          color: HuddlColors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                'All', 'Coffee', 'Playdate', 'Sport', 'Walk', 'Social', 'Food', 'Other',
              ].map((f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: f,
                  isSelected: _filter == f,
                  onTap: () => setState(() => _filter = f),
                ),
              )).toList(),
            ),
          ),
        ),
        // ── List ─────────────────────────────────────────────────
        Expanded(
          child: meetups.isEmpty
              ? _EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No meet-ups yet',
                  subtitle:
                      'Organise a casual get-together with\nother parents in your area.',
                  actionLabel: 'Create Meet-up',
                  onAction: widget.onCreateMeetup,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: meetups.length,
                  itemBuilder: (_, i) => _MeetupCard(meetup: meetups[i]),
                ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENTS TAB — 3rd party / company advertised events (mostly paid)
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// I'M GOING TAB — shows meetups the user has confirmed attendance for
// ═══════════════════════════════════════════════════════════════════════════════

class _ImGoingTab extends StatelessWidget {
  final MeetupService meetupService;

  const _ImGoingTab({required this.meetupService});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final goingMeetups = meetupService.meetups
        .where((m) => m.isGoing)
        .toList();

    final upcoming = goingMeetups.where((m) => m.dateTime.isAfter(now)).toList();
    final past = goingMeetups.where((m) => !m.dateTime.isAfter(now)).toList();

    if (goingMeetups.isEmpty) {
      return _EmptyState(
        icon: Icons.event_available_outlined,
        title: "You're not going to any meet-ups yet",
        subtitle: "Tap 'Count Me In' on a meet-up to add it here!",
        actionLabel: 'Browse Meet-ups',
        onAction: () {},
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (upcoming.isNotEmpty) ...[
          _SectionLabel(
            icon: Icons.upcoming_outlined,
            label: 'Upcoming',
            color: HuddlColors.primaryDark,
          ),
          const SizedBox(height: 8),
          ...upcoming.map((m) => _ImGoingCard(
                meetup: m,
                onCancel: () => meetupService.toggleGoing(m.id),
              )),
        ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionLabel(
            icon: Icons.history,
            label: 'Past',
            color: HuddlColors.textHint,
          ),
          const SizedBox(height: 8),
          ...past.map((m) => _ImGoingCard(
                meetup: m,
                isPast: true,
                onCancel: () => meetupService.toggleGoing(m.id),
              )),
        ],
      ],
    );
  }
}

class _ImGoingCard extends StatelessWidget {
  final Meetup meetup;
  final bool isPast;
  final VoidCallback onCancel;

  const _ImGoingCard({
    required this.meetup,
    this.isPast = false,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isPast ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: HuddlColors.gray900.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MeetupDetailScreen(meetup: meetup),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: HuddlColors.primary.withValues(alpha: 0.1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: meetup.imageUrl.isNotEmpty &&
                          meetup.imageUrl.startsWith('http')
                      ? Image.network(
                          meetup.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(Icons.groups,
                                color: HuddlColors.primary, size: 28),
                          ),
                        )
                      : Center(
                          child: Icon(Icons.groups,
                              color: HuddlColors.primary, size: 28),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
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
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 12, color: HuddlColors.textHint),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${meetup.dateDisplay} · ${meetup.timeDisplay}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: HuddlColors.textHint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 12, color: HuddlColors.textHint),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              meetup.location,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: HuddlColors.textHint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    if (isPast)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: HuddlColors.textHint.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Past',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textHint,
                          ),
                        ),
                      )
                    else
                      Icon(Icons.check_circle,
                          color: HuddlColors.blue, size: 24),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onCancel,
                      child: Text(
                        isPast ? 'Clear' : 'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isPast ? HuddlColors.textHint : HuddlColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventsTab extends StatefulWidget {
  final EventService eventService;
  final VoidCallback onCreateEvent;

  const _EventsTab({required this.eventService, required this.onCreateEvent});

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final allEvents = widget.eventService.eventMaps;
    final events = _filter == 'All'
        ? allEvents
        : allEvents.where((e) {
            if (_filter == 'Free') return e['isFree'] == true;
            if (_filter == 'Paid') return e['isFree'] != true;
            if (_filter == 'Online') return e['isOnline'] == true;
            if (_filter == 'In-Person') return e['isOnline'] != true;
            return true;
          }).toList();

    return Column(
      children: [
        // ── Filter chips ─────────────────────────────────────────
        Container(
          color: HuddlColors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                'All', 'Free', 'Paid', 'Online', 'In-Person',
              ].map((f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: f,
                  isSelected: _filter == f,
                  onTap: () => setState(() => _filter = f),
                ),
              )).toList(),
            ),
          ),
        ),
        // ── List ─────────────────────────────────────────────────
        Expanded(
          child: events.isEmpty
              ? _EmptyState(
                  icon: Icons.event_outlined,
                  title: 'No events yet',
                  subtitle:
                      'Create an event for parents\nin your area to attend.',
                  actionLabel: 'Create Event',
                  onAction: widget.onCreateEvent,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length,
                  itemBuilder: (_, i) =>
                      _EventListCard(event: events[i]),
                ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED CARD WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

/// Section label with icon — used on the All tab to divide meet-ups from events
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: HuddlColors.textDark,
          ),
        ),
      ],
    );
  }
}

/// ── MEET-UP CARD ────────────────────────────────────────────────────────────
class _MeetupCard extends StatelessWidget {
  final Meetup meetup;

  const _MeetupCard({required this.meetup});

  @override
  Widget build(BuildContext context) {
    final catStyle = _meetupCategoryStyle(meetup.category);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetupDetailScreen(meetup: meetup),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: HuddlColors.gray900.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover image ──────────────────────────────────────────
            Stack(
              children: [
                SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: _buildCoverImage(
                    imageUrl: meetup.imageUrl,
                    fallbackIcon: catStyle.icon,
                    fallbackColor: catStyle.color,
                  ),
                ),
                // Gradient overlay at bottom for readability
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          HuddlColors.white.withValues(alpha: 0.0),
                          HuddlColors.gray900.withValues(alpha: 0.4),
                        ],
                      ),
                    ),
                  ),
                ),
                // Category badge
                Positioned(
                  top: 10, left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: catStyle.color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(catStyle.icon, size: 13, color: HuddlColors.white),
                        const SizedBox(width: 4),
                        Text(
                          meetup.category,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Price badge
                Positioned(
                  top: 10, right: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (meetup.privacy != MeetupPrivacy.public)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: HuddlColors.gray900.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  meetup.privacy == MeetupPrivacy.group
                                      ? Icons.group
                                      : Icons.lock,
                                  size: 12,
                                  color: HuddlColors.white,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  meetup.privacy == MeetupPrivacy.group
                                      ? 'Group'
                                      : 'Private',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: HuddlColors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: meetup.isFree ? HuddlColors.blue : HuddlColors.accentAmber,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          meetup.isFree
                              ? 'Free'
                              : '\u00A3${meetup.price?.toStringAsFixed(0) ?? ''}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Attendee count overlay
                Positioned(
                  bottom: 8, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HuddlColors.gray900.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people, size: 13, color: HuddlColors.white),
                        const SizedBox(width: 4),
                        Text(
                          '${meetup.attendeeCount}${meetup.maxAttendees != null ? '/${meetup.maxAttendees}' : ''} going',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // ── Card body ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meetup.title,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Date + time
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 13, color: catStyle.color),
                      const SizedBox(width: 5),
                      Text(
                        meetup.dateDisplay,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.access_time,
                          size: 13, color: catStyle.color),
                      const SizedBox(width: 4),
                      Text(
                        meetup.timeDisplay,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Location
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 13, color: catStyle.color),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          meetup.location,
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
                  const SizedBox(height: 10),
                  // Organiser row
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: catStyle.color.withValues(alpha: 0.15),
                        child: Text(
                          meetup.organiserName.isNotEmpty
                              ? meetup.organiserName[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: catStyle.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Organised by ${meetup.organiserName}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.textSecondary,
                        ),
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
}

/// ── EVENT CARD (3rd party / company events) ─────────────────────────────────
class _EventListCard extends StatelessWidget {
  final Map<String, dynamic> event;

  const _EventListCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final Color eventColor = event['color'] as Color;
    final bool isFree = event['isFree'] == true;
    final bool isOnline = event['isOnline'] == true;
    final String organiser = event['organiser'] as String? ?? '';
    final String imageUrl = event['imageUrl'] as String? ?? '';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(event: event),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: HuddlColors.gray900.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover image ──────────────────────────────────────────
            Stack(
              children: [
                SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: _buildCoverImage(
                    imageUrl: imageUrl,
                    fallbackIcon: event['icon'] as IconData,
                    fallbackColor: eventColor,
                  ),
                ),
                // Gradient overlay
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          HuddlColors.white.withValues(alpha: 0.0),
                          HuddlColors.gray900.withValues(alpha: 0.4),
                        ],
                      ),
                    ),
                  ),
                ),
                // Price badge
                Positioned(
                  top: 10, left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isFree ? HuddlColors.accentAmber : eventColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isFree ? 'Free' : event['price'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.white,
                      ),
                    ),
                  ),
                ),
                // Online / In-person badge
                if (isOnline)
                  Positioned(
                    top: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: HuddlColors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam, size: 13, color: HuddlColors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Online',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Bookmark + attendees
                Positioned(
                  bottom: 8, right: 10,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: HuddlColors.gray900.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people, size: 13, color: HuddlColors.white),
                            const SizedBox(width: 4),
                            Text(
                              '${event['attendees']} going',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 30,
                        height: 28,
                        decoration: BoxDecoration(
                          color: HuddlColors.gray900.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bookmark_border, size: 16, color: HuddlColors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // ── Card body ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event['title'] as String,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Date + time
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 13, color: eventColor),
                      const SizedBox(width: 5),
                      Text(
                        event['date'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.access_time,
                          size: 13, color: eventColor),
                      const SizedBox(width: 4),
                      Text(
                        event['time'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Location
                  Row(
                    children: [
                      Icon(isOnline ? Icons.videocam_outlined : Icons.location_on_outlined,
                          size: 13, color: eventColor),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          event['location'] as String,
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
                  if (organiser.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: eventColor.withValues(alpha: 0.15),
                          child: Icon(Icons.business, size: 12, color: eventColor),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'By $organiser',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.textSecondary,
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? HuddlColors.primary : HuddlColors.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? HuddlColors.white : HuddlColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: HuddlColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 40, color: HuddlColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: HuddlColors.textHint,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 12),
                  elevation: 0,
                ),
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEET-UP CATEGORY STYLING
// ═══════════════════════════════════════════════════════════════════════════════

class _CatStyle {
  final Color color;
  final IconData icon;
  const _CatStyle(this.color, this.icon);
}

_CatStyle _meetupCategoryStyle(String category) {
  switch (category) {
    case 'Coffee':
      return const _CatStyle(HuddlColors.primaryDark, Icons.coffee);
    case 'Playdate':
      return const _CatStyle(HuddlColors.primary, Icons.child_care);
    case 'Sport':
      return const _CatStyle(HuddlColors.blue, Icons.sports_golf);
    case 'Walk':
      return const _CatStyle(HuddlColors.yellowDark, Icons.directions_walk);
    case 'Social':
      return const _CatStyle(HuddlColors.accentAmber, Icons.celebration);
    default:
      return const _CatStyle(HuddlColors.blue, Icons.groups);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED — universal cover-image builder (data-URI, http, asset, fallback)
// ═══════════════════════════════════════════════════════════════════════════════

Widget _buildCoverImage({
  required String imageUrl,
  required IconData fallbackIcon,
  required Color fallbackColor,
}) {
  Widget fallback() => Container(
        color: fallbackColor.withValues(alpha: 0.12),
        child: Center(
          child: Icon(fallbackIcon, size: 40, color: fallbackColor),
        ),
      );

  Widget placeholder() => Container(
        color: fallbackColor.withValues(alpha: 0.12),
        child: Center(
          child: Icon(fallbackIcon, size: 40,
              color: fallbackColor.withValues(alpha: 0.4)),
        ),
      );

  if (imageUrl.isEmpty) return fallback();

  // ── base64 data-URI (user-uploaded photos) ────────────────────────────
  if (imageUrl.startsWith('data:')) {
    try {
      final dataUri = Uri.parse(imageUrl);
      final bytes = dataUri.data?.contentAsBytes();
      if (bytes != null) {
        return Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => fallback(),
        );
      }
    } catch (_) {}
    return fallback();
  }

  // ── http(s) URL (Pexels images etc.) ──────────────────────────────────
  if (imageUrl.startsWith('http')) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => placeholder(),
      errorWidget: (_, __, ___) => fallback(),
    );
  }

  // ── Local asset path ──────────────────────────────────────────────────
  if (imageUrl.startsWith('assets/')) {
    return Image.asset(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => fallback(),
    );
  }

  return fallback();
}

// Events data is now managed by EventService (lib/services/event_service.dart)
