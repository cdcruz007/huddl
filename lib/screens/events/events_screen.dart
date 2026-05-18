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
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/borough_badge.dart';
import '../../services/borough_scope_guard.dart';
import '../../widgets/common/huddl_empty_state.dart';
import '../groups/forward_message_sheet.dart';
import '../services/services_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DISCOVER SCREEN — main entry with 4 tabs: Groups · Meetups · Events · Services
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
  // Fires true to trigger search mode in the Groups tab.
  final ValueNotifier<bool> _groupSearchTrigger = ValueNotifier<bool>(false);
  // Fires true to reset/close search mode when leaving the Groups tab.
  final ValueNotifier<bool> _groupResetTrigger = ValueNotifier<bool>(false);
  // Fires true to open inline search in the Meetups tab.
  final ValueNotifier<bool> _meetupSearchTrigger = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      // Only update the selected tab when the animation has settled,
      // so the FAB never shows/hides based on a mid-swipe index.
      if (!_tabController.indexIsChanging) {
        if (_selectedTab != _tabController.index) {
          // If leaving the Groups tab, reset any active search.
          if (_selectedTab == 0 && _tabController.index != 0) {
            _groupResetTrigger.value = true;
          }
          setState(() { _selectedTab = _tabController.index; });
        }
      }
    });
    // Defer service listener registration until after first frame.
    // MeetupService.restoreCustomImages() and EventService can call
    // notifyListeners() which triggers setState on MainShell during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _meetupService.addListener(_refresh);
        _eventService.addListener(_refresh);
        _meetupService.restoreCustomImages();
        // Load meetups from Firestore (also seeds demo data when Firestore is empty)
        _meetupService.loadFromFirestore();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _meetupService.removeListener(_refresh);
    _eventService.removeListener(_refresh);
    _groupSearchTrigger.dispose();
    _groupResetTrigger.dispose();
    _meetupSearchTrigger.dispose();
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
                            color: HuddlColors.teal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.event,
                              color: HuddlColors.teal, size: 22),
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
                      Row(
                        children: [
                          Text(
                            'Discover',
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Borough chip: blue for Groups/Meetups/Services, UK-wide teal for Events
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: BoroughScopeChip(
                              key: ValueKey('discover_chip_$_selectedTab'),
                              feature: _selectedTab == 2
                                  ? HuddlFeature.events     // UK-wide teal
                                  : _selectedTab == 3
                                      ? HuddlFeature.services // borough blue
                                      : _selectedTab == 1
                                          ? HuddlFeature.meetups  // borough blue
                                          : HuddlFeature.groups,  // borough blue
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Search icon on Groups/Meetups tabs; bell on Events/Services
                          if (_selectedTab == 0)
                            IconButton(
                              icon: Icon(Icons.search,
                                  color: context.hc.textPrimary),
                              tooltip: 'Search groups',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _groupSearchTrigger.value = true;
                              },
                            )
                          else if (_selectedTab == 1)
                            IconButton(
                              icon: Icon(Icons.search,
                                  color: context.hc.textPrimary),
                              tooltip: 'Search meetups',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _meetupSearchTrigger.value = true;
                              },
                            )
                          else
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
                  const SizedBox(height: 8),
                  // ── Tabs: Groups | Meetups | Events ──────────────
                  TabBar(
                    controller: _tabController,
                    onTap: (index) {
                      // Immediately update FAB when user taps a tab.
                      // Also: tapping the Groups tab while already on it
                      // dismisses any active search and returns to tiled view.
                      if (index == 0) {
                        _groupResetTrigger.value = true;
                      }
                      setState(() { _selectedTab = index; });
                    },
                    tabs: const [
                      Tab(text: 'Groups'),
                      Tab(text: 'Meetups'),
                      Tab(text: 'Events'),
                      Tab(text: 'Services'),
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
            // Borough header banners removed — scope shown via compact
            // chip next to the Discover title instead.
            // ── Tab content ─────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  DiscoverGroupsTab(
                    searchTrigger: _groupSearchTrigger,
                    resetTrigger: _groupResetTrigger,
                  ),
                  _MeetupsTab(
                    meetupService: _meetupService,
                    onCreateMeetup: _navigateToCreateMeetup,
                    searchTrigger: _meetupSearchTrigger,
                  ),
                  _EventsTab(
                    eventService: _eventService,
                  ),
                  const ServicesScreen(),
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
                  color: HuddlColors.blueUI,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: HuddlColors.blueUI.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 28),
              ),
            ),
          ),
        // _selectedTab == 2 (Events) or 3 (Services) → no FAB rendered at all
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
  final ValueNotifier<bool> searchTrigger;

  const _MeetupsTab({
    required this.meetupService,
    required this.onCreateMeetup,
    required this.searchTrigger,
  });

  @override
  State<_MeetupsTab> createState() => _MeetupsTabState();
}

class _MeetupsTabState extends State<_MeetupsTab> {
  // ── Category filter (chip row) ────────────────────────────────
  // These labels exactly match the create-meetup category names.
  // Each maps to the short code(s) stored in Meetup.category.
  static const _categoryChips = [
    {'label': 'All',                  'codes': <String>[]},
    {'label': 'Hanging out',          'codes': ['Social']},
    {'label': 'Pregnancy',            'codes': ['Social']},
    {'label': 'Playdate',             'codes': ['Playdate']},
    {'label': 'Sports & exercise',    'codes': ['Sport']},
    {'label': 'Coffee & tea',         'codes': ['Coffee']},
    {'label': 'Parks & Walks',        'codes': ['Walk']},
    {'label': 'Food & nutrition',     'codes': ['Food']},
    {'label': 'Performance & shows',  'codes': ['Social']},
    {'label': 'Other',                'codes': ['Other']},
  ];

  // ── Participant filter options (matches create-meetup form) ───
  static const _participantOptions = [
    'Mums', 'Dads', 'Aspiring parents', 'Expecting parents', 'Kids',
  ];

  String _selectedCategory = 'All'; // top chip-row (feed header)
  String _selectedParticipant = 'All'; // legacy single-select (kept for compat)

  // ── Extended filter state (filter sheet) ─────────────────────
  /// 'none' | 'online' | 'live'
  String _localization = 'none';
  double _distanceKm = 10.0;
  /// Multi-select categories from sheet (labels, e.g. 'Hanging out')
  final Set<String> _sheetCategories = {};
  /// Multi-select participants from sheet (labels, e.g. 'Mums')
  final Set<String> _sheetParticipants = {};
  bool _showFreeOnly = false;
  DateTimeRange? _dateRange;
  /// 'mostPopular' | 'latest'
  String _sortBy = 'mostPopular';

  Set<String> _joinedGroupIds = {};
  final MeetupAiService _aiService = MeetupAiService();
  bool _aiReady = false;
  SmartNudge? _activeNudge;

  // ── Local search ──────────────────────────────────────────────
  bool _isSearchActive = false;
  String _localSearchQuery = '';
  final TextEditingController _localSearchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// True when any filter beyond defaults is active.
  bool get _hasActiveFilter {
    return _selectedCategory != 'All'
        || _selectedParticipant != 'All'
        || _localization != 'none'
        || _sheetCategories.isNotEmpty
        || _sheetParticipants.isNotEmpty
        || _showFreeOnly
        || _dateRange != null
        || _sortBy != 'mostPopular'
        || _distanceKm != 10.0;
  }

  /// The category codes to match from TOP chip row (empty = show all).
  List<String> get _activeCategoryCodes {
    if (_selectedCategory == 'All') return [];
    final chip = _categoryChips.firstWhere(
      (c) => c['label'] == _selectedCategory,
      orElse: () => {'label': 'All', 'codes': <String>[]},
    );
    return (chip['codes'] as List<String>? ?? []);
  }

  /// Short label for the filter pill.
  String get _filterPillLabel {
    final int count = [
      if (_sheetCategories.isNotEmpty) true,
      if (_sheetParticipants.isNotEmpty) true,
      if (_localization != 'none') true,
      if (_showFreeOnly) true,
      if (_dateRange != null) true,
      if (_sortBy != 'mostPopular') true,
    ].length;
    if (count == 0 && _selectedCategory != 'All') return _selectedCategory;
    if (count == 0 && _selectedParticipant != 'All') return _selectedParticipant;
    if (count == 1) {
      if (_localization != 'none') return _localization == 'online' ? 'Online' : 'Live';
      if (_sheetCategories.isNotEmpty) return _sheetCategories.first;
      if (_sheetParticipants.isNotEmpty) return _sheetParticipants.first;
      if (_showFreeOnly) return 'Free only';
      if (_sortBy != 'mostPopular') return 'Latest';
    }
    if (count > 1) return '$count filters';
    return '';
  }

  /// Distance label shown in feed bar ("10 km", "1 km", etc.)
  String get _distanceLabel {
    if (_localization == 'online') return 'Online';
    final v = _distanceKm.round();
    return v >= 50 ? '<50 km' : '$v km';
  }

  @override
  void initState() {
    super.initState();
    _loadUserContext();
    _initAi();
    widget.searchTrigger.addListener(_onSearchTrigger);
  }

  void _onSearchTrigger() {
    if (widget.searchTrigger.value) {
      widget.searchTrigger.value = false;
      setState(() => _isSearchActive = true);
      Future.microtask(() => _searchFocusNode.requestFocus());
    }
  }

  void _clearSearch() {
    setState(() {
      _isSearchActive = false;
      _localSearchQuery = '';
      _localSearchController.clear();
    });
    _searchFocusNode.unfocus();
  }

  @override
  void dispose() {
    widget.searchTrigger.removeListener(_onSearchTrigger);
    _localSearchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final defaultGroups = await groupService.getUserGroups(uid);
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
    final query = _localSearchQuery.toLowerCase();
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

  /// Apply all active filters and sort order.
  List<Meetup> _applyFilters(List<Meetup> meetups) {
    var result = meetups;

    // ── 1. Top chip-row category (single-select, legacy) ─────────
    final codes = _activeCategoryCodes;
    if (codes.isNotEmpty) {
      result = result.where((m) => codes.contains(m.category)).toList();
    }

    // ── 2. Sheet multi-select categories ─────────────────────────
    if (_sheetCategories.isNotEmpty) {
      // Build union of all codes for selected sheet categories
      final Set<String> allCodes = {};
      for (final label in _sheetCategories) {
        final chip = _categoryChips.firstWhere(
          (c) => c['label'] == label,
          orElse: () => {'label': label, 'codes': <String>[]},
        );
        allCodes.addAll((chip['codes'] as List<String>? ?? []));
      }
      if (allCodes.isNotEmpty) {
        result = result.where((m) => allCodes.contains(m.category)).toList();
      }
    }

    // ── 3. Legacy single-select participant ──────────────────────
    if (_selectedParticipant != 'All') {
      result = result.where((m) {
        if (m.targetAudience.isEmpty) return true;
        return m.targetAudience.contains(_selectedParticipant);
      }).toList();
    }

    // ── 4. Sheet multi-select participants ───────────────────────
    if (_sheetParticipants.isNotEmpty) {
      result = result.where((m) {
        if (m.targetAudience.isEmpty) return true;
        return m.targetAudience.any((a) => _sheetParticipants.contains(a));
      }).toList();
    }

    // ── 5. Localization (online / live) ───────────────────────────
    // Meetup.isFree is repurposed as isOnline proxy if no dedicated field.
    // We use location == 'Online' or category to infer; or we use the
    // existing `isOnline` flag in the data layer where available.
    // For robustness we check both.
    if (_localization == 'online') {
      result = result.where((m) =>
        m.location.toLowerCase().contains('online') ||
        m.category.toLowerCase().contains('online')
      ).toList();
    } else if (_localization == 'live') {
      result = result.where((m) =>
        !m.location.toLowerCase().contains('online') &&
        !m.category.toLowerCase().contains('online')
      ).toList();
    }

    // ── 6. Free only ──────────────────────────────────────────────
    if (_showFreeOnly) {
      result = result.where((m) => m.isFree || (m.price == null || m.price == 0)).toList();
    }

    // ── 7. Date range ─────────────────────────────────────────────
    if (_dateRange != null) {
      final start = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
      final end   = DateTime(_dateRange!.end.year,   _dateRange!.end.month,   _dateRange!.end.day, 23, 59, 59);
      result = result.where((m) =>
        m.dateTime.isAfter(start.subtract(const Duration(seconds: 1))) &&
        m.dateTime.isBefore(end.add(const Duration(seconds: 1)))
      ).toList();
    }

    // ── 8. Sort ───────────────────────────────────────────────────
    if (_sortBy == 'latest') {
      result.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    } else {
      // mostPopular — sort by attendeeCount descending
      result.sort((a, b) => b.attendeeCount.compareTo(a.attendeeCount));
    }

    return result;
  }

  bool _canAccessMeetup(Meetup m) {
    switch (m.privacy) {
      case MeetupPrivacy.public:
        return true;
      case MeetupPrivacy.group:
        if (m.organiserId == (FirebaseAuth.instance.currentUser?.uid ?? 'current_user')) return true;
        if (m.groupId == null) return false;
        return _joinedGroupIds.contains(m.groupId);
      case MeetupPrivacy.private_:
        final myUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
        return m.invitedMemberIds.contains(myUid) || m.organiserId == myUid;
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

  // ── Filter bottom sheet — Figma-exact redesign ───────────────
  void _showFilterSheet(BuildContext context) {
    HapticFeedback.selectionClick();

    // ── Local copies of all filter state for the sheet ────────
    String        sheetLocalization    = _localization;
    double        sheetDistanceKm      = _distanceKm;
    Set<String>   sheetCategories      = Set<String>.from(_sheetCategories);
    Set<String>   sheetParticipants    = Set<String>.from(_sheetParticipants);
    bool          sheetFreeOnly        = _showFreeOnly;
    DateTimeRange? sheetDateRange      = _dateRange;
    String        sheetSortBy          = _sortBy;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {

          // ══ DESIGN TOKENS — Figma styleguide exact ════════════
          const Color bgSheet      = Colors.white;
          const Color orange       = Color(0xFFFF965C);  // Figma: "Dark orange" — primary brand
          const Color blue         = Color(0xFF347FEF);  // Figma: "Dark blue" — selected state
          const Color textPrimary  = Color(0xFF42464C);  // Figma: "Black" grayscale
          const Color textSecGray  = Color(0xFF949494);  // Figma: light gray
          const Color chipBg       = Color(0xFFF6F6F6);  // Figma: page background = unselected chip
          const Color dividerColor = Color(0xFFD5D5D5);  // Figma: grayscale divider
          const Color trackInactive= Color(0xFFD5D5D5);
          const Color toggleOff    = Color(0xFFD5D5D5);

          final bool isOnline = sheetLocalization == 'online';

          // ── Helper: section heading ────────────────────────────
          Widget sectionHeading(String title) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
          );

          // ── Helper: localization chip ─────────────────────────
          Widget locChip(String label, String value) {
            final sel = sheetLocalization == value;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setSheetState(() {
                  sheetLocalization = (sheetLocalization == value) ? 'none' : value;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? blue : chipBg,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel ? Colors.white : textPrimary,
                  ),
                ),
              ),
            );
          }

          // ── Helper: filter chip (Participants / Category) ─────
          Widget filterChip({
            required String label,
            required bool isSelected,
            required VoidCallback onTap,
            IconData? icon,
            Color? iconColor,
          }) {
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: icon != null ? 12 : 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? HuddlColors.textDark : chipBg,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 15,
                        color: isSelected ? Colors.white : (iconColor ?? blue),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? Colors.white : textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Helper: radio option row ──────────────────────────
          Widget radioRow(String label, String value) {
            final sel = sheetSortBy == value;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                setSheetState(() => sheetSortBy = value);
              },
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    // Custom radio button
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? orange : HuddlColors.divider,
                          width: sel ? 0 : 1.5,
                        ),
                        color: sel ? orange : Colors.transparent,
                      ),
                      child: sel
                          ? const Center(
                              child: CircleAvatar(
                                radius: 4,
                                backgroundColor: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Category icon map ──────────────────────────────────
          const Map<String, IconData> catIcons = {
            'All':                 Icons.apps_rounded,
            'Hanging out':         Icons.chat_bubble_outline_rounded,
            'Pregnancy':           Icons.pregnant_woman_outlined,
            'Playdate':            Icons.directions_run_rounded,
            'Sports & exercise':   Icons.fitness_center_outlined,
            'Coffee & tea':        Icons.coffee_outlined,
            'Parks & Walks':       Icons.park_outlined,
            'Food & nutrition':    Icons.restaurant_outlined,
            'Performance & shows': Icons.theater_comedy_outlined,
            'Other':               Icons.more_horiz_rounded,
          };

          // ── Count active sheet filters for CTA label ──────────
          int activeCount = 0;
          if (sheetLocalization != 'none') activeCount++;
          if (sheetCategories.isNotEmpty) activeCount++;
          if (sheetParticipants.isNotEmpty) activeCount++;
          if (sheetFreeOnly) activeCount++;
          if (sheetDateRange != null) activeCount++;
          if (sheetSortBy != 'mostPopular') activeCount++;

          // ── Date range display string ─────────────────────────
          String dateLabel = 'Date range';
          bool dateHasValue = sheetDateRange != null;
          if (dateHasValue) {
            final s = sheetDateRange!.start;
            final e = sheetDateRange!.end;
            final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
            dateLabel = '${s.day} ${months[s.month-1]} ${s.year} – ${e.day} ${months[e.month-1]} ${e.year}';
          }

          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Container(
              color: bgSheet,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.93,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // ══ STICKY HEADER ══════════════════════════════
                  Container(
                    color: bgSheet,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 10),
                          child: Center(
                            child: Container(
                              width: 36, height: 4,
                              decoration: BoxDecoration(
                                color: HuddlColors.divider,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        // Header row: close | title | RESET
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                          child: Row(
                            children: [
                              // Bare orange X — Figma-exact (no circle background)
                              GestureDetector(
                                onTap: () => Navigator.pop(ctx),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(Icons.close_rounded, size: 20, color: orange),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Filter and sort',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setSheetState(() {
                                    sheetLocalization  = 'none';
                                    sheetDistanceKm    = 10.0;
                                    sheetCategories    = {};
                                    sheetParticipants  = {};
                                    sheetFreeOnly      = false;
                                    sheetDateRange     = null;
                                    sheetSortBy        = 'mostPopular';
                                  });
                                },
                                child: Text(
                                  'RESET',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: orange,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: dividerColor),
                      ],
                    ),
                  ),

                  // ══ SCROLLABLE CONTENT ═════════════════════════
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          // ══ SECTION 1 — LOCALIZATION ═══════════
                          sectionHeading('Localization'),
                          Row(
                            children: [
                              locChip('Online', 'online'),
                              const SizedBox(width: 10),
                              locChip('Live', 'live'),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // ══ SECTION 2 — DISTANCE ═══════════════
                          Row(
                            children: [
                              Text(
                                'Distance',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: isOnline ? textSecGray : textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Distance tick labels
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: ['1 km', '5 km', '10 km', '<50 km'].map((t) => Text(
                              t,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: isOnline ? textSecGray : textPrimary,
                              ),
                            )).toList(),
                          ),
                          const SizedBox(height: 4),
                          // Slider
                          SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              activeTrackColor: isOnline ? trackInactive : orange,
                              inactiveTrackColor: trackInactive,
                              thumbColor: isOnline ? textSecGray : orange,
                              overlayColor: orange.withValues(alpha: 0.15),
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                            ),
                            child: Slider(
                              value: [1.0, 5.0, 10.0, 50.0].reduce(
                                (a, b) => (a - sheetDistanceKm).abs() < (b - sheetDistanceKm).abs() ? a : b,
                              ),
                              min: 1,
                              max: 50,
                              divisions: 3,
                              onChanged: isOnline ? null : (v) {
                                setSheetState(() {
                                  // snap to 4 discrete values
                                  final snapped = [1.0, 5.0, 10.0, 50.0].reduce(
                                    (a, b) => (a - v).abs() < (b - v).abs() ? a : b,
                                  );
                                  sheetDistanceKm = snapped;
                                });
                              },
                            ),
                          ),
                          // Online info message
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            child: isOnline
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.info_outline_rounded, size: 16, color: orange),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Online events have no distance',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: orange,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 28),

                          // ══ SECTION 3 — PARTICIPANTS ════════════
                          sectionHeading('Participants'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: _participantOptions.map((p) {
                              final sel = sheetParticipants.contains(p);
                              return filterChip(
                                label: p,
                                isSelected: sel,
                                onTap: () => setSheetState(() {
                                  if (sel) { sheetParticipants.remove(p); }
                                  else { sheetParticipants.add(p); }
                                }),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 28),

                          // ══ SECTION 4 — CATEGORY ════════════════
                          sectionHeading('Category'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: _categoryChips
                                .where((c) => (c['label'] as String) != 'All')
                                .map((chip) {
                              final label = chip['label'] as String;
                              final icon  = catIcons[label] ?? Icons.label_outline;
                              final sel   = sheetCategories.contains(label);
                              return filterChip(
                                label: label,
                                isSelected: sel,
                                icon: icon,
                                iconColor: blue,
                                onTap: () {
                                  setSheetState(() {
                                    if (sel) { sheetCategories.remove(label); }
                                    else { sheetCategories.add(label); }
                                  });
                                  _aiService.trackCategoryTap(label);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 28),

                          // ══ SECTION 5 — SHOW FREE ONLY ══════════
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Show only free events',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              Switch(
                                value: sheetFreeOnly,
                                onChanged: (v) => setSheetState(() => sheetFreeOnly = v),
                                activeThumbColor: Colors.white,
                                activeTrackColor: orange,
                                inactiveThumbColor: Colors.white,
                                inactiveTrackColor: toggleOff,
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // ══ SECTION 6 — PICK A DATE ══════════════
                          sectionHeading('Pick a date'),
                          GestureDetector(
                            onTap: () async {
                              final picked = await showDateRangePicker(
                                context: ctx,
                                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                                initialDateRange: sheetDateRange,
                                builder: (context, child) => Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: Theme.of(context).colorScheme.copyWith(
                                      primary: orange,
                                      onPrimary: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                setSheetState(() => sheetDateRange = picked);
                              }
                            },
                            child: Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: HuddlColors.divider, width: 1),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: dateHasValue
                                        ? Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Date range',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 12,
                                                  color: textSecGray,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                dateLabel,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 15,
                                                  color: textPrimary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            'Date range',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: textSecGray,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                  ),
                                  Icon(Icons.calendar_month_outlined, color: orange, size: 22),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // ══ SECTION 7 — SORT BY ══════════════════
                          sectionHeading('Sort by'),
                          radioRow('Most popular', 'mostPopular'),
                          Divider(height: 1, thickness: 1, color: dividerColor),
                          radioRow('Latest', 'latest'),

                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),

                  // ══ STICKY BOTTOM CTA ═══════════════════════════
                  Container(
                    decoration: BoxDecoration(
                      color: bgSheet,
                      border: Border(top: BorderSide(color: dividerColor, width: 1)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4))],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              _localization      = sheetLocalization;
                              _distanceKm        = sheetDistanceKm;
                              _sheetCategories
                                ..clear()
                                ..addAll(sheetCategories);
                              _sheetParticipants
                                ..clear()
                                ..addAll(sheetParticipants);
                              _showFreeOnly      = sheetFreeOnly;
                              _dateRange         = sheetDateRange;
                              _sortBy            = sheetSortBy;
                            });
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: orange,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              activeCount > 0
                                  ? 'Show results · $activeCount filter${activeCount > 1 ? 's' : ''}'
                                  : 'Show results',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final visible = _visibleMeetups;
    var filtered = _applyFilters(visible);

    // ── B) Smart Sort: AI silently reorders meetups ──────────────
    // Skip AI sort when user has explicitly chosen a sort order in the filter sheet
    List<ScoredMeetup> scored = [];
    if (_aiReady) {
      if (_sortBy == 'mostPopular') {
        // Default sort — let AI boost personalised results
        scored = _aiService.smartSort(filtered);
        filtered = scored.map((s) => s.meetup).toList();
      }
      // ── E) Smart Nudge: contextual one-liner ────────────────
      _activeNudge = _aiService.getSmartNudge(visible);
    }

    // Build a map from meetup id to boost reason for card display
    final boostReasons = <String, String>{};
    for (final s in scored) {
      if (s.boostReason != null) boostReasons[s.meetup.id] = s.boostReason!;
    }

    // ── Figma design tokens ────────────────────────────────────────
    const Color filterText  = Color(0xFF42464C); // Figma: dark text
    const Color sectionText = Color(0xFF42464C); // Figma: "Black" grayscale

    return Column(
      children: [
        // ══ TOP HEADER — filter pill + inline search ══════════════════════════
        Container(
          color: context.hc.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Filter pill ↔ inline search (AnimatedCrossFade) ─────────
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: _isSearchActive
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Row(
                  children: [
                    Semantics(
                      label: _hasActiveFilter
                          ? 'Filters active. Tap to change.'
                          : 'Filter meetups',
                      button: true,
                      child: GestureDetector(
                        onTap: () => _showFilterSheet(context),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: _hasActiveFilter
                                    ? HuddlColors.primary
                                    : filterText,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _hasActiveFilter && _filterPillLabel.isNotEmpty
                                    ? _filterPillLabel
                                    : 'Filter and sort',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: _hasActiveFilter
                                      ? HuddlColors.primary
                                      : filterText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                // ── Inline search pill ────────────────────────────────────
                secondChild: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: HuddlColors.background,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                              color: HuddlColors.primary.withValues(alpha: 0.35),
                              width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            const Icon(Icons.search, size: 18,
                                color: HuddlColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _localSearchController,
                                focusNode: _searchFocusNode,
                                onChanged: (v) =>
                                    setState(() => _localSearchQuery = v),
                                style: GoogleFonts.poppins(
                                    fontSize: 14, color: filterText),
                                decoration: InputDecoration(
                                  hintText: 'Search meetups…',
                                  hintStyle: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: HuddlColors.textTertiary),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            if (_localSearchQuery.isNotEmpty)
                              GestureDetector(
                                onTap: () => setState(() {
                                  _localSearchQuery = '';
                                  _localSearchController.clear();
                                }),
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 10),
                                  child: Icon(Icons.close, size: 16,
                                      color: HuddlColors.textTertiary),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _clearSearch,
                      child: Text('Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Active participant badge (set via filter sheet) ──────────
              if (_selectedParticipant != 'All') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: HuddlColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: HuddlColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline,
                              size: 14, color: HuddlColors.primary),
                          const SizedBox(width: 5),
                          Text(_selectedParticipant,
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.primary)),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() => _selectedParticipant = 'All');
                            },
                            child: const Icon(Icons.close,
                                size: 14, color: HuddlColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              // ── Section label ───────────────────────────────────────────
              Text(
                _localSearchQuery.isEmpty
                    ? 'Suggested for you'
                    : 'Search results',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: sectionText,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // Smart Nudge / trending banner removed — surfaced in Home feed instead.

        // ── List — light gray scaffold bg ─────────────────────────
        Expanded(
          child: ColoredBox(
            color: HuddlColors.background,
            child: filtered.isEmpty
                ? _EmptyState(
                    icon: _hasActiveFilter ? Icons.filter_list_off : Icons.groups_outlined,
                    illustration: HuddlIllustration.meetup,
                    title: _hasActiveFilter ? 'No meetups match' : 'No meet-ups yet',
                    subtitle: _hasActiveFilter
                        ? 'Try adjusting your filters to see more meetups.'
                        : 'Organise a casual get-together with\nother parents in your area.',
                    actionLabel: _hasActiveFilter ? 'Clear filters' : 'Create Meet-up',
                    onAction: _hasActiveFilter
                        ? () => setState(() {
                              _selectedCategory = 'All';
                              _selectedParticipant = 'All';
                            })
                        : widget.onCreateMeetup,
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await _loadUserContext();
                      if (mounted) setState(() {});
                    },
                    color: HuddlColors.primary,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
        item.isMeetup ? HuddlColors.primary : HuddlColors.teal;

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
/// exactly — same borderRadius, primary-tint bg, fallback icon pattern.
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
        color: HuddlColors.primary.withValues(alpha: 0.08),
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
      color: HuddlColors.primary.withValues(alpha: 0.08),
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
  /// Optional search notifier passed from the Connect screen shared search bar.
  final ValueNotifier<String>? searchNotifier;
  const ImGoingTab({super.key, this.searchNotifier});

  @override
  State<ImGoingTab> createState() => _ImGoingTabWrapperState();
}

class _ImGoingTabWrapperState extends State<ImGoingTab> {
  final MeetupService _meetupService = MeetupService();
  final EventService _eventService = EventService();
  // Rebuild key — incremented on every cancel to force list rebuild
  int _rebuildKey = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Defer listener registration to avoid setState-during-build crash.
    // MeetupService._loadPersistedMeetups() calls notifyListeners() async
    // from its constructor and may complete during the first build frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _meetupService.addListener(_refresh);
      _eventService.addListener(_refresh);
      widget.searchNotifier?.addListener(_onSearchChanged);
      // Restore RSVP state from Firestore so "I'm Going" survives reinstall
      _meetupService.syncRsvpsFromFirestore();
      _eventService.syncRsvpsFromFirestore();
    });
  }

  @override
  void dispose() {
    _meetupService.removeListener(_refresh);
    _eventService.removeListener(_refresh);
    widget.searchNotifier?.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => _rebuildKey++);
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {
        _searchQuery = widget.searchNotifier?.value ?? '';
      });
    }
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

  /// Apply query filter to a list of going items.
  List<_GoingItem> _filter(List<_GoingItem> items) {
    if (_searchQuery.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    return items.where((i) =>
        i.title.toLowerCase().contains(q) ||
        i.location.toLowerCase().contains(q) ||
        i.organiser.toLowerCase().contains(q)).toList();
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

    // Apply search filter
    final filtered = _filter(allGoing);

    final upcoming = filtered.where((i) => i.dateTime.isAfter(now)).toList();
    final past = filtered.where((i) => !i.dateTime.isAfter(now)).toList();

    if (allGoing.isEmpty) {
      return _EmptyState(
        icon: Icons.event_available_outlined,
        illustration: HuddlIllustration.events,
        title: "You're not going to anything yet",
        subtitle:
            "Tap 'Count Me In' on a meetup or event to add it here!",
      );
    }

    // Search active but no matches
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: context.hc.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No results for "$_searchQuery"',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.hc.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different keyword',
              style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textTertiary),
            ),
          ],
        ),
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

  const _EventsTab({required this.eventService});

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

  // ── Manual filter state (set via bottom sheet) ─────────────
  String _priceFilter = 'All';   // All | Free | Paid
  String _formatFilter = 'All';  // All | Online | In-Person

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
            backgroundColor: HuddlColors.teal,
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
    final parentQuery = ''; // search now handled by in-tab search bar
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

    // Apply manual filters (set via chip row or bottom-sheet)
    if (_activeManualFilter != 'All') {
      events = events.where((e) {
        if (_activeManualFilter == 'Free') return e['isFree'] == true;
        if (_activeManualFilter == 'Paid') return e['isFree'] != true;
        if (_activeManualFilter == 'Online') return e['isOnline'] == true;
        if (_activeManualFilter == 'In-Person') return e['isOnline'] != true;
        return true;
      }).toList();
    }
    // Apply bottom-sheet price filter
    if (_priceFilter != 'All') {
      events = events.where((e) {
        if (_priceFilter == 'Free') return e['isFree'] == true;
        if (_priceFilter == 'Paid') return e['isFree'] != true;
        return true;
      }).toList();
    }
    // Apply bottom-sheet format filter
    if (_formatFilter != 'All') {
      events = events.where((e) {
        if (_formatFilter == 'Online') return e['isOnline'] == true;
        if (_formatFilter == 'In-Person') return e['isOnline'] != true;
        return true;
      }).toList();
    }

    // Intelligent sort (AI-powered ranking)
    if (_recommenderReady && events.isNotEmpty) {
      events = _invisibleAi.intelligentSort(events, _scoredEventMap);
    }

    // Show carousel only when clean state (no active search/filter)
    final showCarousel = _recommenderReady &&
        _recommended.isNotEmpty &&
        parentQuery.isEmpty &&
        _nlpQuery.isEmpty &&
        _activeManualFilter == 'All' &&
        _priceFilter == 'All' &&
        _formatFilter == 'All';

    // Whether bottom-sheet filters are active
    final bool hasSheetFilters = _priceFilter != 'All' || _formatFilter != 'All';
    final int sheetFilterCount = (_priceFilter != 'All' ? 1 : 0) + (_formatFilter != 'All' ? 1 : 0);

    // Active filter chips for NLP
    final activeNlpChips = _buildActiveNlpChips();

    // ── Accent colour for "Clear All" text ─────────────────────
    const Color clearAllOrange = HuddlColors.primary;

    return Column(
      children: [
        // ── Premium header bar: search + filter/sort row ──────────
        Container(
          color: context.hc.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: NLP search bar
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: context.hc.inputBg,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextField(
                  controller: _nlpController,
                  focusNode: _nlpFocusNode,
                  onChanged: _onNlpQueryChanged,
                  textAlignVertical: TextAlignVertical.center,
                  style: GoogleFonts.poppins(fontSize: 13.5, color: context.hc.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search events...',
                    hintStyle: GoogleFonts.poppins(fontSize: 13.5, color: context.hc.textTertiary),
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: context.hc.textTertiary.withValues(alpha: 0.7)),
                    suffixIcon: _nlpQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: _clearSearch,
                            child: Icon(Icons.close_rounded, size: 18, color: context.hc.textTertiary),
                          )
                        : null,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Row 2: "Filter and sort" pill + "Clear All" text
              Row(
                children: [
                  // Filter and sort pill button
                  Semantics(
                    label: hasSheetFilters
                        ? 'Filters active ($sheetFilterCount). Tap to change.'
                        : 'Filter and sort events',
                    button: true,
                    child: GestureDetector(
                      onTap: () => _showEventsFilterSheet(context),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: hasSheetFilters
                              ? HuddlColors.primary.withValues(alpha: 0.08)
                              : context.hc.surfaceAlt,
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(
                            color: hasSheetFilters
                                ? HuddlColors.primary.withValues(alpha: 0.35)
                                : context.hc.divider,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 16,
                              color: hasSheetFilters
                                  ? HuddlColors.primary
                                  : context.hc.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              hasSheetFilters
                                  ? 'Filter and sort ($sheetFilterCount)'
                                  : 'Filter and sort',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: hasSheetFilters
                                    ? HuddlColors.primary
                                    : context.hc.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // "Clear All" — only visible when any filter/search is active
                  if (hasSheetFilters || _activeManualFilter != 'All' || _nlpQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _priceFilter = 'All';
                          _formatFilter = 'All';
                          _activeManualFilter = 'All';
                        });
                        _clearSearch();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text(
                          'Clear All',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: clearAllOrange,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
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

        // ── Filter chips row (always visible, premium style) ──────
        Container(
          color: context.hc.surface,
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _invisibleAi.adaptiveFilterOrder.map((f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: f,
                  isSelected: _activeManualFilter == f ||
                      (f == 'Free' && _priceFilter == 'Free') ||
                      (f == 'Paid' && _priceFilter == 'Paid') ||
                      (f == 'Online' && _formatFilter == 'Online') ||
                      (f == 'In-Person' && _formatFilter == 'In-Person'),
                  // Events tab uses blue active chips (reference design)
                  selectedColor: HuddlColors.blueDark,
                  onTap: () {
                    _invisibleAi.trackFilterClick(f);
                    setState(() {
                      _priceFilter = 'All';
                      _formatFilter = 'All';
                      _activeManualFilter = (_activeManualFilter == f) ? 'All' : f;
                    });
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
                    strokeWidth: 2, color: HuddlColors.teal),
                ),
                const SizedBox(width: 8),
                Text(
                  'Finding events for you\u2026',
                  style: GoogleFonts.poppins(
                    fontSize: 12, color: HuddlColors.teal, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

        // ── Event list (off-white #F7F7F7 background) ────────────
        Expanded(
          child: ColoredBox(
            color: HuddlColors.background,
            child: events.isEmpty && !showCarousel
                ? _EmptyState(
                    icon: hasSheetFilters || _activeManualFilter != 'All'
                        ? Icons.filter_list_off
                        : Icons.event_outlined,
                    illustration: HuddlIllustration.events,
                    title: _nlpQuery.isNotEmpty
                        ? 'No matches'
                        : (hasSheetFilters || _activeManualFilter != 'All')
                            ? 'No events match your filters'
                            : 'No events found',
                    subtitle: _nlpQuery.isNotEmpty
                        ? 'Try a different search like\n"free baby classes near me"'
                        : (hasSheetFilters || _activeManualFilter != 'All')
                            ? 'Try adjusting or clearing your filters.'
                            : 'Pull down to refresh or try searching.',
                    actionLabel: _nlpQuery.isNotEmpty
                        ? 'Clear search'
                        : (hasSheetFilters || _activeManualFilter != 'All')
                            ? 'Clear filters'
                            : null,
                    onAction: _nlpQuery.isNotEmpty
                        ? _clearSearch
                        : (hasSheetFilters || _activeManualFilter != 'All')
                            ? () => setState(() {
                                  _priceFilter = 'All';
                                  _formatFilter = 'All';
                                  _activeManualFilter = 'All';
                                })
                            : null,
                  )
                : RefreshIndicator(
                    onRefresh: _forceRefreshDiscovery,
                    color: HuddlColors.primary,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
        ),
      ],
    );
  }

  String _activeManualFilter = 'All';

  // ── Extended Events filter state (mirrors Meetup filter Figma) ─
  String        _evLocalization    = 'none';   // 'none' | 'online' | 'live'
  double        _evDistanceKm      = 10.0;
  final Set<String>   _evParticipants    = {};
  final Set<String>   _evCategories      = {};
  bool          _evFreeOnly        = false;
  DateTimeRange? _evDateRange;
  String        _evSortBy          = 'mostPopular'; // 'mostPopular' | 'latest'

  // ── Events filter bottom sheet — Figma-exact ─────────────────
  void _showEventsFilterSheet(BuildContext context) {
    HapticFeedback.selectionClick();

    // Snapshot all state into local sheet vars
    String         sheetLocalization  = _evLocalization;
    double         sheetDistanceKm    = _evDistanceKm;
    Set<String>    sheetParticipants  = Set<String>.from(_evParticipants);
    Set<String>    sheetCategories    = Set<String>.from(_evCategories);
    bool           sheetFreeOnly      = _evFreeOnly;
    DateTimeRange? sheetDateRange     = _evDateRange;
    String         sheetSortBy        = _evSortBy;
    // Legacy price/format preserved for existing filter logic
    String         sheetPrice         = _priceFilter;
    String         sheetFormat        = _formatFilter;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {

          // ══ DESIGN TOKENS — Figma styleguide exact ════════════
          const Color bgSheet      = Colors.white;
          const Color orange       = Color(0xFFFF965C);  // Figma: "Dark orange" — primary brand
          const Color blue         = Color(0xFF347FEF);  // Figma: "Dark blue" — selected state
          const Color textPrimary  = Color(0xFF42464C);  // Figma: "Black" grayscale
          const Color textSecGray  = Color(0xFF949494);  // Figma: light gray
          const Color chipBg       = Color(0xFFF6F6F6);  // Figma: page bg = unselected chip
          const Color dividerColor = Color(0xFFD5D5D5);  // Figma: grayscale divider
          const Color trackInactive= Color(0xFFD5D5D5);
          const Color toggleOff    = Color(0xFFD5D5D5);

          final bool isOnline = sheetLocalization == 'online';

          // ── Section heading ────────────────────────────────────
          Widget sectionHeading(String title) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
          );

          // ── Localization chip ──────────────────────────────────
          Widget locChip(String label, String value) {
            final sel = sheetLocalization == value;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setSheetState(() {
                  sheetLocalization = (sheetLocalization == value) ? 'none' : value;
                  // Sync legacy format filter
                  if (sheetLocalization == 'online') {
                    sheetFormat = 'Online';
                  } else if (sheetLocalization == 'live') {
                    sheetFormat = 'In-Person';
                  } else {
                    sheetFormat = 'All';
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? blue : chipBg,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel ? Colors.white : textPrimary,
                  ),
                ),
              ),
            );
          }

          // ── Filter chip (multi-select) ─────────────────────────
          Widget filterChip({
            required String label,
            required bool isSelected,
            required VoidCallback onTap,
            IconData? icon,
          }) {
            return GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); onTap(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: icon != null ? 12 : 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? HuddlColors.textDark : chipBg,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 15,
                          color: isSelected ? Colors.white : blue),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? Colors.white : textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Radio row ──────────────────────────────────────────
          Widget radioRow(String label, String value) {
            final sel = sheetSortBy == value;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                setSheetState(() => sheetSortBy = value);
              },
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label,
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: textPrimary)),
                    ),
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? orange : HuddlColors.divider,
                          width: sel ? 0 : 1.5,
                        ),
                        color: sel ? orange : Colors.transparent,
                      ),
                      child: sel
                          ? const Center(
                              child: CircleAvatar(radius: 4, backgroundColor: Colors.white))
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Category icon map ──────────────────────────────────
          const Map<String, IconData> catIcons = {
            'Hanging out':         Icons.chat_bubble_outline_rounded,
            'Pregnancy':           Icons.pregnant_woman_outlined,
            'Playdate':            Icons.directions_run_rounded,
            'Sports & exercise':   Icons.fitness_center_outlined,
            'Coffee & tea':        Icons.coffee_outlined,
            'Parks & Walks':       Icons.park_outlined,
            'Performance & shows': Icons.theater_comedy_outlined,
          };

          const List<String> participantOptions = [
            'Mums', 'Dads', 'Kids', 'Aspiring parents', 'Expecting parents',
          ];

          // ── Active count for CTA label ─────────────────────────
          int activeCount = 0;
          if (sheetLocalization != 'none') activeCount++;
          if (sheetParticipants.isNotEmpty) activeCount++;
          if (sheetCategories.isNotEmpty) activeCount++;
          if (sheetFreeOnly) activeCount++;
          if (sheetDateRange != null) activeCount++;
          if (sheetSortBy != 'mostPopular') activeCount++;

          // ── Date label ─────────────────────────────────────────
          final bool dateHasValue = sheetDateRange != null;
          String dateLabel = 'Date range';
          if (dateHasValue) {
            final s = sheetDateRange!.start;
            final e = sheetDateRange!.end;
            const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
            dateLabel = '${s.day} ${months[s.month]} ${s.year} – ${e.day} ${months[e.month]} ${e.year}';
          }

          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Container(
              color: bgSheet,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.93,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // ══ STICKY HEADER ══════════════════════════════
                  Container(
                    color: bgSheet,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 10),
                          child: Center(
                            child: Container(
                              width: 36, height: 4,
                              decoration: BoxDecoration(
                                color: HuddlColors.divider,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                          child: Row(
                            children: [
                              // Bare orange X — Figma-exact (no circle background)
                              GestureDetector(
                                onTap: () => Navigator.pop(ctx),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(Icons.close_rounded, size: 20, color: orange),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('Filter and sort',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary)),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setSheetState(() {
                                    sheetLocalization = 'none';
                                    sheetDistanceKm   = 10.0;
                                    sheetParticipants = {};
                                    sheetCategories   = {};
                                    sheetFreeOnly     = false;
                                    sheetDateRange    = null;
                                    sheetSortBy       = 'mostPopular';
                                    sheetPrice        = 'All';
                                    sheetFormat       = 'All';
                                  });
                                  setState(() {
                                    _priceFilter  = 'All';
                                    _formatFilter = 'All';
                                    _activeManualFilter = 'All';
                                  });
                                },
                                child: Text('RESET',
                                    style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: orange,
                                        letterSpacing: 0.3)),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: dividerColor),
                      ],
                    ),
                  ),

                  // ══ SCROLLABLE CONTENT ═════════════════════════
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          // ── SECTION 1: LOCALIZATION ────────────
                          sectionHeading('Localization'),
                          Row(children: [
                            locChip('Online', 'online'),
                            const SizedBox(width: 10),
                            locChip('Live', 'live'),
                          ]),
                          const SizedBox(height: 28),

                          // ── SECTION 2: DISTANCE ────────────────
                          Text('Distance',
                              style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: isOnline ? textSecGray : textPrimary)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: ['1 km','5 km','10 km','<50 km'].map((t) =>
                              Text(t, style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: isOnline ? textSecGray : textPrimary))
                            ).toList(),
                          ),
                          const SizedBox(height: 4),
                          SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              activeTrackColor: isOnline ? trackInactive : orange,
                              inactiveTrackColor: trackInactive,
                              thumbColor: isOnline ? textSecGray : orange,
                              overlayColor: orange.withValues(alpha: 0.15),
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                            ),
                            child: Slider(
                              value: [1.0,5.0,10.0,50.0].reduce(
                                  (a,b) => (a-sheetDistanceKm).abs()<(b-sheetDistanceKm).abs()?a:b),
                              min: 1, max: 50, divisions: 3,
                              onChanged: isOnline ? null : (v) {
                                setSheetState(() {
                                  sheetDistanceKm = [1.0,5.0,10.0,50.0].reduce(
                                      (a,b) => (a-v).abs()<(b-v).abs()?a:b);
                                });
                              },
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            child: isOnline
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                                  child: Row(children: [
                                    Icon(Icons.info_outline_rounded, size: 16, color: orange),
                                    const SizedBox(width: 6),
                                    Text('Online events have no distance',
                                        style: GoogleFonts.poppins(
                                            fontSize: 13, color: orange)),
                                  ]),
                                )
                              : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 28),

                          // ── SECTION 3: PARTICIPANTS ────────────
                          sectionHeading('Participants'),
                          Wrap(
                            spacing: 8, runSpacing: 10,
                            children: participantOptions.map((p) {
                              final sel = sheetParticipants.contains(p);
                              return filterChip(
                                label: p, isSelected: sel,
                                onTap: () => setSheetState(() {
                                  if (sel) { sheetParticipants.remove(p); }
                                  else { sheetParticipants.add(p); }
                                }),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 28),

                          // ── SECTION 4: CATEGORY ────────────────
                          sectionHeading('Category'),
                          Wrap(
                            spacing: 8, runSpacing: 10,
                            children: catIcons.entries.map((e) {
                              final sel = sheetCategories.contains(e.key);
                              return filterChip(
                                label: e.key, isSelected: sel, icon: e.value,
                                onTap: () => setSheetState(() {
                                  if (sel) { sheetCategories.remove(e.key); }
                                  else { sheetCategories.add(e.key); }
                                }),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 28),

                          // ── SECTION 5: SHOW FREE ONLY ──────────
                          Row(children: [
                            Expanded(
                              child: Text('Show only free events',
                                  style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary)),
                            ),
                            Switch(
                              value: sheetFreeOnly,
                              onChanged: (v) => setSheetState(() {
                                sheetFreeOnly = v;
                                sheetPrice = v ? 'Free' : 'All';
                              }),
                              activeThumbColor: Colors.white,
                              activeTrackColor: orange,
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: toggleOff,
                            ),
                          ]),
                          const SizedBox(height: 28),

                          // ── SECTION 6: PICK A DATE ─────────────
                          sectionHeading('Pick a date'),
                          GestureDetector(
                            onTap: () async {
                              final picked = await showDateRangePicker(
                                context: ctx,
                                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                                initialDateRange: sheetDateRange,
                                builder: (context, child) => Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: Theme.of(context).colorScheme.copyWith(
                                      primary: orange,
                                      onPrimary: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                setSheetState(() => sheetDateRange = picked);
                              }
                            },
                            child: Container(
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(
                                    color: HuddlColors.divider, width: 1)),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(children: [
                                Expanded(
                                  child: dateHasValue
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Date range',
                                              style: GoogleFonts.poppins(
                                                  fontSize: 12,
                                                  color: textSecGray)),
                                          const SizedBox(height: 2),
                                          Text(dateLabel,
                                              style: GoogleFonts.poppins(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
                                                  color: textPrimary)),
                                        ],
                                      )
                                    : Text('Date range',
                                        style: GoogleFonts.poppins(
                                            fontSize: 14, color: textSecGray)),
                                ),
                                Icon(Icons.calendar_month_outlined,
                                    color: orange, size: 22),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // ── SECTION 7: SORT BY ─────────────────
                          sectionHeading('Sort by'),
                          radioRow('Most popular', 'mostPopular'),
                          Divider(height: 1, thickness: 1, color: dividerColor),
                          radioRow('Latest', 'latest'),
                          const SizedBox(height: 8),

                        ],
                      ),
                    ),
                  ),

                  // ══ STICKY BOTTOM CTA ═════════════════════════
                  Container(
                    decoration: BoxDecoration(
                      color: bgSheet,
                      border: Border(top: BorderSide(color: dividerColor, width: 1)),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12, offset: const Offset(0, -4))],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              // Commit extended filter state
                              _evLocalization = sheetLocalization;
                              _evDistanceKm   = sheetDistanceKm;
                              _evParticipants
                                ..clear()
                                ..addAll(sheetParticipants);
                              _evCategories
                                ..clear()
                                ..addAll(sheetCategories);
                              _evFreeOnly   = sheetFreeOnly;
                              _evDateRange  = sheetDateRange;
                              _evSortBy     = sheetSortBy;
                              // Also commit legacy filters for existing Events filter logic
                              _priceFilter  = sheetPrice;
                              _formatFilter = sheetFormat;
                              if (sheetLocalization == 'online') {
                                _activeManualFilter = 'Online';
                              } else if (sheetLocalization == 'live') {
                                _activeManualFilter = 'In-Person';
                              } else {
                                if (_activeManualFilter == 'Online' ||
                                    _activeManualFilter == 'In-Person') {
                                  _activeManualFilter = 'All';
                                }
                              }
                            });
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: orange,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              activeCount > 0
                                  ? 'Show results · $activeCount filter${activeCount > 1 ? 's' : ''}'
                                  : 'Show results',
                              style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.2),
                            ),
                          ),
                        ),
                      ),
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

    if (p.containsKey('priceFilter')) addChip(p['priceFilter'] as String, HuddlColors.teal);
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
        // ── "Suggested for you" section header ────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            'Suggested for you',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.hc.textPrimary,
            ),
          ),
        ),
        // Horizontal carousel
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: scoredEvents.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final scored = scoredEvents[index];
              return _RecommendedCard(scored: scored);
            },
          ),
        ),
        const SizedBox(height: 24),
        // "All Events" divider label
        Text(
          'All Events',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.hc.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
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
        width: 230,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image — taller for premium feel
            SizedBox(
              height: 128,
              width: double.infinity,
              child: _buildCoverImage(
                imageUrl: event.imageUrl,
                fallbackIcon: event.icon,
                fallbackColor: HuddlColors.primary,
              ),
            ),
            // Card body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date — light grey
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 11, color: HuddlColors.textTertiary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            event.dateDisplay,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: HuddlColors.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          event.isFree ? 'Free' : event.price,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: event.isFree ? HuddlColors.teal : HuddlColors.blueDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      event.title,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.textDark,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                              color: HuddlColors.teal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: HuddlColors.teal.withValues(alpha: 0.2),
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
                                      color: HuddlColors.teal,
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

  // ── Design tokens (Figma-exact) ────────────────────────────────
  static const _cardOrange  = HuddlColors.primary;     // brand orange — Figma #FF965C
  static const _cardText    = HuddlColors.textDark;     // primary dark text — Figma #42464C
  static const _cardMeta    = HuddlColors.textTertiary; // secondary gray meta — Figma #949494

  @override
  Widget build(BuildContext context) {
    final catStyle = _meetupCategoryStyle(meetup.category);
    final isRestricted = !canAccess;

    // Price display
    final priceText = meetup.isFree
        ? 'Free'
        : '\u00A3${meetup.price?.toStringAsFixed(0) ?? ''}';
    final isFree = meetup.isFree;

    // Date + time display: "1 MAY 2021  |  10 AM – 6 PM"
    final dateStr = meetup.dateDisplay.toUpperCase();
    final timeStr = meetup.timeDisplay;

    return Semantics(
      label: 'Meetup: ${meetup.title}, ${meetup.dateDisplay} ${meetup.timeDisplay}, ${meetup.location}, organised by ${meetup.organiserName}${isRestricted ? ", restricted access" : ""}',
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onView?.call();
          if (isRestricted) {
            onAccessDenied?.call();
            return;
          }
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => MeetupDetailScreen(meetup: meetup),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
              transitionDuration: const Duration(milliseconds: 300),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero image with badge overlay ───────────────────────
              SizedBox(
                height: 185,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'meetup_cover_${meetup.id}',
                      child: _buildCoverImage(
                        imageUrl: meetup.imageUrl.isNotEmpty
                            ? meetup.imageUrl
                            : _GoingItem._meetupCategoryImage(meetup.category),
                        fallbackIcon: catStyle.icon,
                        fallbackColor: catStyle.color,
                      ),
                    ),
                    // Badge row — top-left (only show "Private" when restricted)
                    if (isRestricted)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_outline, size: 11, color: Colors.white),
                              const SizedBox(width: 3),
                              Text('Private',
                                style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Card body ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date + time row
                    Text(
                      '$dateStr  |  $timeStr',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: _cardMeta,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Title
                    Text(
                      meetup.title,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _cardText,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Location row
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: _cardMeta),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            meetup.location,
                            style: GoogleFonts.poppins(fontSize: 13, color: _cardMeta),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Attendees + price row
                    Row(
                      children: [
                        // Avatar stack placeholder circles
                        SizedBox(
                          width: 60,
                          height: 24,
                          child: Stack(
                            children: List.generate(3, (i) => Positioned(
                              left: i * 16.0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: [
                                    HuddlColors.primary,
                                    HuddlColors.blueUI,
                                    HuddlColors.textTertiary,
                                  ][i],
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: Icon(Icons.person, size: 13, color: Colors.white),
                              ),
                            )).reversed.toList(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${meetup.attendeeCount} interested',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _cardText,
                          ),
                        ),
                        const Spacer(),
                        // Price
                        Text(
                          priceText,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isFree ? _cardOrange : _cardText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Single "Join" button — consistent with Groups tab
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onView?.call();
                          if (isRestricted) {
                            onAccessDenied?.call();
                            return;
                          }
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) => MeetupDetailScreen(meetup: meetup),
                              transitionsBuilder: (_, anim, __, child) =>
                                  FadeTransition(opacity: anim, child: child),
                              transitionDuration: const Duration(milliseconds: 300),
                            ),
                          );
                        },
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: isRestricted
                                ? null
                                : const LinearGradient(
                                    colors: [HuddlColors.primaryLight, HuddlColors.primary],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                            color: isRestricted ? HuddlColors.divider : null,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              'Join',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isRestricted ? HuddlColors.textTertiary : Colors.white,
                              ),
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
Shared from Huddl
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
                color: HuddlColors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: HuddlColors.teal.withValues(alpha: 0.2),
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
                      color: HuddlColors.teal,
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
    const Color eventTypeBlue = HuddlColors.blueDark;
    const Radius cardRadius = Radius.circular(20);
    final bool isFree = event['isFree'] == true;
    final bool isOnline = event['isOnline'] == true;
    final String organiser = event['organiser'] as String? ?? '';
    final String imageUrl = event['imageUrl'] as String? ?? '';
    final String eventId = event['id'] as String? ?? '';
    final String borough = event['borough'] as String? ?? '';
    final int attendees = event['attendees'] as int? ?? 0;
    // "New" badge: events with fewer than 10 attendees are considered newly listed
    final bool isNew = attendees < 10;
    final String priceLabel = isFree ? 'Free' : (event['price'] as String? ?? '');

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
        child: Container(
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.all(cardRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero cover image — tall, full-bleed ──────────────────
              Stack(
                children: [
                  SizedBox(
                    height: 190,
                    width: double.infinity,
                    child: Hero(
                      tag: 'event_cover_$eventId',
                      child: _buildCoverImage(
                        imageUrl: imageUrl,
                        fallbackIcon: event['icon'] as IconData,
                        fallbackColor: eventTypeBlue,
                      ),
                    ),
                  ),
                  // Subtle bottom gradient over image for readability
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.22),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // ── Tag chips overlaid top-left ──────────────────────
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Row(
                      children: [
                        if (isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: HuddlColors.accentAmber,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'New',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (isNew) const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: eventTypeBlue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isOnline ? 'Online' : 'Event',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Price badge top-right ────────────────────────────
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isFree
                            ? HuddlColors.teal
                            : Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        priceLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isFree ? Colors.white : eventTypeBlue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Card body ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date + time row — light grey
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 13, color: HuddlColors.textTertiary),
                        const SizedBox(width: 5),
                        Text(
                          '${event['date'] as String}  ·  ${event['time'] as String}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: HuddlColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Bold event title — 2-line max
                    Text(
                      event['title'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.hc.textPrimary,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Location row with outline pin
                    Row(
                      children: [
                        Icon(
                          isOnline ? Icons.videocam_outlined : Icons.location_on_outlined,
                          size: 14,
                          color: context.hc.textTertiary,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            event['location'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: context.hc.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // Borough tag (if present)
                    if (borough.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: HuddlColors.teal.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on, size: 11, color: HuddlColors.teal),
                            const SizedBox(width: 3),
                            Text(
                              borough,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.teal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // AI match reason badges
                    if (widget.matchReasons.isNotEmpty) ..._buildMatchReasonChips(),
                    // AI source attribution
                    if (event['isAiDiscovered'] == true) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: HuddlColors.teal,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.language, size: 10, color: Colors.white),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            event['aiSourceIcon'] as IconData? ?? Icons.language,
                            size: 12,
                            color: HuddlColors.teal,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Found on ${event['aiSourceName'] as String? ?? 'the web'}',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.teal,
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

              // ── Bottom action row ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
                child: Row(
                  children: [
                    // Attendees count
                    Icon(Icons.people_outline, size: 14, color: context.hc.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      '$attendees interested',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.hc.textTertiary,
                      ),
                    ),
                    if (organiser.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Container(
                        width: 4, height: 4,
                        decoration: BoxDecoration(
                          color: context.hc.textTertiary.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          organiser,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: context.hc.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else
                      const Spacer(),
                    // Floating blue circular "See details" button
                    GestureDetector(
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
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: eventTypeBlue,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: eventTypeBlue.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 20),
                      ),
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
            color: HuddlColors.teal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Icon(Icons.insights, size: 10, color: HuddlColors.teal),
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
  /// Override the selected fill/shadow colour (defaults to HuddlColors.primary).
  final Color? selectedColor;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.selectedColor,
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
              color: widget.isSelected
                  ? (widget.selectedColor ?? HuddlColors.primary)
                  : context.hc.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: widget.isSelected
                  ? null
                  : Border.all(color: context.hc.divider, width: 0.5),
              boxShadow: widget.isSelected
                  ? [
                      BoxShadow(
                        color: (widget.selectedColor ?? HuddlColors.primary)
                            .withValues(alpha: 0.3),
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
  /// Legacy icon param kept for call-site compatibility — ignored when
  /// [illustration] is provided. Pass a [HuddlIllustration] asset path via
  /// [illustration] to show the brand illustration instead.
  final IconData icon;
  final String? illustration;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    this.illustration,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return HuddlEmptyState(
      illustration: illustration ?? HuddlIllustration.events,
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
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
      return const _CatStyle(HuddlColors.teal, Icons.sports_golf);
    case 'Walk':
      return const _CatStyle(HuddlColors.accentAmber, Icons.directions_walk);
    case 'Social':
      return const _CatStyle(HuddlColors.accentAmber, Icons.celebration);
    case 'Food':
      return const _CatStyle(HuddlColors.accentAmber, Icons.restaurant);
    case 'Other':
      return const _CatStyle(HuddlColors.teal, Icons.more_horiz);
    default:
      return const _CatStyle(HuddlColors.teal, Icons.groups);
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
  final currentUid = FirebaseAuth.instance.currentUser?.uid;
  if (organiserId == (currentUid ?? 'current_user') || organiserId == 'current_user' || MemberPhotoService.isCurrentUser(name)) {
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
          color: HuddlColors.primary.withValues(alpha: 0.08),
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
