import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/event_service.dart';
import '../../services/ai_event_recommender_service.dart';
import '../../services/invisible_ai_service.dart';
import '../groups/forward_message_sheet.dart';

class EventDetailScreen extends StatefulWidget {
  final Map<String, dynamic> event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final EventService _eventService = EventService();
  final AiEventRecommenderService _recommender = AiEventRecommenderService();
  final InvisibleAiService _invisibleAi = InvisibleAiService();
  ScoredEvent? _scoredEvent;
  AiEventSummary? _aiSummary;
  bool _aiReady = false;
  bool? _userFeedback;

  @override
  void initState() {
    super.initState();
    _loadAiRecommendation();
  }

  Future<void> _loadAiRecommendation() async {
    await _recommender.initialize();
    await _invisibleAi.initialize();
    final eventId = widget.event['id'] as String? ?? '';
    if (eventId.isEmpty) return;
    final allScored = _recommender.rankAllEvents();
    final match = allScored.where((s) => s.event.id == eventId);
    // Generate AI summary
    final summary = _invisibleAi.summarizeEvent(widget.event);
    // Track view
    _invisibleAi.trackEventView(widget.event);
    // Check existing feedback
    final fb = _invisibleAi.getFeedback(eventId);
    if (mounted) {
      setState(() {
        _scoredEvent = match.isNotEmpty ? match.first : null;
        _aiSummary = summary;
        _userFeedback = fb;
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
    final time = e['time'] as String? ?? '';
    final location = e['location'] as String? ?? '';
    final organiser = e['organiser'] as String? ?? '';
    final shareText = title.isNotEmpty
        ? '$title\n📅 $date${time.isNotEmpty ? ' · $time' : ''}\n📍 $location${organiser.isNotEmpty ? '\nBy $organiser' : ''}'
        : 'Check out this event on Huddl!';

    // Build a serialisable eventData map for the rich card
    // Note: Color and IconData cannot be serialised, so we use
    // the category string to reconstruct styling in EventInviteCard.
    final eventData = <String, dynamic>{
      'id': e['id'] ?? '',
      'title': title,
      'date': date,
      'time': time,
      'location': location,
      'organiser': organiser,
      'category': e['category'] ?? 'community',
      'isFree': e['isFree'] ?? true,
      'price': e['price'] ?? '',
      'attendees': e['attendees'] ?? 0,
      'imageUrl': e['imageUrl'] ?? '',
      'isOnline': e['isOnline'] ?? false,
      'description': e['description'] ?? '',
      'borough': e['borough'] ?? '',
    };

    showForwardSheet(
      context: context,
      messageText: shareText,
      eventData: eventData,
      isEventCard: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    // Always use the brand primary for interactive elements (buttons, outlines)
    const Color color = HuddlColors.primary;
    final bool isFree = e['isFree'] == true;
    final String organiser = e['organiser'] as String? ?? 'Unknown';
    final bool isOnline = e['isOnline'] == true;

    return Scaffold(
      backgroundColor: context.hc.scaffold,
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
                icon: Icon(Icons.arrow_back, color: context.hc.surface, size: 20),
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
                    color: context.hc.surface, size: 20,
                  ),
                  onPressed: () async {
                    final id = widget.event['id'] as String? ?? '';
                    if (id.isNotEmpty) {
                      await _eventService.toggleBookmark(id);
                      if (mounted) setState(() {});
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
                  icon: Icon(Icons.share_outlined, color: context.hc.surface, size: 20),
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
                      fallbackIcon: (e['icon'] is IconData ? e['icon'] as IconData : null) ?? Icons.event_outlined,
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
                            color: isFree ? HuddlColors.teal : color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isFree ? 'Free' : (e['price'] as String? ?? ''),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.hc.surface,
                            ),
                          ),
                        ),
                        if (isOnline) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: HuddlColors.teal,
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
                                    color: context.hc.surface,
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
                              color: context.hc.surface,
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
                        e['title'] as String? ?? 'Event',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary,
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
                                  color: context.hc.textTertiary,
                                ),
                              ),
                              Text(
                                organiser,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.hc.textPrimary,
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

                // ── AI Quick Summary (invisible AI) ─────────────────
                if (_aiReady && _aiSummary != null)
                  _buildAiSummarySection(_aiSummary!),
                if (_aiReady && _aiSummary != null)
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
                        title: e['date'] as String? ?? '',
                        subtitle: e['time'] as String? ?? '',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: isOnline
                            ? Icons.videocam_outlined
                            : Icons.location_on_outlined,
                        iconColor: color,
                        title: e['location'] as String? ?? '',
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
                        title: isFree ? 'Free' : (e['price'] as String? ?? ''),
                        subtitle: isFree
                            ? 'No cost to attend'
                            : 'Per person — paid on registration',
                      ),
                      if ((e['borough'] as String? ?? '').isNotEmpty) ...[
                        const Divider(height: 24),
                        _DetailRow(
                          icon: Icons.map_outlined,
                          iconColor: context.hc.textSecondary,
                          title: e['borough'] as String? ?? '',
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
                          color: context.hc.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        e['description'] as String? ?? 'No description provided.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: context.hc.textSecondary,
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

                // AI Recommendation section with feedback
                if (_aiReady && _scoredEvent != null && _scoredEvent!.reasons.isNotEmpty)
                  _buildAiRecommendationSection(_scoredEvent!),
                if (_aiReady && _scoredEvent != null && _scoredEvent!.reasons.isNotEmpty)
                  const SizedBox(height: 8),

                // AI Feedback (human-in-the-loop)
                if (_aiReady && _scoredEvent != null && _scoredEvent!.score >= 40)
                  _buildAiFeedbackSection(),
                if (_aiReady && _scoredEvent != null && _scoredEvent!.score >= 40)
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
                          color: context.hc.textPrimary,
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

      // ── Bottom CTA: single "Join" button ──────────────────────────
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
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              HapticFeedback.mediumImpact();
              final id = widget.event['id'] as String? ?? '';
              if (id.isNotEmpty) {
                final nowGoing = _eventService.toggleGoing(id);
                if (nowGoing) {
                  await _eventService.createEventGroupChat(id);
                }
              }
              setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(
                          _isRegistered ? Icons.check_circle : Icons.close,
                          color: context.hc.surface,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_isRegistered
                              ? 'Joined! Check Messages for the event chat.'
                              : 'You\'ve left this event.'),
                        ),
                      ],
                    ),
                    backgroundColor:
                        _isRegistered ? HuddlColors.teal : HuddlColors.textSecondary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              }
            },
            icon: Icon(
              _isRegistered ? Icons.check_circle : Icons.group_add_outlined,
              color: context.hc.surface,
              size: 20,
            ),
            label: Text(
              _isRegistered ? 'Joined' : 'Join',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.hc.surface,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRegistered ? HuddlColors.teal : color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              padding: const EdgeInsets.symmetric(vertical: 15),
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }

  // ── AI Quick Summary section ──────────────────────────────────────────
  Widget _buildAiSummarySection(AiEventSummary summary) {
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: HuddlColors.teal,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.star_rounded, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Summary',
                  style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600, color: context.hc.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: HuddlColors.teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  summary.vibe,
                  style: GoogleFonts.poppins(
                    fontSize: 10, fontWeight: FontWeight.w500, color: HuddlColors.teal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Suitability line
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: HuddlColors.teal.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.family_restroom, size: 14, color: HuddlColors.teal),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    summary.suitability,
                    style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.teal),
                  ),
                ),
              ],
            ),
          ),
          // Key highlights
          if (summary.highlights.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...summary.highlights.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.check_circle, size: 14, color: HuddlColors.teal),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      h,
                      style: GoogleFonts.poppins(
                        fontSize: 12, color: context.hc.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  // ── AI Feedback section (human-in-the-loop) ─────────────────────────────
  Widget _buildAiFeedbackSection() {
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: HuddlColors.teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.rate_review, size: 14, color: HuddlColors.teal),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Was this recommendation helpful?',
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w500, color: context.hc.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_userFeedback != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _userFeedback!
                    ? HuddlColors.teal.withValues(alpha: 0.06)
                    : HuddlColors.textHint.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _userFeedback! ? Icons.thumb_up_alt : Icons.thumb_down_alt,
                    size: 18,
                    color: _userFeedback! ? HuddlColors.teal : context.hc.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _userFeedback!
                          ? 'Thanks! We\u2019ll show more events like this.'
                          : 'Got it \u2014 we\u2019ll adjust future recommendations.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: _userFeedback! ? HuddlColors.teal : context.hc.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      final id = widget.event['id'] as String? ?? '';
                      if (id.isNotEmpty) {
                        _invisibleAi.submitFeedback(id, true);
                        setState(() => _userFeedback = true);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: HuddlColors.teal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.thumb_up_alt_outlined, size: 18, color: HuddlColors.teal),
                          const SizedBox(width: 8),
                          Text('Yes, helpful', style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.teal)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      final id = widget.event['id'] as String? ?? '';
                      if (id.isNotEmpty) {
                        _invisibleAi.submitFeedback(id, false);
                        setState(() => _userFeedback = false);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: context.hc.scaffold,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.hc.divider),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.thumb_down_alt_outlined, size: 18,
                            color: context.hc.textTertiary.withValues(alpha: 0.7)),
                          const SizedBox(width: 8),
                          Text('Not for me', style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w500, color: context.hc.textTertiary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            'Your feedback helps us show you more of what suits your family',
            style: GoogleFonts.poppins(fontSize: 10, color: context.hc.textTertiary),
          ),
        ],
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
                  color: HuddlColors.teal,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.star_rounded, color: Colors.white, size: 18),
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
                        color: context.hc.textPrimary,
                      ),
                    ),
                    Text(
                      'Matched to your family',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: context.hc.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: HuddlColors.teal,
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
                      color: HuddlColors.teal.withValues(alpha: 0.08),
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
                        color: context.hc.textSecondary,
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
                  color: HuddlColors.teal,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.star_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Newly found for you',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.hc.textPrimary,
                      ),
                    ),
                    Text(
                      'Spotted from local listings and community boards',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: context.hc.textTertiary,
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
              color: HuddlColors.teal.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: HuddlColors.teal.withValues(alpha: 0.12),
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
                        color: HuddlColors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(sourceIcon, size: 18, color: HuddlColors.teal),
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
                              color: context.hc.textTertiary,
                            ),
                          ),
                          Text(
                            sourceName,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: HuddlColors.teal,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'New Find',
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
                    color: context.hc.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: HuddlColors.teal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'We search local listings, council sites, and community boards daily to find events near you.',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: context.hc.textSecondary,
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

  // ── Attendees section ─────────────────────────────────────────────────
  Widget _buildAttendeesSection(Map<String, dynamic> e, Color color) {
    final int attendeeCount = e['attendees'] as int? ?? 0;

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
                  color: context.hc.textPrimary,
                ),
              ),
              Text(
                attendeeCount == 0
                    ? 'Be the first!'
                    : '$attendeeCount ${attendeeCount == 1 ? 'person' : 'people'}',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: attendeeCount == 0 ? color : context.hc.textTertiary,
                  fontWeight: attendeeCount == 0 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
          if (attendeeCount == 0) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.group_outlined, color: color.withValues(alpha: 0.5), size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'No one has RSVP\'d yet.\nBe the first to go!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: context.hc.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            // Count badge — real attendee count from Firestore, no fake names
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, color: color, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '$attendeeCount ${attendeeCount == 1 ? 'parent' : 'parents'} going',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                  color: context.hc.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: context.hc.textTertiary,
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
              color: context.hc.textSecondary,
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
