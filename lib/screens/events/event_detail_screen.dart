import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';

class EventDetailScreen extends StatefulWidget {
  final Map<String, dynamic> event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  bool _isBookmarked = false;
  bool _isRegistered = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final Color color = e['color'] as Color;
    final bool isFree = e['isFree'] == true;
    final String organiser = e['organiser'] as String? ?? 'Unknown';
    final bool isOnline = e['isOnline'] == true;

    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Header ───────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: color,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: Colors.white,
                ),
                onPressed: () => setState(() => _isBookmarked = !_isBookmarked),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined, color: Colors.white),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.7)],
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
                        child: Icon(e['icon'] as IconData,
                            size: 32, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      // Price badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isFree ? 'FREE EVENT' : e['price'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
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
                // Title + organiser
                Container(
                  color: HuddlColors.white,
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e['title'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.textDark,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.business, size: 14, color: color),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Organised by',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: HuddlColors.textHint,
                                ),
                              ),
                              Text(
                                organiser,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Details
                Container(
                  color: HuddlColors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: Icons.calendar_today_outlined,
                        iconColor: color,
                        title: e['date'] as String,
                        subtitle: e['time'] as String,
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: isOnline
                            ? Icons.videocam_outlined
                            : Icons.location_on_outlined,
                        iconColor: color,
                        title: e['location'] as String,
                        subtitle: isOnline
                            ? 'Online event — link shared on registration'
                            : 'Tap for directions',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: Icons.people_outline,
                        iconColor: color,
                        title: '${e['attendees']} people going',
                        subtitle: 'Registrations open',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: Icons.attach_money,
                        iconColor: isFree ? HuddlColors.teal : color,
                        title: isFree ? 'Free' : e['price'] as String,
                        subtitle: isFree
                            ? 'No cost to attend'
                            : 'Per person — paid on registration',
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
                        'About this event',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        e['description'] as String? ?? 'No description provided.',
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

                // What to expect
                Container(
                  color: HuddlColors.white,
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What to expect',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ExpectItem(
                        icon: Icons.check_circle_outline,
                        color: HuddlColors.teal,
                        text: 'Professional facilitators',
                      ),
                      _ExpectItem(
                        icon: Icons.check_circle_outline,
                        color: HuddlColors.teal,
                        text: 'All materials provided',
                      ),
                      _ExpectItem(
                        icon: Icons.check_circle_outline,
                        color: HuddlColors.teal,
                        text: isOnline
                            ? 'Interactive online session'
                            : 'Safe, family-friendly venue',
                      ),
                      _ExpectItem(
                        icon: Icons.check_circle_outline,
                        color: HuddlColors.teal,
                        text: 'Certificate of attendance',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),

      // ── Bottom CTA ──────────────────────────────────────────────────
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
            // Price display
            if (!isFree)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e['price'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.textDark,
                      ),
                    ),
                    Text(
                      'per person',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            // Register button
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _isRegistered = !_isRegistered);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_isRegistered
                          ? 'Registered! You\'ll receive a confirmation email.'
                          : 'Registration cancelled.'),
                      backgroundColor:
                          _isRegistered ? HuddlColors.teal : HuddlColors.textSecondary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isRegistered ? HuddlColors.teal : color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Text(
                  _isRegistered
                      ? 'Registered ✓'
                      : (isFree ? 'Register — Free' : 'Register & Pay'),
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ───────────────────────────────────────────────────────

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

class _ExpectItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _ExpectItem({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: HuddlColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
