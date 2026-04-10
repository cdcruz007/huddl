import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';
import '../../services/event_service.dart';
import '../../services/member_photo_service.dart';
import '../../services/default_group_service.dart';
import '../../services/browser_storage.dart';
import '../../models/group.dart';
import 'create_meetup_screen.dart';
import 'meetup_detail_screen.dart';
import 'event_detail_screen.dart';
import '../../services/meetup_ai_service.dart';
import '../../services/ai_event_recommender_service.dart';
import '../../services/ai_event_discovery_service.dart';
import '../../services/invisible_ai_service.dart';
import '../groups/groups_screen.dart' show DiscoverGroupsTab;
import '../../widgets/borough_badge.dart';
import '../../services/borough_scope_guard.dart';
import '../groups/forward_message_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DISCOVER SCREEN — main entry with 3 tabs: Meetups · Events · Groups
// ═══════════════════════════════════════════════════════════════════════════════

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0; // Tracks the settled tab index for FAB logic
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
      // Only update the selected tab when the animation has settled,
      // so the FAB never shows/hides based on a mid-swipe index.
      if (!_tabController.indexIsChanging) {
        if (_selectedTab != _tabController.index) {
          setState(() { _selectedTab = _tabController.index; });
        }
      }
    });
    _meetupService.addListener(_refresh);
    _eventService.addListener(_refresh);
    // Restore user-uploaded base64 images into in-memory meetup list
    _meetupService.restoreCustomImages();
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
      backgroundColor: context.hc.surface,
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
                      color: context.hc.divider,
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
                    color: context.hc.textPrimary,
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
                              color: context.hc.textTertiary.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No upcoming reminders',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: context.hc.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'RSVP to meetups or register for events',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: context.hc.textTertiary,
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
                            color: context.hc.textTertiary,
                          ),
                        ),
                        trailing: Icon(Icons.chevron_right,
                            color: context.hc.textTertiary, size: 20),
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
                            color: context.hc.textTertiary,
                          ),
                        ),
                        trailing: Icon(Icons.chevron_right,
                            color: context.hc.textTertiary, size: 20),
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
      backgroundColor: context.hc.scaffold,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Main content column ────────────────────────────────
            Column(
              children: [
                // ── Header ─────────────────────────────────────────
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
                        "Discover",
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
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
                            fontSize: 14, color: context.hc.textTertiary),
                        prefixIcon: Icon(Icons.search,
                            color: context.hc.textTertiary, size: 20),
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
                  // ── Tabs: Groups | Meetups | Events ──────────────
                  TabBar(
                    controller: _tabController,
                    onTap: (index) {
                      // Immediately update FAB when user taps a tab
                      setState(() { _selectedTab = index; });
                    },
                    tabs: const [
                      Tab(text: 'Groups'),
                      Tab(text: 'Meetups'),
                      Tab(text: 'Events'),
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
            // ── Borough scope context bar ───────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _selectedTab == 2
                  ? const BoroughHeader(
                      key: ValueKey('uk-wide'),
                      feature: HuddlFeature.events,
                    )
                  : _selectedTab == 1
                      ? const BoroughHeader(
                          key: ValueKey('meetups-borough'),
                          feature: HuddlFeature.meetups,
                        )
                      : const BoroughHeader(
                          key: ValueKey('groups-borough'),
                          feature: HuddlFeature.groups,
                        ),
            ),
            // ── Tab content ─────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  const DiscoverGroupsTab(),
                  _MeetupsTab(
                    meetupService: _meetupService,
                    onCreateMeetup: _navigateToCreateMeetup,
                    searchQuery: _searchQuery,
                  ),
                  _EventsTab(
                    eventService: _eventService,
                    searchQuery: _searchQuery,
                  ),
                ],
              ),
            ),
          ],
        ),
        // ── Circular + FAB ────────────────────────────────────
        // Rendered as a Positioned inside the Stack so we have
        // absolute control: Groups → create group, Meetups →
        // create meetup, Events → hidden entirely.
        if (_selectedTab == 0)
          Positioned(
            bottom: 24,
            right: 16,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pushNamed(context, '/create_group');
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HuddlColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: HuddlColors.primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 28),
              ),
            ),
          ),
        if (_selectedTab == 1)
          Positioned(
            bottom: 24,
            right: 16,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _navigateToCreateMeetup();
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HuddlColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: HuddlColors.primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 28),
              ),
            ),
          ),
        // _selectedTab == 2 (Events) → no FAB rendered at all
          ],
        ),
      ),
    );
  }
}

// Discover screen has three tabs: Groups | Meetups | Events

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
  final MeetupAiService _aiService = MeetupAiService();
  bool _aiReady = false;
  bool _filtersExpanded = false; // progressive disclosure
  SmartNudge? _activeNudge;

  // Compact default filters — only the most common categories
  static const _defaultFilters = [
    {'label': 'All', 'codes': null},
    {'label': 'Playdate', 'codes': ['Playdate']},
    {'label': 'Coffee', 'codes': ['Coffee']},
    {'label': 'Walk', 'codes': ['Walk']},
  ];

  // Full filter set (progressive disclosure — revealed on tap)
  static const _allFilters = [
    {'label': 'All', 'codes': null},
    {'label': 'Playdate', 'codes': ['Playdate']},
    {'label': 'Coffee', 'codes': ['Coffee']},
    {'label': 'Walk', 'codes': ['Walk']},
    {'label': 'Sport', 'codes': ['Sport']},
    {'label': 'Social', 'codes': ['Social']},
    {'label': 'Food', 'codes': ['Food']},
    {'label': 'Other', 'codes': ['Other']},
  ];

  List<Map<String, dynamic>> get _activeFilters =>
      _filtersExpanded ? _allFilters : _defaultFilters;

  List<String>? get _activeFilterCodes {
    if (_filter == 'All') return null;
    final cat = _allFilters.firstWhere(
      (c) => c['label'] == _filter,
      orElse: () => {'label': 'All', 'codes': null},
    );
    return (cat['codes'] as List<String>?);
  }

  @override
  void initState() {
    super.initState();
    _loadUserContext();
    _initAi();
  }

  Future<void> _initAi() async {
    await _aiService.initialize();
    if (mounted) {
      setState(() => _aiReady = true);
    }
  }

  Future<void> _loadUserContext() async {
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

  /// All future meetups — ALL privacy levels listed.
  /// Access control enforced at tap-time.
  List<Meetup> get _visibleMeetups {
    final now = DateTime.now();
    final query = widget.searchQuery.toLowerCase();
    return widget.meetupService.meetups.where((m) {
      if (m.dateTime.isBefore(now)) return false;
      if (query.isNotEmpty) {
        return m.title.toLowerCase().contains(query) ||
            m.location.toLowerCase().contains(query) ||
            m.category.toLowerCase().contains(query) ||
            m.organiserName.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

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

  void _showAccessDeniedDialog(BuildContext context, Meetup meetup) {
    final isGroup = meetup.privacy == MeetupPrivacy.group;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.hc.surface,
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
                  color: context.hc.textPrimary,
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
            color: context.hc.textSecondary,
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
    var filtered = codes == null
        ? visible
        : visible.where((m) => codes.contains(m.category)).toList();

    // ── B) Smart Sort: AI silently reorders meetups ──────────────
    List<ScoredMeetup> scored = [];
    if (_aiReady) {
      scored = _aiService.smartSort(filtered);
      filtered = scored.map((s) => s.meetup).toList();
      // ── E) Smart Nudge: contextual one-liner ────────────────
      _activeNudge = _aiService.getSmartNudge(visible);
    }

    // Build a map from meetup id to boost reason for card display
    final boostReasons = <String, String>{};
    for (final s in scored) {
      if (s.boostReason != null) boostReasons[s.meetup.id] = s.boostReason!;
    }

    return Column(
      children: [
        // ── Slim filter row with progressive disclosure ──────────
        Container(
          color: context.hc.surface,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ..._activeFilters.map((cat) {
                  final label = cat['label'] as String;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(
                      label: label,
                      isSelected: _filter == label,
                      onTap: () {
                        _aiService.trackCategoryTap(label);
                        setState(() => _filter = label);
                      },
                    ),
                  );
                }),
                // More/Less toggle chip
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _filtersExpanded = !_filtersExpanded);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 36,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: context.hc.surfaceAlt,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: context.hc.divider, width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _filtersExpanded ? Icons.keyboard_arrow_left : Icons.tune,
                            size: 16,
                            color: context.hc.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _filtersExpanded ? 'Less' : 'More',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: context.hc.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── E) Smart Nudge — contextual one-liner (dismissible) ──
        if (_activeNudge != null)
          _SmartNudgeBanner(
            nudge: _activeNudge!,
            onDismiss: () {
              _aiService.dismissNudge(_activeNudge!.type.name);
              setState(() => _activeNudge = null);
            },
            onCreateMeetup: widget.onCreateMeetup,
          ),

        // ── List ─────────────────────────────────────────────────
        Expanded(
          child: filtered.isEmpty
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final meetup = filtered[i];
                      return _MeetupCard(
                        meetup: meetup,
                        canAccess: _canAccessMeetup(meetup),
                        onAccessDenied: () => _showAccessDeniedDialog(context, meetup),
                        boostReason: boostReasons[meetup.id],
                        onView: () => _aiService.trackMeetupView(meetup.id, meetup.category),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART NUDGE BANNER — single contextual line, dismissible
// ═══════════════════════════════════════════════════════════════════════════════

class _SmartNudgeBanner extends StatelessWidget {
  final SmartNudge nudge;
  final VoidCallback onDismiss;
  final VoidCallback onCreateMeetup;

  const _SmartNudgeBanner({
    required this.nudge,
    required this.onDismiss,
    required this.onCreateMeetup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.hc.surface,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: HuddlColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Text(nudge.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                nudge.text,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.hc.textPrimary,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (nudge.actionLabel != null) ...[              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCreateMeetup,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: HuddlColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    nudge.actionLabel!,
                    style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.white),
                  ),
                ),
              ),
            ],
            // Dismiss button
            GestureDetector(
              onTap: onDismiss,
              child: Container(
                width: 32, height: 32,
                alignment: Alignment.center,
                child: Icon(Icons.close, size: 15, color: context.hc.textTertiary.withValues(alpha: 0.6)),
              ),
            ),
          ],
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
  final String organiser;
  final int attendees;
  final bool isFree;
  final String price;
  final String category;

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
    this.organiser = '',
    this.attendees = 0,
    this.isFree = true,
    this.price = '',
    this.category = '',
  });

  factory _GoingItem.fromMeetup(Meetup m) => _GoingItem(
        id: m.id,
        title: m.title,
        dateDisplay: m.dateDisplay,
        timeDisplay: m.timeDisplay,
        dateTime: m.dateTime,
        location: m.location,
        imageUrl: m.imageUrl.isNotEmpty
            ? m.imageUrl
            : _meetupCategoryImage(m.category),
        isMeetup: true,
        meetup: m,
        organiser: m.organiserName,
        attendees: m.attendeeCount,
        isFree: m.isFree,
        price: m.isFree ? '' : (m.price != null ? '\u00A3${m.price}' : ''),
        category: m.category,
      );

  /// Category-based Pexels fallback image for meetups.
  static String _meetupCategoryImage(String category) {
    switch (category.toLowerCase()) {
      case 'coffee':
      case 'coffee & chat':
        return 'https://images.pexels.com/photos/302899/pexels-photo-302899.jpeg?auto=compress&cs=tinysrgb&w=600';
      case 'playdate':
      case 'play':
        return 'https://images.pexels.com/photos/3933239/pexels-photo-3933239.jpeg?auto=compress&cs=tinysrgb&w=600';
      case 'walk':
      case 'outdoor':
        return 'https://images.pexels.com/photos/1325735/pexels-photo-1325735.jpeg?auto=compress&cs=tinysrgb&w=600';
      case 'sport':
      case 'fitness':
      case 'exercise':
        return 'https://images.pexels.com/photos/3822864/pexels-photo-3822864.jpeg?auto=compress&cs=tinysrgb&w=600';
      case 'class':
      case 'workshop':
        return 'https://images.pexels.com/photos/3662667/pexels-photo-3662667.jpeg?auto=compress&cs=tinysrgb&w=600';
      case 'music':
        return 'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=600';
      case 'social':
        return 'https://images.pexels.com/photos/3184418/pexels-photo-3184418.jpeg?auto=compress&cs=tinysrgb&w=600';
      default:
        return 'https://images.pexels.com/photos/3933250/pexels-photo-3933250.jpeg?auto=compress&cs=tinysrgb&w=600';
    }
  }

  factory _GoingItem.fromEvent(Event e) => _GoingItem(
        id: e.id,
        title: e.title,
        dateDisplay: e.dateDisplay,
        timeDisplay: e.timeDisplay,
        dateTime: e.dateTime,
        location: e.location,
        imageUrl: e.imageUrl.isNotEmpty
            ? e.imageUrl
            : 'https://images.pexels.com/photos/3933250/pexels-photo-3933250.jpeg?auto=compress&cs=tinysrgb&w=600',
        isMeetup: false,
        event: e,
        organiser: e.organiser,
        attendees: e.attendees,
        isFree: e.isFree,
        price: e.price,
        category: e.category,
      );

  /// Days until this event/meetup. 0 = today, 1 = tomorrow, negative = past.
  int get daysUntil {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(dateTime.year, dateTime.month, dateTime.day);
    return eventDay.difference(today).inDays;
  }

  /// Human-readable countdown label.
  String get countdownLabel {
    final d = daysUntil;
    if (d < 0) return 'Past';
    if (d == 0) return 'Today';
    if (d == 1) return 'Tomorrow';
    if (d <= 7) return 'In $d days';
    return dateDisplay;
  }
}

class _ImGoingCard extends StatelessWidget {
  final _GoingItem item;
  final bool isPast;
  final VoidCallback onCancel;

  const _ImGoingCard({
    super.key,
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
              fontSize: 14, fontWeight: FontWeight.w600, color: context.hc.textTertiary)),
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

    // ── Messages-tab identical row card ──────────────────────────────
    return Dismissible(
      key: ValueKey('going_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: isPast ? HuddlColors.textSecondary : HuddlColors.error,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.close, color: context.hc.surface, size: 22),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Material(
              color: HuddlColors.white,
              borderRadius: BorderRadius.circular(16),
              elevation: 1,
              shadowColor: Colors.black.withValues(alpha: 0.08),
              child: InkWell(
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
                onLongPress: () => _confirmCancel(context),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // ── Rounded-square thumbnail (matches Messages _GroupAvatar) ──
                      _GoingAvatar(
                        imageUrl: item.imageUrl,
                        accentColor: accentColor,
                        isMeetup: item.isMeetup,
                        category: item.category,
                      ),
                      const SizedBox(width: 12),

                      // ── Name + subtitle (same 2-row layout as _GroupMessageRow) ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Row 1: title + type badge + countdown (mirrors name + timestamp)
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
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
                                      if (item.isMeetup) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: context.hc.textTertiary.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Meetup',
                                            style: GoogleFonts.poppins(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                              color: context.hc.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _countdownColor(item.daysUntil, isPast)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    item.countdownLabel,
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: _countdownColor(item.daysUntil, isPast),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),

                            // Row 2: date/location summary + attendee badge (mirrors last-message row)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.dateDisplay}  \u00b7  ${item.timeDisplay}  \u00b7  ${item.location}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: context.hc.textTertiary,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item.attendees > 0) ...[
                                  const SizedBox(width: 8),
                                  Semantics(
                                    label: '${item.attendees} attending',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: accentColor,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${item.attendees}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: context.hc.surface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Colour for countdown badge based on urgency.
  static Color _countdownColor(int daysUntil, bool isPast) {
    if (isPast) return HuddlColors.textSecondary;
    if (daysUntil <= 0) return HuddlColors.error;
    if (daysUntil <= 2) return HuddlColors.accentAmber;
    return HuddlColors.teal;
  }
}

/// 54px rounded-square avatar matching the Messages tab _GroupAvatar style
/// exactly — same borderRadius, peachLight bg, fallback icon pattern.
class _GoingAvatar extends StatelessWidget {
  final String imageUrl;
  final Color accentColor;
  final bool isMeetup;
  final String category;

  const _GoingAvatar({
    required this.imageUrl,
    required this.accentColor,
    required this.isMeetup,
    this.category = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: HuddlColors.peachLight,
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildImage(),
    );
  }

  Widget _buildImage() {
    if (imageUrl.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(imageUrl);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover, width: 54, height: 54,
            errorBuilder: (_, __, ___) => _fallbackIcon(),
          );
        }
      } catch (_) {
        // fall through
      }
      return _fallbackIcon();
    }
    if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover, width: 54, height: 54,
        errorBuilder: (_, __, ___) => _fallbackIcon(),
      );
    }
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover, width: 54, height: 54,
        errorBuilder: (_, __, ___) => _fallbackIcon(),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      color: HuddlColors.peachLight,
      child: Center(
        child: Icon(
          isMeetup ? Icons.groups : Icons.event,
          size: 54 * 0.45,
          color: HuddlColors.primary,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLIC WRAPPER — Exposes the I'm Going functionality for use in other screens
// (e.g. the Connect screen's "I'm Going" tab).
// ═══════════════════════════════════════════════════════════════════════════════

class ImGoingTab extends StatefulWidget {
  const ImGoingTab({super.key});

  @override
  State<ImGoingTab> createState() => _ImGoingTabWrapperState();
}

class _ImGoingTabWrapperState extends State<ImGoingTab> {
  final MeetupService _meetupService = MeetupService();
  final EventService _eventService = EventService();
  // Rebuild key — incremented on every cancel to force list rebuild
  int _rebuildKey = 0;

  @override
  void initState() {
    super.initState();
    _meetupService.addListener(_refresh);
    _eventService.addListener(_refresh);
  }

  @override
  void dispose() {
    _meetupService.removeListener(_refresh);
    _eventService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => _rebuildKey++);
  }

  void _cancelItem(_GoingItem item) {
    if (item.isMeetup) {
      _meetupService.toggleGoing(item.id);
    } else {
      _eventService.toggleGoing(item.id);
    }
    // Force immediate rebuild even if listener hasn't fired yet
    if (mounted) setState(() => _rebuildKey++);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Merge meetups & events the user is going to
    final List<_GoingItem> allGoing = [
      ..._meetupService.meetups
          .where((m) => m.isGoing)
          .map((m) => _GoingItem.fromMeetup(m)),
      ..._eventService.goingEvents
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
            "Tap 'Count Me In' on a meetup or event to add it here!",
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() => _rebuildKey++);
      },
      color: HuddlColors.primary,
      child: ListView(
        key: ValueKey('im_going_list_$_rebuildKey'),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        children: [
          if (upcoming.isNotEmpty) ...[
            _SectionLabel(
              icon: Icons.upcoming_outlined,
              label: 'Upcoming',
              color: HuddlColors.primaryDark,
            ),
            const SizedBox(height: 8),
            ...upcoming.map((item) => _ImGoingCard(
                  key: ValueKey('going_card_${item.id}_$_rebuildKey'),
                  item: item,
                  onCancel: () => _cancelItem(item),
                )),
          ],
          if (past.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionLabel(
              icon: Icons.history,
              label: 'Past',
              color: context.hc.textTertiary,
            ),
            const SizedBox(height: 8),
            ...past.map((item) => _ImGoingCard(
                  key: ValueKey('going_card_${item.id}_$_rebuildKey'),
                  item: item,
                  isPast: true,
                  onCancel: () => _cancelItem(item),
                )),
          ],
        ],
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
            content: Text(
              'Found $count new events near you',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            backgroundColor: HuddlColors.blue,
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

  // AI assistant sheet removed — AI now works invisibly behind the scenes.

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
                    color: context.hc.scaffold,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _nlpFocusNode.hasFocus
                          ? HuddlColors.blue.withValues(alpha: 0.4)
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
                        color: context.hc.textTertiary,
                      ),
                      prefixIcon: Icon(Icons.search,
                                size: 18, color: context.hc.textTertiary),
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

              // ── Toggle manual filters ──
              IconButton(
                icon: Icon(
                  _filtersExpanded ? Icons.tune : Icons.tune_outlined,
                  size: 20,
                  color: _filtersExpanded ? HuddlColors.blue : HuddlColors.textHint,
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
                Icon(Icons.filter_list_rounded, size: 14, color: context.hc.textTertiary),
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
              height: 40,
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
                    strokeWidth: 2, color: HuddlColors.blue),
                ),
                const SizedBox(width: 8),
                Text(
                  'Finding events for you\u2026',
                  style: GoogleFonts.poppins(
                    fontSize: 12, color: HuddlColors.blue, fontWeight: FontWeight.w500),
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
          Text('Try searching for', style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w500, color: context.hc.textTertiary)),
          const SizedBox(height: 6),
          ...suggestions.map((s) => GestureDetector(
            onTap: () => _applySuggestion(s),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.hc.scaffold,
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
                          fontSize: 13, fontWeight: FontWeight.w500, color: context.hc.textPrimary)),
                        Text(s.reason, style: GoogleFonts.poppins(
                          fontSize: 11, color: context.hc.textTertiary)),
                      ],
                    ),
                  ),
                  Icon(Icons.north_west, size: 14, color: context.hc.textTertiary),
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

    if (p.containsKey('priceFilter')) addChip(p['priceFilter'] as String, HuddlColors.blue);
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
        // Section header — clean, no AI branding
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.star_rounded, size: 18, color: HuddlColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                'Picked for you',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary,
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
            // Clean cover image (no overlay tags)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: SizedBox(
                height: 110,
                width: double.infinity,
                child: _buildCoverImage(
                  imageUrl: event.imageUrl,
                  fallbackIcon: event.icon,
                  fallbackColor: HuddlColors.primary,
                ),
              ),
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
                        const Icon(Icons.calendar_today_outlined, size: 11, color: HuddlColors.primary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            event.dateDisplay,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: context.hc.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          event.isFree ? 'Free' : event.price,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: event.isFree ? HuddlColors.blue : HuddlColors.primary,
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
                              color: HuddlColors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: HuddlColors.blue.withValues(alpha: 0.2),
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
                                      color: HuddlColors.blue,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
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
      ),
    );
  }
}

/// ── MEET-UP CARD ────────────────────────────────────────────────────────────
class _MeetupCard extends StatelessWidget {
  final Meetup meetup;
  final bool canAccess;
  final VoidCallback? onAccessDenied;
  final String? boostReason; // AI-generated boost reason (subtle sparkle)
  final VoidCallback? onView; // track AI view for learning

  const _MeetupCard({
    required this.meetup,
    this.canAccess = true,
    this.onAccessDenied,
    this.boostReason,
    this.onView,
  });

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
        onView?.call(); // track for AI learning
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
            // ── Clean cover image (no overlay tags) ──────────────────
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: Hero(
                  tag: 'meetup_cover_${meetup.id}',
                  child: _buildCoverImage(
                    imageUrl: meetup.imageUrl.isNotEmpty
                        ? meetup.imageUrl
                        : _GoingItem._meetupCategoryImage(meetup.category),
                    fallbackIcon: catStyle.icon,
                    fallbackColor: catStyle.color,
                  ),
                ),
              ),
            ),
            // ── Info row (category, price, attendees) ─────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  // Category
                  Icon(catStyle.icon, size: 13, color: catStyle.color),
                  const SizedBox(width: 4),
                  Text(
                    meetup.category,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: catStyle.color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Price
                  Text(
                    meetup.isFree
                        ? 'Free'
                        : '\u00A3${meetup.price?.toStringAsFixed(0) ?? ''}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: meetup.isFree ? HuddlColors.blue : HuddlColors.accentAmber,
                    ),
                  ),
                  const Spacer(),
                  // Attendees
                  Icon(Icons.people_outline, size: 13, color: context.hc.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    '${meetup.attendeeCount}${meetup.maxAttendees != null ? '/${meetup.maxAttendees}' : ''} going',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // ── Card body ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meetup.title,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
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
                          color: context.hc.textSecondary,
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
                          color: context.hc.textTertiary,
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
                            color: context.hc.textTertiary,
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
                      _buildOrganiserAvatar(meetup.organiserName, meetup.organiserId, 22, catStyle.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Organised by ${meetup.organiserName}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: context.hc.textSecondary,
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
    
    // Convert meetup to map for forwarding
    final meetupData = {
      'id': meetup.id,
      'title': meetup.title,
      'category': meetup.category,
      'dateDisplay': meetup.dateDisplay,
      'timeDisplay': meetup.timeDisplay,
      'location': meetup.location,
      'imageUrl': meetup.imageUrl,
      'organiserName': meetup.organiserName,
      'attendeeCount': meetup.attendeeCount,
      'maxAttendees': meetup.maxAttendees,
      'isFree': meetup.isFree,
      'price': meetup.price,
      'description': meetup.description,
      'privacy': meetup.privacy.toString(),
      'groupName': meetup.groupName,
    };

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

    // Show forward sheet to send as meetup card
    showForwardSheet(
      context: context,
      messageText: shareText,
      meetupData: meetupData,
      isMeetupCard: true,
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
          // Reason tags (AI score hidden — works invisibly)
          ...reasons.map((reason) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: HuddlColors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: HuddlColors.blue.withValues(alpha: 0.2),
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
                      color: HuddlColors.blue,
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
    // Always use brand primary for consistency across all event cards
    const Color eventColor = HuddlColors.primary;
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
            // ── Clean cover image (no overlay tags) ──────────────────
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: SizedBox(
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
            ),
            // ── Info row (price, attendees, bookmark) ─────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  // Price
                  Text(
                    isFree ? 'Free' : event['price'] as String,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isFree ? HuddlColors.blue : eventColor,
                    ),
                  ),
                  if (isOnline) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.videocam_outlined, size: 13, color: HuddlColors.blue),
                    const SizedBox(width: 3),
                    Text(
                      'Online',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.blue,
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Attendees
                  Icon(Icons.people_outline, size: 13, color: context.hc.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    '${event['attendees']} going',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Bookmark
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
                      child: Icon(
                        isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                        size: 20,
                        color: isBookmarked ? HuddlColors.accentAmber : context.hc.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Card body ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event['title'] as String,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
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
                          color: context.hc.textSecondary,
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
                          color: context.hc.textTertiary,
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
                            color: context.hc.textTertiary,
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
                              color: context.hc.textSecondary,
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
                              colors: [HuddlColors.blue, HuddlColors.lightBlue],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.language, size: 10, color: Colors.white),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          event['aiSourceIcon'] as IconData? ?? Icons.language,
                          size: 12,
                          color: HuddlColors.blue,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Found on ${event['aiSourceName'] as String? ?? 'the web'}',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: HuddlColors.blue,
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
            color: HuddlColors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Icon(Icons.insights, size: 10, color: HuddlColors.blue),
        ),
        const SizedBox(width: 5),
        Text(
          'Pick',
          style: GoogleFonts.poppins(
            fontSize: 10, color: context.hc.textTertiary, fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        if (_localFeedback != null)
          Text(
            _localFeedback! ? 'Liked' : 'Not for me',
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: _localFeedback! ? HuddlColors.teal : context.hc.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          )
        else ...[
          Text('Helpful?', style: GoogleFonts.poppins(
            fontSize: 10, color: context.hc.textTertiary)),
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
                color: context.hc.textTertiary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.hc.textTertiary.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.thumb_down_alt_outlined, size: 12,
                    color: context.hc.textTertiary.withValues(alpha: 0.7)),
                  const SizedBox(width: 3),
                  Text('No', style: GoogleFonts.poppins(
                    fontSize: 10, fontWeight: FontWeight.w500, color: context.hc.textTertiary)),
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
            height: 36,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    color: context.hc.surface,
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
// SHARED — Organiser avatar helper
// ═══════════════════════════════════════════════════════════════════════════════

/// Builds a small circular avatar for the meetup organiser.
/// For the current user: show onboarding photo or local asset fallback.
/// For known community members: show their Pexels photo.
Widget _buildOrganiserAvatar(String name, String organiserId, double size, Color accentColor) {
  // Current user: use local asset avatar
  if (organiserId == 'current_user' || MemberPhotoService.isCurrentUser(name)) {
    final photoUrl = MemberPhotoService.getPhotoByName(name);
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:')) {
        try {
          final parts = photoUrl.split(',');
          if (parts.length > 1) {
            final bytes = base64Decode(parts[1]);
            return Container(
              width: size, height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: HuddlColors.primary, width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(bytes, fit: BoxFit.cover, width: size, height: size),
            );
          }
        } catch (_) {}
      }
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: HuddlColors.primary, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(photoUrl, fit: BoxFit.cover, width: size, height: size,
          errorBuilder: (_, __, ___) => _currentUserAssetAvatar(size)),
      );
    }
    return _currentUserAssetAvatar(size);
  }

  // Known community member
  final photoUrl = MemberPhotoService.getPhotoByName(name);
  if (photoUrl != null && photoUrl.isNotEmpty) {
    return Container(
      width: size, height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: Image.network(photoUrl, fit: BoxFit.cover, width: size, height: size,
        errorBuilder: (_, __, ___) => CircleAvatar(
          radius: size / 2,
          backgroundColor: accentColor.withValues(alpha: 0.15),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: GoogleFonts.poppins(fontSize: size * 0.45, fontWeight: FontWeight.w700, color: accentColor),
          ),
        )),
    );
  }

  return CircleAvatar(
    radius: size / 2,
    backgroundColor: accentColor.withValues(alpha: 0.15),
    child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: GoogleFonts.poppins(fontSize: size * 0.45, fontWeight: FontWeight.w700, color: accentColor),
    ),
  );
}

/// Local asset avatar for the current user (gender-based), used in events_screen.
Widget _currentUserAssetAvatar(double size) {
  return Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: HuddlColors.primary, width: 1),
    ),
    child: ClipOval(
      child: Image.asset(
        MemberPhotoService.currentUserAvatarAsset,
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: HuddlColors.peachLight,
          child: Center(child: Icon(Icons.person, size: size * 0.5, color: HuddlColors.primary)),
        ),
      ),
    ),
  );
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
