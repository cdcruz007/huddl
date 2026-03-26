import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                        'Events',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.search, color: HuddlColors.textDark),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.filter_list, color: HuddlColors.textDark),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Tabs
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Upcoming'),
                      Tab(text: 'Going'),
                      Tab(text: 'Invitations'),
                    ],
                    labelColor: HuddlColors.primary,
                    unselectedLabelColor: HuddlColors.textHint,
                    labelStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    indicatorColor: HuddlColors.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: HuddlColors.divider,
                  ),
                ],
              ),
            ),
            // Filter chips
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: ['All', 'Free', 'Paid', 'Online', 'In-Person']
                      .map((filter) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: HuddlChip(
                              label: filter,
                              isSelected: _selectedFilter == filter,
                              onTap: () {
                                setState(() => _selectedFilter = filter);
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _UpcomingTab(),
                  _GoingTab(),
                  _InvitationsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
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
          onPressed: () {},
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: HuddlColors.white),
          label: Text(
            'Create',
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

class _UpcomingTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      itemBuilder: (context, index) {
        final event = _events[index];
        return _EventListCard(event: event);
      },
    );
  }
}

class _EventListCard extends StatelessWidget {
  final Map<String, dynamic> event;

  const _EventListCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final Color eventColor = event['color'] as Color;
    final bool isFree = event['isFree'] == true;

    return Container(
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
          // ── Left: coloured icon area ─────────────────────────────
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
          // ── Right: details ───────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row with bookmark
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
                // Date + time + badge
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
                    // Free / price badge
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
                          color: isFree ? HuddlColors.teal : HuddlColors.primary,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoingTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final goingEvents = _events.take(2).toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: goingEvents.length,
      itemBuilder: (context, index) {
        return _EventListCard(event: goingEvents[index]);
      },
    );
  }
}

class _InvitationsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: HuddlColors.blueBackground,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.mail_outline,
              size: 40,
              color: HuddlColors.blue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No invitations yet',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When someone invites you to an event,\nit will appear here.',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: HuddlColors.textHint,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

final _events = [
  {
    'title': 'Baby Sensory Play Session',
    'description': 'A fun sensory play session designed for babies aged 0-12 months. Come explore different textures, sounds and colours.',
    'date': 'SAT, MAR 15',
    'time': '10:00 - 11:30 AM',
    'location': 'Community Centre, Carlton',
    'attendees': 24,
    'isFree': true,
    'price': '',
    'color': HuddlColors.primary,
    'icon': Icons.child_care,
  },
  {
    'title': 'Parents Coffee & Chat Morning',
    'description': 'Casual meet-up for parents in the area. Grab a coffee and make new friends while the kids play.',
    'date': 'MON, MAR 17',
    'time': '9:30 - 11:00 AM',
    'location': 'Little Bean Cafe, Fitzroy',
    'attendees': 12,
    'isFree': true,
    'price': '',
    'color': HuddlColors.blue,
    'icon': Icons.coffee,
  },
  {
    'title': 'Toddler Music & Movement',
    'description': 'Interactive music and movement class for toddlers aged 1-3 years. Singing, dancing and instrument play!',
    'date': 'WED, MAR 19',
    'time': '2:00 - 3:00 PM',
    'location': 'Music Room, Brunswick',
    'attendees': 18,
    'isFree': false,
    'price': '\$15',
    'color': HuddlColors.teal,
    'icon': Icons.music_note,
  },
  {
    'title': 'Pram Walk & Picnic',
    'description': 'Join us for a gentle walk with prams through the park followed by a BYO picnic. All parents welcome!',
    'date': 'FRI, MAR 21',
    'time': '10:00 AM - 12:00 PM',
    'location': 'Edinburgh Gardens, North Fitzroy',
    'attendees': 32,
    'isFree': true,
    'price': '',
    'color': HuddlColors.purple,
    'icon': Icons.directions_walk,
  },
  {
    'title': 'New Parents Workshop',
    'description': 'A comprehensive workshop covering baby basics: feeding, sleeping, and settling techniques from certified professionals.',
    'date': 'SAT, MAR 22',
    'time': '1:00 - 4:00 PM',
    'location': 'Health Hub, Collingwood',
    'attendees': 20,
    'isFree': false,
    'price': '\$25',
    'color': const Color(0xFFE8A838),
    'icon': Icons.school,
  },
];
