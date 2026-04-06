import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/event_service.dart';
import '../../services/ai_event_recommender_service.dart';

class EventDetailScreen extends StatefulWidget {
  final Map<String, dynamic> event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final EventService _eventService = EventService();
  final AiEventRecommenderService _recommender = AiEventRecommenderService();
  ScoredEvent? _scoredEvent;
  bool _aiReady = false;

  @override
  void initState() {
    super.initState();
    _loadAiRecommendation();
  }

  Future<void> _loadAiRecommendation() async {
    await _recommender.initialize();
    final eventId = widget.event['id'] as String? ?? '';
    if (eventId.isEmpty) return;
    final allScored = _recommender.rankAllEvents();
    final match = allScored.where((s) => s.event.id == eventId);
    if (mounted) {
      setState(() {
        _scoredEvent = match.isNotEmpty ? match.first : null;
        _aiReady = true;
      });
    }
  }

  bool get _isRegistered {
    final id = widget.event['id'] as String? ?? '';
    return id.isNotEmpty && _eventService.isGoing(id);
  }

  bool get _isBookmarked {
    final id = widget.event['id'] as String? ?? '';
    return id.isNotEmpty && _eventService.isBookmarked(id);
  }

  void _shareEvent() {
    HapticFeedback.mediumImpact();
    final e = widget.event;
    final title = e['title'] as String? ?? 'Event';
    final date = e['date'] as String? ?? '';
    final location = e['location'] as String? ?? '';
    final organiser = e['organiser'] as String? ?? '';
    final shareText = '$title\n📅 $date\n📍 $location\nOrganised by $organiser\n\nShared via Huddl Connect';
    Clipboard.setData(ClipboardData(text: shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Event link copied to clipboard'),
          ],
        ),
        backgroundColor: HuddlColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

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
            expandedHeight: 240,
            pinned: true,
            backgroundColor: color,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: HuddlColors.gray900.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: HuddlColors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: HuddlColors.gray900.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: HuddlColors.white, size: 20,
                  ),
                  onPressed: () {
                    final id = widget.event['id'] as String? ?? '';
                    if (id.isNotEmpty) {
                      _eventService.toggleBookmark(id);
                      setState(() {});
                    }
                  },
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                decoration: BoxDecoration(
                  color: HuddlColors.gray900.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.share_outlined, color: HuddlColors.white, size: 20),
                  onPressed: () => _shareEvent(),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Cover image — supports data-URI, http, and asset paths
                  Hero(
                    tag: 'event_cover_${widget.event['id'] ?? ''}',
                    child: _buildEventDetailCover(
                      imageUrl: e['imageUrl'] as String? ?? '',
                      fallbackIcon: e['icon'] as IconData,
                      fallbackColor: color,
                    ),
                  ),
                  // Dark gradient overlay for text readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          HuddlColors.gray900.withValues(alpha: 0.1),
                          HuddlColors.gray900.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  // Price + Online badges at bottom
                  Positioned(
                    bottom: 16, left: 16,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: isFree ? HuddlColors.blue : color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isFree ? 'Free' : e['price'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.white,
                            ),
                          ),
                        ),
                        if (isOnline) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: HuddlColors.blue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.videocam, size: 14, color: HuddlColors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'Online',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: HuddlColors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Organiser badge at bottom right
                  Positioned(
                    bottom: 16, right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: HuddlColors.gray900.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.business, size: 13, color: HuddlColors.white),
                          const SizedBox(width: 4),
                          Text(
                            organiser,
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
            ),
          ),

          // ── Body ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + organiser
                Container(
                  color: context.hc.surface,
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
                          MemberAvatar(
                            name: organiser,
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Organised by',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: HuddlColors.textTertiary,
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

                // ── AI Discovered source section ─────────────────────
                if (e['isAiDiscovered'] == true)
                  _buildAiDiscoveredSection(e),
                if (e['isAiDiscovered'] == true)
                  const SizedBox(height: 8),

                // Details
                Container(
                  color: context.hc.surface,
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
                        iconColor: isFree ? HuddlColors.blue : color,
                        title: isFree ? 'Free' : e['price'] as String,
                        subtitle: isFree
                            ? 'No cost to attend'
                            : 'Per person — paid on registration',
                      ),
                      if ((e['borough'] as String? ?? '').isNotEmpty) ...[
                        const Divider(height: 24),
                        _DetailRow(
                          icon: Icons.map_outlined,
                          iconColor: HuddlColors.blue,
                          title: e['borough'] as String,
                          subtitle: 'Borough',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Description
                Container(
                  color: context.hc.surface,
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

                // Who's going section
                _buildAttendeesSection(e, color),
                const SizedBox(height: 8),

                // AI Recommendation section
                if (_aiReady && _scoredEvent != null && _scoredEvent!.reasons.isNotEmpty)
                  _buildAiRecommendationSection(_scoredEvent!),
                if (_aiReady && _scoredEvent != null && _scoredEvent!.reasons.isNotEmpty)
                  const SizedBox(height: 8),

                // What to expect
                Container(
                  color: context.hc.surface,
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
                        color: HuddlColors.blue,
                        text: 'Professional facilitators',
                      ),
                      _ExpectItem(
                        icon: Icons.check_circle_outline,
                        color: HuddlColors.blue,
                        text: 'All materials provided',
                      ),
                      _ExpectItem(
                        icon: Icons.check_circle_outline,
                        color: HuddlColors.blue,
                        text: isOnline
                            ? 'Interactive online session'
                            : 'Safe, family-friendly venue',
                      ),
                      _ExpectItem(
                        icon: Icons.check_circle_outline,
                        color: HuddlColors.blue,
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
          color: context.hc.surface,
          boxShadow: [
            BoxShadow(
              color: HuddlColors.gray900.withValues(alpha: 0.06),
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
                        color: HuddlColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            // Register button
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  final id = widget.event['id'] as String? ?? '';
                  if (id.isNotEmpty) {
                    _eventService.toggleGoing(id);
                  }
                  setState(() {});
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

  // ── AI Recommendation section ────────────────────────────────────────
  Widget _buildAiRecommendationSection(ScoredEvent scored) {
    final reasons = scored.reasons.take(4).toList();
    final scorePercent = scored.score.round();

    return Container(
      color: context.hc.surface,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      'Why we recommend this',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textDark,
                      ),
                    ),
                    Text(
                      'AI-matched to your family profile',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: HuddlColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$scorePercent% match',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Reason list
          ...reasons.map((reason) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3580F0).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(reason.emoji, style: const TextStyle(fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      reason.label,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── AI Discovered source section ────────────────────────────────────
  Widget _buildAiDiscoveredSection(Map<String, dynamic> e) {
    final sourceName = e['aiSourceName'] as String? ?? 'the web';
    final sourceIcon = e['aiSourceIcon'] as IconData? ?? Icons.language;

    return Container(
      color: context.hc.surface,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
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
                      'AI Discovered Event',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textDark,
                      ),
                    ),
                    Text(
                      'Found automatically by our AI scanner',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Source details
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF3580F0).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF3580F0).withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              children: [
                // Source row
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3580F0).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(sourceIcon, size: 18, color: const Color(0xFF3580F0)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Discovered on',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: HuddlColors.textHint,
                            ),
                          ),
                          Text(
                            sourceName,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF3580F0),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'AI Found',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // How it works explanation
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: HuddlColors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Color(0xFF3580F0)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Our AI scans local event listings, council sites, and community boards daily to find events near you.',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: HuddlColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Attendees section with profile photos ─────────────────────────────
  Widget _buildAttendeesSection(Map<String, dynamic> e, Color color) {
    final int attendeeCount = e['attendees'] as int? ?? 0;
    // Generate sample attendee names for the event
    final attendeeNames = <String>[
      'Sarah Mitchell', 'Emma Collins', 'James Whitfield',
      'Lucy Brennan', 'Oliver Chen', 'Priya Sharma',
      'Kate Nguyen', 'Fatima Hassan', 'Liam O\'Brien', 'Sophie Andrews',
    ];

    return Container(
      color: context.hc.surface,
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
                '$attendeeCount people',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: HuddlColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Stacked avatar row
          SizedBox(
            height: 44,
            child: Row(
              children: [
                ...attendeeNames.take(6).toList().asMap().entries.map((entry) {
                  return Align(
                    widthFactor: entry.key == 0 ? 1.0 : 0.65,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: HuddlColors.white, width: 2),
                      ),
                      child: MemberAvatar(
                        name: entry.value,
                        size: 36,
                      ),
                    ),
                  );
                }),
                if (attendeeCount > 6)
                  Align(
                    widthFactor: 0.65,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.15),
                        border: Border.all(color: HuddlColors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '+${attendeeCount - 6}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Named attendee chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: attendeeNames.take(8).map((name) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: HuddlColors.background,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MemberAvatar(name: name, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      name.split(' ').first,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.textDark,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
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
                  color: HuddlColors.textTertiary,
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

// ── Universal cover-image builder for event detail ─────────────────────────
Widget _buildEventDetailCover({
  required String imageUrl,
  required IconData fallbackIcon,
  required Color fallbackColor,
}) {
  Widget gradientFallback({bool showIcon = true}) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [fallbackColor, fallbackColor.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: showIcon
            ? Center(child: Icon(fallbackIcon, size: 48, color: HuddlColors.white))
            : null,
      );

  if (imageUrl.isEmpty) return gradientFallback();

  // base64 data-URI (user-uploaded)
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
          errorBuilder: (_, __, ___) => gradientFallback(),
        );
      }
    } catch (_) {}
    return gradientFallback();
  }

  // http(s) URL — use Image.network for reliable web rendering
  if (imageUrl.startsWith('http')) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return gradientFallback(showIcon: false);
      },
      errorBuilder: (_, __, ___) => gradientFallback(),
    );
  }

  // asset path
  if (imageUrl.startsWith('assets/')) {
    return Image.asset(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => gradientFallback(),
    );
  }

  return gradientFallback();
}
