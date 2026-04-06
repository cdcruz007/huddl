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
import 'meetup_detail_screen.dart';
import 'event_detail_screen.dart';
import '../ai/ai_matchmaker_sheet.dart';
import '../ai/ai_copilot_screen.dart';
import '../../services/ai_event_recommender_service.dart';
import '../../services/ai_event_discovery_service.dart';
import '../../services/invisible_ai_service.dart';

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
    // Show FAB only on Meetups tab (index 0)
    final showFab = _tabController.index == 0;

    return Scaffold(
      backgroundColor: context.hc.scaffold,
      // ── Material You FAB for Create Meet-up (always accessible) ──
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _navigateToCreateMeetup,
              backgroundColor: HuddlColors.primary,
              foregroundColor: HuddlColors.white,
              elevation: 3,
              icon: const Icon(Icons.add, size: 20),
              label: Text(
                'Create',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────
            Container(
              color: context.hc.surface,
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
                          color: context.hc.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          Semantics(
                            label: 'Open AI Copilot',
                            button: true,
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AiCopilotScreen(),
                                ),
                              ),
                              child: Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
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
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isSearching ? Icons.close : Icons.search,
                              color: context.hc.textPrimary,
                            ),
                            tooltip: _isSearching ? 'Close search' : 'Search',
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
                            icon: Icon(Icons.notifications_outlined,
                                color: context.hc.textPrimary),
                            tooltip: 'Notifications',
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
                      style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
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
                        fillColor: context.hc.inputBg,
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
                    unselectedLabelColor: context.hc.textTertiary,
                    labelStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    indicatorColor: HuddlColors.primary,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: context.hc.divider,
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
          color: context.hc.surface,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SizedBox(
            height: 44, // 48dp minimum touch target height
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
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadUserContext();
                    if (mounted) setState(() {});
                  },
                  color: HuddlColors.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), // bottom padding for FAB
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
        ),
      ],
    );
  }

  Widget _buildAiMatchmakerCard(BuildContext context) {
    return Semantics(
      label: 'AI Matchmaker - Find compatible parents and suggested meetups',
      button: true,
      child: Container(
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

    return RefreshIndicator(
      onRefresh: () async {
        // Trigger a UI rebuild; services auto-refresh their state
        await Future.delayed(const Duration(milliseconds: 500));
      },
      color: HuddlColors.primary,
      child: ListView(
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
    ),
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

  void _confirmCancel(BuildContext context) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.hc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isPast ? 'Clear from history?' : 'Cancel attendance?',
          style: GoogleFonts.poppins(
            fontSize: 17, fontWeight: FontWeight.w600, color: context.hc.textPrimary),
        ),
        content: Text(
          isPast
              ? 'Remove "${item.title}" from your past events list?'
              : 'You will be removed from "${item.title}" and the organiser will be notified.',
          style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Keep', style: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textHint)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onCancel();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isPast ? HuddlColors.textSecondary : HuddlColors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              isPast ? 'Clear' : 'Cancel',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor =
        item.isMeetup ? HuddlColors.primary : HuddlColors.blue;
    final fallbackIcon =
        item.isMeetup ? Icons.groups : Icons.event;

    // Swipe-to-dismiss for one-handed usability
    return Dismissible(
      key: ValueKey('going_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isPast ? HuddlColors.textSecondary : HuddlColors.error,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.close, color: HuddlColors.white, size: 22),
            const SizedBox(height: 2),
            Text(isPast ? 'Clear' : 'Cancel',
              style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.white)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        return true;
      },
      onDismissed: (_) => onCancel(),
      child: Opacity(
      opacity: isPast ? 0.55 : 1.0,
      child: Semantics(
        label: '${item.isMeetup ? "Meetup" : "Event"}: ${item.title}, ${item.dateDisplay} ${item.timeDisplay} at ${item.location}${isPast ? " (Past)" : ""}. Swipe left to ${isPast ? "clear" : "cancel"}.',
        button: true,
        child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(16),
          border: context.hc.cardBorder,
          boxShadow: [
            BoxShadow(
              color: context.hc.shadow,
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
                                color: context.hc.textPrimary,
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
                              size: 12, color: context.hc.textTertiary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${item.dateDisplay} · ${item.timeDisplay}',
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
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 12, color: context.hc.textTertiary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.location,
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
                    // ── 48dp touch target for cancel/clear ──
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _confirmCancel(context),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          alignment: Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              isPast ? 'Clear' : 'Cancel',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isPast ? HuddlColors.textTertiary : HuddlColors.error,
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
  // ── Core AI services ───────────────────────────────────────
  final AiEventRecommenderService _recommender = AiEventRecommenderService();
  final AiEventDiscoveryService _discovery = AiEventDiscoveryService();
  final InvisibleAiService _invisibleAi = InvisibleAiService();

  // ── State ──────────────────────────────────────────────────
  bool _recommenderReady = false;
  bool _isDiscovering = false;
  List<ScoredEvent> _recommended = [];
  Map<String, ScoredEvent> _scoredEventMap = {};

  // ── "Less is more" invisible AI state ──────────────────────
  String _nlpQuery = '';
  final TextEditingController _nlpController = TextEditingController();
  final FocusNode _nlpFocusNode = FocusNode();
  bool _showSuggestions = false;
  Map<String, dynamic> _activeParsedFilters = {};
  bool _filtersExpanded = false; // progressive disclosure: filters hidden by default

  @override
  void initState() {
    super.initState();
    _initServices();
    _nlpFocusNode.addListener(() {
      if (mounted) setState(() => _showSuggestions = _nlpFocusNode.hasFocus && _nlpQuery.isEmpty);
    });
  }

  @override
  void dispose() {
    _nlpController.dispose();
    _nlpFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initServices() async {
    setState(() => _isDiscovering = true);
    final count = await _discovery.runDailyDiscovery();
    if (mounted) setState(() => _isDiscovering = false);

    await _recommender.initialize();
    await _invisibleAi.initialize();
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
                    'Found $count new events near you',
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF3580F0),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _forceRefreshDiscovery() async {
    setState(() => _isDiscovering = true);
    await _discovery.runDailyDiscovery(force: true);
    _refreshRecommendations();
    if (mounted) setState(() => _isDiscovering = false);
  }

  void _refreshRecommendations() {
    _recommended = _recommender.recommendedEvents;
    final allScored = _recommender.rankAllEvents();
    _scoredEventMap = { for (final s in allScored) s.event.id: s };
  }

  void _onNlpQueryChanged(String value) {
    setState(() {
      _nlpQuery = value;
      _showSuggestions = value.isEmpty && _nlpFocusNode.hasFocus;
      if (value.isNotEmpty) {
        _activeParsedFilters = _invisibleAi.parseNaturalQuery(value);
      } else {
        _activeParsedFilters = {};
      }
    });
  }

  void _applySuggestion(AiSearchSuggestion suggestion) {
    _nlpController.text = suggestion.query;
    _onNlpQueryChanged(suggestion.query);
    _nlpFocusNode.unfocus();
  }

  void _clearSearch() {
    _nlpController.clear();
    setState(() {
      _nlpQuery = '';
      _activeParsedFilters = {};
      _showSuggestions = false;
    });
    _nlpFocusNode.unfocus();
  }

  void _showAiAssistantSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AiAssistantSheet(
        invisibleAi: _invisibleAi,
        onSuggestionTap: (query) {
          Navigator.pop(context);
          _nlpController.text = query;
          _onNlpQueryChanged(query);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_recommenderReady) _refreshRecommendations();

    // ── Build events list ────────────────────────────────────
    var allEvents = widget.eventService.eventMaps;

    // Apply parent-level search
    final parentQuery = widget.searchQuery.toLowerCase();
    if (parentQuery.isNotEmpty) {
      allEvents = allEvents.where((e) {
        final title = (e['title'] as String? ?? '').toLowerCase();
        final location = (e['location'] as String? ?? '').toLowerCase();
        final organiser = (e['organiser'] as String? ?? '').toLowerCase();
        return title.contains(parentQuery) ||
            location.contains(parentQuery) ||
            organiser.contains(parentQuery);
      }).toList();
    }

    // Apply NLP smart filters (invisible AI)
    List<Map<String, dynamic>> events;
    if (_activeParsedFilters.isNotEmpty) {
      events = _invisibleAi.applySmartFilter(allEvents, _activeParsedFilters);
    } else {
      events = allEvents;
    }

    // Apply manual filters if expanded
    if (_filtersExpanded && _activeManualFilter != 'All') {
      events = events.where((e) {
        if (_activeManualFilter == 'Free') return e['isFree'] == true;
        if (_activeManualFilter == 'Paid') return e['isFree'] != true;
        if (_activeManualFilter == 'Online') return e['isOnline'] == true;
        if (_activeManualFilter == 'In-Person') return e['isOnline'] != true;
        return true;
      }).toList();
    }

    // Intelligent sort (AI-powered ranking)
    if (_recommenderReady && events.isNotEmpty) {
      events = _invisibleAi.intelligentSort(events, _scoredEventMap);
    }

    // Show carousel only when clean state
    final showCarousel = _recommenderReady &&
        _recommended.isNotEmpty &&
        parentQuery.isEmpty &&
        _nlpQuery.isEmpty &&
        !_filtersExpanded;

    // Active filter chips for NLP
    final activeNlpChips = _buildActiveNlpChips();

    return Column(
      children: [
        // ── Predictive NLP Search Bar ─────────────────────────
        Container(
          color: context.hc.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: HuddlColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _nlpFocusNode.hasFocus
                          ? const Color(0xFF3580F0).withValues(alpha: 0.4)
                          : HuddlColors.divider,
                    ),
                  ),
                  child: TextField(
                    controller: _nlpController,
                    focusNode: _nlpFocusNode,
                    onChanged: _onNlpQueryChanged,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Try "free baby classes this weekend"',
                      hintStyle: GoogleFonts.poppins(
                        fontSize: 13,
                        color: HuddlColors.textHint,
                      ),
                      prefixIcon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _nlpQuery.isNotEmpty
                            ? const Icon(Icons.auto_awesome, key: ValueKey('ai'),
                                size: 18, color: Color(0xFF3580F0))
                            : const Icon(Icons.search, key: ValueKey('search'),
                                size: 18, color: HuddlColors.textHint),
                      ),
                      suffixIcon: _nlpQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: _clearSearch,
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
              ),
              // ── Sparkle entry point (progressive disclosure) ──
              Semantics(
                label: 'AI Assistant',
                button: true,
                child: GestureDetector(
                  onTap: _showAiAssistantSheet,
                  child: Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.only(left: 4),
                    alignment: Alignment.center,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.auto_awesome, size: 17, color: Colors.white),
                    ),
                  ),
                ),
              ),
              // ── Toggle manual filters ──
              IconButton(
                icon: Icon(
                  _filtersExpanded ? Icons.tune : Icons.tune_outlined,
                  size: 20,
                  color: _filtersExpanded ? const Color(0xFF3580F0) : HuddlColors.textHint,
                ),
                tooltip: 'Filters',
                onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
              ),
            ],
          ),
        ),

        // ── AI Suggestions (shown when search is focused & empty) ──
        if (_showSuggestions)
          _buildSuggestionsPanel(),

        // ── Active NLP filter chips (shown when smart search is active) ──
        if (activeNlpChips.isNotEmpty && _nlpQuery.isNotEmpty)
          Container(
            color: context.hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)]),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 10, color: Colors.white),
                ),
                const SizedBox(width: 6),
                Text('AI understood:', style: GoogleFonts.poppins(
                  fontSize: 10, color: HuddlColors.textHint, fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: activeNlpChips),
                  ),
                ),
              ],
            ),
          ),

        // ── Manual filter chips (progressive disclosure, hidden by default) ──
        if (_filtersExpanded)
          Container(
            color: context.hc.surface,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _invisibleAi.adaptiveFilterOrder.map((f) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: f,
                    isSelected: _activeManualFilter == f,
                    onTap: () {
                      _invisibleAi.trackFilterClick(f);
                      setState(() => _activeManualFilter = f);
                    },
                  ),
                )).toList(),
              ),
            ),
          ),

        // ── AI Context line (transparent about what AI is doing) ──
        if (_recommenderReady && _nlpQuery.isEmpty && !_isDiscovering && parentQuery.isEmpty)
          Container(
            color: context.hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3580F0).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 11, color: Color(0xFF3580F0)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _invisibleAi.getContextExplanation(),
                    style: GoogleFonts.poppins(
                      fontSize: 11, color: HuddlColors.textHint, fontWeight: FontWeight.w400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isDiscovering)
                  const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF3580F0)),
                  ),
              ],
            ),
          ),

        // ── Discovering indicator ─────────────────────────────
        if (_isDiscovering)
          Container(
            color: context.hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF3580F0)),
                ),
                const SizedBox(width: 8),
                Text(
                  'Finding events for you\u2026',
                  style: GoogleFonts.poppins(
                    fontSize: 12, color: const Color(0xFF3580F0), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

        // ── Event list ───────────────────────────────────────
        Expanded(
          child: events.isEmpty && !showCarousel
              ? _EmptyState(
                  icon: Icons.event_outlined,
                  title: _nlpQuery.isNotEmpty ? 'No matches' : 'No events found',
                  subtitle: _nlpQuery.isNotEmpty
                      ? 'Try a different search like\n"free baby classes near me"'
                      : 'Pull down to refresh or try searching.',
                  actionLabel: _nlpQuery.isNotEmpty ? 'Clear search' : null,
                  onAction: _nlpQuery.isNotEmpty ? _clearSearch : null,
                )
              : RefreshIndicator(
                  onRefresh: _forceRefreshDiscovery,
                  color: HuddlColors.primary,
                  child: ListView.builder(
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
                        invisibleAi: _invisibleAi,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  String _activeManualFilter = 'All';

  Widget _buildSuggestionsPanel() {
    final suggestions = _invisibleAi.getSearchSuggestions();
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      color: context.hc.surface,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)]),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.auto_awesome, size: 10, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Text('Suggested for you', style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.textHint)),
            ],
          ),
          const SizedBox(height: 6),
          ...suggestions.map((s) => GestureDetector(
            onTap: () => _applySuggestion(s),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: HuddlColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(s.icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.query, style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.textDark)),
                        Text(s.reason, style: GoogleFonts.poppins(
                          fontSize: 11, color: HuddlColors.textHint)),
                      ],
                    ),
                  ),
                  const Icon(Icons.north_west, size: 14, color: HuddlColors.textHint),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  List<Widget> _buildActiveNlpChips() {
    final chips = <Widget>[];
    final p = _activeParsedFilters;

    void addChip(String label, Color color) {
      chips.add(Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: GoogleFonts.poppins(
          fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ));
    }

    if (p.containsKey('priceFilter')) addChip(p['priceFilter'] as String, const Color(0xFF3580F0));
    if (p.containsKey('formatFilter')) addChip(p['formatFilter'] as String, HuddlColors.teal);
    if (p.containsKey('timeFilter')) addChip(p['timeFilter'] as String, HuddlColors.primaryDark);
    if (p.containsKey('category')) addChip(p['category'] as String, HuddlColors.accentAmber);
    if (p.containsKey('ageStage')) addChip(p['ageStage'] as String, HuddlColors.primary);
    if (p.containsKey('keywords')) addChip('"${p['keywords']}"', HuddlColors.textSecondary);

    return chips;
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
                        color: context.hc.textPrimary,
                      ),
                    ),
                    Text(
                      'AI-matched to your family profile',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: context.hc.textTertiary,
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
                color: context.hc.textPrimary,
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

    return Semantics(
      label: 'Recommended event: ${event.title}, $scorePercent% match, ${event.dateDisplay}${event.isFree ? ", Free" : ""}',
      button: true,
      child: GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => EventDetailScreen(event: event.toMap()),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      },
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(16),
          border: context.hc.cardBorder,
          boxShadow: [
            BoxShadow(
              color: context.hc.shadow.withValues(alpha: 0.08),
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
                        color: context.hc.textPrimary,
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
            color: context.hc.textPrimary,
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

    return Semantics(
      label: 'Meetup: ${meetup.title}, ${meetup.dateDisplay} ${meetup.timeDisplay}, ${meetup.location}, organised by ${meetup.organiserName}${isRestricted ? ", restricted access" : ""}',
      button: true,
      child: GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (isRestricted) {
          onAccessDenied?.call();
          return;
        }
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => MeetupDetailScreen(meetup: meetup),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: catStyle.color.withValues(alpha: 0.15),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: catStyle.color.withValues(alpha: 0.08),
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
                  child: Hero(
                    tag: 'meetup_cover_${meetup.id}',
                    child: _buildCoverImage(
                    imageUrl: meetup.imageUrl,
                    fallbackIcon: catStyle.icon,
                    fallbackColor: catStyle.color,
                  ),
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
                          color: HuddlColors.textTertiary,
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
                            color: HuddlColors.textTertiary,
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
                      // Share button -- public: anyone can share; group/private: only creator
                      if (meetup.privacy == MeetupPrivacy.public ||
                          meetup.organiserId == 'current_user')
                        Semantics(
                          label: 'Share meetup',
                          button: true,
                          child: GestureDetector(
                            onTap: () => _shareMeetup(context, meetup),
                            child: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
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
      ),
    );
  }

  static void _shareMeetup(BuildContext context, Meetup meetup) {
    HapticFeedback.mediumImpact();
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
  final InvisibleAiService? invisibleAi;

  const _EventListCard({
    required this.event,
    this.matchReasons = const [],
    this.aiScore = 0,
    this.invisibleAi,
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

    return Semantics(
      label: 'Event: ${event['title']}, ${event['date']} ${event['time']}, ${event['location']}${isFree ? ", Free" : ", ${event['price']}"}',
      button: true,
      child: GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => EventDetailScreen(event: event),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: eventColor.withValues(alpha: 0.15),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: eventColor.withValues(alpha: 0.08),
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
                  child: Hero(
                    tag: 'event_cover_$eventId',
                    child: _buildCoverImage(
                    imageUrl: imageUrl,
                    fallbackIcon: event['icon'] as IconData,
                    fallbackColor: eventColor,
                  ),
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
                      color: isFree ? HuddlColors.blue : eventColor,
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
                      Semantics(
                        label: isBookmarked ? 'Remove bookmark' : 'Bookmark event',
                        button: true,
                        child: GestureDetector(
                          onTap: () {
                            if (eventId.isNotEmpty) {
                              HapticFeedback.lightImpact();
                              _eventService.toggleBookmark(eventId);
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isBookmarked ? 'Bookmark removed' : 'Event bookmarked!'),
                                  backgroundColor: isBookmarked ? HuddlColors.textSecondary : HuddlColors.teal,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
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
                          color: HuddlColors.textTertiary,
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
                            color: HuddlColors.textTertiary,
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
                  // ── AI Feedback thumbs (human-in-the-loop) ──
                  if (widget.invisibleAi != null && widget.aiScore >= 40) ...[
                    const SizedBox(height: 8),
                    _AiFeedbackRow(
                      eventId: eventId,
                      invisibleAi: widget.invisibleAi!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AI FEEDBACK ROW — thumbs up/down for human-in-the-loop
// ═══════════════════════════════════════════════════════════════════════════════

class _AiFeedbackRow extends StatefulWidget {
  final String eventId;
  final InvisibleAiService invisibleAi;

  const _AiFeedbackRow({
    required this.eventId,
    required this.invisibleAi,
  });

  @override
  State<_AiFeedbackRow> createState() => _AiFeedbackRowState();
}

class _AiFeedbackRowState extends State<_AiFeedbackRow> {
  bool? _localFeedback;

  @override
  void initState() {
    super.initState();
    _localFeedback = widget.invisibleAi.getFeedback(widget.eventId);
  }

  void _submit(bool positive) {
    HapticFeedback.lightImpact();
    widget.invisibleAi.submitFeedback(widget.eventId, positive);
    setState(() => _localFeedback = positive);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(positive
            ? 'Thanks! We\u2019ll show more like this'
            : 'Got it \u2014 fewer like this'),
        backgroundColor: positive ? HuddlColors.teal : HuddlColors.textSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFF3580F0).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Icon(Icons.auto_awesome, size: 10, color: Color(0xFF3580F0)),
        ),
        const SizedBox(width: 5),
        Text(
          'AI pick',
          style: GoogleFonts.poppins(
            fontSize: 10, color: HuddlColors.textHint, fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        if (_localFeedback != null)
          Text(
            _localFeedback! ? 'Liked' : 'Not for me',
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: _localFeedback! ? HuddlColors.teal : HuddlColors.textHint,
              fontWeight: FontWeight.w500,
            ),
          )
        else ...[
          Text('Helpful?', style: GoogleFonts.poppins(
            fontSize: 10, color: HuddlColors.textHint)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _submit(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: HuddlColors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.thumb_up_alt_outlined, size: 12, color: HuddlColors.teal),
                  const SizedBox(width: 3),
                  Text('Yes', style: GoogleFonts.poppins(
                    fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.teal)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _submit(false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: HuddlColors.textHint.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HuddlColors.textHint.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.thumb_down_alt_outlined, size: 12,
                    color: HuddlColors.textHint.withValues(alpha: 0.7)),
                  const SizedBox(width: 3),
                  Text('No', style: GoogleFonts.poppins(
                    fontSize: 10, fontWeight: FontWeight.w500, color: HuddlColors.textHint)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AI ASSISTANT BOTTOM-SHEET — progressive disclosure via sparkle icon
// ═══════════════════════════════════════════════════════════════════════════════

class _AiAssistantSheet extends StatelessWidget {
  final InvisibleAiService invisibleAi;
  final void Function(String query) onSuggestionTap;

  const _AiAssistantSheet({
    required this.invisibleAi,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    final suggestions = invisibleAi.getSearchSuggestions();
    final posCount = invisibleAi.totalPositiveFeedback;
    final negCount = invisibleAi.totalNegativeFeedback;

    return Container(
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: context.hc.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Event Assistant',
                          style: GoogleFonts.poppins(
                            fontSize: 18, fontWeight: FontWeight.w700,
                            color: context.hc.textPrimary,
                          ),
                        ),
                        Text(
                          'Finding the perfect events for your family',
                          style: GoogleFonts.poppins(
                            fontSize: 12, color: context.hc.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // How AI works (transparency)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF3580F0).withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF3580F0).withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('How it works', style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                    const SizedBox(height: 8),
                    _AssistantInfoRow(
                      icon: Icons.search, label: 'Type naturally',
                      detail: 'e.g. "free baby classes this weekend"'),
                    _AssistantInfoRow(
                      icon: Icons.auto_awesome, label: 'AI understands intent',
                      detail: 'Automatically applies price, time, age filters'),
                    _AssistantInfoRow(
                      icon: Icons.thumb_up_alt_outlined, label: 'You give feedback',
                      detail: 'Thumbs up/down helps AI learn your preferences'),
                    _AssistantInfoRow(
                      icon: Icons.sort, label: 'Smart sorting',
                      detail: 'Events are ranked by relevance to your family'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Quick searches
              Text('Quick searches', style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: suggestions.map((s) => GestureDetector(
                  onTap: () => onSuggestionTap(s.query),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: HuddlColors.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: HuddlColors.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(s.icon, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(s.query, style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w500,
                          color: HuddlColors.textDark)),
                      ],
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),

              // Feedback stats (transparency)
              if (posCount + negCount > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: HuddlColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insights, size: 18, color: Color(0xFF3580F0)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your feedback: $posCount likes, $negCount dislikes \u2014 AI is learning your taste',
                          style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint),
                        ),
                      ),
                    ],
                  ),
                ),

              // Voice command placeholder
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: HuddlColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: HuddlColors.divider),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: HuddlColors.textHint.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.mic, size: 18, color: HuddlColors.textHint),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Voice search', style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.textSecondary)),
                          Text('Coming soon \u2014 search by speaking', style: GoogleFonts.poppins(
                            fontSize: 11, color: HuddlColors.textHint)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: HuddlColors.textHint.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('SOON', style: GoogleFonts.poppins(
                        fontSize: 9, fontWeight: FontWeight.w700, color: HuddlColors.textHint)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;

  const _AssistantInfoRow({
    required this.icon,
    required this.label,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF3580F0).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: const Color(0xFF3580F0)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w600, color: context.hc.textPrimary)),
                Text(detail, style: GoogleFonts.poppins(
                  fontSize: 11, color: context.hc.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _FilterChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    _animCtrl.forward().then((_) {
      _animCtrl.reverse();
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.label} filter${widget.isSelected ? ", selected" : ""}',
      button: true,
      selected: widget.isSelected,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _scaleAnim,
          builder: (context, child) => Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            // 48dp minimum touch target height
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isSelected ? HuddlColors.primary : context.hc.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: widget.isSelected
                  ? null
                  : Border.all(color: context.hc.divider, width: 0.5),
              boxShadow: widget.isSelected
                  ? [
                      BoxShadow(
                        color: HuddlColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                // WCAG fix: white on primary (7.1:1) instead of dark (3.1:1)
                color: widget.isSelected ? HuddlColors.white : context.hc.textSecondary,
              ),
              child: Text(widget.label),
            ),
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
                color: context.hc.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: context.hc.textTertiary,
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
                  // 48dp minimum touch target
                  minimumSize: const Size(120, 48),
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
  String semanticLabel = 'Event cover image',
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

  if (imageUrl.isEmpty) return Semantics(label: semanticLabel, image: true, child: fallback());

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
