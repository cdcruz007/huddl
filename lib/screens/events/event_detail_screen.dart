import 'package:flutter/material.dart';
import '../../theme/huddl_icons.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../widgets/common/huddl_button.dart';
import '../../services/event_service.dart';
import '../../services/ai_event_recommender_service.dart';
import '../../services/invisible_ai_service.dart';
import '../../constants/app_text_styles.dart';

// ── matchReasonIcons: maps Cloud Function icon keys → Flutter IconData ──────
// Keys match the strings written by the generateEventRecommendations CF.
const Map<String, IconData> _matchReasonIcons = {
  'location' : HuddlIcons.locationPinFill,
  'age'      : HuddlIcons.childCare,
  'star'     : HuddlIcons.starFill,
  'calendar' : HuddlIcons.calendar,
  'category' : HuddlIcons.topic,
  'uk_wide'  : HuddlIcons.language,
  'people'   : HuddlIcons.usersThree,
  'free'     : HuddlIcons.moneyOff,
  'online'   : HuddlIcons.videocam,
  'new'      : HuddlIcons.fiberNew,
};

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

  // ── Local AI state (summary + client-side fallback scoring) ──────────────
  ScoredEvent? _scoredEvent;
  AiEventSummary? _aiSummary;
  bool _aiReady = false;

  // ── Firestore userRecommendations state ──────────────────────────────────
  // Populated by _loadFirestoreRecommendation() once Firebase read completes.
  int?  _firestoreMatchScore;                         // matchScore (0-100)
  List<Map<String, dynamic>> _firestoreMatchReasons = []; // [{icon,label}]
  bool? _firestoreIsDiscoverNew;                      // isDiscoverSomethingNew
  bool? _userFeedback;                                // feedbackGiven
  bool  _feedbackSubmitting = false;                  // CF call in-flight guard
  bool  _firestoreLoaded    = false;                  // read attempt done flag

  @override
  void initState() {
    super.initState();
    _loadAiRecommendation();
    _loadFirestoreRecommendation();
  }

  // ── Local AI load (summary + client-side fallback scoring) ───────────────
  Future<void> _loadAiRecommendation() async {
    await _recommender.initialize();
    await _invisibleAi.initialize();
    final eventId = widget.event['id'] as String? ?? '';
    if (eventId.isEmpty) return;
    final allScored = _recommender.rankAllEvents();
    final match = allScored.where((s) => s.event.id == eventId);
    final summary = _invisibleAi.summarizeEvent(widget.event);
    _invisibleAi.trackEventView(widget.event);
    if (mounted) {
      setState(() {
        _scoredEvent = match.isNotEmpty ? match.first : null;
        _aiSummary   = summary;
        _aiReady     = true;
      });
    }
  }

  // ── Firestore userRecommendations/{userId}/events/{eventId} read ─────────
  // Written by the generateEventRecommendations Cloud Function.
  // Falls back gracefully if user is unauthenticated or document doesn't exist.
  Future<void> _loadFirestoreRecommendation() async {
    final eventId = widget.event['id'] as String? ?? '';
    if (eventId.isEmpty) {
      if (mounted) setState(() => _firestoreLoaded = true);
      return;
    }
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (userId.isEmpty) {
        // Not signed in — use local feedback as fallback
        final localFb = _invisibleAi.getFeedback(eventId);
        if (mounted) setState(() { _userFeedback = localFb; _firestoreLoaded = true; });
        return;
      }

      final docSnap = await FirebaseFirestore.instance
          .collection('userRecommendations')
          .doc(userId)
          .collection('events')
          .doc(eventId)
          .get();

      if (!mounted) return;

      if (docSnap.exists) {
        final data = docSnap.data()!;

        // matchScore — number 0-100
        final score = (data['matchScore'] as num?)?.toInt();

        // matchReasons — [{icon: String, label: String}]
        final rawReasons = data['matchReasons'];
        final reasons = <Map<String, dynamic>>[];
        if (rawReasons is List) {
          for (final r in rawReasons) {
            if (r is Map) {
              reasons.add({
                'icon' : (r['icon']  as String? ?? 'star'),
                'label': (r['label'] as String? ?? ''),
              });
            }
          }
        }

        // isDiscoverSomethingNew — overrides the local Firestore default (false)
        final isDiscoverNew = data['isDiscoverSomethingNew'] as bool?;

        // feedbackGiven — previously persisted feedback
        final fb = data['feedbackGiven'] as bool?;

        setState(() {
          _firestoreMatchScore    = score;
          _firestoreMatchReasons  = reasons;
          _firestoreIsDiscoverNew = isDiscoverNew;
          _userFeedback           = fb;
          _firestoreLoaded        = true;
          // Push Cloud Function's isDiscoverSomethingNew into the event map so
          // the Summary section badge reflects the server-authoritative value.
          if (isDiscoverNew != null) {
            widget.event['isDiscoverSomethingNew'] = isDiscoverNew;
          }
        });
      } else {
        // No CF recommendation doc yet — load local feedback as fallback
        final localFb = _invisibleAi.getFeedback(eventId);
        setState(() { _userFeedback = localFb; _firestoreLoaded = true; });
      }
    } catch (_) {
      // Any error — graceful degradation; keep local scoring + local feedback
      if (mounted) setState(() => _firestoreLoaded = true);
    }
  }

  // ── recordRecommendationFeedback Cloud Function call ─────────────────────
  // Primary: calls the Cloud Function (persists to Firestore + updates user
  // likedCategories). Secondary: always writes locally via _invisibleAi for
  // offline resilience. CF failure (offline/not yet deployed) is silenced.
  Future<void> _submitRecommendationFeedback(bool isPositive) async {
    final id = widget.event['id'] as String? ?? '';
    if (id.isEmpty || _feedbackSubmitting) return;

    // Optimistic UI
    setState(() { _userFeedback = isPositive; _feedbackSubmitting = true; });

    // Always persist locally (offline resilience)
    _invisibleAi.submitFeedback(id, isPositive);

    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('recordRecommendationFeedback');
      await callable.call(<String, dynamic>{
        'eventId'   : id,
        'isHelpful' : isPositive,
      });
    } catch (_) {
      // CF unreachable (offline / not yet deployed) — local write is the fallback
    } finally {
      if (mounted) setState(() => _feedbackSubmitting = false);
    }
  }

  // ── Effective recommendation accessors ───────────────────────────────────
  // Prefers Firestore CF data; falls back to client-side scoring.

  /// Effective match score: CF value if available, else local scoring.
  int? get _effectiveMatchScore =>
      _firestoreMatchScore ?? _scoredEvent?.score.round();

  /// Show recommendation section when score ≥ 40 from either source.
  bool get _showRecommendationSection {
    if (_firestoreMatchScore != null) return _firestoreMatchScore! >= 40;
    return _scoredEvent != null && _scoredEvent!.score >= 40;
  }

  /// Show feedback widget once at least one data source has loaded.
  bool get _showFeedbackSection =>
      (_firestoreLoaded || _aiReady) && _showRecommendationSection;

  bool get _isRegistered {
    final id = widget.event['id'] as String? ?? '';
    return id.isNotEmpty && _eventService.isGoing(id);
  }

  /// True if the event date has passed — CTA shows "Ended" and is disabled.
  bool get _hasEnded {
    final dateStr = widget.event['date'] as String? ?? '';
    try {
      // Try to parse from dateTime field first (most reliable)
      final rawDt = widget.event['dateTime'];
      if (rawDt is DateTime) return rawDt.isBefore(DateTime.now());
      // Fallback: parse from date + time display strings
      // We use a simple heuristic: if date string contains a year < current year, it's ended
      if (dateStr.isEmpty) return false;
      // Try ISO format
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) return parsed.isBefore(DateTime.now());
    } catch (_) {}
    return false;
  }

  void _shareEvent() {
    HapticFeedback.mediumImpact();
    final e = widget.event;
    final title = e['title'] as String? ?? 'Event';
    final date = e['date'] as String? ?? '';
    final time = e['time'] as String? ?? '';
    final location = e['location'] as String? ?? '';
    final organiser = e['organiser'] as String? ?? '';
    final eventId = e['id'] as String? ?? '';

    // Build share text + deep-link for native OS share sheet
    final shareText = StringBuffer();
    if (title.isNotEmpty) shareText.write(title);
    if (date.isNotEmpty) shareText.write('\n📅 $date${time.isNotEmpty ? ' · $time' : ''}');
    if (location.isNotEmpty) shareText.write('\n📍 $location');
    if (organiser.isNotEmpty) shareText.write('\nBy $organiser');
    shareText.write('\n\nDiscover family events on Huddl!');
    if (eventId.isNotEmpty) {
      shareText.write('\nhttps://huddl.app/events/$eventId');
    }

    // Use native OS share sheet via share_plus
    Share.share(
      shareText.toString(),
      subject: title.isNotEmpty ? title : 'Check out this event on Huddl!',
    );
  }

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    // Brand primary for interactive elements (buttons, price badge, online badge)
    const Color color = HuddlColors.primary;
    // Passive metadata icons (date, location, people) — use textTertiary, not brand orange
    const Color metaIconColor = HuddlColors.textTertiary;
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
            backgroundColor: context.hc.surface,
            leading: _EventCircleButton(
              icon: HuddlIcons.arrowBack,
              onTap: () => Navigator.pop(context),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _EventCircleButton(
                  icon: HuddlIcons.share,
                  onTap: () => _shareEvent(),
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
                      fallbackIcon: (e['icon'] is IconData ? e['icon'] as IconData : null) ?? HuddlIcons.calendar,
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
                            color: isFree ? HuddlColors.success : color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isFree ? 'Free' : (e['price'] as String? ?? ''),
                            style: HuddlText.caption(weight: FontWeight.w700),
                          ),
                        ),
                        if (isOnline) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: HuddlColors.nearBlack,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(HuddlIcons.videocam, size: 14, color: HuddlColors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'Online',
                                  style: HuddlText.caption(weight: FontWeight.w600),
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
                          const Icon(HuddlIcons.business, size: 13, color: HuddlColors.white),
                          const SizedBox(width: 4),
                          Text(
                            organiser,
                            style: HuddlText.caption(),
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
                        style: HuddlText.display(color: context.hc.textPrimary),
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
                                style: HuddlText.caption(),
                              ),
                              Text(
                                organiser,
                                style: HuddlText.body(weight: FontWeight.w600),
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

                // ── "Newly found for you" section ────────────────────
                // Show for AI-discovered OR externally-sourced events
                if (e['isAiDiscovered'] == true ||
                    e['isExternallySourced'] == true)
                  _buildAiDiscoveredSection(e),
                if (e['isAiDiscovered'] == true ||
                    e['isExternallySourced'] == true)
                  const SizedBox(height: 8),



                // Details
                Container(
                  color: context.hc.surface,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: HuddlIcons.calendar,
                        iconColor: metaIconColor,
                        title: e['date'] as String? ?? '',
                        subtitle: e['time'] as String? ?? '',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: isOnline
                            ? HuddlIcons.videocam
                            : HuddlIcons.locationPin,
                        iconColor: metaIconColor,
                        title: e['location'] as String? ?? '',
                        subtitle: isOnline
                            ? 'Online event — link shared on registration'
                            : 'Tap for directions',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: HuddlIcons.usersThree,
                        iconColor: metaIconColor,
                        title: () { final n = e['attendees'] as int? ?? 0; return '$n ${n == 1 ? 'person' : 'people'} going'; }(),
                        subtitle: 'Registrations open',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: HuddlIcons.money,
                        iconColor: isFree ? HuddlColors.success : color,
                        title: isFree ? 'Free' : (e['price'] as String? ?? ''),
                        subtitle: isFree
                            ? 'No cost to attend'
                            : 'Per person — paid on registration',
                      ),
                      if ((e['borough'] as String? ?? '').isNotEmpty) ...[
                        const Divider(height: 24),
                        _DetailRow(
                          icon: HuddlIcons.map,
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
                        style: HuddlText.body(weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        e['description'] as String? ?? 'No description provided.',
                        style: HuddlText.body(color: context.hc.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Who's going section
                _buildAttendeesSection(e, color),
                const SizedBox(height: 8),

                // AI Recommendation section — Firestore CF data preferred,
                // local AiEventRecommenderService scoring as fallback.
                if (_showRecommendationSection)
                  _buildAiRecommendationSection(),
                if (_showRecommendationSection)
                  const SizedBox(height: 8),

                // AI Feedback — calls recordRecommendationFeedback CF
                if (_showFeedbackSection)
                  _buildAiFeedbackSection(),
                if (_showFeedbackSection)
                  const SizedBox(height: 8),

                // What to expect — dynamic from event data
                _buildWhatToExpectSection(e, isOnline),
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
          child: HuddlButton(
            label: _hasEnded ? 'Ended' : (_isRegistered ? 'Going' : 'Join'),
            variant: _isRegistered ? HuddlButtonVariant.confirmed : HuddlButtonVariant.primary,
            leadingIcon: _hasEnded
                ? HuddlIcons.calendarX
                : (_isRegistered ? HuddlIcons.checkCircle : HuddlIcons.userGroupPlus),
            // Disabled when event has ended
            onPressed: _hasEnded ? null : () async {
              HapticFeedback.mediumImpact();
              final id = widget.event['id'] as String? ?? '';
              final eventTitle = widget.event['title'] as String? ?? 'this event';
              if (id.isNotEmpty) {
                final wasGoing = _eventService.isGoing(id);
                final nowGoing = _eventService.toggleGoing(id);
                if (nowGoing) {
                  await _eventService.createEventGroupChat(id);
                }
                if (mounted) {
                  // Update attendee count in the local event map
                  final currentCount = widget.event['attendees'] as int? ?? 0;
                  if (nowGoing && !wasGoing) {
                    widget.event['attendees'] = currentCount + 1;
                    widget.event['attendeeCount'] = currentCount + 1;
                  } else if (!nowGoing && wasGoing) {
                    widget.event['attendees'] = (currentCount - 1).clamp(0, 99999);
                    widget.event['attendeeCount'] = (currentCount - 1).clamp(0, 99999);
                  }
                  setState(() {});
                  final isNowGoing = _eventService.isGoing(id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(
                            isNowGoing ? HuddlIcons.checkCircle : HuddlIcons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isNowGoing
                                  ? 'You\'re going to $eventTitle!'
                                  : 'You\'ve left this event.',
                              style: HuddlText.body(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor:
                          isNowGoing ? HuddlColors.success : HuddlColors.textSecondary,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            },
          ),
        ),
      ),
    );
  }

  // ── AI Quick Summary section ──────────────────────────────────────────
  Widget _buildAiSummarySection(AiEventSummary summary) {
    // Prefer the server-authoritative Firestore CF value (_firestoreIsDiscoverNew)
    // when available; fall back to the event map value (set on discovery ingestion).
    final isDiscoverNew = _firestoreIsDiscoverNew
        ?? (widget.event['isDiscoverSomethingNew'] == true);

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
                  color: HuddlColors.nearBlack,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(HuddlIcons.starFill, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Summary',
                  style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary),
                ),
              ),
              // ✨ Discover Something New badge — shown when AI flags novelty
              if (isDiscoverNew)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: HuddlColors.peachWarm,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: HuddlColors.amberWarm.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('\u2728', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text(
                        'Discover Something New',
                        style: HuddlText.label(color: HuddlColors.warningDark)),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: HuddlColors.nearBlack.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    summary.vibe,
                    style: HuddlText.label(color: HuddlColors.nearBlack),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Suitability line
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: HuddlColors.nearBlack.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: HuddlColors.nearBlack.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                const Icon(HuddlIcons.family, size: 14, color: HuddlColors.nearBlack),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    summary.suitability,
                    style: HuddlText.caption(color: HuddlColors.nearBlack),
                  ),
                ),
              ],
            ),
          ),
          // Key highlights — prefer summaryBullets from event data, fall back to AI highlights
          Builder(builder: (_) {
            final rawBullets = widget.event['summaryBullets'];
            final List<String> bullets = (rawBullets is List && rawBullets.isNotEmpty)
                ? List<String>.from(rawBullets)
                : summary.highlights;
            if (bullets.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                ...bullets.map((h) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(HuddlIcons.checkCircle, size: 14, color: HuddlColors.nearBlack),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          h,
                          style: HuddlText.caption(color: context.hc.textSecondary).copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            );
          }),
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
                  color: HuddlColors.nearBlack.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(HuddlIcons.rateReview, size: 14, color: HuddlColors.nearBlack),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Was this recommendation helpful?',
                  style: HuddlText.body(color: context.hc.textPrimary),
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
                    ? HuddlColors.nearBlack.withValues(alpha: 0.06)
                    : HuddlColors.textHint.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _userFeedback! ? HuddlIcons.thumbUp : HuddlIcons.thumbDown,
                    size: 18,
                    color: _userFeedback! ? HuddlColors.nearBlack : context.hc.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _userFeedback!
                          ? 'Thanks! We\u2019ll show more events like this.'
                          : 'Got it \u2014 we\u2019ll adjust future recommendations.',
                      style: HuddlText.caption(),
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
                    onTap: _feedbackSubmitting
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            _submitRecommendationFeedback(true);
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: HuddlColors.nearBlack.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: HuddlColors.nearBlack.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(HuddlIcons.thumbUp, size: 18, color: HuddlColors.nearBlack),
                          const SizedBox(width: 8),
                          Text('Yes, helpful', style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.nearBlack)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _feedbackSubmitting
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            _submitRecommendationFeedback(false);
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
                          Icon(HuddlIcons.thumbDown, size: 18,
                            color: context.hc.textTertiary.withValues(alpha: 0.7)),
                          const SizedBox(width: 8),
                          Text('Not for me', style: HuddlText.body(color: context.hc.textTertiary)),
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
            style: HuddlText.label(color: context.hc.textTertiary),
          ),
        ],
      ),
    );
  }

  // ── AI Recommendation section ────────────────────────────────────────
  // Prefers Firestore Cloud Function data (matchScore + matchReasons with
  // icon keys mapped via _matchReasonIcons). Falls back to local scoring.
  Widget _buildAiRecommendationSection() {
    final scorePercent = _effectiveMatchScore ?? 0;
    final bool useFirestore =
        _firestoreMatchScore != null && _firestoreMatchReasons.isNotEmpty;

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
                  color: HuddlColors.nearBlack,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(HuddlIcons.starFill, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why we recommend this',
                      style: HuddlText.body(weight: FontWeight.w600),
                    ),
                    Text(
                      'Matched to your family',
                      style: HuddlText.caption(),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: HuddlColors.nearBlack,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$scorePercent% match',
                  style: HuddlText.caption(weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Reason list ─────────────────────────────────────────────────────
          // A) Firestore CF reasons: {icon: String key, label: String}
          //    → icon key resolved via _matchReasonIcons map
          // B) Local fallback: MatchReason with emoji + label
          if (useFirestore)
            ..._firestoreMatchReasons.take(4).map((reason) {
              final iconKey  = reason['icon']  as String? ?? 'star';
              final label    = reason['label'] as String? ?? '';
              final iconData = _matchReasonIcons[iconKey] ?? HuddlIcons.starFill;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: HuddlColors.nearBlack.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(iconData, size: 16, color: HuddlColors.nearBlack),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: HuddlText.body(),
                      ),
                    ),
                  ],
                ),
              );
            })
          else if (_scoredEvent != null)
            ..._scoredEvent!.reasons.take(4).map((reason) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: HuddlColors.nearBlack.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(reason.emoji,
                            style: const TextStyle(fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        reason.label,
                        style: HuddlText.body(),
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
    final sourceName = (e['sourceName'] as String? ?? '').isNotEmpty
        ? e['sourceName'] as String
        : (e['aiSourceName'] as String? ?? 'the web');
    final sourceIcon = e['aiSourceIcon'] as IconData? ?? HuddlIcons.language;
    final sourceUrl = e['sourceUrl'] as String? ?? '';

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
                  color: HuddlColors.nearBlack,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(HuddlIcons.starFill, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Newly found for you',
                      style: HuddlText.body(weight: FontWeight.w600),
                    ),
                    Text(
                      'Spotted from local listings and community boards',
                      style: HuddlText.caption(),
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
              color: HuddlColors.nearBlack.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: HuddlColors.nearBlack.withValues(alpha: 0.08),
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
                        color: HuddlColors.nearBlack.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(sourceIcon, size: 18, color: HuddlColors.nearBlack),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Discovered on',
                            style: HuddlText.label(),
                          ),
                          GestureDetector(
                            onTap: sourceUrl.isNotEmpty
                                ? () => _launchUrl(sourceUrl)
                                : null,
                            child: Text(
                              sourceName,
                              style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.nearBlack),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: HuddlColors.nearBlack,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(HuddlIcons.starFill, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'New Find',
                            style: HuddlText.caption(weight: FontWeight.w600),
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
                      const Icon(HuddlIcons.info, size: 16, color: HuddlColors.nearBlack),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'We search local listings, council sites, and community boards daily to find events near you.',
                          style: HuddlText.caption(color: context.hc.textSecondary),
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

  // ── Dynamic "What to expect" section ─────────────────────────────────
  Widget _buildWhatToExpectSection(Map<String, dynamic> e, bool isOnline) {
    // Prefer dynamic whatToExpect from event data
    final rawExpect = e['whatToExpect'];
    final List<String> bullets = (rawExpect is List && rawExpect.isNotEmpty)
        ? List<String>.from(rawExpect)
        : _buildFallbackWhatToExpect(isOnline);

    // Hide section entirely when no bullets
    if (bullets.isEmpty) return const SizedBox.shrink();

    return Container(
      color: context.hc.surface,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What to expect',
            style: HuddlText.body(weight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...bullets.map((bullet) => _ExpectItem(
            icon: HuddlIcons.checkCircle,
            color: HuddlColors.nearBlack,
            text: bullet,
          )),
        ],
      ),
    );
  }

  /// Fallback bullets when event has no whatToExpect data.
  List<String> _buildFallbackWhatToExpect(bool isOnline) {
    if (isOnline) {
      return [
        'Interactive online session',
        'Link shared on registration',
        'Recording available after the session',
      ];
    }
    return [
      'Safe, family-friendly venue',
      'Welcoming, community-focused environment',
      'Babies and young children welcome',
    ];
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
                style: HuddlText.body(weight: FontWeight.w600),
              ),
              Text(
                attendeeCount == 0
                    ? 'Be the first!'
                    : '$attendeeCount ${attendeeCount == 1 ? 'person' : 'people'}',
                style: HuddlText.body(color: attendeeCount == 0 ? color : context.hc.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_isRegistered && attendeeCount == 0) ...[  
            // Empty state — no one going yet
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(HuddlIcons.usersThree, color: color.withValues(alpha: 0.5), size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'No one has RSVP\'d yet.\nBe the first to go!',
                    textAlign: TextAlign.center,
                    style: HuddlText.body(),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Show avatar stack — current user first if joined, then sample avatars
            Row(
              children: [
                SizedBox(
                  width: (_isRegistered ? 3 : 3) * 20.0 + 12,
                  height: 36,
                  child: Stack(
                    children: [
                      // Sample community avatars
                      for (int i = 0; i < 2; i++)
                        Positioned(
                          left: (_isRegistered ? i + 1 : i) * 20.0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: context.hc.surface, width: 2),
                            ),
                            child: MemberAvatar(
                              name: ['Emma T.', 'James K.'][i],
                              size: 32,
                            ),
                          ),
                        ),
                      // Current user avatar in front (leftmost) if joined
                      if (_isRegistered)
                        Positioned(
                          left: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: color, width: 2),
                            ),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: color.withValues(alpha: 0.15),
                              child: Icon(HuddlIcons.user, size: 16, color: color),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isRegistered ? 'You\'re going!' : '$attendeeCount going',
                      style: HuddlText.body(weight: FontWeight.w600),
                    ),
                    if (attendeeCount > 0 || _isRegistered)
                      Text(
                        _isRegistered
                            ? (attendeeCount > 1 ? '+ ${attendeeCount - 1} others' : 'Be the first!')
                            : '${attendeeCount == 1 ? '1 parent' : '$attendeeCount parents'} attending',
                        style: HuddlText.caption(),
                      ),
                  ],
                ),
              ],
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
                style: HuddlText.body(weight: FontWeight.w600),
              ),
              Text(
                subtitle,
                style: HuddlText.caption(),
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
            style: HuddlText.body(),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton shimmer for image loading in event detail ─────────────────────
class _DetailShimmerBox extends StatefulWidget {
  const _DetailShimmerBox();

  @override
  State<_DetailShimmerBox> createState() => _DetailShimmerBoxState();
}

class _DetailShimmerBoxState extends State<_DetailShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value + 1, 0),
            colors: const [
              HuddlColors.neutral100,
              HuddlColors.neutral100,
              HuddlColors.neutral100,
              HuddlColors.neutral100,
              HuddlColors.neutral100,
            ],
            stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
          ),
        ),
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

  // http(s) URL — shimmer during load, gradient fallback on error
  if (imageUrl.startsWith('http')) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        // Show skeleton shimmer while the hero image is downloading
        return const _DetailShimmerBox();
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

// ── Circle icon button (matches Groups _CircleButton style) ───────────────
class _EventCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _EventCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
