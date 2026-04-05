import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';
import '../../services/event_service.dart';
import '../../services/default_group_service.dart';
import '../../services/browser_storage.dart';
import '../../models/group.dart';
import 'create_meetup_screen.dart';
import '../../services/postcode_service.dart';
import 'meetup_detail_screen.dart';
import 'event_detail_screen.dart';
import '../ai/ai_matchmaker_sheet.dart';
import '../../services/ai_event_recommender_service.dart';
import '../../services/ai_event_discovery_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MINGLE SCREEN — main entry with 3 tabs: Meetups · Events · I'm Going
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
    _tabController = TabController(length: 3, vsync: this);
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
    final goingEvents = _eventService.goingEvents;
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
                if (goingMeetups.isEmpty && goingEvents.isEmpty)
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
                            'RSVP to meetups or register for events',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: HuddlColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  // Meetup reminders
                  ...goingMeetups.take(5).map((meetup) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.groups,
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
                  // Event reminders
                  ...goingEvents.take(5).map((event) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: HuddlColors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.event,
                              color: HuddlColors.blue, size: 22),
                        ),
                        title: Text(
                          event.title,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${event.dateDisplay} · ${event.timeDisplay}',
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
                                  EventDetailScreen(event: event.toMap()),
                            ),
                          );
                        },
                      )),
                ],
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
                        "Mingle",
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
                  // ── Tabs: Meetups | Events | I'm Going ──────────────
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Meetups'),
                      Tab(text: 'Events'),
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
                    searchQuery: _searchQuery,
                  ),
                  _EventsTab(
                    eventService: _eventService,
                    searchQuery: _searchQuery,
                  ),
                  _ImGoingTab(
                    meetupService: _meetupService,
                    eventService: _eventService,
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

// Mingle screen has three tabs: Nearby | Events | I'm Going

// ═══════════════════════════════════════════════════════════════════════════════
// MEET-UPS TAB — parent-organized casual gatherings
// ═══════════════════════════════════════════════════════════════════════════════

class _MeetupsTab extends StatefulWidget {
  final MeetupService meetupService;
  final VoidCallback onCreateMeetup;
  final String searchQuery;

  const _MeetupsTab({required this.meetupService, required this.onCreateMeetup, this.searchQuery = ''});

  @override
  State<_MeetupsTab> createState() => _MeetupsTabState();
}

class _MeetupsTabState extends State<_MeetupsTab> {
  String _filter = 'All';
  Set<String> _joinedGroupIds = {};

  // Filter categories matching Create Meetup screen categories
  // label → list of meetup short-code categories it maps to
  static const _filterCategories = [
    {'label': 'All', 'icon': null, 'codes': null},
    {'label': 'Hanging out', 'icon': Icons.people_outline, 'codes': ['Social']},
    {'label': 'Pregnancy', 'icon': Icons.pregnant_woman, 'codes': ['Social']},
    {'label': 'Playdate', 'icon': Icons.child_care, 'codes': ['Playdate']},
    {'label': 'Sports & exercise', 'icon': Icons.fitness_center, 'codes': ['Sport']},
    {'label': 'Coffee & tea', 'icon': Icons.coffee, 'codes': ['Coffee']},
    {'label': 'Parks & Walks', 'icon': Icons.park, 'codes': ['Walk']},
    {'label': 'Food & nutrition', 'icon': Icons.restaurant, 'codes': ['Food']},
    {'label': 'Performance & shows', 'icon': Icons.theater_comedy, 'codes': ['Social']},
    {'label': 'Other', 'icon': Icons.more_horiz, 'codes': ['Other']},
  ];

  List<String>? get _activeFilterCodes {
    if (_filter == 'All') return null;
    final cat = _filterCategories.firstWhere(
      (c) => c['label'] == _filter,
      orElse: () => {'label': 'All', 'icon': null, 'codes': null},
    );
    return (cat['codes'] as List<String>?);
  }

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

  /// All future meetups — ALL privacy levels are now listed on Nearby tab.
  /// Access control is enforced at tap-time, not at listing-time.
  List<Meetup> get _visibleMeetups {
    final now = DateTime.now();
    final query = widget.searchQuery.toLowerCase();
    return widget.meetupService.meetups.where((m) {
      // Exclude past meetups from Nearby
      if (m.dateTime.isBefore(now)) return false;
      // Apply search filter
      if (query.isNotEmpty) {
        return m.title.toLowerCase().contains(query) ||
            m.location.toLowerCase().contains(query) ||
            m.category.toLowerCase().contains(query) ||
            m.organiserName.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

  /// Check if current user can open/join this meetup.
  /// Public: anyone. Group: members of that group + organiser. Private: invited + organiser.
  bool _canAccessMeetup(Meetup m) {
    switch (m.privacy) {
      case MeetupPrivacy.public:
        return true;
      case MeetupPrivacy.group:
        if (m.organiserId == 'current_user') return true;
        if (m.groupId == null) return false;
        return _joinedGroupIds.contains(m.groupId);
      case MeetupPrivacy.private_:
        return m.invitedMemberIds.contains('current_user') || m.organiserId == 'current_user';
    }
  }

  /// Show restricted-access dialog for private/group meetups
  void _showAccessDeniedDialog(BuildContext context, Meetup meetup) {
    final isGroup = meetup.privacy == MeetupPrivacy.group;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isGroup ? Icons.group : Icons.lock,
              color: HuddlColors.primary,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isGroup ? 'Group Members Only' : 'Private Meetup',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          isGroup
              ? 'This meetup is only open to members of ${meetup.groupName ?? 'a specific group'}. Join the group first to access this meetup.'
              : 'This meetup is private and only open to invited members. Ask the organiser for an invitation.',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: HuddlColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: HuddlColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleMeetups;
    final codes = _activeFilterCodes;
    final meetups = codes == null
        ? visible
        : visible.where((m) => codes.contains(m.category)).toList();

    return Column(
      children: [
        // ── Filter chips (matching Create Meetup categories) ─────
        Container(
          color: HuddlColors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _filterCategories.map((cat) {
                final label = cat['label'] as String;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: label,
                    isSelected: _filter == label,
                    onTap: () => setState(() => _filter = label),
                  ),
                );
              }).toList(),
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
                  itemCount: meetups.length + 1, // +1 for AI Matchmaker card
                  itemBuilder: (_, i) {
                    if (i == 0) return _buildAiMatchmakerCard(context);
                    return _MeetupCard(
                      meetup: meetups[i - 1],
                      canAccess: _canAccessMeetup(meetups[i - 1]),
                      onAccessDenied: () => _showAccessDeniedDialog(context, meetups[i - 1]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAiMatchmakerCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF0E6), Color(0xFFFFE8D6)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const AiMatchmakerSheet(),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: HuddlColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Matchmaker',
                        style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Find compatible parents & suggested meetups personalised for you',
                        style: GoogleFonts.poppins(
                          fontSize: 12, color: HuddlColors.textSecondary, height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: HuddlColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'NEW',
                    style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: HuddlColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENTS TAB — 3rd party / company advertised events (mostly paid)
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// I'M GOING TAB — shows meetups the user has confirmed attendance for
// ═══════════════════════════════════════════════════════════════════════════════

/// A unified item that wraps either a Meetup or an Event for the I'm Going list.
class _GoingItem {
  final String id;
  final String title;
  final String dateDisplay;
  final String timeDisplay;
  final DateTime dateTime;
  final String location;
  final String imageUrl;
  final bool isMeetup; // true = meetup, false = event
  final Meetup? meetup;
  final Event? event;

  _GoingItem({
    required this.id,
    required this.title,
    required this.dateDisplay,
    required this.timeDisplay,
    required this.dateTime,
    required this.location,
    required this.imageUrl,
    required this.isMeetup,
    this.meetup,
    this.event,
  });

  factory _GoingItem.fromMeetup(Meetup m) => _GoingItem(
        id: m.id,
        title: m.title,
        dateDisplay: m.dateDisplay,
        timeDisplay: m.timeDisplay,
        dateTime: m.dateTime,
        location: m.location,
        imageUrl: m.imageUrl,
        isMeetup: true,
        meetup: m,
      );

  factory _GoingItem.fromEvent(Event e) => _GoingItem(
        id: e.id,
        title: e.title,
        dateDisplay: e.dateDisplay,
        timeDisplay: e.timeDisplay,
        dateTime: e.dateTime,
        location: e.location,
        imageUrl: e.imageUrl,
        isMeetup: false,
        event: e,
      );
}

class _ImGoingTab extends StatelessWidget {
  final MeetupService meetupService;
  final EventService eventService;

  const _ImGoingTab({
    required this.meetupService,
    required this.eventService,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Merge meetups & events the user is going to
    final List<_GoingItem> allGoing = [
      ...meetupService.meetups
          .where((m) => m.isGoing)
          .map((m) => _GoingItem.fromMeetup(m)),
      ...eventService.goingEvents
          .map((e) => _GoingItem.fromEvent(e)),
    ];

    // Sort by date ascending
    allGoing.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final upcoming = allGoing.where((i) => i.dateTime.isAfter(now)).toList();
    final past = allGoing.where((i) => !i.dateTime.isAfter(now)).toList();

    if (allGoing.isEmpty) {
      return _EmptyState(
        icon: Icons.event_available_outlined,
        title: "You're not going to anything yet",
        subtitle:
            "Tap 'Count Me In' on a meetup or 'Register' on an event to add it here!",
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
          ...upcoming.map((item) => _ImGoingCard(
                item: item,
                onCancel: () => item.isMeetup
                    ? meetupService.toggleGoing(item.id)
                    : eventService.toggleGoing(item.id),
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
          ...past.map((item) => _ImGoingCard(
                item: item,
                isPast: true,
                onCancel: () => item.isMeetup
                    ? meetupService.toggleGoing(item.id)
                    : eventService.toggleGoing(item.id),
              )),
        ],
      ],
    );
  }
}

class _ImGoingCard extends StatelessWidget {
  final _GoingItem item;
  final bool isPast;
  final VoidCallback onCancel;

  const _ImGoingCard({
    required this.item,
    this.isPast = false,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor =
        item.isMeetup ? HuddlColors.primary : HuddlColors.blue;
    final fallbackIcon =
        item.isMeetup ? Icons.groups : Icons.event;

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
            if (item.isMeetup && item.meetup != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MeetupDetailScreen(meetup: item.meetup!),
                ),
              );
            } else if (item.event != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      EventDetailScreen(event: item.event!.toMap()),
                ),
              );
            }
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
                    color: accentColor.withValues(alpha: 0.1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildCoverImage(
                    imageUrl: item.imageUrl,
                    fallbackIcon: fallbackIcon,
                    fallbackColor: accentColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type badge + title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.isMeetup ? 'Meetup' : 'Event',
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.title,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.textDark,
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
                          Icon(Icons.calendar_today_outlined,
                              size: 12, color: HuddlColors.textHint),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${item.dateDisplay} · ${item.timeDisplay}',
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
                              item.location,
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
                          color: accentColor, size: 24),
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
  final String searchQuery;

  const _EventsTab({required this.eventService, this.searchQuery = ''});

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  String _filter = 'All';
  String _selectedBorough = 'All Boroughs';
  final AiEventRecommenderService _recommender = AiEventRecommenderService();
  final AiEventDiscoveryService _discovery = AiEventDiscoveryService();
  final PostcodeService _postcodeService = PostcodeService();
  bool _recommenderReady = false;
  bool _isDiscovering = false;
  int _discoveredCount = 0;
  List<ScoredEvent> _recommended = [];
  // Cache scored events to pass match reasons to list cards
  Map<String, ScoredEvent> _scoredEventMap = {};
  // Borough list for the location filter
  List<String> _boroughs = [];

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    // 0. Populate borough list from all known events + postcode service
    _boroughs = _buildBoroughList();

    // 1. Run AI discovery first (populates events)
    setState(() => _isDiscovering = true);
    final count = await _discovery.runDailyDiscovery();
    _discoveredCount = _discovery.discoveredEventCount;
    _boroughs = _buildBoroughList(); // refresh after discovery adds events
    if (mounted) setState(() => _isDiscovering = false);

    // 2. Then init recommender (scores the now-populated events)
    await _recommender.initialize();
    _refreshRecommendations();
    if (mounted) {
      setState(() => _recommenderReady = true);
      if (count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI found $count new events in ${_discovery.userBorough}!',
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF3580F0),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Build a sorted, unique list of boroughs from all events.
  List<String> _buildBoroughList() {
    final fromEvents = widget.eventService.events
        .where((e) => e.borough.isNotEmpty)
        .map((e) => e.borough)
        .toSet();
    // Merge with the known postcodeService boroughs
    final allBoroughs = {...fromEvents, ..._postcodeService.getAllBoroughs()};
    return allBoroughs.toList()..sort();
  }

  void _showBoroughPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        String localSearch = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = localSearch.isEmpty
                ? _boroughs
                : _boroughs
                    .where((b) => b.toLowerCase().contains(localSearch.toLowerCase()))
                    .toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: HuddlColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: Color(0xFF3580F0), size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Filter by Borough',
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Search field
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search boroughs...',
                          hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
                          prefixIcon: const Icon(Icons.search, size: 20, color: HuddlColors.textHint),
                          filled: true,
                          fillColor: HuddlColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        style: GoogleFonts.poppins(fontSize: 14),
                        onChanged: (v) => setSheetState(() => localSearch = v),
                      ),
                    ),
                    // "All Boroughs" option
                    ListTile(
                      leading: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: _selectedBorough == 'All Boroughs'
                              ? const Color(0xFF3580F0).withValues(alpha: 0.15)
                              : HuddlColors.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.public, size: 18,
                          color: _selectedBorough == 'All Boroughs'
                              ? const Color(0xFF3580F0) : HuddlColors.textHint),
                      ),
                      title: Text('All Boroughs',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: _selectedBorough == 'All Boroughs'
                              ? FontWeight.w600 : FontWeight.w400,
                          color: _selectedBorough == 'All Boroughs'
                              ? const Color(0xFF3580F0) : HuddlColors.textDark,
                        ),
                      ),
                      trailing: _selectedBorough == 'All Boroughs'
                          ? const Icon(Icons.check_circle, color: Color(0xFF3580F0), size: 20)
                          : null,
                      onTap: () {
                        setState(() => _selectedBorough = 'All Boroughs');
                        Navigator.pop(ctx);
                      },
                    ),
                    const Divider(height: 1),
                    // Borough list
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final borough = filtered[i];
                          final isSelected = _selectedBorough == borough;
                          // Count events in this borough
                          final count = widget.eventService.events
                              .where((e) => e.borough == borough || (e.isOnline && e.borough.isEmpty))
                              .length;
                          return ListTile(
                            leading: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF3580F0).withValues(alpha: 0.15)
                                    : HuddlColors.background,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.location_on_outlined, size: 18,
                                color: isSelected
                                    ? const Color(0xFF3580F0) : HuddlColors.textHint),
                            ),
                            title: Text(borough,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                color: isSelected
                                    ? const Color(0xFF3580F0) : HuddlColors.textDark,
                              ),
                            ),
                            subtitle: count > 0
                                ? Text('$count event${count == 1 ? '' : 's'}',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11, color: HuddlColors.textHint))
                                : null,
                            trailing: isSelected
                                ? const Icon(Icons.check_circle, color: Color(0xFF3580F0), size: 20)
                                : null,
                            onTap: () {
                              setState(() => _selectedBorough = borough);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _forceRefreshDiscovery() async {
    setState(() => _isDiscovering = true);
    final count = await _discovery.runDailyDiscovery(force: true);
    _discoveredCount = _discovery.discoveredEventCount;
    _boroughs = _buildBoroughList();
    _refreshRecommendations();
    if (mounted) {
      setState(() => _isDiscovering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.sync, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  count > 0
                      ? 'Refreshed! Found $count new events.'
                      : 'All events up to date.',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: HuddlColors.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _refreshRecommendations() {
    _recommended = _recommender.recommendedEvents;
    // Build scored map for all events
    final allScored = _recommender.rankAllEvents();
    _scoredEventMap = {
      for (final s in allScored) s.event.id: s,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Refresh recommendations on each build (picks up new registrations etc.)
    if (_recommenderReady) _refreshRecommendations();

    final query = widget.searchQuery.toLowerCase();
    var allEvents = widget.eventService.eventMaps;

    // ── 1. Apply text search ───────────────────────────────────
    if (query.isNotEmpty) {
      allEvents = allEvents.where((e) {
        final title = (e['title'] as String? ?? '').toLowerCase();
        final location = (e['location'] as String? ?? '').toLowerCase();
        final organiser = (e['organiser'] as String? ?? '').toLowerCase();
        final borough = (e['borough'] as String? ?? '').toLowerCase();
        return title.contains(query) ||
            location.contains(query) ||
            organiser.contains(query) ||
            borough.contains(query);
      }).toList();
    }

    // ── 2. Apply borough / location filter ─────────────────────
    if (_selectedBorough != 'All Boroughs') {
      allEvents = allEvents.where((e) {
        final borough = e['borough'] as String? ?? '';
        final isOnline = e['isOnline'] == true;
        // Online events are visible everywhere
        return isOnline || borough == _selectedBorough;
      }).toList();
    }

    // ── 3. Apply type filter (Free / Paid / Online / In-Person) ─
    var events = _filter == 'All'
        ? allEvents
        : allEvents.where((e) {
            if (_filter == 'Free') return e['isFree'] == true;
            if (_filter == 'Paid') return e['isFree'] != true;
            if (_filter == 'Online') return e['isOnline'] == true;
            if (_filter == 'In-Person') return e['isOnline'] != true;
            return true;
          }).toList();

    // Sort feed by AI score (highest first)
    if (_recommenderReady && events.isNotEmpty) {
      events = List<Map<String, dynamic>>.from(events);
      events.sort((a, b) {
        final scoreA = _scoredEventMap[a['id'] as String?]?.score ?? 0;
        final scoreB = _scoredEventMap[b['id'] as String?]?.score ?? 0;
        return scoreB.compareTo(scoreA);
      });
    }

    // Whether to show the carousel (only when no search, no borough filter, no type filter)
    final showCarousel = _recommenderReady &&
        _recommended.isNotEmpty &&
        query.isEmpty &&
        _filter == 'All' &&
        _selectedBorough == 'All Boroughs';

    return Column(
      children: [
        // ── Borough selector + Type filter row ───────────────────
        Container(
          color: HuddlColors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: GestureDetector(
            onTap: _showBoroughPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _selectedBorough != 'All Boroughs'
                    ? const Color(0xFF3580F0).withValues(alpha: 0.06)
                    : HuddlColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedBorough != 'All Boroughs'
                      ? const Color(0xFF3580F0).withValues(alpha: 0.3)
                      : HuddlColors.divider,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 18,
                    color: _selectedBorough != 'All Boroughs'
                        ? const Color(0xFF3580F0)
                        : HuddlColors.textHint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedBorough,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: _selectedBorough != 'All Boroughs'
                            ? FontWeight.w600 : FontWeight.w400,
                        color: _selectedBorough != 'All Boroughs'
                            ? const Color(0xFF3580F0)
                            : HuddlColors.textSecondary,
                      ),
                    ),
                  ),
                  if (_selectedBorough != 'All Boroughs')
                    GestureDetector(
                      onTap: () => setState(() => _selectedBorough = 'All Boroughs'),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3580F0).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 14, color: Color(0xFF3580F0)),
                      ),
                    ),
                  if (_selectedBorough == 'All Boroughs')
                    const Icon(Icons.keyboard_arrow_down, size: 20, color: HuddlColors.textHint),
                ],
              ),
            ),
          ),
        ),
        // ── Type filter chips ────────────────────────────────────
        Container(
          color: HuddlColors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
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
        // ── AI Discovery status bar ─────────────────────────────
        if (_isDiscovering || (_discoveredCount > 0 && query.isEmpty))
          Container(
            color: HuddlColors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _isDiscovering
                ? Row(
                    children: [
                      const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF3580F0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI scanning London boroughs for events\u2026',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: const Color(0xFF3580F0),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3580F0).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.auto_awesome, size: 13, color: Color(0xFF3580F0)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _selectedBorough != 'All Boroughs'
                              ? '${events.length} events in $_selectedBorough'
                              : '$_discoveredCount AI-discovered events across London',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: HuddlColors.textHint,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _isDiscovering ? null : _forceRefreshDiscovery,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3580F0).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sync, size: 12, color: Color(0xFF3580F0)),
                              const SizedBox(width: 4),
                              Text(
                                'Refresh',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF3580F0),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        // ── List ─────────────────────────────────────────────────
        Expanded(
          child: events.isEmpty && !showCarousel
              ? _EmptyState(
                  icon: Icons.event_outlined,
                  title: _selectedBorough != 'All Boroughs'
                      ? 'No events in $_selectedBorough'
                      : 'No events found',
                  subtitle: _selectedBorough != 'All Boroughs'
                      ? 'Try selecting a different borough\nor reset to see all events.'
                      : 'Our AI is scanning local sources.\nNew events will appear soon.',
                  actionLabel: _selectedBorough != 'All Boroughs'
                      ? 'Show All Boroughs' : null,
                  onAction: _selectedBorough != 'All Boroughs'
                      ? () => setState(() => _selectedBorough = 'All Boroughs')
                      : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length + (showCarousel ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (showCarousel && i == 0) {
                      return _RecommendedCarousel(
                        scoredEvents: _recommended,
                        eventService: widget.eventService,
                      );
                    }
                    final eventIdx = showCarousel ? i - 1 : i;
                    final event = events[eventIdx];
                    final eventId = event['id'] as String? ?? '';
                    final scored = _scoredEventMap[eventId];
                    return _EventListCard(
                      event: event,
                      matchReasons: scored?.reasons ?? [],
                      aiScore: scored?.score ?? 0,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AI RECOMMENDED FOR YOU CAROUSEL
// ═══════════════════════════════════════════════════════════════════════════════

class _RecommendedCarousel extends StatelessWidget {
  final List<ScoredEvent> scoredEvents;
  final EventService eventService;

  const _RecommendedCarousel({
    required this.scoredEvents,
    required this.eventService,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommended For You',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.textDark,
                      ),
                    ),
                    Text(
                      'AI-matched to your family profile',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 11, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(
                      'AI',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Horizontal carousel
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: scoredEvents.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final scored = scoredEvents[index];
              return _RecommendedCard(scored: scored);
            },
          ),
        ),
        const SizedBox(height: 20),
        // "All Events" divider label
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: HuddlColors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.event, size: 16, color: HuddlColors.blue),
            ),
            const SizedBox(width: 8),
            Text(
              'All Events',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: HuddlColors.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  final ScoredEvent scored;

  const _RecommendedCard({required this.scored});

  @override
  Widget build(BuildContext context) {
    final event = scored.event;
    final topReasons = scored.reasons.take(2).toList();
    final scorePercent = scored.score.round();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(event: event.toMap()),
          ),
        );
      },
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: HuddlColors.gray900.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image with AI score badge
            Stack(
              children: [
                SizedBox(
                  height: 110,
                  width: double.infinity,
                  child: _buildCoverImage(
                    imageUrl: event.imageUrl,
                    fallbackIcon: event.icon,
                    fallbackColor: event.color,
                  ),
                ),
                // Gradient overlay
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          HuddlColors.gray900.withValues(alpha: 0.5),
                        ],
                      ),
                    ),
                  ),
                ),
                // AI match score badge
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome, size: 11, color: Colors.white),
                        const SizedBox(width: 3),
                        Text(
                          '$scorePercent%',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Price badge
                Positioned(
                  top: 8, left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: event.isFree ? HuddlColors.blue : event.color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      event.isFree ? 'Free' : event.price,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Card body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 11, color: event.color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            event.dateDisplay,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: HuddlColors.textHint,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Match reason chips
                    if (topReasons.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: topReasons.map((reason) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3580F0).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF3580F0).withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  reason.emoji,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    reason.label,
                                    style: GoogleFonts.poppins(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF3580F0),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
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
  final bool canAccess;
  final VoidCallback? onAccessDenied;

  const _MeetupCard({
    required this.meetup,
    this.canAccess = true,
    this.onAccessDenied,
  });

  /// Privacy tag label: 'Public', 'Private', or the group name
  String get _privacyTagLabel {
    switch (meetup.privacy) {
      case MeetupPrivacy.public:
        return 'Public';
      case MeetupPrivacy.group:
        return meetup.groupName ?? 'Group';
      case MeetupPrivacy.private_:
        return 'Private';
    }
  }

  /// Privacy tag colour
  Color get _privacyTagColor {
    switch (meetup.privacy) {
      case MeetupPrivacy.public:
        return HuddlColors.blue;
      case MeetupPrivacy.group:
        return HuddlColors.primaryDark;
      case MeetupPrivacy.private_:
        return HuddlColors.error;
    }
  }

  /// Privacy tag icon
  IconData get _privacyTagIcon {
    switch (meetup.privacy) {
      case MeetupPrivacy.public:
        return Icons.public;
      case MeetupPrivacy.group:
        return Icons.group;
      case MeetupPrivacy.private_:
        return Icons.lock;
    }
  }

  @override
  Widget build(BuildContext context) {
    final catStyle = _meetupCategoryStyle(meetup.category);
    final isRestricted = !canAccess;

    return GestureDetector(
      onTap: () {
        if (isRestricted) {
          onAccessDenied?.call();
          return;
        }
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
                // ── Privacy tag badge (always shown) ──────────────────────
                Positioned(
                  top: 10, right: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _privacyTagColor.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_privacyTagIcon, size: 12, color: HuddlColors.white),
                            const SizedBox(width: 3),
                            Text(
                              _privacyTagLabel,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.white,
                              ),
                            ),
                            if (isRestricted) ...[
                              const SizedBox(width: 3),
                              const Icon(Icons.block, size: 10, color: HuddlColors.white),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
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
                  // Organiser row + share button
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
                      Expanded(
                        child: Text(
                          'Organised by ${meetup.organiserName}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Share button — public: anyone can share; group/private: only creator
                      if (meetup.privacy == MeetupPrivacy.public ||
                          meetup.organiserId == 'current_user')
                        GestureDetector(
                          onTap: () => _shareMeetup(context, meetup),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: catStyle.color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.share_outlined,
                                size: 16, color: catStyle.color),
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

  static void _shareMeetup(BuildContext context, Meetup meetup) {
    final priceText = meetup.isFree
        ? 'Free'
        : '\u00A3${meetup.price?.toStringAsFixed(0) ?? ''}';
    final privacyText = meetup.privacy == MeetupPrivacy.public
        ? ''
        : meetup.privacy == MeetupPrivacy.group
            ? ' [Group: ${meetup.groupName ?? ''}]'
            : ' [Private]';

    final shareText = '''
\u{1F91D} ${meetup.title}$privacyText
\u{1F4C5} ${meetup.dateDisplay}  \u23F0 ${meetup.timeDisplay}
\u{1F4CD} ${meetup.location}
\u{1F3F7}\uFE0F ${meetup.category}  |  $priceText
\u{1F464} Organised by ${meetup.organiserName}
\u{1F465} ${meetup.attendeeCount}${meetup.maxAttendees != null ? '/${meetup.maxAttendees}' : ''} going

${meetup.description.isNotEmpty ? meetup.description : ''}
---
Shared from Huddl Connect
'''.trim();

    Clipboard.setData(ClipboardData(text: shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Meetup card copied to clipboard!',
                  style: GoogleFonts.poppins(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor: HuddlColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// ── EVENT CARD (3rd party / company events) ─────────────────────────────────
class _EventListCard extends StatefulWidget {
  final Map<String, dynamic> event;
  final List<MatchReason> matchReasons;
  final double aiScore;

  const _EventListCard({
    required this.event,
    this.matchReasons = const [],
    this.aiScore = 0,
  });

  @override
  State<_EventListCard> createState() => _EventListCardState();
}

class _EventListCardState extends State<_EventListCard> {
  final EventService _eventService = EventService();

  Map<String, dynamic> get event => widget.event;

  List<Widget> _buildMatchReasonChips() {
    final reasons = widget.matchReasons.take(2).toList();
    if (reasons.isEmpty) return [];
    return [
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          // AI score badge
          if (widget.aiScore >= 50)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, size: 11, color: Colors.white),
                  const SizedBox(width: 3),
                  Text(
                    '${widget.aiScore.round()}% match',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          // Reason tags
          ...reasons.map((reason) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF3580F0).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF3580F0).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reason.emoji, style: const TextStyle(fontSize: 10)),
                  const SizedBox(width: 3),
                  Text(
                    reason.label,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF3580F0),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final Color eventColor = event['color'] as Color;
    final bool isFree = event['isFree'] == true;
    final bool isOnline = event['isOnline'] == true;
    final String organiser = event['organiser'] as String? ?? '';
    final String imageUrl = event['imageUrl'] as String? ?? '';
    final String eventId = event['id'] as String? ?? '';
    final String borough = event['borough'] as String? ?? '';
    final bool isBookmarked = eventId.isNotEmpty && _eventService.isBookmarked(eventId);

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
                // AI Discovered badge (top-right, below online badge)
                if (event['isAiDiscovered'] == true && !isOnline)
                  Positioned(
                    top: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome, size: 11, color: Colors.white),
                          const SizedBox(width: 3),
                          Text(
                            'AI Found',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
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
                      GestureDetector(
                        onTap: () {
                          if (eventId.isNotEmpty) {
                            _eventService.toggleBookmark(eventId);
                            setState(() {});
                          }
                        },
                        child: Container(
                          width: 30,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isBookmarked
                                ? HuddlColors.accentAmber.withValues(alpha: 0.85)
                                : HuddlColors.gray900.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                            size: 16,
                            color: HuddlColors.white,
                          ),
                        ),
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
                  // Borough tag
                  if (borough.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: HuddlColors.blue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: HuddlColors.blue.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on, size: 11, color: HuddlColors.blue),
                              const SizedBox(width: 3),
                              Text(
                                borough,
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: HuddlColors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  // AI Match reason badges
                if (widget.matchReasons.isNotEmpty) ..._buildMatchReasonChips(),
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
                        Expanded(
                          child: Text(
                            'By $organiser',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: HuddlColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // AI source attribution row
                  if (event['isAiDiscovered'] == true) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.auto_awesome, size: 10, color: Colors.white),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          event['aiSourceIcon'] as IconData? ?? Icons.language,
                          size: 12,
                          color: const Color(0xFF3580F0),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Found on ${event['aiSourceName'] as String? ?? 'the web'}',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF3580F0),
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
    case 'Food':
      return const _CatStyle(HuddlColors.accentAmber, Icons.restaurant);
    case 'Other':
      return const _CatStyle(HuddlColors.blue, Icons.more_horiz);
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
  // Use Image.network instead of CachedNetworkImage for reliable web
  // rendering — CachedNetworkImage can silently fail to load images on
  // Flutter Web due to its IndexedDB caching layer.
  if (imageUrl.startsWith('http')) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder();
      },
      errorBuilder: (_, __, ___) => fallback(),
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
