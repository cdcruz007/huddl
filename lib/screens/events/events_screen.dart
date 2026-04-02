import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';
import '../../services/event_service.dart';
import 'create_meetup_screen.dart';
import 'create_event_screen.dart';
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

  void _navigateToCreateEvent() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateEventScreen()),
    );
  }

  void _navigateToCreate() {
    _navigateToCreateMeetup();
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
                            icon: const Icon(Icons.search,
                                color: HuddlColors.textDark),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.notifications_outlined,
                                color: HuddlColors.textDark),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
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

// ═══════════════════════════════════════════════════════════════════════════════
// ALL TAB — combined feed of meet-ups and events, sorted by date
// ═══════════════════════════════════════════════════════════════════════════════

class _AllTab extends StatelessWidget {
  final MeetupService meetupService;
  final EventService eventService;
  final VoidCallback onCreateMeetup;
  final VoidCallback onCreateEvent;

  const _AllTab({
    required this.meetupService,
    required this.eventService,
    required this.onCreateMeetup,
    required this.onCreateEvent,
  });

  @override
  Widget build(BuildContext context) {
    final meetups = meetupService.meetups;
    final eventMaps = eventService.eventMaps;
    final totalItems = meetups.length + eventMaps.length;

    if (totalItems == 0) {
      return _EmptyState(
        icon: Icons.explore_outlined,
        title: 'Nothing here yet',
        subtitle: 'Be the first to create a meet-up\nor check back for upcoming events!',
        actionLabel: 'Create Meet-up',
        onAction: onCreateMeetup,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: totalItems + 1, // +1 for section divider
      itemBuilder: (context, index) {
        // Meet-ups section
        if (index < meetups.length) {
          final meetup = meetups[index];
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(
                  icon: Icons.groups_outlined,
                  label: 'Meet-ups',
                  color: HuddlColors.primaryDark,
                ),
                const SizedBox(height: 8),
                _MeetupCard(meetup: meetup),
              ],
            );
          }
          return _MeetupCard(meetup: meetup);
        }

        // Section divider
        if (index == meetups.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: _SectionLabel(
              icon: Icons.event_outlined,
              label: 'Events',
              color: HuddlColors.blue,
            ),
          );
        }

        // Events section (now from EventService)
        final eventIdx = index - meetups.length - 1;
        if (eventIdx >= 0 && eventIdx < eventMaps.length) {
          return _EventListCard(event: eventMaps[eventIdx]);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final allMeetups = widget.meetupService.meetups;
    final meetups = _filter == 'All'
        ? allMeetups
        : allMeetups.where((m) => m.category == _filter).toList();

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
                'All', 'Coffee', 'Playdate', 'Sport', 'Walk', 'Social', 'Other',
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
                // Free badge
                Positioned(
                  top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: HuddlColors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Free',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.white,
                      ),
                    ),
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
      return const _CatStyle(HuddlColors.paleBlue, Icons.directions_walk);
    case 'Social':
      return const _CatStyle(HuddlColors.lightBlue, Icons.celebration);
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
