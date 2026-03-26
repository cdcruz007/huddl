import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';

class MeetupDetailScreen extends StatefulWidget {
  final Meetup meetup;

  const MeetupDetailScreen({super.key, required this.meetup});

  @override
  State<MeetupDetailScreen> createState() => _MeetupDetailScreenState();
}

class _MeetupDetailScreenState extends State<MeetupDetailScreen> {
  final _meetupService = MeetupService();
  late Meetup _meetup;

  @override
  void initState() {
    super.initState();
    _meetup = widget.meetup;
    _meetupService.addListener(_refresh);
  }

  @override
  void dispose() {
    _meetupService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final updated = _meetupService.meetups
        .where((m) => m.id == _meetup.id)
        .toList();
    if (updated.isNotEmpty) {
      setState(() => _meetup = updated.first);
    }
  }

  void _toggleGoing() {
    _meetupService.toggleGoing(_meetup.id);
  }

  @override
  Widget build(BuildContext context) {
    final catStyle = _getCatStyle(_meetup.category);

    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: CustomScrollView(
        slivers: [
          // ── App bar with category colour ──────────────────────────
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: catStyle.color,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined, color: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Share link copied!'),
                      backgroundColor: HuddlColors.teal,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      catStyle.color,
                      catStyle.color.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(catStyle.icon, size: 32, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _meetup.category.toUpperCase(),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Body ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Container(
                  color: HuddlColors.white,
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _meetup.title,
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.textDark,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Organised by ',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: HuddlColors.textHint,
                            ),
                          ),
                          Text(
                            _meetup.organiserName,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Details section
                Container(
                  color: HuddlColors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: Icons.calendar_today_outlined,
                        iconColor: catStyle.color,
                        title: _meetup.dateDisplay,
                        subtitle: _meetup.timeDisplay,
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        iconColor: catStyle.color,
                        title: _meetup.location,
                        subtitle: 'Tap for directions',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: Icons.people_outline,
                        iconColor: catStyle.color,
                        title:
                            '${_meetup.attendeeCount}${_meetup.maxAttendees != null ? ' / ${_meetup.maxAttendees}' : ''} people going',
                        subtitle: _meetup.maxAttendees != null
                            ? '${_meetup.maxAttendees! - _meetup.attendeeCount} spots left'
                            : 'Open to all',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: Icons.attach_money_outlined,
                        iconColor: HuddlColors.teal,
                        title: 'Free',
                        subtitle: 'No cost to attend',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Description
                Container(
                  color: HuddlColors.white,
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _meetup.description,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: HuddlColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Attendees
                Container(
                  color: HuddlColors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Who\'s going',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.textDark,
                            ),
                          ),
                          Text(
                            '${_meetup.attendeeCount} people',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: HuddlColors.textHint,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _meetup.attendeeNames
                            .take(8)
                            .map((name) => _AttendeeChip(name: name))
                            .toList(),
                      ),
                      if (_meetup.attendeeCount > 8)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '+${_meetup.attendeeCount - 8} more',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: HuddlColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 100), // bottom padding for button
              ],
            ),
          ),
        ],
      ),

      // ── Bottom action button ───────────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Message organiser button
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Message ${_meetup.organiserName}'),
                      backgroundColor: HuddlColors.teal,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: HuddlColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Icon(Icons.chat_bubble_outline,
                    color: HuddlColors.primary, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            // Going / Not going button
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: _toggleGoing,
                icon: Icon(
                  _meetup.isGoing ? Icons.check_circle : Icons.groups,
                  color: Colors.white,
                  size: 20,
                ),
                label: Text(
                  _meetup.isGoing ? "I'm Going!" : "Count Me In",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _meetup.isGoing ? HuddlColors.teal : HuddlColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail row widget ─────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _DetailRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: HuddlColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Attendee chip ──────────────────────────────────────────────────────────

class _AttendeeChip extends StatelessWidget {
  final String name;

  const _AttendeeChip({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: HuddlColors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: HuddlColors.primary.withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: HuddlColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: HuddlColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category style helper ─────────────────────────────────────────────────

class _CatStyleInfo {
  final Color color;
  final IconData icon;
  const _CatStyleInfo(this.color, this.icon);
}

_CatStyleInfo _getCatStyle(String category) {
  switch (category) {
    case 'Coffee':
      return const _CatStyleInfo(Color(0xFF8D6E63), Icons.coffee);
    case 'Playdate':
      return _CatStyleInfo(HuddlColors.primary, Icons.child_care);
    case 'Sport':
      return const _CatStyleInfo(Color(0xFF43A047), Icons.sports_golf);
    case 'Walk':
      return const _CatStyleInfo(Color(0xFF00897B), Icons.directions_walk);
    case 'Social':
      return _CatStyleInfo(HuddlColors.purple, Icons.celebration);
    default:
      return _CatStyleInfo(HuddlColors.blue, Icons.groups);
  }
}
