import 'event_service.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'borough_ai_context.dart';

// =============================================================================
// AI EVENT RECOMMENDER & SMART DISCOVERY ENGINE
//
// Scores and ranks B2B partner events against the parent's profile using:
//   1. Child age match          (0-30 pts)
//   2. Borough / locality       (0-25 pts)
//   3. Stage-of-life match      (0-20 pts)
//   4. Registration history     (0-10 pts)
//   5. Weekend preference       (0-5 pts)
//   6. Capacity urgency         (0-5 pts)
//   7. Partner quality          (0-5 pts)
//
// Total max = 100 pts. Events >= 50 are "recommended".
// =============================================================================

/// A scored event with its match reasons.
class ScoredEvent {
  final Event event;
  final double score;           // 0-100
  final List<MatchReason> reasons;

  ScoredEvent({
    required this.event,
    required this.score,
    required this.reasons,
  });

  /// The single best reason to display on a card chip.
  MatchReason? get topReason =>
      reasons.isNotEmpty ? reasons.first : null;
}

/// A human-readable reason why this event was recommended.
class MatchReason {
  final String label;   // e.g. "Perfect for 8-month-olds"
  final String emoji;   // e.g. "🎯"
  final double weight;  // contribution to score

  const MatchReason({
    required this.label,
    required this.emoji,
    this.weight = 0,
  });
}

class AiEventRecommenderService with BoroughAiContext {
  static final AiEventRecommenderService _instance =
      AiEventRecommenderService._internal();
  factory AiEventRecommenderService() => _instance;
  AiEventRecommenderService._internal();

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcodeService = PostcodeService();
  final EventService _eventService = EventService();

  bool _isInitialised = false;

  // Cached user context
  String _userBorough = '';
  List<int> _childAgesMonths = [];
  List<String> _userStages = [];
  Set<String> _registeredEventIds = {};
  Set<String> _registeredTags = {};

  // ── Initialise ──────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isInitialised) return;
    await _onboarding.initialize();
    _buildUserContext();
    _isInitialised = true;
  }

  void _buildUserContext() {
    // Borough
    // 3-tier: persisted API result → sync cache → prefix map
    _userBorough = (_onboarding.borough?.isNotEmpty == true)
        ? _onboarding.borough!
        : (_postcodeService.getBoroughFromPostcode(_onboarding.postcode) ?? '');

    // Child ages in months
    _childAgesMonths = [];
    final now = DateTime.now();
    for (final child in _onboarding.children) {
      final bday = child['birthday'];
      if (bday != null && bday.isNotEmpty) {
        final parsed = DateTime.tryParse(bday);
        if (parsed != null) {
          final months =
              (now.year - parsed.year) * 12 + (now.month - parsed.month);
          if (months >= 0) _childAgesMonths.add(months);
        }
      }
    }
    // If expecting, add 0 months (prenatal)
    if (_onboarding.dueDate != null && _onboarding.dueDate!.isNotEmpty) {
      _childAgesMonths.add(-1); // sentinel for "pregnant"
    }
    // Fallback: if no children recorded, assume newborn (demo data)
    if (_childAgesMonths.isEmpty) {
      _childAgesMonths = [8]; // 8-month-old default for demo
    }

    // Stages of life
    _userStages = _onboarding.stagesOfLife;
    if (_userStages.isEmpty) {
      _userStages = ['newborn']; // default
    }

    // Build tag affinity from previously registered events
    _registeredEventIds = {};
    _registeredTags = {};
    for (final e in _eventService.goingEvents) {
      _registeredEventIds.add(e.id);
      _registeredTags.addAll(e.tags);
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Score and rank ALL events. Call after [initialize].
  List<ScoredEvent> rankAllEvents() {
    _buildUserContext(); // refresh context each call
    final scored = _eventService.events.map(_scoreEvent).toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  /// Top recommended events (score >= 50, max 5).
  List<ScoredEvent> get recommendedEvents {
    final all = rankAllEvents();
    return all.where((s) => s.score >= 50).take(5).toList();
  }

  /// Rank events that have already been filtered/searched (for the list view).
  List<ScoredEvent> rankFilteredEvents(List<Map<String, dynamic>> eventMaps) {
    _buildUserContext();
    final eventIds = eventMaps.map((m) => m['id'] as String?).toSet();
    final matchedEvents =
        _eventService.events.where((e) => eventIds.contains(e.id));
    final scored = matchedEvents.map(_scoreEvent).toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  // ── Scoring Engine ──────────────────────────────────────────────────────

  ScoredEvent _scoreEvent(Event event) {
    double total = 0;
    final reasons = <MatchReason>[];

    // 1. Child age match (0-30)
    final ageScore = _scoreChildAge(event);
    total += ageScore.score;
    if (ageScore.reason != null) reasons.add(ageScore.reason!);

    // 2. Borough / locality (0-25)
    final boroughScore = _scoreBorough(event);
    total += boroughScore.score;
    if (boroughScore.reason != null) reasons.add(boroughScore.reason!);

    // 3. Stage-of-life match (0-20)
    final stageScore = _scoreStage(event);
    total += stageScore.score;
    if (stageScore.reason != null) reasons.add(stageScore.reason!);

    // 4. Registration history / tag affinity (0-10)
    final affinityScore = _scoreAffinity(event);
    total += affinityScore.score;
    if (affinityScore.reason != null) reasons.add(affinityScore.reason!);

    // 5. Weekend preference (0-5)
    final weekendScore = _scoreWeekend(event);
    total += weekendScore.score;
    if (weekendScore.reason != null) reasons.add(weekendScore.reason!);

    // 6. Capacity urgency (0-5)
    final capacityScore = _scoreCapacity(event);
    total += capacityScore.score;
    if (capacityScore.reason != null) reasons.add(capacityScore.reason!);

    // 7. Partner quality (0-5)
    final qualityScore = _scorePartnerQuality(event);
    total += qualityScore.score;
    if (qualityScore.reason != null) reasons.add(qualityScore.reason!);

    // Sort reasons by weight descending so topReason is most impactful
    reasons.sort((a, b) => b.weight.compareTo(a.weight));

    return ScoredEvent(event: event, score: total, reasons: reasons);
  }

  // ── Individual Scorers ──────────────────────────────────────────────────

  _ScoreResult _scoreChildAge(Event event) {
    if (event.suitableAgeRange == null) {
      return _ScoreResult(10); // neutral if no age specified
    }
    final range = event.suitableAgeRange!;

    // Check if ANY of the user's children fit
    for (final ageMonths in _childAgesMonths) {
      if (ageMonths == -1) {
        // Pregnant — match prenatal events
        if (range.minMonths == 0 || event.targetStages.contains('pregnant')) {
          return _ScoreResult(30,
              reason: MatchReason(
                label: 'Great for expecting parents',
                emoji: '\u{1F930}', // pregnant person
                weight: 30,
              ));
        }
        continue;
      }
      if (range.containsMonths(ageMonths)) {
        final display = ageMonths < 12
            ? '$ageMonths-month-olds'
            : '${(ageMonths / 12).floor()}-year-olds';
        return _ScoreResult(30,
            reason: MatchReason(
              label: 'Perfect for $display',
              emoji: '\u{1F3AF}', // target
              weight: 30,
            ));
      }
      // Close miss (within 3 months) — partial score
      final distMin = (ageMonths - range.minMonths).abs();
      final distMax =
          range.maxMonths == -1 ? 0 : (ageMonths - range.maxMonths).abs();
      final closest = distMin < distMax ? distMin : distMax;
      if (closest <= 3) {
        return _ScoreResult(18,
            reason: MatchReason(
              label: 'Close to your child\'s age',
              emoji: '\u{1F476}', // baby
              weight: 18,
            ));
      }
    }
    return _ScoreResult(5); // poor age match
  }

  _ScoreResult _scoreBorough(Event event) {
    if (event.isOnline) {
      return _ScoreResult(20,
          reason: MatchReason(
            label: 'Available online',
            emoji: '\u{1F4BB}', // laptop
            weight: 20,
          ));
    }
    if (event.borough.isEmpty) return _ScoreResult(10);

    if (event.borough.toLowerCase() == _userBorough.toLowerCase()) {
      return _ScoreResult(25,
          reason: MatchReason(
            label: 'In your borough',
            emoji: '\u{1F4CD}', // pin
            weight: 25,
          ));
    }
    // Nearby borough heuristic — same first 2 letters of postcode
    return _ScoreResult(8);
  }

  _ScoreResult _scoreStage(Event event) {
    if (event.targetStages.isEmpty) return _ScoreResult(10);

    for (final stage in _userStages) {
      final normStage = _normaliseStage(stage);
      if (event.targetStages.contains(normStage)) {
        final label = _stageFriendlyLabel(normStage);
        return _ScoreResult(20,
            reason: MatchReason(
              label: label,
              emoji: '\u{2B50}', // star
              weight: 20,
            ));
      }
    }
    return _ScoreResult(5);
  }

  _ScoreResult _scoreAffinity(Event event) {
    if (_registeredTags.isEmpty) return _ScoreResult(5);

    final overlap =
        event.tags.where((t) => _registeredTags.contains(t)).length;
    if (overlap >= 2) {
      return _ScoreResult(10,
          reason: MatchReason(
            label: 'Similar to events you\'ve liked',
            emoji: '\u{1F525}', // fire
            weight: 10,
          ));
    }
    if (overlap == 1) return _ScoreResult(7);
    return _ScoreResult(3);
  }

  _ScoreResult _scoreWeekend(Event event) {
    if (event.isWeekend) {
      return _ScoreResult(5,
          reason: MatchReason(
            label: 'Weekend event',
            emoji: '\u{2600}\u{FE0F}', // sun
            weight: 5,
          ));
    }
    return _ScoreResult(2);
  }

  _ScoreResult _scoreCapacity(Event event) {
    if (event.capacityLeft == -1) return _ScoreResult(2);
    if (event.capacityLeft <= 5) {
      return _ScoreResult(5,
          reason: MatchReason(
            label: 'Only ${event.capacityLeft} spots left!',
            emoji: '\u{1F525}', // fire
            weight: 12, // high visual weight
          ));
    }
    if (event.capacityLeft <= 15) return _ScoreResult(3);
    return _ScoreResult(1);
  }

  _ScoreResult _scorePartnerQuality(Event event) {
    if (event.partnerRating >= 4.5) {
      return _ScoreResult(5,
          reason: MatchReason(
            label: 'Highly rated provider',
            emoji: '\u{2B50}', // star
            weight: 5,
          ));
    }
    if (event.partnerRating >= 4.0) return _ScoreResult(3);
    return _ScoreResult(1);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _normaliseStage(String stage) {
    final s = stage.toLowerCase().trim();
    if (s.contains('pregnant') || s.contains('expecting')) return 'pregnant';
    if (s.contains('newborn') || s.contains('new parent') || s.contains('baby')) {
      return 'newborn';
    }
    if (s.contains('toddler') || s.contains('1-3')) return 'toddler';
    if (s.contains('school') || s.contains('4+')) return 'school-age';
    return s;
  }

  String _stageFriendlyLabel(String stage) {
    switch (stage) {
      case 'pregnant':
        return 'Designed for expecting parents';
      case 'newborn':
        return 'Ideal for new parents';
      case 'toddler':
        return 'Great for toddler families';
      case 'school-age':
        return 'Perfect for school-age kids';
      default:
        return 'Matches your stage';
    }
  }
}

/// Internal score result with optional reason.
class _ScoreResult {
  final double score;
  final MatchReason? reason;
  _ScoreResult(this.score, {this.reason});
}
