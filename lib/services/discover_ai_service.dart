import 'dart:convert';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'borough_ai_context.dart';

// =============================================================================
// DISCOVER AI SERVICE
//
// Powers the "Invisible AI" strategy for the Discover Tab:
//   - Predictive NLP search with auto-suggestions & pre-filling
//   - AI-driven group recommendation scoring & adaptive reordering
//   - Intelligent group summarisation (one-liners, highlights, suitability)
//   - Adaptive interface (reorder/hide items based on usage patterns)
//   - Feedback loops (thumbs up/down for continuous learning)
//   - Voice-command intent parsing for multi-step group tasks
//   - Usage-behaviour tracking for personalisation
//   - Context-aware transparency explanations
// =============================================================================

/// AI-generated search suggestion for predictive pre-filling.
class DiscoverSearchSuggestion {
  final String query;
  final String reason;
  final String icon;
  final double relevance; // 0-1

  const DiscoverSearchSuggestion({
    required this.query,
    required this.reason,
    required this.icon,
    this.relevance = 0.5,
  });
}

/// AI quick action for contextual task automation.
class DiscoverQuickAction {
  final String id;
  final String label;
  final String description;
  final String iconName;
  final double confidence;
  final Map<String, dynamic> data;

  const DiscoverQuickAction({
    required this.id,
    required this.label,
    required this.description,
    required this.iconName,
    this.confidence = 0.5,
    this.data = const {},
  });
}

/// AI-generated group summary for card display.
class AiGroupSummary {
  final String oneLiner;
  final String suitability;
  final String vibe;
  final double matchScore; // 0-100

  const AiGroupSummary({
    required this.oneLiner,
    required this.suitability,
    required this.vibe,
    this.matchScore = 50,
  });
}

/// Voice intent parsed from natural language.
class DiscoverVoiceIntent {
  final String action; // 'search', 'filter', 'join', 'create', 'sort', 'browse'
  final String? target;
  final Map<String, dynamic> params;
  final double confidence;

  const DiscoverVoiceIntent({
    required this.action,
    this.target,
    this.params = const {},
    this.confidence = 0.8,
  });
}

/// User feedback on an AI recommendation.
class DiscoverFeedback {
  final String groupId;
  final bool isPositive;
  final DateTime timestamp;
  final String? reason;

  DiscoverFeedback({
    required this.groupId,
    required this.isPositive,
    DateTime? timestamp,
    this.reason,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'groupId': groupId,
    'isPositive': isPositive,
    'timestamp': timestamp.toIso8601String(),
    'reason': reason,
  };

  factory DiscoverFeedback.fromJson(Map<String, dynamic> json) =>
      DiscoverFeedback(
        groupId: json['groupId'] as String,
        isPositive: json['isPositive'] as bool,
        timestamp: DateTime.parse(json['timestamp'] as String),
        reason: json['reason'] as String?,
      );
}

/// Internal usage-behaviour profile for adaptive reordering.
class _DiscoverBehaviour {
  Map<String, int> groupViews = {};
  Map<String, int> groupJoins = {};
  Map<String, int> searchQueries = {};
  Set<String> viewedCategories = {};
  Set<String> likedCategories = {};
  Set<String> dislikedCategories = {};
  Set<String> joinedGroupIds = {};
  int totalSearches = 0;
  int totalViews = 0;
  int totalFilterUses = 0;
  DateTime? lastActiveTime;

  /// Top viewed groups by frequency.
  List<String> get topViewedGroups {
    final sorted = groupViews.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => e.key).toList();
  }

  /// Top search queries.
  List<String> get topSearches {
    final sorted = searchQueries.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => e.key).toList();
  }

  /// Whether user rarely uses filters (should auto-collapse).
  bool get shouldCollapseFilters => totalViews > 5 && totalFilterUses < 2;

  /// Whether search bar should be auto-shown (power user).
  bool get shouldAutoShowSearch => totalSearches > 5;

  Map<String, dynamic> toJson() => {
    'groupViews': groupViews,
    'groupJoins': groupJoins,
    'searchQueries': searchQueries,
    'viewedCategories': viewedCategories.toList(),
    'likedCategories': likedCategories.toList(),
    'dislikedCategories': dislikedCategories.toList(),
    'joinedGroupIds': joinedGroupIds.toList(),
    'totalSearches': totalSearches,
    'totalViews': totalViews,
    'totalFilterUses': totalFilterUses,
    'lastActiveTime': lastActiveTime?.toIso8601String(),
  };

  static _DiscoverBehaviour fromJson(Map<String, dynamic> json) {
    final b = _DiscoverBehaviour();
    b.groupViews = Map<String, int>.from(json['groupViews'] ?? {});
    b.groupJoins = Map<String, int>.from(json['groupJoins'] ?? {});
    b.searchQueries = Map<String, int>.from(json['searchQueries'] ?? {});
    b.viewedCategories = Set<String>.from(json['viewedCategories'] ?? []);
    b.likedCategories = Set<String>.from(json['likedCategories'] ?? []);
    b.dislikedCategories = Set<String>.from(json['dislikedCategories'] ?? []);
    b.joinedGroupIds = Set<String>.from(json['joinedGroupIds'] ?? []);
    b.totalSearches = json['totalSearches'] as int? ?? 0;
    b.totalViews = json['totalViews'] as int? ?? 0;
    b.totalFilterUses = json['totalFilterUses'] as int? ?? 0;
    final ts = json['lastActiveTime'] as String?;
    if (ts != null) b.lastActiveTime = DateTime.tryParse(ts);
    return b;
  }
}

class DiscoverAiService with BoroughAiContext {
  static final DiscoverAiService _instance = DiscoverAiService._internal();
  factory DiscoverAiService() => _instance;
  DiscoverAiService._internal();

  static const String _behaviourKey = 'huddl_discover_ai_behaviour';
  static const String _feedbackKey = 'huddl_discover_ai_feedback';

  final OnboardingDataService _onboarding = OnboardingDataService();

  _DiscoverBehaviour _behaviour = _DiscoverBehaviour();
  final List<DiscoverFeedback> _feedbackHistory = [];
  bool _initialized = false;

  // ── Initialise ──────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    await _onboarding.initialize();
    try {
      final raw = await BrowserStorage.getString(_behaviourKey);
      if (raw != null && raw.isNotEmpty) {
        _behaviour = _DiscoverBehaviour.fromJson(json.decode(raw));
      }
      final fbRaw = await BrowserStorage.getString(_feedbackKey);
      if (fbRaw != null && fbRaw.isNotEmpty) {
        final List<dynamic> decoded = json.decode(fbRaw);
        _feedbackHistory.addAll(
          decoded.map((j) => DiscoverFeedback.fromJson(j as Map<String, dynamic>)),
        );
      }
    } catch (_) {
      // Start fresh on decode errors
    }
    _initialized = true;
  }

  Future<void> _persist() async {
    await BrowserStorage.setString(
      _behaviourKey, json.encode(_behaviour.toJson()),
    );
    await BrowserStorage.setString(
      _feedbackKey,
      json.encode(_feedbackHistory.map((f) => f.toJson()).toList()),
    );
  }

  // ── Usage Tracking ────────────────────────────────────────────────────

  void recordGroupView(String groupId, String category) {
    _behaviour.groupViews[groupId] =
        (_behaviour.groupViews[groupId] ?? 0) + 1;
    _behaviour.viewedCategories.add(category);
    _behaviour.totalViews++;
    _behaviour.lastActiveTime = DateTime.now();
    _persist();
  }

  void recordGroupJoin(String groupId) {
    _behaviour.groupJoins[groupId] =
        (_behaviour.groupJoins[groupId] ?? 0) + 1;
    _behaviour.joinedGroupIds.add(groupId);
    _persist();
  }

  void recordSearch(String query) {
    if (query.length < 2) return;
    final normalised = query.toLowerCase().trim();
    _behaviour.searchQueries[normalised] =
        (_behaviour.searchQueries[normalised] ?? 0) + 1;
    _behaviour.totalSearches++;
    _persist();
  }

  void recordFilterUse() {
    _behaviour.totalFilterUses++;
    _persist();
  }

  // ── Predictive Search (pre-filling) ─────────────────────────────────

  List<DiscoverSearchSuggestion> getPredictiveSuggestions({
    String? partialQuery,
    String? userBorough,
    List<String> stagesOfLife = const [],
    String? parentType,
  }) {
    final suggestions = <DiscoverSearchSuggestion>[];

    // 1. Past searches (highest weight)
    for (final q in _behaviour.topSearches) {
      if (partialQuery == null ||
          partialQuery.isEmpty ||
          q.contains(partialQuery.toLowerCase())) {
        suggestions.add(DiscoverSearchSuggestion(
          query: q,
          reason: 'Recent search',
          icon: '\u{1F50D}',
          relevance: 0.95,
        ));
      }
    }

    // 2. Category-based suggestions from viewed groups
    final topCats = _behaviour.viewedCategories.take(3);
    for (final cat in topCats) {
      final catLabel = _categoryDisplayName(cat);
      if (partialQuery == null ||
          partialQuery.isEmpty ||
          catLabel.toLowerCase().contains(partialQuery.toLowerCase())) {
        suggestions.add(DiscoverSearchSuggestion(
          query: catLabel.toLowerCase(),
          reason: 'You often browse $catLabel',
          icon: _categoryEmoji(cat),
          relevance: 0.85,
        ));
      }
    }

    // 3. Stage-of-life contextual suggestions
    if (stagesOfLife.contains('expecting')) {
      suggestions.add(const DiscoverSearchSuggestion(
        query: 'expecting parents',
        reason: 'Groups for your journey',
        icon: '\u{1F930}',
        relevance: 0.9,
      ));
    }
    if (parentType == 'mum') {
      suggestions.add(const DiscoverSearchSuggestion(
        query: 'mums groups',
        reason: 'Connect with other mums',
        icon: '\u{1F469}\u200D\u{1F467}',
        relevance: 0.88,
      ));
    }
    if (parentType == 'dad') {
      suggestions.add(const DiscoverSearchSuggestion(
        query: 'dads groups',
        reason: 'Connect with other dads',
        icon: '\u{1F468}\u200D\u{1F466}',
        relevance: 0.88,
      ));
    }

    // 4. Time-of-day context
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 10) {
      suggestions.add(const DiscoverSearchSuggestion(
        query: 'morning meetups',
        reason: 'Good morning! Find today\'s groups',
        icon: '\u2600\uFE0F',
        relevance: 0.6,
      ));
    } else if (hour >= 20) {
      suggestions.add(const DiscoverSearchSuggestion(
        query: 'sleep support',
        reason: 'Late night? Find support groups',
        icon: '\u{1F319}',
        relevance: 0.65,
      ));
    }

    // 5. Borough-based
    if (userBorough != null && userBorough != 'Unknown Borough') {
      suggestions.add(DiscoverSearchSuggestion(
        query: 'groups near $userBorough',
        reason: 'Local communities',
        icon: '\u{1F4CD}',
        relevance: 0.75,
      ));
    }

    // De-duplicate & sort
    final seen = <String>{};
    suggestions.retainWhere((s) => seen.add(s.query.toLowerCase()));
    suggestions.sort((a, b) => b.relevance.compareTo(a.relevance));
    return suggestions.take(5).toList();
  }

  // ── NLP Query Parsing ─────────────────────────────────────────────────

  Map<String, dynamic> parseNaturalQuery(String query) {
    final q = query.toLowerCase().trim();
    final result = <String, dynamic>{};

    // Audience intent
    if (q.contains('mum') || q.contains('mother')) result['audience'] = 'Mums';
    if (q.contains('dad') || q.contains('father')) result['audience'] = 'Dads';
    if (q.contains('expecting') || q.contains('pregnant')) {
      result['audience'] = 'Parents expecting a baby';
    }

    // Category intent
    if (q.contains('sleep')) result['category'] = 'SLEEP';
    if (q.contains('fitness') || q.contains('exercise')) result['category'] = 'FITNESS';
    if (q.contains('food') || q.contains('meal') || q.contains('recipe')) {
      result['category'] = 'FOOD & NUTRITION';
    }
    if (q.contains('work') || q.contains('career')) result['category'] = 'WORK-LIFE';
    if (q.contains('parent')) result['category'] = 'PARENTING';

    // Sort intent
    if (q.contains('popular') || q.contains('most members')) result['sort'] = 'Most Members';
    if (q.contains('new') || q.contains('latest')) result['sort'] = 'Newest';
    if (q.contains('alpha') || q.contains('a-z')) result['sort'] = 'A-Z';

    return result;
  }

  // ── AI-Driven Recommendation Scoring ──────────────────────────────────

  /// Compute a recommendation score for each group. Higher = shown first.
  double getGroupRecommendationScore(
    Map<String, dynamic> group, {
    String? userBorough,
    String? parentType,
    List<String> stagesOfLife = const [],
  }) {
    double score = 50.0; // base

    final groupId = group['id'] as String? ?? '';
    final category = group['category'] as String? ?? '';
    final memberCount = group['memberCount'] as int? ?? 0;
    final borough = group['creatorBorough'] as String?;
    final audiences = group['targetAudience'] as List<String>? ?? [];

    // 1. Liked/disliked category from feedback
    if (_behaviour.likedCategories.contains(category)) score += 15;
    if (_behaviour.dislikedCategories.contains(category)) score -= 20;

    // 2. Previously viewed category boost
    if (_behaviour.viewedCategories.contains(category)) score += 8;

    // 3. Borough match boost
    if (userBorough != null && borough == userBorough) score += 12;

    // 4. Audience match boost
    if (parentType != null) {
      if (parentType == 'mum' && audiences.contains('Mums')) score += 10;
      if (parentType == 'dad' && audiences.contains('Dads')) score += 10;
    }
    if (stagesOfLife.contains('expecting') &&
        audiences.contains('Parents expecting a baby')) {
      score += 10;
    }
    if (stagesOfLife.contains('has_children') &&
        audiences.contains('Kids')) {
      score += 10;
    }

    // 5. Popularity boost (log scale)
    if (memberCount > 1000) {
      score += 5;
    } else if (memberCount > 500) {
      score += 3;
    }

    // 6. Already joined penalty (push down)
    if (_behaviour.joinedGroupIds.contains(groupId)) score -= 30;

    // 7. Already viewed many times penalty (freshness)
    final views = _behaviour.groupViews[groupId] ?? 0;
    if (views > 5) score -= 5;

    return score.clamp(0, 100);
  }

  // ── Intelligent Sorting ───────────────────────────────────────────────

  /// Sort groups by AI recommendation score + apply NLP-parsed params.
  List<Map<String, dynamic>> intelligentSort(
    List<Map<String, dynamic>> groups, {
    String? userBorough,
    String? parentType,
    List<String> stagesOfLife = const [],
    Map<String, dynamic>? nlpParams,
  }) {
    var result = List<Map<String, dynamic>>.from(groups);

    // Apply NLP-parsed audience filter
    if (nlpParams != null && nlpParams.containsKey('audience')) {
      final aud = nlpParams['audience'] as String;
      result = result.where((g) {
        final ta = g['targetAudience'] as List<String>? ?? [];
        return ta.isEmpty || ta.contains(aud);
      }).toList();
    }

    // Apply NLP-parsed category filter
    if (nlpParams != null && nlpParams.containsKey('category')) {
      final cat = nlpParams['category'] as String;
      result = result.where((g) {
        return (g['category'] as String? ?? '').toUpperCase() == cat.toUpperCase();
      }).toList();
    }

    // Score and sort
    result.sort((a, b) {
      final sa = getGroupRecommendationScore(a,
          userBorough: userBorough,
          parentType: parentType,
          stagesOfLife: stagesOfLife);
      final sb = getGroupRecommendationScore(b,
          userBorough: userBorough,
          parentType: parentType,
          stagesOfLife: stagesOfLife);
      return sb.compareTo(sa);
    });

    // Apply NLP-parsed sort override
    if (nlpParams != null && nlpParams.containsKey('sort')) {
      final sort = nlpParams['sort'] as String;
      switch (sort) {
        case 'Most Members':
          result.sort(
              (a, b) => (b['memberCount'] as int).compareTo(a['memberCount'] as int));
        case 'Newest':
          result = result.reversed.toList();
        case 'A-Z':
          result.sort((a, b) => (a['name'] as String)
              .toLowerCase()
              .compareTo((b['name'] as String).toLowerCase()));
      }
    }

    return result;
  }

  // ── Group Summarisation ───────────────────────────────────────────────

  AiGroupSummary summarizeGroup(Map<String, dynamic> group, {
    String? parentType,
    List<String> stagesOfLife = const [],
    String? userBorough,
  }) {
    final name = group['name'] as String? ?? '';
    final description = group['description'] as String? ?? '';
    final category = group['category'] as String? ?? '';
    final memberCount = group['memberCount'] as int? ?? 0;
    final audiences = group['targetAudience'] as List<String>? ?? [];
    final borough = group['creatorBorough'] as String?;

    // One-liner: contextual summary
    String oneLiner;
    if (description.length > 60) {
      oneLiner = '${description.substring(0, 57)}...';
    } else if (description.isNotEmpty) {
      oneLiner = description;
    } else {
      oneLiner = '$name — a ${_categoryDisplayName(category).toLowerCase()} community';
    }

    // Suitability
    String suitability;
    if (audiences.contains('Mums') && parentType == 'mum') {
      suitability = 'Great match for you';
    } else if (audiences.contains('Dads') && parentType == 'dad') {
      suitability = 'Great match for you';
    } else if (audiences.contains('Parents expecting a baby') &&
        stagesOfLife.contains('expecting')) {
      suitability = 'Perfect for your journey';
    } else if (memberCount > 1000) {
      suitability = 'Popular community with $memberCount+ members';
    } else if (borough != null && borough == userBorough) {
      suitability = 'Local to your area';
    } else {
      suitability = 'Open to all parents';
    }

    final vibe = _categoryVibe(category);
    final matchScore = getGroupRecommendationScore(group,
        userBorough: userBorough,
        parentType: parentType,
        stagesOfLife: stagesOfLife);

    return AiGroupSummary(
      oneLiner: oneLiner,
      suitability: suitability,
      vibe: vibe,
      matchScore: matchScore,
    );
  }

  // ── Quick Actions (contextual, auto-generated) ────────────────────────

  List<DiscoverQuickAction> getQuickActions({
    int totalGroups = 0,
    int joinedCount = 0,
    bool hasUnjoined = true,
  }) {
    final actions = <DiscoverQuickAction>[];

    // Suggest browsing if user hasn't joined any
    if (joinedCount == 0 && totalGroups > 0) {
      actions.add(const DiscoverQuickAction(
        id: 'browse_top',
        label: 'Browse popular',
        description: 'See the most active groups',
        iconName: 'trending_up',
        confidence: 0.9,
        data: {'sort': 'Most Members'},
      ));
    }

    // Suggest creating if user is active
    if (_behaviour.totalViews > 10 && joinedCount > 0) {
      actions.add(const DiscoverQuickAction(
        id: 'create_group',
        label: 'Start a group',
        description: 'Create your own community',
        iconName: 'add_circle',
        confidence: 0.75,
      ));
    }

    // Category-based suggestion
    if (_behaviour.viewedCategories.isNotEmpty) {
      final topCat = _behaviour.viewedCategories.first;
      actions.add(DiscoverQuickAction(
        id: 'explore_$topCat',
        label: 'More ${_categoryDisplayName(topCat)}',
        description: 'You seem interested in ${_categoryDisplayName(topCat).toLowerCase()}',
        iconName: 'explore',
        confidence: 0.8,
        data: {'category': topCat},
      ));
    }

    // Filter suggestion
    if (!_behaviour.shouldCollapseFilters) {
      actions.add(const DiscoverQuickAction(
        id: 'smart_filter',
        label: 'Filter for me',
        description: 'AI picks the best groups for you',
        iconName: 'auto_awesome',
        confidence: 0.85,
      ));
    }

    actions.sort((a, b) => b.confidence.compareTo(a.confidence));
    return actions.take(3).toList();
  }

  // ── Voice Command Parsing ─────────────────────────────────────────────

  DiscoverVoiceIntent parseVoiceCommand(String command) {
    final lower = command.toLowerCase().trim();

    // Search intent
    if (lower.startsWith('search') ||
        lower.startsWith('find') ||
        lower.startsWith('look for')) {
      final query = lower
          .replaceFirst(RegExp(r'^(search|find|look for)\s+(for\s+)?'), '')
          .trim();
      return DiscoverVoiceIntent(
        action: 'search',
        target: query,
        confidence: 0.9,
      );
    }

    // Filter intent
    if (lower.contains('show me') ||
        lower.contains('filter') ||
        lower.contains('only')) {
      final params = parseNaturalQuery(lower);
      return DiscoverVoiceIntent(
        action: 'filter',
        params: params,
        confidence: 0.85,
      );
    }

    // Join intent
    if (lower.startsWith('join')) {
      final target = lower.replaceFirst('join', '').trim();
      return DiscoverVoiceIntent(
        action: 'join',
        target: target,
        confidence: 0.85,
      );
    }

    // Create intent
    if (lower.contains('create') || lower.contains('start') || lower.contains('new group')) {
      return const DiscoverVoiceIntent(
        action: 'create',
        confidence: 0.9,
      );
    }

    // Sort intent
    if (lower.contains('sort') || lower.contains('order')) {
      final params = parseNaturalQuery(lower);
      return DiscoverVoiceIntent(
        action: 'sort',
        params: params,
        confidence: 0.8,
      );
    }

    // Default: search
    return DiscoverVoiceIntent(
      action: 'search',
      target: lower,
      confidence: 0.5,
    );
  }

  // ── Feedback Loop ─────────────────────────────────────────────────────

  void submitFeedback(String groupId, bool isPositive,
      {String? reason, String? category}) {
    final fb = DiscoverFeedback(
      groupId: groupId,
      isPositive: isPositive,
      reason: reason,
    );
    _feedbackHistory.add(fb);
    if (_feedbackHistory.length > 100) {
      _feedbackHistory.removeRange(0, _feedbackHistory.length - 100);
    }

    // Update category preferences
    if (category != null) {
      if (isPositive) {
        _behaviour.likedCategories.add(category);
        _behaviour.dislikedCategories.remove(category);
      } else {
        _behaviour.dislikedCategories.add(category);
      }
    }
    _persist();
  }

  bool hasFeedback(String groupId) =>
      _feedbackHistory.any((f) => f.groupId == groupId);

  bool? getFeedback(String groupId) {
    final fbs = _feedbackHistory.where((f) => f.groupId == groupId);
    return fbs.isEmpty ? null : fbs.last.isPositive;
  }

  double get feedbackSatisfactionRate {
    if (_feedbackHistory.isEmpty) return 0.8;
    final positive = _feedbackHistory.where((f) => f.isPositive).length;
    return positive / _feedbackHistory.length;
  }

  // ── Adaptive UI Signals ───────────────────────────────────────────────

  bool get shouldCollapseFilters => _behaviour.shouldCollapseFilters;
  bool get shouldAutoShowSearch => _behaviour.shouldAutoShowSearch;
  Set<String> get joinedGroupIds => _behaviour.joinedGroupIds;

  /// Context explanation for AI transparency.
  String getContextExplanation({
    String? userBorough,
    String? parentType,
  }) {
    final parts = <String>[];

    if (_behaviour.likedCategories.isNotEmpty) {
      parts.add('prioritising ${_categoryDisplayName(_behaviour.likedCategories.first).toLowerCase()}');
    }
    if (userBorough != null && userBorough != 'Unknown Borough') {
      parts.add('near $userBorough');
    }
    if (parentType == 'mum') {
      parts.add('tailored for mums');
    } else if (parentType == 'dad') {
      parts.add('tailored for dads');
    }

    if (parts.isEmpty) return 'Personalised for your family';
    return parts.join(' \u00B7 ');
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  String _categoryDisplayName(String category) {
    switch (category.toUpperCase()) {
      case 'PARENTING':
        return 'Parenting';
      case 'SLEEP':
        return 'Sleep';
      case 'FITNESS':
        return 'Fitness';
      case 'FOOD & NUTRITION':
        return 'Food & Nutrition';
      case 'WORK-LIFE':
        return 'Work-Life Balance';
      default:
        return category;
    }
  }

  String _categoryEmoji(String category) {
    switch (category.toUpperCase()) {
      case 'PARENTING':
        return '\u{1F476}';
      case 'SLEEP':
        return '\u{1F634}';
      case 'FITNESS':
        return '\u{1F3CB}';
      case 'FOOD & NUTRITION':
        return '\u{1F957}';
      case 'WORK-LIFE':
        return '\u{1F4BC}';
      default:
        return '\u{2728}';
    }
  }

  String _categoryVibe(String category) {
    switch (category.toUpperCase()) {
      case 'PARENTING':
        return '\u{1F91D} Supportive & Welcoming';
      case 'SLEEP':
        return '\u{1F319} Calm & Helpful';
      case 'FITNESS':
        return '\u{1F4AA} Active & Motivating';
      case 'FOOD & NUTRITION':
        return '\u{1F957} Healthy & Creative';
      case 'WORK-LIFE':
        return '\u{2696}\uFE0F Balanced & Practical';
      default:
        return '\u{2728} Discover Something New';
    }
  }
}
