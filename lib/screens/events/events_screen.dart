import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _meetupService.addListener(_refresh);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _meetupService.removeListener(_refresh);
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
    // Meetup service notifies listeners automatically
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
                        'Discover',
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
                  // ── Tabs ──────────────────────────────────────────
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'All'),
                      Tab(text: 'Meet-ups'),
                      Tab(text: 'Events'),
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
            // ── Tab content ────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _AllTab(
                    meetupService: _meetupService,
                    onCreateMeetup: _navigateToCreateMeetup,
                  ),
                  _MeetupsTab(
                    meetupService: _meetupService,
                    onCreateMeetup: _navigateToCreateMeetup,
                  ),
                  const _EventsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      // ── FAB ──────────────────────────────────────────────────────
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: HuddlColors.primaryGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: HuddlColors.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _navigateToCreateMeetup,
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: HuddlColors.white),
          label: Text(
            'Create Meet-up',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: HuddlColors.white,
            ),
          ),
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
  final VoidCallback onCreateMeetup;

  const _AllTab({required this.meetupService, required this.onCreateMeetup});

  @override
  Widget build(BuildContext context) {
    final meetups = meetupService.meetups;
    // Combine: meetups first (as cards), then events
    final totalItems = meetups.length + _thirdPartyEvents.length;

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
                  color: HuddlColors.teal,
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

        // Events section
        final eventIdx = index - meetups.length - 1;
        if (eventIdx >= 0 && eventIdx < _thirdPartyEvents.length) {
          return _EventListCard(event: _thirdPartyEvents[eventIdx]);
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

class _EventsTab extends StatefulWidget {
  const _EventsTab();

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final events = _filter == 'All'
        ? _thirdPartyEvents
        : _thirdPartyEvents.where((e) {
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
                  title: 'No events match',
                  subtitle: 'Try a different filter to find events.',
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
        margin: const EdgeInsets.only(bottom: 12),
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
        child: Column(
          children: [
            // ── Top: category banner ───────────────────────────────
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: catStyle.color,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Icon ───────────────────────────────────────────
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: catStyle.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(catStyle.icon, size: 24, color: catStyle.color),
                  ),
                  const SizedBox(width: 12),
                  // ── Details ────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title + category badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                meetup.title,
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: catStyle.color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                meetup.category,
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: catStyle.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Date + time
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                size: 12, color: HuddlColors.textHint),
                            const SizedBox(width: 4),
                            Text(
                              meetup.dateDisplay,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.access_time,
                                size: 12, color: HuddlColors.textHint),
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
                            const Icon(Icons.location_on_outlined,
                                size: 12, color: HuddlColors.textHint),
                            const SizedBox(width: 4),
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
                        const SizedBox(height: 8),
                        // Bottom row: organiser + attendees
                        Row(
                          children: [
                            // Organiser avatar
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: HuddlColors.primary.withValues(alpha: 0.15),
                              child: Text(
                                meetup.organiserName.isNotEmpty
                                    ? meetup.organiserName[0].toUpperCase()
                                    : '?',
                                style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: HuddlColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              meetup.organiserName,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.people_outline,
                                size: 14, color: HuddlColors.textHint),
                            const SizedBox(width: 4),
                            Text(
                              '${meetup.attendeeCount}${meetup.maxAttendees != null ? '/${meetup.maxAttendees}' : ''} going',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
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
    final String organiser = event['organiser'] as String? ?? '';

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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left: coloured icon area ───────────────────────────
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: eventColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                event['icon'] as IconData,
                size: 26,
                color: eventColor,
              ),
            ),
            const SizedBox(width: 12),
            // ── Right: details ─────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + bookmark
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          event['title'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.bookmark_border,
                          size: 18, color: HuddlColors.textHint),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Date + time + price badge
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 12, color: HuddlColors.textHint),
                      const SizedBox(width: 4),
                      Text(
                        event['date'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        event['time'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: HuddlColors.textHint,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isFree
                              ? HuddlColors.teal.withValues(alpha: 0.1)
                              : HuddlColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isFree ? 'Free' : event['price'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color:
                                isFree ? HuddlColors.teal : HuddlColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Location + attendees
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: HuddlColors.textHint),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event['location'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: HuddlColors.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.people_outline,
                          size: 12, color: HuddlColors.textHint),
                      const SizedBox(width: 4),
                      Text(
                        '${event['attendees']} going',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: HuddlColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  if (organiser.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.business_outlined,
                            size: 12, color: HuddlColors.textHint),
                        const SizedBox(width: 4),
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
      return const _CatStyle(Color(0xFF8D6E63), Icons.coffee);
    case 'Playdate':
      return _CatStyle(HuddlColors.primary, Icons.child_care);
    case 'Sport':
      return const _CatStyle(Color(0xFF43A047), Icons.sports_golf);
    case 'Walk':
      return const _CatStyle(Color(0xFF00897B), Icons.directions_walk);
    case 'Social':
      return _CatStyle(HuddlColors.purple, Icons.celebration);
    default:
      return _CatStyle(HuddlColors.blue, Icons.groups);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3RD PARTY EVENTS DATA — company / organisation advertised events
// ═══════════════════════════════════════════════════════════════════════════════

final _thirdPartyEvents = [
  {
    'title': 'Baby Sensory Play Session',
    'description':
        'A fun sensory play session designed for babies aged 0-12 months. Come explore different textures, sounds and colours. Run by qualified early childhood educators with 10+ years experience. All materials provided.',
    'date': 'SAT, MAR 15',
    'time': '10:00 - 11:30 AM',
    'location': 'Community Centre, Carlton',
    'attendees': 24,
    'isFree': false,
    'price': '\$18',
    'isOnline': false,
    'color': HuddlColors.primary,
    'icon': Icons.child_care,
    'organiser': 'Little Explorers Co.',
    'organiserLogo': '',
  },
  {
    'title': 'Toddler Music & Movement',
    'description':
        'Interactive music and movement class for toddlers aged 1-3 years. Singing, dancing and instrument play! Led by professional musicians who specialise in early childhood music education.',
    'date': 'WED, MAR 19',
    'time': '2:00 - 3:00 PM',
    'location': 'Music Room, Brunswick',
    'attendees': 18,
    'isFree': false,
    'price': '\$15',
    'isOnline': false,
    'color': HuddlColors.teal,
    'icon': Icons.music_note,
    'organiser': 'Tiny Tunes Academy',
    'organiserLogo': '',
  },
  {
    'title': 'New Parents Workshop',
    'description':
        'A comprehensive workshop covering baby basics: feeding, sleeping, and settling techniques from certified professionals. Morning tea provided. Certificate of completion included.',
    'date': 'SAT, MAR 22',
    'time': '1:00 - 4:00 PM',
    'location': 'Health Hub, Collingwood',
    'attendees': 20,
    'isFree': false,
    'price': '\$45',
    'isOnline': false,
    'color': const Color(0xFFE8A838),
    'icon': Icons.school,
    'organiser': 'Parent Pro Australia',
    'organiserLogo': '',
  },
  {
    'title': 'Online: Sleep Training Masterclass',
    'description':
        'Join our expert paediatric sleep consultant for a live interactive webinar on establishing healthy sleep routines for babies 4-18 months. Q&A session included.',
    'date': 'THU, MAR 27',
    'time': '7:30 - 9:00 PM',
    'location': 'Online (Zoom)',
    'attendees': 85,
    'isFree': false,
    'price': '\$25',
    'isOnline': true,
    'color': HuddlColors.blue,
    'icon': Icons.nightlight_round,
    'organiser': 'Sleep Well Babies',
    'organiserLogo': '',
  },
  {
    'title': 'Family Fun Day — Free Entry',
    'description':
        'A free community event with face painting, balloon artists, petting zoo, food trucks and live music. Bring the whole family for a day of fun! Organised by the Carlton Community Association.',
    'date': 'SUN, MAR 30',
    'time': '10:00 AM - 3:00 PM',
    'location': 'Princes Park, Carlton North',
    'attendees': 150,
    'isFree': true,
    'price': '',
    'isOnline': false,
    'color': HuddlColors.purple,
    'icon': Icons.celebration,
    'organiser': 'Carlton Community Assoc.',
    'organiserLogo': '',
  },
  {
    'title': 'Baby First Aid & CPR',
    'description':
        'Essential baby and child first aid course. Learn CPR, choking response, and how to handle common childhood injuries. Accredited certification included.',
    'date': 'SAT, APR 5',
    'time': '9:00 AM - 1:00 PM',
    'location': 'St Vincent\'s Hospital, Fitzroy',
    'attendees': 30,
    'isFree': false,
    'price': '\$65',
    'isOnline': false,
    'color': const Color(0xFFE53935),
    'icon': Icons.medical_services_outlined,
    'organiser': 'Red Cross Australia',
    'organiserLogo': '',
  },
];
