import 'dart:convert';
import 'browser_storage.dart';
import 'event_service.dart';
import 'onboarding_data_service.dart';
import 'ai_event_recommender_service.dart';
import 'borough_ai_context.dart';

// =============================================================================
// INVISIBLE AI SERVICE
//
// Powers the "less is more" AI strategy for the Events tab:
//   - Predictive NLP search with auto-suggestions
//   - Contextual intelligence (auto-classify, summarize, tag)
//   - Adaptive UI (reorder/hide based on user patterns)
//   - Feedback loops (thumbs up/down for learning)
//   - Event summarization for long descriptions
//   - User behaviour tracking for personalization
// =============================================================================

/// Represents an AI search suggestion derived from user context.
class AiSearchSuggestion {
  final String query;
  final String reason;    // why this was suggested
  final String icon;      // emoji
  final double relevance; // 0-1

  const AiSearchSuggestion({
    required this.query,
    required this.reason,
    required this.icon,
    this.relevance = 0.5,
  });
}

/// AI-generated event summary for long descriptions.
class AiEventSummary {
  final String oneLiner;         // 1-sentence summary
  final List<String> highlights; // 3-4 key highlights
  final String suitability;      // "Perfect for..." line
  final String vibe;             // emoji vibe (e.g. "Relaxed & Social")

  const AiEventSummary({
    required this.oneLiner,
    required this.highlights,
    required this.suitability,
    required this.vibe,
  });
}

/// User feedback on an AI recommendation.
class AiFeedback {
  final String eventId;
  final bool isPositive; // thumbs up = true, down = false
  final DateTime timestamp;
  final String? reason;  // optional reason text

  AiFeedback({
    required this.eventId,
    required this.isPositive,
    DateTime? timestamp,
    this.reason,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'isPositive': isPositive,
    'timestamp': timestamp.toIso8601String(),
    'reason': reason,
  };

  factory AiFeedback.fromJson(Map<String, dynamic> json) => AiFeedback(
    eventId: json['eventId'] as String,
    isPositive: json['isPositive'] as bool,
    timestamp: DateTime.parse(json['timestamp'] as String),
    reason: json['reason'] as String?,
  );
}

/// Tracks which filter types the user interacts with most.
class _UserBehaviourProfile {
  int freeClicks = 0;
  int paidClicks = 0;
  int onlineClicks = 0;
  int inPersonClicks = 0;
  int weekendViews = 0;
  int weekdayViews = 0;
  Set<String> viewedCategories = {};
  Set<String> viewedBoroughs = {};
  int totalViews = 0;
  DateTime? lastActiveTime;

  /// Return the preferred filter order based on behaviour.
  List<String> get adaptiveFilterOrder {
    final scores = <String, int>{
      'All': 1000, // always first
      'Free': freeClicks * 3,
      'Paid': paidClicks * 3,
      'Online': onlineClicks * 3,
      'In-Person': inPersonClicks * 3,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  /// Whether to auto-collapse filters (user rarely uses them).
  bool get shouldCollapseFilters {
    final total = freeClicks + paidClicks + onlineClicks + inPersonClicks;
    return totalViews > 5 && total < 2;
  }

  Map<String, dynamic> toJson() => {
    'freeClicks': freeClicks,
    'paidClicks': paidClicks,
    'onlineClicks': onlineClicks,
    'inPersonClicks': inPersonClicks,
    'weekendViews': weekendViews,
    'weekdayViews': weekdayViews,
    'viewedCategories': viewedCategories.toList(),
    'viewedBoroughs': viewedBoroughs.toList(),
    'totalViews': totalViews,
    'lastActiveTime': lastActiveTime?.toIso8601String(),
  };

  static _UserBehaviourProfile fromJson(Map<String, dynamic> json) {
    final p = _UserBehaviourProfile();
    p.freeClicks = json['freeClicks'] as int? ?? 0;
    p.paidClicks = json['paidClicks'] as int? ?? 0;
    p.onlineClicks = json['onlineClicks'] as int? ?? 0;
    p.inPersonClicks = json['inPersonClicks'] as int? ?? 0;
    p.weekendViews = json['weekendViews'] as int? ?? 0;
    p.weekdayViews = json['weekdayViews'] as int? ?? 0;
    p.viewedCategories = Set<String>.from(json['viewedCategories'] as List? ?? []);
    p.viewedBoroughs = Set<String>.from(json['viewedBoroughs'] as List? ?? []);
    p.totalViews = json['totalViews'] as int? ?? 0;
    final ts = json['lastActiveTime'] as String?;
    if (ts != null) p.lastActiveTime = DateTime.tryParse(ts);
    return p;
  }
}

class InvisibleAiService with BoroughAiContext {
  static final InvisibleAiService _instance = InvisibleAiService._internal();
  factory InvisibleAiService() => _instance;
  InvisibleAiService._internal();

  final OnboardingDataService _onboarding = OnboardingDataService();
  final EventService _eventService = EventService();
  final AiEventRecommenderService _recommender = AiEventRecommenderService();

  bool _isInitialised = false;
  _UserBehaviourProfile _behaviour = _UserBehaviourProfile();
  final List<AiFeedback> _feedbackHistory = [];
  final Set<String> _dislikedCategories = {};
  final Set<String> _likedCategories = {};

  // ── Initialise ───────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isInitialised) return;
    await _onboarding.initialize();
    await _recommender.initialize();
    await _loadBehaviour();
    await _loadFeedback();
    _isInitialised = true;
  }

  Future<void> _loadBehaviour() async {
    final raw = await BrowserStorage.getString('ai_behaviour_v1');
    if (raw != null) {
      try {
        _behaviour = _UserBehaviourProfile.fromJson(
          json.decode(raw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
  }

  Future<void> _saveBehaviour() async {
    await BrowserStorage.setString(
      'ai_behaviour_v1',
      json.encode(_behaviour.toJson()),
    );
  }

  Future<void> _loadFeedback() async {
    final raw = await BrowserStorage.getString('ai_feedback_v1');
    if (raw != null) {
      try {
        final list = json.decode(raw) as List;
        _feedbackHistory.clear();
        for (final item in list) {
          final fb = AiFeedback.fromJson(item as Map<String, dynamic>);
          _feedbackHistory.add(fb);
          _updateCategoryPreferences(fb);
        }
      } catch (_) {}
    }
  }

  Future<void> _saveFeedback() async {
    await BrowserStorage.setString(
      'ai_feedback_v1',
      json.encode(_feedbackHistory.map((f) => f.toJson()).toList()),
    );
  }

  void _updateCategoryPreferences(AiFeedback fb) {
    final event = _eventService.events
        .where((e) => e.id == fb.eventId)
        .toList();
    if (event.isEmpty) return;
    final cat = event.first.category;
    if (fb.isPositive) {
      _likedCategories.add(cat);
      _dislikedCategories.remove(cat);
    } else {
      _dislikedCategories.add(cat);
    }
  }

  // ── Behaviour tracking ────────────────────────────────────────────────────

  void trackFilterClick(String filter) {
    switch (filter) {
      case 'Free': _behaviour.freeClicks++;
      case 'Paid': _behaviour.paidClicks++;
      case 'Online': _behaviour.onlineClicks++;
      case 'In-Person': _behaviour.inPersonClicks++;
    }
    _saveBehaviour();
  }

  void trackEventView(Map<String, dynamic> event) {
    _behaviour.totalViews++;
    _behaviour.lastActiveTime = DateTime.now();
    final cat = event['category'] as String? ?? '';
    if (cat.isNotEmpty) _behaviour.viewedCategories.add(cat);
    final borough = event['borough'] as String? ?? '';
    if (borough.isNotEmpty) _behaviour.viewedBoroughs.add(borough);
    final dt = event['dateTime'] as DateTime?;
    if (dt != null) {
      if (dt.weekday >= 6) {
        _behaviour.weekendViews++;
      } else {
        _behaviour.weekdayViews++;
      }
    }
    _saveBehaviour();
  }

  // ── Feedback ──────────────────────────────────────────────────────────────

  Future<void> submitFeedback(String eventId, bool isPositive, {String? reason}) async {
    final fb = AiFeedback(
      eventId: eventId,
      isPositive: isPositive,
      reason: reason,
    );
    _feedbackHistory.add(fb);
    _updateCategoryPreferences(fb);
    await _saveFeedback();
  }

  bool hasFeedback(String eventId) =>
      _feedbackHistory.any((f) => f.eventId == eventId);

  bool? getFeedback(String eventId) {
    final fbs = _feedbackHistory.where((f) => f.eventId == eventId);
    return fbs.isEmpty ? null : fbs.last.isPositive;
  }

  int get totalPositiveFeedback =>
      _feedbackHistory.where((f) => f.isPositive).length;

  int get totalNegativeFeedback =>
      _feedbackHistory.where((f) => !f.isPositive).length;

  // ── Adaptive UI ───────────────────────────────────────────────────────────

  /// Whether to auto-hide filters (user rarely uses them).
  bool get shouldCollapseFilters => _behaviour.shouldCollapseFilters;

  /// Adaptive filter order based on usage.
  List<String> get adaptiveFilterOrder => _behaviour.adaptiveFilterOrder;

  // ── Predictive NLP Search ─────────────────────────────────────────────────

  /// Generate contextual search suggestions based on user profile.
  List<AiSearchSuggestion> getSearchSuggestions() {
    final suggestions = <AiSearchSuggestion>[];
    final now = DateTime.now();

    // Time-of-day context
    if (now.hour < 12) {
      suggestions.add(const AiSearchSuggestion(
        query: 'morning activities',
        reason: 'Good morning! Here are morning events',
        icon: '\u2615',
        relevance: 0.8,
      ));
    } else if (now.hour >= 17) {
      suggestions.add(const AiSearchSuggestion(
        query: 'evening classes',
        reason: 'Evening activities for after bedtime',
        icon: '\u{1F319}',
        relevance: 0.7,
      ));
    }

    // Weekend context
    if (now.weekday >= 5) {
      suggestions.add(const AiSearchSuggestion(
        query: 'weekend family events',
        reason: 'Weekend plans for the family',
        icon: '\u{2600}\u{FE0F}',
        relevance: 0.9,
      ));
    }

    // Child-age context
    for (final child in _onboarding.children) {
      final bday = child['birthday'];
      if (bday != null && bday.isNotEmpty) {
        final parsed = DateTime.tryParse(bday);
        if (parsed != null) {
          final months = (now.year - parsed.year) * 12 + (now.month - parsed.month);
          if (months < 6) {
            suggestions.add(const AiSearchSuggestion(
              query: 'baby classes near me',
              reason: 'Classes suitable for your baby',
              icon: '\u{1F476}',
              relevance: 0.95,
            ));
          } else if (months < 18) {
            suggestions.add(const AiSearchSuggestion(
              query: 'toddler activities',
              reason: 'Fun for your little one',
              icon: '\u{1F9D2}',
              relevance: 0.9,
            ));
          } else if (months < 48) {
            suggestions.add(const AiSearchSuggestion(
              query: 'preschool classes',
              reason: 'Learning through play',
              icon: '\u{1F3A8}',
              relevance: 0.85,
            ));
          }
        }
      }
    }

    // Stage-of-life context
    if (_onboarding.stagesOfLife.any((s) => s.toLowerCase().contains('pregnant'))) {
      suggestions.add(const AiSearchSuggestion(
        query: 'antenatal classes',
        reason: 'Preparing for your new arrival',
        icon: '\u{1F930}',
        relevance: 0.95,
      ));
    }

    // Free events (always popular)
    suggestions.add(const AiSearchSuggestion(
      query: 'free events this week',
      reason: 'No-cost activities nearby',
      icon: '\u{1F389}',
      relevance: 0.75,
    ));

    // Sort by relevance
    suggestions.sort((a, b) => b.relevance.compareTo(a.relevance));
    return suggestions.take(5).toList();
  }

  /// NLP search: parse natural language queries into structured filters.
  Map<String, dynamic> parseNaturalQuery(String query) {
    final q = query.toLowerCase().trim();
    final result = <String, dynamic>{};

    // Price intent
    if (q.contains('free') || q.contains('no cost') || q.contains('budget')) {
      result['priceFilter'] = 'Free';
    } else if (q.contains('paid') || q.contains('premium') || q.contains('worth')) {
      result['priceFilter'] = 'Paid';
    }

    // Format intent
    if (q.contains('online') || q.contains('virtual') || q.contains('zoom') || q.contains('remote')) {
      result['formatFilter'] = 'Online';
    } else if (q.contains('in-person') || q.contains('local') || q.contains('nearby') || q.contains('near me')) {
      result['formatFilter'] = 'In-Person';
    }

    // Time intent
    if (q.contains('weekend') || q.contains('saturday') || q.contains('sunday')) {
      result['timeFilter'] = 'weekend';
    } else if (q.contains('morning')) {
      result['timeFilter'] = 'morning';
    } else if (q.contains('afternoon')) {
      result['timeFilter'] = 'afternoon';
    } else if (q.contains('evening') || q.contains('night')) {
      result['timeFilter'] = 'evening';
    } else if (q.contains('today')) {
      result['timeFilter'] = 'today';
    } else if (q.contains('this week')) {
      result['timeFilter'] = 'this_week';
    }

    // Category intent
    if (q.contains('music') || q.contains('sing')) result['category'] = 'class';
    if (q.contains('yoga') || q.contains('fitness') || q.contains('exercise')) result['category'] = 'health';
    if (q.contains('play') || q.contains('messy') || q.contains('sensory')) result['category'] = 'play';
    if (q.contains('swim') || q.contains('sport')) result['category'] = 'sport';
    if (q.contains('workshop') || q.contains('learn')) result['category'] = 'workshop';

    // Age intent
    if (q.contains('baby') || q.contains('newborn')) result['ageStage'] = 'newborn';
    if (q.contains('toddler')) result['ageStage'] = 'toddler';
    if (q.contains('school')) result['ageStage'] = 'school-age';
    if (q.contains('pregnant') || q.contains('expecting') || q.contains('antenatal')) {
      result['ageStage'] = 'pregnant';
    }

    // The remaining text (stripped of filter words) becomes the keyword search
    var keywords = q;
    for (final word in ['free', 'paid', 'online', 'virtual', 'in-person', 'local',
      'nearby', 'weekend', 'morning', 'afternoon', 'evening', 'today', 'this week',
      'near me', 'baby', 'toddler', 'pregnant', 'antenatal']) {
      keywords = keywords.replaceAll(word, '');
    }
    keywords = keywords.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (keywords.isNotEmpty) result['keywords'] = keywords;

    return result;
  }

  /// Apply NLP-parsed filters to events list.
  List<Map<String, dynamic>> applySmartFilter(
    List<Map<String, dynamic>> events,
    Map<String, dynamic> parsed,
  ) {
    var result = List<Map<String, dynamic>>.from(events);

    if (parsed.containsKey('priceFilter')) {
      final pf = parsed['priceFilter'] as String;
      result = result.where((e) {
        return pf == 'Free' ? e['isFree'] == true : e['isFree'] != true;
      }).toList();
    }

    if (parsed.containsKey('formatFilter')) {
      final ff = parsed['formatFilter'] as String;
      result = result.where((e) {
        return ff == 'Online' ? e['isOnline'] == true : e['isOnline'] != true;
      }).toList();
    }

    if (parsed.containsKey('timeFilter')) {
      final tf = parsed['timeFilter'] as String;
      final now = DateTime.now();
      result = result.where((e) {
        final dt = e['dateTime'] as DateTime?;
        if (dt == null) return true;
        switch (tf) {
          case 'weekend': return dt.weekday >= 6;
          case 'morning': return dt.hour < 12;
          case 'afternoon': return dt.hour >= 12 && dt.hour < 17;
          case 'evening': return dt.hour >= 17;
          case 'today':
            return dt.year == now.year && dt.month == now.month && dt.day == now.day;
          case 'this_week':
            final weekEnd = now.add(Duration(days: 7 - now.weekday));
            return dt.isAfter(now) && dt.isBefore(weekEnd);
          default: return true;
        }
      }).toList();
    }

    if (parsed.containsKey('category')) {
      final cat = parsed['category'] as String;
      result = result.where((e) {
        return (e['category'] as String? ?? '').toLowerCase() == cat;
      }).toList();
    }

    if (parsed.containsKey('ageStage')) {
      final stage = parsed['ageStage'] as String;
      result = result.where((e) {
        final stages = e['targetStages'] as List<String>? ?? [];
        return stages.isEmpty || stages.contains(stage);
      }).toList();
    }

    if (parsed.containsKey('keywords')) {
      final kw = (parsed['keywords'] as String).toLowerCase();
      result = result.where((e) {
        final title = (e['title'] as String? ?? '').toLowerCase();
        final loc = (e['location'] as String? ?? '').toLowerCase();
        final org = (e['organiser'] as String? ?? '').toLowerCase();
        final desc = (e['description'] as String? ?? '').toLowerCase();
        return title.contains(kw) || loc.contains(kw) || org.contains(kw) || desc.contains(kw);
      }).toList();
    }

    return result;
  }

  // ── Event Summarization ───────────────────────────────────────────────────

  /// Generate a quick summary for an event (local, no API call).
  AiEventSummary summarizeEvent(Map<String, dynamic> event) {
    final description = event['description'] as String? ?? '';
    final isFree = event['isFree'] == true;
    final isOnline = event['isOnline'] == true;
    final borough = event['borough'] as String? ?? '';
    final category = event['category'] as String? ?? '';

    // Build one-liner
    final pricePart = isFree ? 'Free' : (event['price'] as String? ?? 'Paid');
    final formatPart = isOnline ? 'online' : (borough.isNotEmpty ? 'in $borough' : 'local');
    final oneLiner = '$pricePart ${_categoryLabel(category)} event $formatPart';

    // Build highlights from description
    final sentences = description
        .split(RegExp(r'[.!?]+'))
        .map((s) => s.trim())
        .where((s) => s.length > 10)
        .toList();
    final highlights = sentences.take(3).map((s) {
      if (!s.endsWith('.')) return '$s.';
      return s;
    }).toList();

    // Suitability line from age/stage data
    final stages = event['targetStages'] as List<String>? ?? [];
    String suitability;
    if (stages.contains('pregnant')) {
      suitability = 'Perfect for expecting parents';
    } else if (stages.contains('newborn')) {
      suitability = 'Ideal for parents with babies';
    } else if (stages.contains('toddler')) {
      suitability = 'Great for toddler families';
    } else {
      suitability = 'Suitable for all families';
    }

    // Vibe from category
    final vibe = _categoryVibe(category);

    return AiEventSummary(
      oneLiner: oneLiner,
      highlights: highlights,
      suitability: suitability,
      vibe: vibe,
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'play': return 'play & sensory';
      case 'health': return 'health & wellness';
      case 'sport': return 'sports & fitness';
      case 'workshop': return 'workshop';
      case 'class': return 'class';
      case 'community': return 'community';
      default: return 'family';
    }
  }

  String _categoryVibe(String category) {
    switch (category) {
      case 'play': return '\u{1F3A8} Creative & Fun';
      case 'health': return '\u{1F9D8} Calm & Nurturing';
      case 'sport': return '\u{1F3C3} Active & Energetic';
      case 'workshop': return '\u{1F4DA} Learn & Grow';
      case 'class': return '\u{1F3B5} Interactive & Social';
      case 'community': return '\u{1F91D} Friendly & Welcoming';
      default: return '\u{2728} Discover Something New';
    }
  }

  // ── Intelligent Event Sorting ──────────────────────────────────────────────

  /// Sort events with AI: boost by recommendation score, penalize disliked
  /// categories, boost events matching user behaviour patterns.
  List<Map<String, dynamic>> intelligentSort(
    List<Map<String, dynamic>> events,
    Map<String, ScoredEvent> scoredMap,
  ) {
    final sorted = List<Map<String, dynamic>>.from(events);
    sorted.sort((a, b) {
      final idA = a['id'] as String? ?? '';
      final idB = b['id'] as String? ?? '';
      final scoreA = _computeIntelligentScore(a, scoredMap[idA]);
      final scoreB = _computeIntelligentScore(b, scoredMap[idB]);
      return scoreB.compareTo(scoreA);
    });
    return sorted;
  }

  double _computeIntelligentScore(Map<String, dynamic> event, ScoredEvent? scored) {
    double base = scored?.score ?? 30.0;

    // Boost liked categories
    final cat = event['category'] as String? ?? '';
    if (_likedCategories.contains(cat)) base += 8;
    if (_dislikedCategories.contains(cat)) base -= 15;

    // Boost frequently viewed boroughs
    final borough = event['borough'] as String? ?? '';
    if (_behaviour.viewedBoroughs.contains(borough)) base += 5;

    // Weekend boost if user prefers weekends
    if (_behaviour.weekendViews > _behaviour.weekdayViews) {
      final dt = event['dateTime'] as DateTime?;
      if (dt != null && dt.weekday >= 6) base += 3;
    }

    // Recency boost for events happening soon
    final dt = event['dateTime'] as DateTime?;
    if (dt != null) {
      final daysAway = dt.difference(DateTime.now()).inDays;
      if (daysAway <= 3) {
        base += 5;
      } else if (daysAway <= 7) {
        base += 3;
      }
    }

    return base;
  }

  // ── Context line for AI transparency ──────────────────────────────────────

  /// Returns a brief explanation of why the feed is ordered this way.
  String getContextExplanation() {
    final parts = <String>[];

    if (_likedCategories.isNotEmpty) {
      parts.add('showing more ${_likedCategories.first} events');
    }

    final now = DateTime.now();
    if (now.weekday >= 5) {
      parts.add('weekend picks');
    }

    if (_behaviour.viewedBoroughs.isNotEmpty) {
      parts.add('near ${_behaviour.viewedBoroughs.first}');
    }

    if (parts.isEmpty) return 'Personalised for your family';
    return 'AI: ${parts.join(' \u00B7 ')}';
  }
}
