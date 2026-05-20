import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';
import '../../services/event_service.dart';
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
import '../../services/discover_ai_service.dart';
import '../../services/location_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';
import '../groups/groups_screen.dart' show DiscoverGroupsTab;
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/borough_badge.dart';
import '../../services/borough_scope_guard.dart';
import '../../widgets/common/huddl_empty_state.dart';
import '../services/services_screen.dart';

// ── Shared avatar URLs for meetup attendee stack (mirrors _kMemberAvatars in groups_screen) ──
const List<String> _kAttendeeAvatars = [
  'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=100&h=100&fit=crop&crop=face',
];

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
  // Fires true to open inline search in the Events tab.
  final ValueNotifier<bool> _eventSearchTrigger  = ValueNotifier<bool>(false);
  // Fires true to open inline search in the Services tab.
  final ValueNotifier<bool> _serviceSearchTrigger = ValueNotifier<bool>(false);

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
    _eventSearchTrigger.dispose();
    _serviceSearchTrigger.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _navigateToCreateMeetup() async {
    final newMeetup = await Navigator.push<Meetup>(
      context,
      MaterialPageRoute(builder: (_) => const CreateMeetupScreen()),
    );
    if (newMeetup != null && mounted) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => MeetupDetailScreen(meetup: newMeetup),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
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
                          else if (_selectedTab == 2)
                            IconButton(
                              icon: Icon(Icons.search,
                                  color: context.hc.textPrimary),
                              tooltip: 'Search events',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _eventSearchTrigger.value = true;
                              },
                            )
                          else if (_selectedTab == 3)
                            IconButton(
                              icon: Icon(Icons.search,
                                  color: context.hc.textPrimary),
                              tooltip: 'Search services',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _serviceSearchTrigger.value = true;
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
                    searchTrigger: _eventSearchTrigger,
                  ),
                  ServicesScreen(searchTrigger: _serviceSearchTrigger),
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
  // 'Kids' added so Meetups matches Events; Groups uses a slightly different set
  static const _audienceLabels = [
    'Aspiring parents', 'Parents expecting a baby', 'Mums', 'Dads', 'Kids',
  ];

  String _selectedCategory = 'All'; // top chip-row (feed header)
  String _selectedParticipant = 'All'; // legacy single-select (kept for compat)

  // ── Extended filter state (filter sheet) ─────────────────────
  double _distanceKm = 10.0;
  /// Multi-select categories from sheet (labels, e.g. 'Hanging out')
  final Set<String> _sheetCategories = {};
  /// Multi-select participants from sheet (labels, e.g. 'Mums')
  final Set<String> _sheetParticipants = {};
  bool _showFreeOnly = false;
  DateTimeRange? _dateRange;
  /// 'mostPopular' | 'latest' | 'smartSort'
  String _sortBy = 'mostPopular';

  // ── Smart Sort / user profile ─────────────────────────────────
  bool _aiSmartSortEnabled = true;
  String? _userParentType;
  List<String> _userStagesOfLife = [];
  String? _userBorough;
  final DiscoverAiService _discoverAiService = DiscoverAiService();

  Set<String> _joinedGroupIds = {};
  final MeetupAiService _aiService = MeetupAiService();
  bool _aiReady = false;
  SmartNudge? _activeNudge; // contextual banner shown above the list

  // ── Distance filter — GPS + geocoding ───────────────────────
  /// The user's GPS position, fetched once when the filter sheet opens.
  Position? _userPosition;
  /// Status from the last location fetch attempt.
  LocationStatus? _locationStatus;
  /// Singleton services
  final LocationService _locationService = LocationService();
  final GeocodingService _geocodingService = GeocodingService();
  /// Pre-geocoded lat/lng cache for meetup locations (keyed by location string).
  /// Shared across filter calls — avoids re-geocoding on every build.
  final Map<String, _LatLng?> _meetupLatLngCache = {};

  // ── Local search ──────────────────────────────────────────────
  bool _isSearchActive = false;
  String _localSearchQuery = '';
  final TextEditingController _localSearchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// True when any filter beyond defaults is active.
  bool get _hasActiveFilter {
    return _selectedCategory != 'All'
        || _selectedParticipant != 'All'
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
      if (_showFreeOnly) true,
      if (_dateRange != null) true,
      if (_sortBy != 'mostPopular') true,
    ].length;
    if (count == 0 && _selectedCategory != 'All') return _selectedCategory;
    if (count == 0 && _selectedParticipant != 'All') return _selectedParticipant;
    if (count == 1) {
      if (_sheetCategories.isNotEmpty) return _sheetCategories.first;
      if (_sheetParticipants.isNotEmpty) return _sheetParticipants.first;
      if (_showFreeOnly) return 'Free only';
      if (_sortBy == 'smartSort') return 'Smart Sort';
      if (_sortBy != 'mostPopular') return 'Latest';
    }
    if (count > 1) return '$count filters';
    return '';
  }

  /// Human-readable distance label shown beneath the section header.
  String get _distanceLabel {
    if (_distanceKm >= 50.0) return 'Up to 50 km';
    return 'Within ${_distanceKm.toInt()} km';
  }

  @override
  void initState() {
    super.initState();
    _loadUserContext();
    _initAi();
    _loadUserProfile();
    widget.searchTrigger.addListener(_onSearchTrigger);
    // Silently attempt location fetch on tab init so it's ready when the
    // filter sheet opens.  We do NOT ask for permission here — that happens
    // only when the user opens the filter sheet.
    _prefetchLocation();
  }

  Future<void> _prefetchLocation() async {
    // Only fetch if already granted — no permission dialog on tab open.
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      final result = await _locationService.getUserPosition();
      if (mounted && result.hasPosition) {
        setState(() {
          _userPosition = result.position;
          _locationStatus = LocationStatus.success;
        });
        // Pre-warm geocoding cache for currently visible meetup addresses
        unawaited(_geocodingService.prewarm(
          widget.meetupService.meetups.map((m) => m.location),
        ));
      }
    }
  }

  /// Called when the user taps "Enable location" in the filter sheet.
  Future<void> _requestLocationPermission(VoidCallback onUpdate) async {
    final result = await _locationService.getUserPosition();
    if (mounted) {
      setState(() {
        _userPosition = result.position;
        _locationStatus = result.status;
      });
      onUpdate();
      if (result.hasPosition) {
        unawaited(_geocodingService.prewarm(
          widget.meetupService.meetups.map((m) => m.location),
        ));
      }
    }
  }

  void _onSearchTrigger() {
    if (widget.searchTrigger.value) {
      widget.searchTrigger.value = false;
      if (_isSearchActive) {
        // Second tap on search icon collapses back to filter pill (no Cancel button)
        _clearSearch();
      } else {
        setState(() => _isSearchActive = true);
        Future.microtask(() => _searchFocusNode.requestFocus());
      }
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

  Future<void> _loadUserProfile() async {
    try {
      final onboarding = OnboardingDataService();
      await onboarding.initialize();
      if (mounted) {
        setState(() {
          _userParentType = onboarding.parentType;
          _userStagesOfLife = List<String>.from(onboarding.stagesOfLife);
          // Add 'has_children' stage if user has children recorded
          if (onboarding.children.isNotEmpty &&
              !_userStagesOfLife.contains('has_children')) {
            _userStagesOfLife = [..._userStagesOfLife, 'has_children'];
          }
          final postcode = onboarding.postcode;
          _userBorough = PostcodeService().getBoroughFromPostcode(postcode);
        });
      }
    } catch (_) {}
  }

  /// Score factor pills shown in the Smart Sort card for Meetups.
  /// Mirrors _buildScoreFactors() in groups_screen.dart.
  List<String> _buildMeetupScoreFactors() {
    final factors = <String>[];
    if (_userBorough != null && _userBorough!.isNotEmpty &&
        _userBorough != 'Unknown Borough') {
      factors.add('\u{1F4CD} ${_userBorough!}');
    }
    if (_userParentType == 'mum') {
      factors.add('\u{1F469} Mums');
    } else if (_userParentType == 'dad') {
      factors.add('\u{1F468} Dads');
    }
    if (_userStagesOfLife.contains('expecting')) {
      factors.add('\u{1F930} Expecting');
    }
    if (_userStagesOfLife.contains('new_parent')) {
      factors.add('\u{1F476} New parent');
    }
    if (_userStagesOfLife.contains('has_children')) {
      factors.add('\u{1F9D2} Kids');
    }
    factors.add('\u2B50 Popularity');
    return factors;
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
    // Localization filter removed — all meetups are in-person community events

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

    // ── 8. Distance filter ────────────────────────────────────────
    // Only active when: (a) user has a GPS position AND (b) slider is not
    // at max (50 km = "any distance").
    if (_userPosition != null && _distanceKm < 50.0) {
      result = result.where((m) {
        // Skip distance check for online / TBC locations
        final loc = m.location.trim().toLowerCase();
        if (loc.isEmpty || loc == 'online' || loc.contains('online event') ||
            loc == 'tbc' || loc == 'tbd') {
          return true; // always include vague locations
        }
        // Use already-geocoded result from cache if available
        final cacheKey = m.location.trim().toLowerCase();
        if (_meetupLatLngCache.containsKey(cacheKey)) {
          final cached = _meetupLatLngCache[cacheKey];
          if (cached == null) return true; // unresolvable → include
          final km = LocationService.distanceInKm(
            _userPosition!, cached.lat, cached.lng);
          return km <= _distanceKm;
        }
        // Not yet geocoded — include and geocode asynchronously
        _geocodingService.geocode(m.location).then((latLng) {
          if (!mounted) return;
          setState(() {
            _meetupLatLngCache[cacheKey] =
                latLng != null ? _LatLng(latLng.lat, latLng.lng) : null;
          });
        });
        return true; // optimistic include until geocoded
      }).toList();
    }

    // ── 9. Sort ───────────────────────────────────────────────────
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
    double        sheetDistanceKm      = _distanceKm;
    Set<String>   sheetCategories      = Set<String>.from(_sheetCategories);
    Set<String>   sheetParticipants    = Set<String>.from(_sheetParticipants);
    bool          sheetFreeOnly        = _showFreeOnly;
    DateTimeRange? sheetDateRange      = _dateRange;
    String        sheetSortBy          = _sortBy;
    bool          sheetSmartSort       = _aiSmartSortEnabled;

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

          // ── Helper: section heading ──────────────────────────────────
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

          // ── Helper: checkbox row (matches Groups "Show groups for" pattern) ──
          Widget checkboxRow(String label) {
            final isChecked = sheetParticipants.contains(label);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                setSheetState(() {
                  if (isChecked) {
                    sheetParticipants.remove(label);
                  } else {
                    sheetParticipants.add(label);
                  }
                });
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: isChecked ? orange : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isChecked ? orange : dividerColor,
                          width: 2,
                        ),
                      ),
                      child: isChecked
                          ? const Icon(Icons.check, size: 18, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Smart Sort card (mirrors Groups exactly) ───────────────────────
          final sampleScore = _discoverAiService.getGroupRecommendationScore(
            {'id': 'sample', 'category': 'PARENTING', 'memberCount': 500,
             'creatorBorough': _userBorough, 'targetAudience': <String>[]},
            userBorough: _userBorough,
            parentType: _userParentType,
            stagesOfLife: _userStagesOfLife,
          );
          final scoreFactors = _buildMeetupScoreFactors();

          Widget smartSortCard = GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setSheetState(() => sheetSortBy = 'smartSort');
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: sheetSortBy == 'smartSort'
                    ? LinearGradient(
                        colors: [
                          orange.withValues(alpha: 0.12),
                          blue.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: sheetSortBy == 'smartSort' ? null : chipBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sheetSortBy == 'smartSort'
                      ? orange.withValues(alpha: 0.45)
                      : dividerColor,
                  width: sheetSortBy == 'smartSort' ? 1.5 : 1,
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: sheetSortBy == 'smartSort'
                              ? orange
                              : orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.auto_awesome_rounded,
                          size: 18,
                          color: sheetSortBy == 'smartSort' ? Colors.white : orange,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Smart Sort',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14, fontWeight: FontWeight.w700,
                                    color: sheetSortBy == 'smartSort'
                                        ? orange : textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                        colors: [blue, orange]),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('AI',
                                    style: GoogleFonts.poppins(
                                      fontSize: 9, fontWeight: FontWeight.w700,
                                      color: Colors.white, letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text('Personalised to your profile',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: textSecGray)),
                          ],
                        ),
                      ),
                      if (sheetSortBy == 'smartSort')
                        Icon(Icons.check_circle, size: 22, color: orange),
                    ],
                  ),
                  if (scoreFactors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: scoreFactors.map((f) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: orange.withValues(alpha: 0.18)),
                        ),
                        child: Text(f,
                          style: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w500,
                            color: orange,
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Meetups are ranked by how well they match your profile — '
                    'location, parenting stage, interests, and activity.',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: textSecGray, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        sheetSmartSort
                            ? Icons.psychology_rounded
                            : Icons.psychology_alt_outlined,
                        size: 16,
                        color: sheetSmartSort ? orange : textSecGray,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          sheetSmartSort
                              ? 'AI ranking active'
                              : 'AI ranking off — showing default order',
                          style: GoogleFonts.poppins(
                            fontSize: 12, fontWeight: FontWeight.w500,
                            color: sheetSmartSort ? orange : textSecGray,
                          ),
                        ),
                      ),
                      Transform.scale(
                        scale: 0.82,
                        alignment: Alignment.centerRight,
                        child: Switch(
                          value: sheetSmartSort,
                          activeThumbColor: orange,
                          activeTrackColor: orange.withValues(alpha: 0.35),
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            setSheetState(() {
                              sheetSmartSort = val;
                              if (val) sheetSortBy = 'smartSort';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (sheetSmartSort) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Match quality',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: textSecGray)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (sampleScore / 100).clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor: orange.withValues(alpha: 0.12),
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(orange),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${sampleScore.round()}%',
                          style: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );

          // ── Helper: filter chip (Category only) ───────────────────────────
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

                          // ══ SECTION 2 — DISTANCE ═══════════════
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Distance',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              // Live selected-value badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  sheetDistanceKm >= 50
                                      ? 'Up to 50 km'
                                      : 'Within ${sheetDistanceKm.toInt()} km',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Slider
                          SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              activeTrackColor: orange,
                              inactiveTrackColor: trackInactive,
                              thumbColor: orange,
                              overlayColor: orange.withValues(alpha: 0.15),
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                            ),
                            child: Slider(
                              value: sheetDistanceKm.clamp(1.0, 50.0),
                              min: 1,
                              max: 50,
                              divisions: 49,
                              onChanged: (v) {
                                setSheetState(() {
                                  sheetDistanceKm = v.roundToDouble();
                                });
                              },
                            ),
                          ),
                          // Min / max scale labels beneath the track
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('1 km',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: const Color(0xFFB0B0B0))),
                                Text('25 km',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: const Color(0xFFB0B0B0))),
                                Text('50 km',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: const Color(0xFFB0B0B0))),
                              ],
                            ),
                          ),
                          // Location status banner (shown only when GPS unavailable)
                          if (_userPosition == null) ...[
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                if (_locationStatus == LocationStatus.permissionDeniedForever) {
                                  _locationService.openSettings();
                                } else {
                                  _requestLocationPermission(() => setSheetState(() {}));
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE0E0E0)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_off_rounded, size: 18, color: Color(0xFF9E9E9E)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _locationStatus == LocationStatus.permissionDeniedForever
                                            ? 'Distance filter needs location. Tap to open Settings.'
                                            : _locationStatus == LocationStatus.serviceDisabled
                                                ? 'Enable location services to filter by distance.'
                                                : 'Tap to enable location and filter by distance.',
                                        style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF757575)),
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFBDBDBD)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),

                          // ══ SECTION 3 — SHOW MEETUPS FOR (checkboxes) ═════
                          Text('Show meetups for',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ..._audienceLabels.map(checkboxRow),
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

                          // ══ SECTION 7 — SORT BY ════════════════
                          Text('Sort by',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          smartSortCard,
                          const SizedBox(height: 6),
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
                              _aiSmartSortEnabled = sheetSmartSort;
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
    }

    // Build a map from meetup id to boost reason for card display
    final boostReasons = <String, String>{};
    for (final s in scored) {
      if (s.boostReason != null) boostReasons[s.meetup.id] = s.boostReason!;
    }

    // ── Smart Nudge — compute once per build from live filtered list ──
    // Only re-evaluate when AI is ready and no nudge is already showing.
    if (_aiReady && _activeNudge == null) {
      final nudge = _aiService.getSmartNudge(filtered);
      if (nudge != null) {
        // Schedule state update after build — avoids setState-during-build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _activeNudge = nudge);
        });
      }
    }

    // ── Figma design tokens ────────────────────────────────────────
    const Color filterText  = Color(0xFF42464C); // Figma: dark text
    const Color sectionText = Color(0xFF42464C); // Figma: "Black" grayscale

    return Column(
      children: [
        // ══ TOP HEADER ════════════════════════════════════════════════════════
        // Search active → inline search field only (no filter pill, no headings)
        // Search inactive → filter pill + section label + distance indicator
        if (_isSearchActive)
          // ── Search field row (mirrors Groups inline search exactly) ────────
          Container(
            color: context.hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: context.hc.inputBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 12, right: 6),
                    child: Icon(Icons.search, size: 18,
                        color: HuddlColors.primary),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _localSearchController,
                      focusNode: _searchFocusNode,
                      textAlignVertical: TextAlignVertical.center,
                      onChanged: (v) =>
                          setState(() => _localSearchQuery = v),
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: filterText),
                      decoration: InputDecoration(
                        hintText: 'Search meetups',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 14,
                            color: HuddlColors.textTertiary),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.only(bottom: 2),
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
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.close, size: 16,
                            color: HuddlColors.textTertiary),
                      ),
                    )
                  else
                    const SizedBox(width: 10),
                ],
              ),
            ),
          )
        else
          // ── Filter pill + section label + distance (default state) ──────────
          Container(
            color: context.hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filter pill row
                Row(
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
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
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
                              // Icon with orange dot badge when filters active
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(
                                    Icons.tune_rounded,
                                    size: 18,
                                    color: _hasActiveFilter
                                        ? HuddlColors.primary
                                        : filterText,
                                  ),
                                  if (_hasActiveFilter)
                                    Positioned(
                                      top: -3,
                                      right: -3,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: HuddlColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _hasActiveFilter &&
                                        _filterPillLabel.isNotEmpty
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

                // Active participant badge (set via filter sheet)
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
                              color:
                                  HuddlColors.primary.withValues(alpha: 0.3)),
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
                                setState(
                                    () => _selectedParticipant = 'All');
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
                // Section label
                Text(
                  'Suggested for you',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: sectionText,
                  ),
                ),
                // Distance indicator
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 13,
                      color: HuddlColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _distanceLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: HuddlColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        // ── Smart Nudge banner (hidden during search) ─────────────
        if (_activeNudge != null && !_isSearchActive)
          _SmartNudgeBanner(
            nudge: _activeNudge!,
            onDismiss: () {
              _aiService.dismissNudge(_activeNudge!.type.name);
              setState(() => _activeNudge = null);
            },
            onAction: _activeNudge!.actionLabel != null
                ? widget.onCreateMeetup
                : null,
          ),

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
                      padding: EdgeInsets.fromLTRB(
                          _isSearchActive ? 0 : 16,
                          8,
                          _isSearchActive ? 0 : 16,
                          80),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final meetup = filtered[i];
                        if (_isSearchActive) {
                          // ── Compact row (matches Groups search result style) ──
                          return _MeetupSearchRow(
                            meetup: meetup,
                            canAccess: _canAccessMeetup(meetup),
                            onAccessDenied: () => _showAccessDeniedDialog(context, meetup),
                          );
                        }
                        return _MeetupCard(
                          meetup: meetup,
                          canAccess: _canAccessMeetup(meetup),
                          onAccessDenied: () => _showAccessDeniedDialog(context, meetup),
                          boostReason: boostReasons[meetup.id],
                          onView: () => _aiService.trackMeetupView(meetup.id, meetup.category),
                          onTagFilter: (tag) {
                            // Apply tag as a participant or category filter
                            const participantLabels = ['Mums', 'Dads', 'Aspiring parents',
                                'Parents expecting a baby', 'Kids'];
                            if (participantLabels.contains(tag)) {
                              setState(() => _selectedParticipant = tag);
                            } else {
                              // Category tag — map code to sheet label and apply
                              const codeToLabel = {
                                'Coffee': 'Coffee & tea', 'Playdate': 'Playdate',
                                'Sport': 'Sports & exercise', 'Walk': 'Parks & Walks',
                                'Social': 'Hanging out', 'Food': 'Food & nutrition',
                                'Other': 'Other',
                              };
                              final label = codeToLabel[tag] ?? tag;
                              setState(() { _sheetCategories.clear(); _sheetCategories.add(label); });
                            }
                          },
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
  final ValueNotifier<bool> searchTrigger;

  const _EventsTab({
    required this.eventService,
    required this.searchTrigger,
  });

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  // ── Core AI services ───────────────────────────────────────
  final AiEventRecommenderService _recommender = AiEventRecommenderService();
  final AiEventDiscoveryService _discovery = AiEventDiscoveryService();
  final InvisibleAiService _invisibleAi = InvisibleAiService();

  // ── Recommender state ──────────────────────────────────────
  bool _recommenderReady = false;
  bool _isDiscovering = false;
  Map<String, ScoredEvent> _scoredEventMap = {};

  // ── Inline search state (mirrors Meetups tab) ───────────────
  bool _isSearchActive = false;
  String _localSearchQuery = '';
  final TextEditingController _localSearchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // ── NLP / invisible AI filter state ─────────────────────────
  Map<String, dynamic> _activeParsedFilters = {};

  // ── Manual filter state (set via bottom sheet) ─────────────
  // ── Distance filter ─── GPS + geocoding ──────────────────────────────────
  Position? _evUserPosition;
  LocationStatus? _evLocationStatus;
  final LocationService _evLocationService = LocationService();
  final GeocodingService _evGeocodingService = GeocodingService();
  final Map<String, _LatLng?> _evLatLngCache = {};

  // ── Manual filter state (set via bottom sheet) ──────────────
  String _priceFilter = 'All';   // All | Free | Paid
  String _formatFilter = 'All';  // All | Online | In-Person

  void _onSearchTrigger() {
    if (!mounted) return;
    setState(() => _isSearchActive = true);
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _clearSearch() {
    _localSearchController.clear();
    setState(() {
      _isSearchActive = false;
      _localSearchQuery = '';
      _activeParsedFilters = {};
    });
    _searchFocusNode.unfocus();
  }

  @override
  void initState() {
    super.initState();
    _initServices();
    _loadEventsUserProfile();
    widget.searchTrigger.addListener(_onSearchTrigger);
    _prefetchEvLocation();
  }

  Future<void> _prefetchEvLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      final result = await _evLocationService.getUserPosition();
      if (mounted && result.hasPosition) {
        setState(() {
          _evUserPosition = result.position;
          _evLocationStatus = LocationStatus.success;
        });
        final locations = widget.eventService.eventMaps
            .map((e) => e['location'] as String? ?? '')
            .where((l) => l.isNotEmpty);
        unawaited(_evGeocodingService.prewarm(locations));
      }
    }
  }

  Future<void> _requestEvLocationPermission(VoidCallback onUpdate) async {
    final result = await _evLocationService.getUserPosition();
    if (mounted) {
      setState(() {
        _evUserPosition = result.position;
        _evLocationStatus = result.status;
      });
      onUpdate();
      if (result.hasPosition) {
        final locations = widget.eventService.eventMaps
            .map((e) => e['location'] as String? ?? '')
            .where((l) => l.isNotEmpty);
        unawaited(_evGeocodingService.prewarm(locations));
      }
    }
  }

  @override
  void dispose() {
    widget.searchTrigger.removeListener(_onSearchTrigger);
    _localSearchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadEventsUserProfile() async {
    try {
      final onboarding = OnboardingDataService();
      await onboarding.initialize();
      if (mounted) {
        setState(() {
          _evUserParentType = onboarding.parentType;
          _evUserStagesOfLife = List<String>.from(onboarding.stagesOfLife);
          if (onboarding.children.isNotEmpty &&
              !_evUserStagesOfLife.contains('has_children')) {
            _evUserStagesOfLife = [..._evUserStagesOfLife, 'has_children'];
          }
          final postcode = onboarding.postcode;
          _evUserBorough = PostcodeService().getBoroughFromPostcode(postcode);
        });
      }
    } catch (_) {}
  }

  /// Score factor pills shown in the Smart Sort card for Events.
  List<String> _buildEventsScoreFactors() {
    final factors = <String>[];
    if (_evUserBorough != null && _evUserBorough!.isNotEmpty &&
        _evUserBorough != 'Unknown Borough') {
      factors.add('\u{1F4CD} ${_evUserBorough!}');
    }
    if (_evUserParentType == 'mum') {
      factors.add('\u{1F469} Mums');
    } else if (_evUserParentType == 'dad') {
      factors.add('\u{1F468} Dads');
    }
    if (_evUserStagesOfLife.contains('expecting')) {
      factors.add('\u{1F930} Expecting');
    }
    if (_evUserStagesOfLife.contains('new_parent')) {
      factors.add('\u{1F476} New parent');
    }
    if (_evUserStagesOfLife.contains('has_children')) {
      factors.add('\u{1F9D2} Kids');
    }
    factors.add('\u2B50 Popularity');
    return factors;
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
    final allScored = _recommender.rankAllEvents();
    _scoredEventMap = { for (final s in allScored) s.event.id: s };
  }



  @override
  Widget build(BuildContext context) {
    if (_recommenderReady) _refreshRecommendations();

    // ── Build events list with local search + filters ────────────
    var allEvents = widget.eventService.eventMaps;

    // Apply inline local search (title / location / organiser)
    if (_localSearchQuery.isNotEmpty) {
      final q = _localSearchQuery.toLowerCase();
      allEvents = allEvents.where((e) {
        final title    = (e['title']    as String? ?? '').toLowerCase();
        final location = (e['location'] as String? ?? '').toLowerCase();
        final organiser = (e['organiser'] as String? ?? '').toLowerCase();
        return title.contains(q) || location.contains(q) || organiser.contains(q);
      }).toList();
    }

    // Apply NLP smart filters (invisible AI)
    List<Map<String, dynamic>> events;
    if (_activeParsedFilters.isNotEmpty) {
      events = _invisibleAi.applySmartFilter(allEvents, _activeParsedFilters);
    } else {
      events = allEvents;
    }

    // Apply manual filter (price / format)
    if (_activeManualFilter != 'All') {
      events = events.where((e) {
        if (_activeManualFilter == 'Free')      return e['isFree'] == true;
        if (_activeManualFilter == 'Paid')      return e['isFree'] != true;
        if (_activeManualFilter == 'Online')    return e['isOnline'] == true;
        if (_activeManualFilter == 'In-Person') return e['isOnline'] != true;
        return true;
      }).toList();
    }
    if (_priceFilter != 'All') {
      events = events.where((e) {
        if (_priceFilter == 'Free') return e['isFree'] == true;
        if (_priceFilter == 'Paid') return e['isFree'] != true;
        return true;
      }).toList();
    }
    if (_formatFilter != 'All') {
      events = events.where((e) {
        if (_formatFilter == 'Online')    return e['isOnline'] == true;
        if (_formatFilter == 'In-Person') return e['isOnline'] != true;
        return true;
      }).toList();
    }

    // ── Extended filter state from the Events filter bottom sheet ────────────
    // Free-only toggle
    if (_evFreeOnly) {
      events = events.where((e) => e['isFree'] == true).toList();
    }
    // "Show events for" participants filter (maps to suitableFor / targetStages)
    if (_evParticipants.isNotEmpty) {
      final Map<String, List<String>> participantStageMap = {
        'Aspiring parents':         ['pregnant', 'aspiring'],
        'Parents expecting a baby': ['pregnant'],
        'Mums':                     ['newborn', 'toddler', 'school-age'],
        'Dads':                     ['newborn', 'toddler', 'school-age'],
        'Kids':                     ['toddler', 'school-age'],
      };
      events = events.where((e) {
        final stages = (e['targetStages'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ??
            [];
        final suitableFor = (e['suitableFor'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ??
            [];
        // Include if any selected participant type matches event stages
        for (final p in _evParticipants) {
          final matchStages = participantStageMap[p] ?? [];
          if (suitableFor.contains('all_families')) return true;
          if (stages.any((s) => matchStages.contains(s))) return true;
        }
        return false;
      }).toList();
    }
    // Category filter
    if (_evCategories.isNotEmpty) {
      // Map display labels to category keys used in event data
      const Map<String, String> categoryKeyMap = {
        'Hanging out':         'community',
        'Pregnancy':           'health',
        'Playdate':            'play',
        'Sports & exercise':   'sport',
        'Coffee & tea':        'community',
        'Parks & Walks':       'community',
        'Performance & shows': 'class',
      };
      events = events.where((e) {
        final cat = (e['category'] as String? ?? '').toLowerCase();
        for (final label in _evCategories) {
          final mappedKey = categoryKeyMap[label]?.toLowerCase() ?? '';
          if (cat == mappedKey || cat.contains(label.toLowerCase())) return true;
        }
        return false;
      }).toList();
    }
    // Date range filter (best-effort — full implementation requires Firestore Event objects)
    // In the current in-memory model, we include all events when a date range is set
    // rather than incorrectly excluding events. Full date filtering is applied at
    // Firestore query level in the production backend integration.
    // _evDateRange != null signals to the CTA count that a filter is active.

    // ── Distance filter ──────────────────────────────────────────────────────
    // Only active when: (a) user has a GPS position AND (b) slider < 50 km max.
    if (_evUserPosition != null && _evDistanceKm < 50.0) {
      final List<Map<String, dynamic>> distanceFiltered = [];
      for (final e in events) {
        final address = (e['location'] as String? ?? '').trim();
        final loc = address.toLowerCase();
        // Always include vague / online locations
        if (loc.isEmpty || loc == 'online' || loc.contains('online event') ||
            loc == 'tbc' || loc == 'tbd') {
          distanceFiltered.add(e);
          continue;
        }
        final cacheKey = loc;
        if (_evLatLngCache.containsKey(cacheKey)) {
          final cached = _evLatLngCache[cacheKey];
          if (cached == null) {
            distanceFiltered.add(e); // unresolvable → include
          } else {
            final km = LocationService.distanceInKm(
                _evUserPosition!, cached.lat, cached.lng);
            if (km <= _evDistanceKm) distanceFiltered.add(e);
          }
        } else {
          // Not yet geocoded — include optimistically; geocode async
          distanceFiltered.add(e);
          _evGeocodingService.geocode(address).then((latLng) {
            if (!mounted) return;
            setState(() {
              _evLatLngCache[cacheKey] =
                  latLng != null ? _LatLng(latLng.lat, latLng.lng) : null;
            });
          });
        }
      }
      events = distanceFiltered;
    }

    // AI-powered intelligent sort
    if (_recommenderReady && events.isNotEmpty) {
      events = _invisibleAi.intelligentSort(events, _scoredEventMap);
    }

    final bool hasActiveFilter = _priceFilter != 'All' ||
        _formatFilter != 'All' ||
        _activeManualFilter != 'All' ||
        _evParticipants.isNotEmpty ||
        _evCategories.isNotEmpty ||
        _evFreeOnly ||
        _evDateRange != null ||
        _evDistanceKm != 10.0;

    const Color filterText  = Color(0xFF42464C);
    const Color sectionText = Color(0xFF42464C);

    return Column(
      children: [
        // ══ TOP HEADER — filter pill ↔ inline search (Meetups pattern) ══
        Container(
          color: context.hc.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AnimatedCrossFade: filter pill  ↔  inline search bar
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: _isSearchActive
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Row(
                  children: [
                    Semantics(
                      label: hasActiveFilter
                          ? 'Filters active. Tap to change.'
                          : 'Filter and sort events',
                      button: true,
                      child: GestureDetector(
                        onTap: () => _showEventsFilterSheet(context),
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
                                color: hasActiveFilter
                                    ? HuddlColors.primary
                                    : filterText,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                hasActiveFilter ? 'Filter and sort •' : 'Filter and sort',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: hasActiveFilter
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
                    // Clear all — visible only when filters active
                    if (hasActiveFilter)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _priceFilter = 'All';
                            _formatFilter = 'All';
                            _activeManualFilter = 'All';
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          child: Text(
                            'Clear',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // ── Inline search bar (grey pill — matches Meetups/Groups) ─
                secondChild: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.hc.inputBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 12, right: 6),
                        child: Icon(Icons.search, size: 18,
                            color: HuddlColors.primary),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _localSearchController,
                          focusNode: _searchFocusNode,
                          textAlignVertical: TextAlignVertical.center,
                          onChanged: (v) =>
                              setState(() => _localSearchQuery = v),
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: filterText),
                          decoration: InputDecoration(
                            hintText: 'Search events',
                            hintStyle: GoogleFonts.poppins(
                                fontSize: 14,
                                color: HuddlColors.textTertiary),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.only(bottom: 2),
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
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.close, size: 16,
                                color: HuddlColors.textTertiary),
                          ),
                        )
                      else
                        const SizedBox(width: 10),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              // Section label — mirrors Meetups pattern
              Text(
                _localSearchQuery.isEmpty ? 'Suggested for you' : 'Search results',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: sectionText,
                ),
              ),
              // ── Distance indicator ──────────────────────────────────────
              // Shows the active radius (or "Online") below the section header.
              // Hidden during search — the label is irrelevant when searching by keyword.
              if (_localSearchQuery.isEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      _evLocalization == 'online'
                          ? Icons.wifi_rounded
                          : Icons.place_outlined,
                      size: 13,
                      color: HuddlColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _evDistanceLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: HuddlColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),

        // ── Discovering indicator ─────────────────────────────────
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
                      fontSize: 12,
                      color: HuddlColors.teal,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

        // ── Event list — all events as vertical cards under "Suggested for you" ──
        Expanded(
          child: ColoredBox(
            color: HuddlColors.background,
            child: events.isEmpty
                ? _EmptyState(
                    icon: hasActiveFilter
                        ? Icons.filter_list_off
                        : Icons.event_outlined,
                    illustration: HuddlIllustration.events,
                    title: _localSearchQuery.isNotEmpty
                        ? 'No matches'
                        : hasActiveFilter
                            ? 'No events match your filters'
                            : 'No events found',
                    subtitle: _localSearchQuery.isNotEmpty
                        ? 'Try a different search term.'
                        : hasActiveFilter
                            ? 'Try adjusting or clearing your filters.'
                            : 'Pull down to refresh or use the search icon.',
                    actionLabel: _localSearchQuery.isNotEmpty
                        ? 'Clear search'
                        : hasActiveFilter
                            ? 'Clear filters'
                            : null,
                    onAction: _localSearchQuery.isNotEmpty
                        ? _clearSearch
                        : hasActiveFilter
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: events.length,
                      itemBuilder: (_, i) {
                        final event = events[i];
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

  // ── Extended Events filter state (mirrors Meetup/Groups filter) ──────────
  double        _evDistanceKm      = 10.0;
  final Set<String>   _evParticipants    = {};
  final Set<String>   _evCategories      = {};
  bool          _evFreeOnly        = false;
  DateTimeRange? _evDateRange;
  String        _evSortBy          = 'mostPopular'; // 'mostPopular' | 'latest' | 'smartSort'
  final String  _evLocalization    = 'none';   // kept for legacy format filter compat

  // ── Smart Sort / user profile for Events ─────────────────────────────
  static const _evAudienceLabels = [
    'Aspiring parents', 'Parents expecting a baby', 'Mums', 'Dads', 'Kids',
  ];
  bool          _evSmartSortEnabled = true;
  String?       _evUserParentType;
  List<String>  _evUserStagesOfLife = [];
  String?       _evUserBorough;
  final DiscoverAiService _evDiscoverAiService = DiscoverAiService();

    /// Human-readable distance label shown beneath the section header.
  /// Mirrors the original _distanceLabel getter removed in the dead-code sweep.
  String get _evDistanceLabel {
    if (_evDistanceKm >= 50.0) return 'Up to 50 km';
    return 'Within ${_evDistanceKm.toInt()} km';
  }

  // ── Events filter bottom sheet — Figma-exact ─────────────────
  void _showEventsFilterSheet(BuildContext context) {
    HapticFeedback.selectionClick();

    // Snapshot all state into local sheet vars
    double         sheetDistanceKm    = _evDistanceKm;
    Set<String>    sheetParticipants  = Set<String>.from(_evParticipants);
    Set<String>    sheetCategories    = Set<String>.from(_evCategories);
    bool           sheetFreeOnly      = _evFreeOnly;
    DateTimeRange? sheetDateRange     = _evDateRange;
    String         sheetSortBy        = _evSortBy;
    bool           sheetSmartSort     = _evSmartSortEnabled;
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

          // ── Checkbox row (matches Groups "Show groups for" pattern) ──
          Widget checkboxRow(String label) {
            final isChecked = sheetParticipants.contains(label);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                setSheetState(() {
                  if (isChecked) {
                    sheetParticipants.remove(label);
                  } else {
                    sheetParticipants.add(label);
                  }
                });
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: isChecked ? orange : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isChecked ? orange : dividerColor,
                          width: 2,
                        ),
                      ),
                      child: isChecked
                          ? const Icon(Icons.check, size: 18, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Smart Sort card (mirrors Groups/Meetups exactly) ──────────────────
          final evSampleScore = _evDiscoverAiService.getGroupRecommendationScore(
            {'id': 'sample', 'category': 'PARENTING', 'memberCount': 500,
             'creatorBorough': _evUserBorough, 'targetAudience': <String>[]},
            userBorough: _evUserBorough,
            parentType: _evUserParentType,
            stagesOfLife: _evUserStagesOfLife,
          );
          final evScoreFactors = _buildEventsScoreFactors();

          Widget smartSortCard = GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setSheetState(() => sheetSortBy = 'smartSort');
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: sheetSortBy == 'smartSort'
                    ? LinearGradient(
                        colors: [
                          orange.withValues(alpha: 0.12),
                          blue.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: sheetSortBy == 'smartSort' ? null : chipBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sheetSortBy == 'smartSort'
                      ? orange.withValues(alpha: 0.45)
                      : dividerColor,
                  width: sheetSortBy == 'smartSort' ? 1.5 : 1,
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: sheetSortBy == 'smartSort'
                              ? orange
                              : orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.auto_awesome_rounded,
                          size: 18,
                          color: sheetSortBy == 'smartSort' ? Colors.white : orange,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Smart Sort',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14, fontWeight: FontWeight.w700,
                                    color: sheetSortBy == 'smartSort'
                                        ? orange : textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                        colors: [blue, orange]),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('AI',
                                    style: GoogleFonts.poppins(
                                      fontSize: 9, fontWeight: FontWeight.w700,
                                      color: Colors.white, letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text('Personalised to your profile',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: textSecGray)),
                          ],
                        ),
                      ),
                      if (sheetSortBy == 'smartSort')
                        Icon(Icons.check_circle, size: 22, color: orange),
                    ],
                  ),
                  if (evScoreFactors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: evScoreFactors.map((f) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: orange.withValues(alpha: 0.18)),
                        ),
                        child: Text(f,
                          style: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w500,
                            color: orange,
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Events are ranked by how well they match your profile — '
                    'location, parenting stage, interests, and activity.',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: textSecGray, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: dividerColor),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        sheetSmartSort
                            ? Icons.psychology_rounded
                            : Icons.psychology_alt_outlined,
                        size: 16,
                        color: sheetSmartSort ? orange : textSecGray,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          sheetSmartSort
                              ? 'AI ranking active'
                              : 'AI ranking off — showing default order',
                          style: GoogleFonts.poppins(
                            fontSize: 12, fontWeight: FontWeight.w500,
                            color: sheetSmartSort ? orange : textSecGray,
                          ),
                        ),
                      ),
                      Transform.scale(
                        scale: 0.82,
                        alignment: Alignment.centerRight,
                        child: Switch(
                          value: sheetSmartSort,
                          activeThumbColor: orange,
                          activeTrackColor: orange.withValues(alpha: 0.35),
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            setSheetState(() {
                              sheetSmartSort = val;
                              if (val) sheetSortBy = 'smartSort';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (sheetSmartSort) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Match quality',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: textSecGray)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (evSampleScore / 100).clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor: orange.withValues(alpha: 0.12),
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(orange),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${evSampleScore.round()}%',
                          style: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );

          // ── Filter chip (Category only) ───────────────────────────────────
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



          // ── Active count for CTA label ─────────────────────────
          // Count each active filter type as +1 (per spec Section 2G)
          int activeCount = 0;
          if (sheetDistanceKm != 10.0) activeCount++;       // distance ≠ default (10 km)
          if (sheetParticipants.isNotEmpty) activeCount++;  // each selected "show for" checkbox
          if (sheetCategories.isNotEmpty) activeCount++;    // each selected category pill group
          if (sheetFreeOnly) activeCount++;                 // free-only toggle
          if (sheetDateRange != null) activeCount++;        // active date range
          if (sheetSortBy != 'mostPopular' && !sheetSmartSort) activeCount++; // non-default sort

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
                                    sheetDistanceKm   = 10.0;
                                    sheetParticipants = {};
                                    sheetCategories   = {};
                                    sheetFreeOnly     = false;
                                    sheetDateRange    = null;
                                    sheetSortBy       = 'smartSort';
                                    sheetSmartSort    = true;
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

                          // ── SECTION 2: DISTANCE ────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Distance',
                                  style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary)),
                              // Live selected-value badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  sheetDistanceKm >= 50
                                      ? 'Up to 50 km'
                                      : 'Within ${sheetDistanceKm.toInt()} km',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: orange),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              activeTrackColor: orange,
                              inactiveTrackColor: trackInactive,
                              thumbColor: orange,
                              overlayColor: orange.withValues(alpha: 0.15),
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                            ),
                            child: Slider(
                              value: sheetDistanceKm.clamp(1.0, 50.0),
                              min: 1,
                              max: 50,
                              divisions: 49,
                              onChanged: (v) {
                                setSheetState(() {
                                  sheetDistanceKm = v.roundToDouble();
                                });
                              },
                            ),
                          ),
                          // Min / max scale labels beneath the track
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('1 km',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: const Color(0xFFB0B0B0))),
                                Text('25 km',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: const Color(0xFFB0B0B0))),
                                Text('50 km',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: const Color(0xFFB0B0B0))),
                              ],
                            ),
                          ),
                          // Location status banner (shown only when GPS unavailable)
                          if (_evUserPosition == null) ...[
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                if (_evLocationStatus == LocationStatus.permissionDeniedForever) {
                                  _evLocationService.openSettings();
                                } else {
                                  _requestEvLocationPermission(() => setSheetState(() {}));
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE0E0E0)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_off_rounded, size: 18, color: Color(0xFF9E9E9E)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _evLocationStatus == LocationStatus.permissionDeniedForever
                                            ? 'Distance filter needs location. Tap to open Settings.'
                                            : _evLocationStatus == LocationStatus.serviceDisabled
                                                ? 'Enable location services to filter by distance.'
                                                : 'Tap to enable location and filter by distance.',
                                        style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF757575)),
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFBDBDBD)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),

                          // ── SECTION 3: PARTICIPANTS ────────────
                          sectionHeading('Show events for'),
                          ..._evAudienceLabels.map(checkboxRow),
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
                          smartSortCard,
                          const SizedBox(height: 8),
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
                              _evSmartSortEnabled = sheetSmartSort;
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
// ── Compact search-result row — mirrors the Groups tab search row style ──────
class _MeetupSearchRow extends StatelessWidget {
  final Meetup meetup;
  final bool canAccess;
  final VoidCallback? onAccessDenied;

  const _MeetupSearchRow({
    required this.meetup,
    this.canAccess = true,
    this.onAccessDenied,
  });

  @override
  Widget build(BuildContext context) {
    final isJoined = meetup.isGoing;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (!canAccess) { onAccessDenied?.call(); return; }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetupDetailScreen(meetup: meetup),
          ),
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: context.hc.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Thumbnail — 56×56 rounded rect
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: meetup.imageUrl.isNotEmpty
                  ? Image.network(
                      meetup.imageUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _MeetupSearchPlaceholder(title: meetup.title),
                    )
                  : _MeetupSearchPlaceholder(title: meetup.title),
            ),
            const SizedBox(width: 12),
            // Text block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category + date — small caps
                  Text(
                    '${meetup.category.toUpperCase()}  ·  ${meetup.dateDisplay.toUpperCase()}',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textTertiary,
                      letterSpacing: 0.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Title
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
                  // Location + attendee count
                  Text(
                    '${meetup.location}  ·  ${meetup.attendeeCount} attending',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: context.hc.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Join / Joined button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isJoined
                    ? HuddlColors.teal.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isJoined
                      ? HuddlColors.teal.withValues(alpha: 0.4)
                      : context.hc.divider,
                ),
              ),
              child: Text(
                isJoined ? 'Joined' : 'Join',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isJoined ? HuddlColors.teal : context.hc.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetupSearchPlaceholder extends StatelessWidget {
  final String title;
  const _MeetupSearchPlaceholder({required this.title});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: HuddlColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          title.isNotEmpty ? title[0].toUpperCase() : 'M',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: HuddlColors.primary,
          ),
        ),
      ),
    );
  }
}

// ── Large card widget (default feed view) ────────────────────────────────────
class _MeetupCard extends StatefulWidget {
  final Meetup meetup;
  final bool canAccess;
  final VoidCallback? onAccessDenied;
  final String? boostReason; // AI-generated boost reason (subtle sparkle)
  final VoidCallback? onView; // track AI view for learning
  /// Called when user taps a tag inside the detail screen and wants to filter
  final void Function(String tag)? onTagFilter;

  const _MeetupCard({
    required this.meetup,
    this.canAccess = true,
    this.onAccessDenied,
    this.boostReason,
    this.onView,
    this.onTagFilter,
  });

  @override
  State<_MeetupCard> createState() => _MeetupCardState();
}

class _MeetupCardState extends State<_MeetupCard> {
  Meetup get meetup => widget.meetup;
  final _meetupService = MeetupService();

  // ── Design tokens (Figma-exact) ────────────────────────────────
  static const _cardText = HuddlColors.textDark;     // primary dark text — Figma #42464C
  static const _cardMeta = HuddlColors.textTertiary; // secondary gray meta — Figma #949494

  bool get _isFull =>
      meetup.maxAttendees != null &&
      meetup.attendeeCount >= meetup.maxAttendees!;

  void _handleJoin(BuildContext context) {
    HapticFeedback.mediumImpact();
    if (!meetup.isGoing) {
      // Show green "You're going" toast
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "You're going to \${meetup.title}!",
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: HuddlColors.teal,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    try {
      _meetupService.toggleGoing(meetup.id);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't update RSVP. Please try again."),
          backgroundColor: HuddlColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final catStyle = _meetupCategoryStyle(meetup.category);
    final isRestricted = !widget.canAccess;

    // Price display
    final priceText = meetup.isFree
        ? 'Free'
        : '\u00A3${meetup.price?.toStringAsFixed(0) ?? ''}';
    final isFree = meetup.isFree;

    // "New" badge: fewer than 10 attendees = newly listed (mirrors Events card logic)
    final isNew = meetup.attendeeCount < 10;

    // Date + time display: "1 MAY 2021  ·  10 AM – 6 PM"
    final dateStr = meetup.dateDisplay.toUpperCase();
    final timeStr = meetup.timeDisplay;

    return Semantics(
      label: 'Meetup: ${meetup.title}, ${meetup.dateDisplay} ${meetup.timeDisplay}, ${meetup.location}, organised by ${meetup.organiserName}${isRestricted ? ", restricted access" : ""}',
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onView?.call();
          if (isRestricted) {
            widget.onAccessDenied?.call();
            return;
          }
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => MeetupDetailScreen(
                meetup: meetup,
                onTagFilter: widget.onTagFilter,
              ),
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
              // ── Hero image with Events-style badge overlay ──────────
              Stack(
                children: [
                  SizedBox(
                    height: 185,
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
                  // Subtle bottom gradient for readability (mirrors Events card)
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 55,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // ── Top-left: New + type badges (mirrors Events card) ──
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Row(
                      children: [
                        // "New" badge — amber/yellow, same as Events tab
                        if (isNew) ...[
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
                          const SizedBox(width: 6),
                        ],
                        // Type badge: "Private" lock only — shown when restricted
                        if (isRestricted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_outline, size: 11, color: Colors.white),
                                const SizedBox(width: 3),
                                Text(
                                  'Private',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
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
                  // ── Top-right: price badge (mirrors Events card) ───────
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
                        priceText,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isFree ? Colors.white : HuddlColors.blueDark,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Card body — Events-style: date · title · location + Join ─
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date + time row (calendar icon, mirrors Events card)
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 13, color: _cardMeta),
                        const SizedBox(width: 5),
                        Text(
                          '$dateStr  ·  $timeStr',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: _cardMeta,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Title
                    Text(
                      meetup.title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _cardText,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Location row
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 14, color: _cardMeta),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            meetup.location,
                            style: GoogleFonts.poppins(
                                fontSize: 12.5, color: _cardMeta),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Bottom row: avatar stack + attendee count (left) + grey pill Join (right)
                    Row(
                      children: [
                        // Overlapping real-photo avatar circles — mirrors Groups card
                        SizedBox(
                          width: 62,
                          height: 24,
                          child: Stack(
                            children: [
                              for (int i = 0; i < 3; i++)
                                Positioned(
                                  left: i * 18.0,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 1.5),
                                    ),
                                    child: ClipOval(
                                      child: Image.network(
                                        _kAttendeeAvatars[
                                            (meetup.id.hashCode + i) %
                                                _kAttendeeAvatars.length],
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Container(
                                          color: catStyle.color
                                              .withValues(alpha: 0.25),
                                          child: Icon(Icons.person,
                                              size: 12,
                                              color: catStyle.color),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Attendee count
                        Expanded(
                          child: Text(
                            '${meetup.attendeeCount} attending',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: _cardMeta,
                            ),
                          ),
                        ),
                        // Join / Joined / Full / Restricted button
                        Semantics(
                          label: isRestricted
                              ? 'Restricted meetup'
                              : _isFull && !meetup.isGoing
                                  ? 'This meetup is full'
                                  : meetup.isGoing
                                      ? 'You are going to ${meetup.title}'
                                      : 'Join ${meetup.title}',
                          button: true,
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onView?.call();
                              if (isRestricted) {
                                widget.onAccessDenied?.call();
                                return;
                              }
                              if (_isFull && !meetup.isGoing) return; // Full — block join
                              _handleJoin(context);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: isRestricted
                                    ? const Color(0xFFF0F0F0)
                                    : _isFull && !meetup.isGoing
                                        ? const Color(0xFFFFE5D5)
                                        : meetup.isGoing
                                            ? HuddlColors.teal
                                            : HuddlColors.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isRestricted
                                    ? 'Restricted'
                                    : _isFull && !meetup.isGoing
                                        ? 'Full'
                                        : meetup.isGoing
                                            ? 'Joined'
                                            : 'Join',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isRestricted
                                      ? HuddlColors.textTertiary
                                      : _isFull && !meetup.isGoing
                                          ? HuddlColors.primary
                                          : Colors.white,
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
        ),
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
  Map<String, dynamic> get event => widget.event;

  // Match reason chips removed — kept only in detail screen to reduce card clutter.

  @override
  Widget build(BuildContext context) {
    const Color eventTypeBlue = HuddlColors.blueDark;
    const Radius cardRadius = Radius.circular(20);
    final bool isFree = event['isFree'] == true;
    final bool isOnline = event['isOnline'] == true;
    final String imageUrl = event['imageUrl'] as String? ?? '';
    final String eventId = event['id'] as String? ?? '';
    final int attendees = event['attendees'] as int? ?? 0;
    // "New" badge: driven by isNew field (time-based 20-day window from ingestion).
    // Falls back to attendees < 10 for legacy events without isNew field.
    final bool isNew = event['isNew'] == true || attendees < 10;
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
                        // Type badge: "Online" only — shown for virtual events; in-person needs no label
                        if (isOnline) ...[  
                          if (isNew) const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: eventTypeBlue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Online',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
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
                    // Borough, match-reason chips, and AI source attribution
                    // removed from card — available in detail screen on tap.
                  ],
                ),
              ),

              // ── Bottom row: avatar stack + count (left) + Join pill (right) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  children: [
                    // Overlapping real-photo avatar circles — mirrors Groups/Meetups cards
                    SizedBox(
                      width: 62,
                      height: 24,
                      child: Stack(
                        children: [
                          for (int i = 0; i < 3; i++)
                            Positioned(
                              left: i * 18.0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                ),
                                child: ClipOval(
                                  child: Image.network(
                                    _kAttendeeAvatars[
                                        (eventId.hashCode + i) %
                                            _kAttendeeAvatars.length],
                                    width: 24,
                                    height: 24,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: eventTypeBlue.withValues(alpha: 0.25),
                                      child: Icon(Icons.person,
                                          size: 12, color: eventTypeBlue),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Attendee count
                    Expanded(
                      child: Text(
                        '$attendees attending',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: context.hc.textTertiary,
                        ),
                      ),
                    ),
                    // Join pill — Groups-style grey
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (_, __, ___) =>
                                EventDetailScreen(event: event),
                            transitionsBuilder: (_, animation, __, child) =>
                                FadeTransition(opacity: animation, child: child),
                            transitionDuration:
                                const Duration(milliseconds: 300),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Join',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF42464C),
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
              color: widget.isSelected
                  ? HuddlColors.primary
                  : context.hc.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: widget.isSelected
                  ? null
                  : Border.all(color: context.hc.divider, width: 0.5),
              boxShadow: widget.isSelected
                  ? [
                      BoxShadow(
                        color: HuddlColors.primary
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

// ═══════════════════════════════════════════════════════════════════════════════
// SMART NUDGE BANNER — Meetups tab contextual engagement prompt
// Thin orange-left-bordered card; dismissible; optional action button.
// Sits between the filter header and the meetup list, hidden during search.
// ═══════════════════════════════════════════════════════════════════════════════
class _SmartNudgeBanner extends StatelessWidget {
  final SmartNudge nudge;
  final VoidCallback onDismiss;
  final VoidCallback? onAction;

  const _SmartNudgeBanner({
    required this.nudge,
    required this.onDismiss,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HuddlColors.background,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: HuddlColors.primary, width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Emoji icon
            Text(nudge.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            // Text + optional action
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nudge.text,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF42464C),
                      height: 1.4,
                    ),
                  ),
                  if (onAction != null && nudge.actionLabel != null) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onAction!();
                      },
                      child: Text(
                        nudge.actionLabel!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Dismiss ✕
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onDismiss();
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 1),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: HuddlColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _LatLng ─────────────────────────────────────────────────────────────────
// Lightweight lat/lng holder used by the distance-filter cache in both
// _MeetupsTabState and _EventsTabState.  Avoids importing LatLng from the
// GeocodingService directly (which would create a circular dependency).
class _LatLng {
  final double lat;
  final double lng;
  const _LatLng(this.lat, this.lng);
}
