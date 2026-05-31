import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'ai_knowledge_base_service.dart';

// =============================================================================
// AI LEARNING ENGINE SERVICE  — ENRICHED V4
//
// Centralised user-behaviour learning system for Huddl.
//
// V4 enrichment: Tracks engagement across 50+ source categories:
//   - Single parent group/content interactions (Gingerbread)
//   - SEN/disability content engagement (Contact, Family Fund, Sibs)
//   - Digital safety content engagement (Parent Zone, BBC Bitesize)
//   - Adoption/fostering content engagement (Adoption UK, CoramBAAF, Home for Good)
//   - Emotional intelligence content engagement (Parent Talk Podcast)
//   - Blended family content engagement (HappySteps)
//   - Eco-parenting content engagement (Green Parent, Berkshire Mummies)
//   - School-readiness content engagement (Parentkind, National Parent Survey)
//   - Sibling support content engagement (Sibs)
//   - Family lifestyle content engagement (MyBaba, Mamas & Papas)
//   - Separation/co-parenting content engagement (OnlyMums & Dads)
//   - Mental health signposting engagement (Selmind, Coram Family Lives)
//
// ┌──────────────────────────────────────────────────────────────────────────┐
// │ HYPERLOCAL ARCHITECTURE — BOROUGH IS THE PRIMARY PARTITION KEY          │
// │                                                                         │
// │  Every signal is tagged with a borough.                                 │
// │  Borough-scoped features (chat, groups, meetups, marketplace):          │
// │    → Signals are ONLY used within the SAME borough                      │
// │    → When user changes borough, borough-only signals stay in old        │
// │      borough; new signals accumulate in new borough                     │
// │    → Counters (groupsJoined, meetupsAttended, etc.) are PER-BOROUGH    │
// │                                                                         │
// │  UK-wide features (events ONLY):                                        │
// │    → Event signals carry the EVENT's borough (destination), not user's  │
// │    → Event preferences are global (not partitioned by borough)          │
// │    → Event browsing for other boroughs is encouraged                    │
// │                                                                         │
// │  Prompt context always includes:                                        │
// │    1. The user's CURRENT borough                                        │
// │    2. Borough-scoped engagement stats                                   │
// │    3. Global event preferences (cross-borough)                          │
// │    4. HyperlocalRules enforcement statement                             │
// └──────────────────────────────────────────────────────────────────────────┘
//
// Signal sources (12):
//   - Copilot conversations       (query topics, follow-ups, satisfaction)
//   - Chat / DMs                  (activity, sentiment keywords, response speed)
//   - Groups                      (views, joins, posts, reactions)
//   - Meetups                     (RSVPs, attendance, creation, no-shows)
//   - Events                      (views, RSVPs — UK-WIDE, tagged with event borough)
//   - Marketplace                 (listings created, items viewed, price range)
//   - Profile updates             (bio changes, photo updates, postcode changes)
//   - Feed interactions           (nudge taps, feed scrolls, nudge dismissals)
//   - External content affinity   (article clicks, knowledge-base queries)
//   - Offers                      (deal views, taps, redemptions)
//   - Matchmaker                  (match views, accepts, dismissals)
//
// Learning maturity stages (per-borough):
//   1. Cold Start    (< 10 signals)    — profile mainly from onboarding
//   2. Warming       (10 - 50 signals) — behavioural weights emerging
//   3. Personalised  (50 - 200 signals)— strong personal model
//   4. Mature        (> 200 signals)   — stable, decayed model
//
// Persistence: all data stored via BrowserStorage (shared_preferences).
// =============================================================================

/// Learning maturity stages
enum LearningMaturity {
  coldStart, // < 10 signals
  warming, // 10 - 50 signals
  personalised, // 50 - 200 signals
  mature, // > 200 signals
}

/// Signal source categories
enum SignalSource {
  copilot,
  chat,
  group,
  meetup,
  event, // UK-WIDE — the only cross-borough source
  marketplace,
  profile,
  feed,
  knowledgeBase,
  offers,
  matchmaker,
  supportOrg, // V3: Interactions with charity/support org content
}

/// Whether a signal source is borough-scoped or UK-wide.
/// This is the CORE architectural decision of Huddl.
bool isSignalBoroughScoped(SignalSource source) {
  switch (source) {
    case SignalSource.event:
      return false; // Events are UK-wide
    case SignalSource.copilot:
    case SignalSource.chat:
    case SignalSource.group:
    case SignalSource.meetup:
    case SignalSource.marketplace:
    case SignalSource.profile:
    case SignalSource.feed:
    case SignalSource.knowledgeBase:
    case SignalSource.offers:
    case SignalSource.matchmaker:
    case SignalSource.supportOrg:
      return true; // Everything else is borough-scoped
  }
}

/// A single recorded user signal — now with borough tagging.
class UserSignal {
  final String id;
  final SignalSource source;
  final String action; // e.g. 'group_join', 'meetup_rsvp', 'copilot_query'
  final Map<String, dynamic> data; // action-specific payload
  final double weight; // initial importance (0.0 - 1.0)
  final DateTime timestamp;

  /// The borough this signal belongs to.
  /// For borough-scoped features: always the user's current borough.
  /// For events: the EVENT's borough (where the event takes place).
  final String? borough;

  const UserSignal({
    required this.id,
    required this.source,
    required this.action,
    this.data = const {},
    this.weight = 0.5,
    required this.timestamp,
    this.borough,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'action': action,
        'data': data,
        'weight': weight,
        'timestamp': timestamp.toIso8601String(),
        'borough': borough,
      };

  factory UserSignal.fromJson(Map<String, dynamic> json) => UserSignal(
        id: json['id'] as String,
        source: SignalSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => SignalSource.profile,
        ),
        action: json['action'] as String,
        data: Map<String, dynamic>.from(json['data'] ?? {}),
        weight: (json['weight'] as num?)?.toDouble() ?? 0.5,
        timestamp: DateTime.parse(json['timestamp'] as String),
        borough: json['borough'] as String?,
      );
}

/// Weighted topic affinity score
class TopicAffinity {
  final String topic;
  double score; // 0.0 - 1.0 (decayed, weighted)
  int signalCount;
  DateTime lastSeen;

  TopicAffinity({
    required this.topic,
    this.score = 0.0,
    this.signalCount = 0,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'topic': topic,
        'score': score,
        'signalCount': signalCount,
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory TopicAffinity.fromJson(Map<String, dynamic> json) => TopicAffinity(
        topic: json['topic'] as String,
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
        signalCount: json['signalCount'] as int? ?? 0,
        lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Time-of-day engagement pattern
class TimePattern {
  final int hour; // 0-23
  int engagementCount;
  double avgEngagement; // running average 0.0 - 1.0

  TimePattern({
    required this.hour,
    this.engagementCount = 0,
    this.avgEngagement = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'hour': hour,
        'engagementCount': engagementCount,
        'avgEngagement': avgEngagement,
      };

  factory TimePattern.fromJson(Map<String, dynamic> json) => TimePattern(
        hour: json['hour'] as int,
        engagementCount: json['engagementCount'] as int? ?? 0,
        avgEngagement: (json['avgEngagement'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Content format preference tracking
class ContentFormatPreference {
  double articleAffinity; // long-form reading
  double quickTipAffinity; // short nudges, tips
  double socialAffinity; // group chats, DMs, community
  double eventAffinity; // meetups, events, activities
  double marketplaceAffinity; // buying / selling
  double aiCopilotAffinity; // direct AI interaction

  ContentFormatPreference({
    this.articleAffinity = 0.0,
    this.quickTipAffinity = 0.0,
    this.socialAffinity = 0.0,
    this.eventAffinity = 0.0,
    this.marketplaceAffinity = 0.0,
    this.aiCopilotAffinity = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'articleAffinity': articleAffinity,
        'quickTipAffinity': quickTipAffinity,
        'socialAffinity': socialAffinity,
        'eventAffinity': eventAffinity,
        'marketplaceAffinity': marketplaceAffinity,
        'aiCopilotAffinity': aiCopilotAffinity,
      };

  factory ContentFormatPreference.fromJson(Map<String, dynamic> json) =>
      ContentFormatPreference(
        articleAffinity:
            (json['articleAffinity'] as num?)?.toDouble() ?? 0.0,
        quickTipAffinity:
            (json['quickTipAffinity'] as num?)?.toDouble() ?? 0.0,
        socialAffinity:
            (json['socialAffinity'] as num?)?.toDouble() ?? 0.0,
        eventAffinity:
            (json['eventAffinity'] as num?)?.toDouble() ?? 0.0,
        marketplaceAffinity:
            (json['marketplaceAffinity'] as num?)?.toDouble() ?? 0.0,
        aiCopilotAffinity:
            (json['aiCopilotAffinity'] as num?)?.toDouble() ?? 0.0,
      );

  /// Return the dominant format preference name
  String get dominantFormat {
    final map = {
      'articles': articleAffinity,
      'quick_tips': quickTipAffinity,
      'social': socialAffinity,
      'events': eventAffinity,
      'marketplace': marketplaceAffinity,
      'ai_copilot': aiCopilotAffinity,
    };
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }
}

// =============================================================================
// BOROUGH ENGAGEMENT STATS — per-borough counters
//
// These are the HYPERLOCAL counters. A user who moves from Cambridge to Camden
// starts fresh in Camden for groups/meetups/marketplace, but retains their
// Cambridge history (read-only, not actively used for recommendations).
// =============================================================================

class BoroughEngagementStats {
  final String borough;
  int groupsJoined;
  int meetupsAttended;
  int meetupsCreated;
  int dmConversations;
  int chatMessagesSent;
  int marketplaceListings;
  int marketplaceItemsBought;
  int marketplaceViews;
  int matchesAccepted;
  int matchesDismissed;
  int totalBoroughSignals;
  DateTime? firstActive;
  DateTime? lastActive;

  BoroughEngagementStats({
    required this.borough,
    this.groupsJoined = 0,
    this.meetupsAttended = 0,
    this.meetupsCreated = 0,
    this.dmConversations = 0,
    this.chatMessagesSent = 0,
    this.marketplaceListings = 0,
    this.marketplaceItemsBought = 0,
    this.marketplaceViews = 0,
    this.matchesAccepted = 0,
    this.matchesDismissed = 0,
    this.totalBoroughSignals = 0,
    this.firstActive,
    this.lastActive,
  });

  /// Maturity level for this specific borough
  LearningMaturity get maturity {
    if (totalBoroughSignals >= 200) return LearningMaturity.mature;
    if (totalBoroughSignals >= 50) return LearningMaturity.personalised;
    if (totalBoroughSignals >= 10) return LearningMaturity.warming;
    return LearningMaturity.coldStart;
  }

  Map<String, dynamic> toJson() => {
        'borough': borough,
        'groupsJoined': groupsJoined,
        'meetupsAttended': meetupsAttended,
        'meetupsCreated': meetupsCreated,
        'dmConversations': dmConversations,
        'chatMessagesSent': chatMessagesSent,
        'marketplaceListings': marketplaceListings,
        'marketplaceItemsBought': marketplaceItemsBought,
        'marketplaceViews': marketplaceViews,
        'matchesAccepted': matchesAccepted,
        'matchesDismissed': matchesDismissed,
        'totalBoroughSignals': totalBoroughSignals,
        'firstActive': firstActive?.toIso8601String(),
        'lastActive': lastActive?.toIso8601String(),
      };

  factory BoroughEngagementStats.fromJson(Map<String, dynamic> json) =>
      BoroughEngagementStats(
        borough: json['borough'] as String? ?? 'Unknown',
        groupsJoined: json['groupsJoined'] as int? ?? 0,
        meetupsAttended: json['meetupsAttended'] as int? ?? 0,
        meetupsCreated: json['meetupsCreated'] as int? ?? 0,
        dmConversations: json['dmConversations'] as int? ?? 0,
        chatMessagesSent: json['chatMessagesSent'] as int? ?? 0,
        marketplaceListings: json['marketplaceListings'] as int? ?? 0,
        marketplaceItemsBought:
            json['marketplaceItemsBought'] as int? ?? 0,
        marketplaceViews: json['marketplaceViews'] as int? ?? 0,
        matchesAccepted: json['matchesAccepted'] as int? ?? 0,
        matchesDismissed: json['matchesDismissed'] as int? ?? 0,
        totalBoroughSignals: json['totalBoroughSignals'] as int? ?? 0,
        firstActive: json['firstActive'] != null
            ? DateTime.tryParse(json['firstActive'] as String)
            : null,
        lastActive: json['lastActive'] != null
            ? DateTime.tryParse(json['lastActive'] as String)
            : null,
      );

  /// Summary for prompt injection
  String toPromptSummary() {
    final buf = StringBuffer();
    buf.writeln('BOROUGH ENGAGEMENT IN $borough (${maturity.name}):');
    if (groupsJoined > 0) buf.writeln('  Groups joined: $groupsJoined');
    if (meetupsAttended > 0) {
      buf.writeln('  Meetups attended: $meetupsAttended');
    }
    if (meetupsCreated > 0) buf.writeln('  Meetups created: $meetupsCreated');
    if (dmConversations > 0) buf.writeln('  DM conversations: $dmConversations');
    if (chatMessagesSent > 0) {
      buf.writeln('  Chat messages: $chatMessagesSent');
    }
    if (marketplaceListings > 0) {
      buf.writeln('  Marketplace listings: $marketplaceListings');
    }
    if (marketplaceViews > 0) {
      buf.writeln('  Marketplace views: $marketplaceViews');
    }
    buf.writeln('  Total signals: $totalBoroughSignals');
    return buf.toString();
  }
}

// =============================================================================
// GLOBAL EVENT PREFERENCES — cross-borough (UK-wide)
// =============================================================================

class GlobalEventPreferences {
  int eventsRsvpd;
  int eventsViewed;
  Map<String, int> eventCategoryCount; // category -> count
  Map<String, int> eventBoroughCount; // borough -> count of events browsed
  List<String> preferredCategories; // top 5 inferred

  GlobalEventPreferences({
    this.eventsRsvpd = 0,
    this.eventsViewed = 0,
    Map<String, int>? eventCategoryCount,
    Map<String, int>? eventBoroughCount,
    this.preferredCategories = const [],
  })  : eventCategoryCount = eventCategoryCount ?? {},
        eventBoroughCount = eventBoroughCount ?? {};

  /// Recompute the preferred categories from counts
  void recomputePreferred() {
    final sorted = eventCategoryCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    preferredCategories = sorted.take(5).map((e) => e.key).toList();
  }

  /// Boroughs the user has browsed events in (for travel detection)
  List<String> get exploredBoroughs {
    final sorted = eventBoroughCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  Map<String, dynamic> toJson() => {
        'eventsRsvpd': eventsRsvpd,
        'eventsViewed': eventsViewed,
        'eventCategoryCount': eventCategoryCount,
        'eventBoroughCount': eventBoroughCount,
        'preferredCategories': preferredCategories,
      };

  factory GlobalEventPreferences.fromJson(Map<String, dynamic> json) =>
      GlobalEventPreferences(
        eventsRsvpd: json['eventsRsvpd'] as int? ?? 0,
        eventsViewed: json['eventsViewed'] as int? ?? 0,
        eventCategoryCount: Map<String, int>.from(
          (json['eventCategoryCount'] as Map<String, dynamic>? ?? {}).map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ),
        ),
        eventBoroughCount: Map<String, int>.from(
          (json['eventBoroughCount'] as Map<String, dynamic>? ?? {}).map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ),
        ),
        preferredCategories:
            List<String>.from(json['preferredCategories'] ?? []),
      );

  String toPromptSummary() {
    final buf = StringBuffer();
    buf.writeln('UK-WIDE EVENT PREFERENCES:');
    if (eventsRsvpd > 0) buf.writeln('  Events RSVP\'d: $eventsRsvpd');
    if (eventsViewed > 0) buf.writeln('  Events browsed: $eventsViewed');
    if (preferredCategories.isNotEmpty) {
      buf.writeln(
          '  Favourite categories: ${preferredCategories.join(", ")}');
    }
    if (exploredBoroughs.isNotEmpty) {
      buf.writeln(
          '  Boroughs explored: ${exploredBoroughs.take(5).join(", ")}');
    }
    return buf.toString();
  }
}

// =============================================================================
// THE COMPLETE USER LEARNING PROFILE — consumed by the Prompt Builder
// =============================================================================

class UserLearningProfile {
  // ── Identity (from onboarding, refreshed) ──
  String? userName;
  String? parentType; // mum, dad, provider
  String? currentBorough; // THE primary key
  List<String> stagesOfLife;
  List<Map<String, String>> children;
  String? dueDate;

  // ── Borough-scoped engagement (map of borough -> stats) ──
  Map<String, BoroughEngagementStats> boroughStats;

  // ── Global event preferences (UK-wide, cross-borough) ──
  GlobalEventPreferences eventPreferences;

  // ── Behavioural (built from all signals, but weighted toward current borough) ──
  Map<String, TopicAffinity> topicAffinities; // topic -> affinity
  List<TimePattern> timePatterns; // 24-hour engagement
  ContentFormatPreference formatPreference;
  Map<String, double> categoryScores; // category -> score

  // ── Global counters (across all boroughs) ──
  int copilotConversations;
  int copilotQueries;
  int feedNudgesTapped;
  int feedNudgesDismissed;
  int articlesRead;
  int profileUpdates;

  // ── Engagement velocity ──
  double dailyEngagementScore; // 0.0 - 1.0 (7-day rolling average)
  double weeklyEngagementTrend; // -1.0 to +1.0 (declining to growing)
  int consecutiveActiveDays;
  DateTime? lastActiveAt;
  DateTime? firstSignalAt;

  // ── Inferred preferences ──
  List<String> inferredInterests; // top 10 inferred interests
  String? preferredMeetupType; // playdate, coffee, walk, social
  String? preferredMeetupTime; // morning, afternoon, evening, weekend
  bool prefersIndoor;
  bool prefersFree;
  bool isDadEngaged; // shows dad-specific content patterns

  // ── Borough change tracking ──
  String? previousBorough; // for migration logic
  DateTime? boroughChangedAt;

  // ── Learning metadata ──
  int totalSignals; // across ALL boroughs
  DateTime lastRefreshed;

  UserLearningProfile({
    this.userName,
    this.parentType,
    this.currentBorough,
    this.stagesOfLife = const [],
    this.children = const [],
    this.dueDate,
    Map<String, BoroughEngagementStats>? boroughStats,
    GlobalEventPreferences? eventPreferences,
    Map<String, TopicAffinity>? topicAffinities,
    List<TimePattern>? timePatterns,
    ContentFormatPreference? formatPreference,
    Map<String, double>? categoryScores,
    this.copilotConversations = 0,
    this.copilotQueries = 0,
    this.feedNudgesTapped = 0,
    this.feedNudgesDismissed = 0,
    this.articlesRead = 0,
    this.profileUpdates = 0,
    this.dailyEngagementScore = 0.0,
    this.weeklyEngagementTrend = 0.0,
    this.consecutiveActiveDays = 0,
    this.lastActiveAt,
    this.firstSignalAt,
    this.inferredInterests = const [],
    this.preferredMeetupType,
    this.preferredMeetupTime,
    this.prefersIndoor = false,
    this.prefersFree = true,
    this.isDadEngaged = false,
    this.previousBorough,
    this.boroughChangedAt,
    this.totalSignals = 0,
    DateTime? lastRefreshed,
  })  : boroughStats = boroughStats ?? {},
        eventPreferences = eventPreferences ?? GlobalEventPreferences(),
        topicAffinities = topicAffinities ?? {},
        timePatterns =
            timePatterns ?? List.generate(24, (h) => TimePattern(hour: h)),
        formatPreference = formatPreference ?? ContentFormatPreference(),
        categoryScores = categoryScores ?? {},
        lastRefreshed = lastRefreshed ?? DateTime.now();

  // ── Current borough stats (convenience) ────────────────────────────────

  /// Get or create engagement stats for the current borough.
  BoroughEngagementStats get currentBoroughStats {
    if (currentBorough == null) {
      return BoroughEngagementStats(borough: 'Unknown');
    }
    return boroughStats.putIfAbsent(
      currentBorough!,
      () => BoroughEngagementStats(borough: currentBorough!),
    );
  }

  /// Maturity is now PER-BOROUGH (for borough-scoped features).
  LearningMaturity get currentBoroughMaturity =>
      currentBoroughStats.maturity;

  /// Overall maturity (across all boroughs) for global features.
  LearningMaturity get globalMaturity {
    if (totalSignals >= 200) return LearningMaturity.mature;
    if (totalSignals >= 50) return LearningMaturity.personalised;
    if (totalSignals >= 10) return LearningMaturity.warming;
    return LearningMaturity.coldStart;
  }

  // ── Serialisation ──────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'userName': userName,
        'parentType': parentType,
        'currentBorough': currentBorough,
        'stagesOfLife': stagesOfLife,
        'children': children,
        'dueDate': dueDate,
        'boroughStats': boroughStats
            .map((k, v) => MapEntry(k, v.toJson())),
        'eventPreferences': eventPreferences.toJson(),
        'topicAffinities':
            topicAffinities.map((k, v) => MapEntry(k, v.toJson())),
        'timePatterns': timePatterns.map((t) => t.toJson()).toList(),
        'formatPreference': formatPreference.toJson(),
        'categoryScores': categoryScores,
        'copilotConversations': copilotConversations,
        'copilotQueries': copilotQueries,
        'feedNudgesTapped': feedNudgesTapped,
        'feedNudgesDismissed': feedNudgesDismissed,
        'articlesRead': articlesRead,
        'profileUpdates': profileUpdates,
        'dailyEngagementScore': dailyEngagementScore,
        'weeklyEngagementTrend': weeklyEngagementTrend,
        'consecutiveActiveDays': consecutiveActiveDays,
        'lastActiveAt': lastActiveAt?.toIso8601String(),
        'firstSignalAt': firstSignalAt?.toIso8601String(),
        'inferredInterests': inferredInterests,
        'preferredMeetupType': preferredMeetupType,
        'preferredMeetupTime': preferredMeetupTime,
        'prefersIndoor': prefersIndoor,
        'prefersFree': prefersFree,
        'isDadEngaged': isDadEngaged,
        'previousBorough': previousBorough,
        'boroughChangedAt': boroughChangedAt?.toIso8601String(),
        'totalSignals': totalSignals,
        'lastRefreshed': lastRefreshed.toIso8601String(),
      };

  factory UserLearningProfile.fromJson(Map<String, dynamic> json) {
    final topicMap = <String, TopicAffinity>{};
    final rawTopics =
        json['topicAffinities'] as Map<String, dynamic>? ?? {};
    for (final entry in rawTopics.entries) {
      topicMap[entry.key] = TopicAffinity.fromJson(
        entry.value is Map<String, dynamic>
            ? entry.value as Map<String, dynamic>
            : {},
      );
    }

    final rawTimePatterns = json['timePatterns'] as List<dynamic>? ?? [];
    final patterns = rawTimePatterns.isNotEmpty
        ? rawTimePatterns
            .map((t) =>
                TimePattern.fromJson(t as Map<String, dynamic>))
            .toList()
        : List.generate(24, (h) => TimePattern(hour: h));

    final rawBoroughStats =
        json['boroughStats'] as Map<String, dynamic>? ?? {};
    final bStats = <String, BoroughEngagementStats>{};
    for (final entry in rawBoroughStats.entries) {
      bStats[entry.key] = BoroughEngagementStats.fromJson(
        entry.value is Map<String, dynamic>
            ? entry.value as Map<String, dynamic>
            : {},
      );
    }

    return UserLearningProfile(
      userName: json['userName'] as String?,
      parentType: json['parentType'] as String?,
      currentBorough: json['currentBorough'] as String?,
      stagesOfLife: List<String>.from(json['stagesOfLife'] ?? []),
      children: (json['children'] as List<dynamic>? ?? [])
          .map((c) => Map<String, String>.from(c as Map))
          .toList(),
      dueDate: json['dueDate'] as String?,
      boroughStats: bStats,
      eventPreferences: json['eventPreferences'] != null
          ? GlobalEventPreferences.fromJson(
              json['eventPreferences'] as Map<String, dynamic>)
          : GlobalEventPreferences(),
      topicAffinities: topicMap,
      timePatterns: patterns,
      formatPreference: json['formatPreference'] != null
          ? ContentFormatPreference.fromJson(
              json['formatPreference'] as Map<String, dynamic>)
          : ContentFormatPreference(),
      categoryScores: Map<String, double>.from(
        (json['categoryScores'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      ),
      copilotConversations: json['copilotConversations'] as int? ?? 0,
      copilotQueries: json['copilotQueries'] as int? ?? 0,
      feedNudgesTapped: json['feedNudgesTapped'] as int? ?? 0,
      feedNudgesDismissed: json['feedNudgesDismissed'] as int? ?? 0,
      articlesRead: json['articlesRead'] as int? ?? 0,
      profileUpdates: json['profileUpdates'] as int? ?? 0,
      dailyEngagementScore:
          (json['dailyEngagementScore'] as num?)?.toDouble() ?? 0.0,
      weeklyEngagementTrend:
          (json['weeklyEngagementTrend'] as num?)?.toDouble() ?? 0.0,
      consecutiveActiveDays:
          json['consecutiveActiveDays'] as int? ?? 0,
      lastActiveAt: json['lastActiveAt'] != null
          ? DateTime.tryParse(json['lastActiveAt'] as String)
          : null,
      firstSignalAt: json['firstSignalAt'] != null
          ? DateTime.tryParse(json['firstSignalAt'] as String)
          : null,
      inferredInterests:
          List<String>.from(json['inferredInterests'] ?? []),
      preferredMeetupType: json['preferredMeetupType'] as String?,
      preferredMeetupTime: json['preferredMeetupTime'] as String?,
      prefersIndoor: json['prefersIndoor'] as bool? ?? false,
      prefersFree: json['prefersFree'] as bool? ?? true,
      isDadEngaged: json['isDadEngaged'] as bool? ?? false,
      previousBorough: json['previousBorough'] as String?,
      boroughChangedAt: json['boroughChangedAt'] != null
          ? DateTime.tryParse(json['boroughChangedAt'] as String)
          : null,
      totalSignals: json['totalSignals'] as int? ?? 0,
      lastRefreshed: json['lastRefreshed'] != null
          ? DateTime.tryParse(json['lastRefreshed'] as String) ??
              DateTime.now()
          : DateTime.now(),
    );
  }

  // ── Convenience getters ────────────────────────────────────────────────

  /// Top N topic affinities sorted by score descending
  List<TopicAffinity> topTopics([int n = 10]) {
    final sorted = topicAffinities.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return sorted.take(n).toList();
  }

  /// Peak engagement hour (0-23)
  int get peakHour {
    if (timePatterns.isEmpty) return 10;
    final sorted = List<TimePattern>.from(timePatterns)
      ..sort((a, b) => b.engagementCount.compareTo(a.engagementCount));
    return sorted.first.hour;
  }

  /// Peak engagement period label
  String get peakPeriod {
    final h = peakHour;
    if (h >= 6 && h < 12) return 'morning';
    if (h >= 12 && h < 17) return 'afternoon';
    if (h >= 17 && h < 21) return 'evening';
    return 'night';
  }

  /// Human-readable maturity label for current borough
  String get maturityLabel {
    switch (currentBoroughMaturity) {
      case LearningMaturity.coldStart:
        return 'Getting to know you in ${currentBorough ?? "your area"}';
      case LearningMaturity.warming:
        return 'Learning your preferences in ${currentBorough ?? "your area"}';
      case LearningMaturity.personalised:
        return 'Personalised for you in ${currentBorough ?? "your area"}';
      case LearningMaturity.mature:
        return 'Deeply personalised in ${currentBorough ?? "your area"}';
    }
  }

  /// Maturity progress (0.0 - 1.0) within current borough
  double get maturityProgress {
    final total = currentBoroughStats.totalBoroughSignals;
    // Onboarding data (name, stage, postcode, due date, etc.) gives a
    // meaningful baseline — never show 0%.  Minimum 15% so the user
    // sees the AI is already active from day one.
    if (total < 10) return 0.15 + (total / 10.0) * 0.85;
    if (total < 50) return (total - 10) / 40.0;
    if (total < 200) return (total - 50) / 150.0;
    return 1.0;
  }

  /// Engagement level label
  String get engagementLevel {
    if (dailyEngagementScore >= 0.7) return 'highly_active';
    if (dailyEngagementScore >= 0.4) return 'active';
    if (dailyEngagementScore >= 0.15) return 'moderate';
    return 'low';
  }

  /// Whether the user recently changed boroughs
  bool get hasRecentlyChangedBorough {
    if (boroughChangedAt == null) return false;
    return DateTime.now().difference(boroughChangedAt!).inDays <= 30;
  }
}

// =============================================================================
// THE LEARNING ENGINE (Singleton)
// =============================================================================

class AiLearningEngineService {
  static final AiLearningEngineService _instance =
      AiLearningEngineService._internal();
  factory AiLearningEngineService() => _instance;
  AiLearningEngineService._internal();

  static const String _profileKey = 'huddl_learning_profile_v2';
  static const String _signalLogKey = 'huddl_signal_log_v2';
  static const int _maxSignalLog = 500; // keep last 500 signals
  static const double _decayFactor = 0.97; // daily decay multiplier
  static const int _maxTopics = 50; // max tracked topics

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();

  UserLearningProfile _profile = UserLearningProfile();
  List<UserSignal> _signalLog = [];
  bool _isInitialised = false;

  /// The current user learning profile (read-only copy)
  UserLearningProfile get profile => _profile;

  /// Current learning maturity FOR THE CURRENT BOROUGH
  LearningMaturity get maturity => _profile.currentBoroughMaturity;

  /// Global maturity (across all boroughs)
  LearningMaturity get globalMaturity => _profile.globalMaturity;

  /// Whether the engine is initialised and ready
  bool get isReady => _isInitialised;

  /// The user's current borough
  String? get currentBorough => _profile.currentBorough;

  // ── INITIALISATION ─────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isInitialised) return;
    await _onboarding.initialize();

    // Load persisted profile and signal log
    await _loadProfile();
    await _loadSignalLog();

    // Refresh identity fields from onboarding (always fresh)
    _syncFromOnboarding();

    // Apply daily decay to topic scores
    _applyDecay();

    _isInitialised = true;
    _log('Learning engine initialised (hyperlocal). '
        'Borough: ${_profile.currentBorough}, '
        'Borough maturity: ${_profile.currentBoroughMaturity.name}, '
        'Global signals: ${_profile.totalSignals}');
  }

  // ── SIGNAL RECORDING ───────────────────────────────────────────────────
  // Every user interaction in the app calls one of these methods.
  // Signals are now TAGGED WITH A BOROUGH.

  /// Generic signal recorder — all specialised methods delegate here.
  ///
  /// [boroughOverride] — For events, pass the EVENT's borough (where it takes
  /// place), not the user's home borough.
  Future<void> recordSignal({
    required SignalSource source,
    required String action,
    Map<String, dynamic> data = const {},
    double weight = 0.5,
    List<String> topics = const [],
    String? category,
    String? boroughOverride,
  }) async {
    final now = DateTime.now();
    final isBoroughScoped = isSignalBoroughScoped(source);

    // Determine the borough tag for this signal
    String? signalBorough;
    if (source == SignalSource.event) {
      // Events use the event's borough (could be anywhere in the UK)
      signalBorough = boroughOverride ?? _profile.currentBorough;
    } else if (isBoroughScoped) {
      // All other features use the user's CURRENT borough
      signalBorough = _profile.currentBorough;
    }

    final signal = UserSignal(
      id: '${source.name}_${action}_${now.millisecondsSinceEpoch}',
      source: source,
      action: action,
      data: data,
      weight: weight,
      timestamp: now,
      borough: signalBorough,
    );

    // Append to in-memory log
    _signalLog.add(signal);
    if (_signalLog.length > _maxSignalLog) {
      _signalLog = _signalLog.sublist(_signalLog.length - _maxSignalLog);
    }

    // Update global counters
    _profile.totalSignals++;
    _profile.lastActiveAt = now;
    _profile.firstSignalAt ??= now;

    // Update BOROUGH-SCOPED counters
    if (isBoroughScoped && signalBorough != null) {
      final stats = _profile.boroughStats.putIfAbsent(
        signalBorough,
        () => BoroughEngagementStats(borough: signalBorough!),
      );
      stats.totalBoroughSignals++;
      stats.lastActive = now;
      stats.firstActive ??= now;
      _updateBoroughCounters(stats, source, action);
    }

    // Update GLOBAL event preferences (UK-wide)
    if (source == SignalSource.event) {
      _updateEventPreferences(action, data, signalBorough);
    }

    // Update time pattern
    final hourIdx = now.hour;
    if (hourIdx >= 0 && hourIdx < _profile.timePatterns.length) {
      final tp = _profile.timePatterns[hourIdx];
      tp.engagementCount++;
      tp.avgEngagement =
          (tp.avgEngagement * (tp.engagementCount - 1) + weight) /
              tp.engagementCount;
    }

    // Update topic affinities
    for (final topic in topics) {
      _boostTopic(topic, weight);
    }

    // Update category score
    if (category != null) {
      _profile.categoryScores[category] =
          (_profile.categoryScores[category] ?? 0.0) + weight * 0.1;
    }

    // Update format preference
    _updateFormatPreference(source, weight);

    // Update global source-specific counters
    _updateGlobalCounters(source, action);

    // Update engagement velocity
    _updateEngagement(now);

    // Recompute inferred interests
    _recomputeInferredInterests();

    // Persist
    await _persist();

    _log('Signal: ${source.name}/$action '
        '(w=$weight, borough=$signalBorough, topics=$topics)');
  }

  // ── SPECIALISED SIGNAL RECORDERS ───────────────────────────────────────

  /// Copilot: user asked a question (borough-scoped)
  Future<void> recordCopilotQuery({
    required String query,
    required String detectedCategory,
  }) async {
    final topics = _extractTopics(query);
    await recordSignal(
      source: SignalSource.copilot,
      action: 'query',
      data: {'query': query, 'category': detectedCategory},
      weight: 0.7,
      topics: topics,
      category: detectedCategory,
    );
  }

  /// Copilot: user gave feedback (thumbs up/down)
  Future<void> recordCopilotFeedback({
    required bool positive,
    required String queryTopic,
  }) async {
    await recordSignal(
      source: SignalSource.copilot,
      action: positive ? 'thumbs_up' : 'thumbs_down',
      data: {'topic': queryTopic, 'positive': positive},
      weight: positive ? 0.8 : 0.3,
      topics: [queryTopic],
    );
  }

  /// Group: user joined a group (BOROUGH-SCOPED)
  Future<void> recordGroupJoin({
    required String groupId,
    required String groupName,
    List<String> groupTags = const [],
  }) async {
    await recordSignal(
      source: SignalSource.group,
      action: 'join',
      data: {'groupId': groupId, 'groupName': groupName},
      weight: 0.8,
      topics: groupTags,
      category: 'social',
    );
  }

  /// Group: user viewed a group (BOROUGH-SCOPED)
  Future<void> recordGroupView({
    required String groupId,
    List<String> groupTags = const [],
  }) async {
    await recordSignal(
      source: SignalSource.group,
      action: 'view',
      data: {'groupId': groupId},
      weight: 0.3,
      topics: groupTags,
    );
  }

  /// Group: user sent a message in a group chat (BOROUGH-SCOPED)
  Future<void> recordGroupMessage({
    required String groupId,
    int messageLength = 0,
  }) async {
    await recordSignal(
      source: SignalSource.chat,
      action: 'group_message',
      data: {'groupId': groupId, 'length': messageLength},
      weight: 0.6,
      category: 'social',
    );
  }

  /// Meetup: user RSVP'd to a meetup (BOROUGH-SCOPED)
  Future<void> recordMeetupRsvp({
    required String meetupId,
    required String meetupCategory,
    required bool isFree,
    bool isIndoor = false,
    List<String> tags = const [],
  }) async {
    await recordSignal(
      source: SignalSource.meetup,
      action: 'rsvp',
      data: {
        'meetupId': meetupId,
        'category': meetupCategory,
        'isFree': isFree,
        'isIndoor': isIndoor,
      },
      weight: 0.9,
      topics: [meetupCategory, ...tags],
      category: 'meetup',
    );

    // Update meetup preference tracking
    _updateMeetupPreferences(meetupCategory, isIndoor, isFree);
  }

  /// Meetup: user created a meetup (BOROUGH-SCOPED)
  Future<void> recordMeetupCreated({
    required String meetupCategory,
    required bool isFree,
  }) async {
    await recordSignal(
      source: SignalSource.meetup,
      action: 'created',
      data: {'category': meetupCategory, 'isFree': isFree},
      weight: 1.0,
      topics: [meetupCategory],
      category: 'meetup',
    );
  }

  /// Event: user RSVP'd to an event (UK-WIDE — uses event's borough)
  Future<void> recordEventRsvp({
    required String eventId,
    required String eventCategory,
    required bool isFree,
    String? eventBorough, // The borough WHERE the event takes place
    List<String> tags = const [],
  }) async {
    await recordSignal(
      source: SignalSource.event,
      action: 'rsvp',
      data: {
        'eventId': eventId,
        'category': eventCategory,
        'isFree': isFree,
        'eventBorough': eventBorough,
      },
      weight: 0.85,
      topics: [eventCategory, ...tags],
      category: 'event',
      boroughOverride: eventBorough,
    );
  }

  /// Event: user viewed an event (UK-WIDE — uses event's borough)
  Future<void> recordEventView({
    required String eventId,
    required String eventCategory,
    String? eventBorough, // The borough WHERE the event takes place
  }) async {
    await recordSignal(
      source: SignalSource.event,
      action: 'view',
      data: {
        'eventId': eventId,
        'category': eventCategory,
        'eventBorough': eventBorough,
      },
      weight: 0.3,
      topics: [eventCategory],
      category: 'event',
      boroughOverride: eventBorough,
    );
  }

  /// Marketplace: user created a listing (BOROUGH-SCOPED)
  Future<void> recordMarketplaceListing({
    required String category,
    required double price,
    List<String> tags = const [],
  }) async {
    await recordSignal(
      source: SignalSource.marketplace,
      action: 'listing_created',
      data: {'category': category, 'price': price},
      weight: 0.8,
      topics: ['marketplace', category, ...tags],
      category: 'marketplace',
    );
  }

  /// Marketplace: user viewed an item (BOROUGH-SCOPED)
  Future<void> recordMarketplaceView({
    required String category,
  }) async {
    await recordSignal(
      source: SignalSource.marketplace,
      action: 'item_viewed',
      data: {'category': category},
      weight: 0.25,
      topics: ['marketplace', category],
      category: 'marketplace',
    );
  }

  /// DM: user sent a direct message (BOROUGH-SCOPED)
  Future<void> recordDmSent() async {
    await recordSignal(
      source: SignalSource.chat,
      action: 'dm_sent',
      weight: 0.5,
      category: 'social',
    );
  }

  /// Feed: user tapped a nudge card
  Future<void> recordNudgeTapped({
    required String nudgeType,
  }) async {
    await recordSignal(
      source: SignalSource.feed,
      action: 'nudge_tapped',
      data: {'type': nudgeType},
      weight: 0.6,
      topics: [nudgeType],
    );
  }

  /// Feed: user dismissed a nudge card
  Future<void> recordNudgeDismissed({
    required String nudgeType,
  }) async {
    await recordSignal(
      source: SignalSource.feed,
      action: 'nudge_dismissed',
      data: {'type': nudgeType},
      weight: 0.2,
    );
  }

  /// Knowledge base: user read an article
  Future<void> recordArticleRead({
    required String articleId,
    required String category,
    required String source,
    List<String> tags = const [],
  }) async {
    await recordSignal(
      source: SignalSource.knowledgeBase,
      action: 'article_read',
      data: {
        'articleId': articleId,
        'category': category,
        'articleSource': source,
      },
      weight: 0.6,
      topics: [category, ...tags],
      category: category,
    );
  }

  /// Profile: user updated their profile
  Future<void> recordProfileUpdate({
    required String field,
  }) async {
    await recordSignal(
      source: SignalSource.profile,
      action: 'update',
      data: {'field': field},
      weight: 0.4,
    );
  }

  /// Offers: user interacted with a deal
  Future<void> recordOfferInteraction({
    required String storeId,
    required String action,
  }) async {
    await recordSignal(
      source: SignalSource.offers,
      action: 'offer_$action',
      data: {'storeId': storeId},
      weight: action == 'redeem' ? 0.9 : 0.4,
      topics: ['offers', 'deals'],
      category: 'offers',
    );
  }

  /// Matchmaker: user accepted or viewed a match suggestion (BOROUGH-SCOPED)
  Future<void> recordMatchInteraction({
    required String matchId,
    required String action,
  }) async {
    await recordSignal(
      source: SignalSource.matchmaker,
      action: 'match_$action',
      data: {'matchId': matchId},
      weight: action == 'accepted' ? 0.9 : 0.3,
      topics: ['social', 'matchmaker'],
      category: 'social',
    );
  }

  // ── PROFILE QUERY METHODS ──────────────────────────────────────────────
  // Used by the Prompt Builder and downstream services.

  /// Build a concise text summary of the user's learning profile
  /// suitable for injection into a Gemini system prompt.
  /// Now includes hyperlocal borough context as the FIRST thing.
  String buildPromptContext() {
    final buf = StringBuffer();
    final borough = _profile.currentBorough;

    // ── 0. HYPERLOCAL RULES (always first) ───────────────────────────────
    if (borough != null) {
      buf.writeln(HyperlocalRules.toPromptContext(borough));
      buf.writeln();
    }

    // ── 1. User identity + borough ───────────────────────────────────────
    buf.writeln(
        'USER LEARNING PROFILE (${_profile.maturityLabel}):');
    if (_profile.userName != null) {
      buf.writeln('- Name: ${_profile.userName}');
    }
    if (_profile.parentType != null) {
      buf.writeln('- Role: ${_profile.parentType}');
    }
    if (borough != null) {
      buf.writeln('- Borough: $borough (ALL social features scoped here)');
    }
    if (_profile.stagesOfLife.isNotEmpty) {
      buf.writeln(
          '- Life stages: ${_profile.stagesOfLife.join(", ")}');
    }
    if (_profile.dueDate != null) {
      buf.writeln('- Expecting: due ${_profile.dueDate}');
    }
    for (final child in _profile.children) {
      final name = child['name'] ?? 'Child';
      final birthday = child['birthday'];
      if (birthday != null) {
        buf.writeln('- Child: $name (born $birthday)');
      }
    }

    // ── 2. Borough-scoped engagement (only if warming+) ──────────────────
    if (borough != null) {
      final bStats = _profile.currentBoroughStats;
      if (bStats.maturity != LearningMaturity.coldStart) {
        buf.writeln();
        buf.write(bStats.toPromptSummary());
      }
    }

    // ── 3. Global event preferences ──────────────────────────────────────
    if (_profile.eventPreferences.eventsRsvpd > 0 ||
        _profile.eventPreferences.eventsViewed > 5) {
      buf.writeln();
      buf.write(_profile.eventPreferences.toPromptSummary());
    }

    // ── 4. Behavioural insights (only if warming+ globally) ──────────────
    if (_profile.globalMaturity != LearningMaturity.coldStart) {
      final topTopics = _profile.topTopics(5);
      if (topTopics.isNotEmpty) {
        buf.writeln(
            '- Top interests: ${topTopics.map((t) => t.topic).join(", ")}');
      }
      buf.writeln('- Engagement level: ${_profile.engagementLevel}');
      buf.writeln('- Peak activity: ${_profile.peakPeriod}');
      buf.writeln(
          '- Preferred content: ${_profile.formatPreference.dominantFormat}');

      if (_profile.preferredMeetupType != null) {
        buf.writeln(
            '- Preferred meetup: ${_profile.preferredMeetupType}');
      }
      if (_profile.prefersIndoor) {
        buf.writeln('- Prefers: indoor activities');
      }
      if (_profile.prefersFree) {
        buf.writeln('- Prefers: free events');
      }
      if (_profile.isDadEngaged) {
        buf.writeln('- Dad-specific content interest detected');
      }
    }

    // ── 5. Borough change context ────────────────────────────────────────
    if (_profile.hasRecentlyChangedBorough &&
        _profile.previousBorough != null) {
      buf.writeln();
      buf.writeln(
          'NOTE: This user recently moved from ${_profile.previousBorough} '
          'to $borough. They may be rebuilding their local network. '
          'Be extra welcoming and suggest ways to connect with '
          '$borough parents.');
    }

    return buf.toString();
  }

  /// Get topic affinity score for a specific topic (0.0 - 1.0)
  double getTopicScore(String topic) {
    return _profile.topicAffinities[topic.toLowerCase()]?.score ?? 0.0;
  }

  /// Check if user has shown interest in a set of tags
  double getTagRelevance(List<String> tags) {
    if (tags.isEmpty) return 0.5;
    double total = 0;
    int matched = 0;
    for (final tag in tags) {
      final score = getTopicScore(tag);
      if (score > 0) {
        total += score;
        matched++;
      }
    }
    if (matched == 0) return 0.3; // neutral if no data
    return (total / matched).clamp(0.0, 1.0);
  }

  /// Get the user's engagement score for a time window (hour 0-23)
  double getTimeRelevance(int hour) {
    if (hour < 0 || hour >= 24) return 0.5;
    return _profile.timePatterns[hour].avgEngagement;
  }

  /// Whether the user profile has enough data for personalised AI
  /// in the CURRENT BOROUGH.
  bool get hasPersonalisedData =>
      _profile.currentBoroughMaturity == LearningMaturity.personalised ||
      _profile.currentBoroughMaturity == LearningMaturity.mature;

  /// Get signals from the last N hours, optionally filtered by borough.
  List<UserSignal> recentSignals({
    int hours = 24,
    String? borough,
    bool boroughScopedOnly = false,
  }) {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    return _signalLog.where((s) {
      if (!s.timestamp.isAfter(cutoff)) return false;
      if (borough != null && s.borough != borough) return false;
      if (boroughScopedOnly && !isSignalBoroughScoped(s.source)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Get a summary of recent activity for prompt context.
  /// Borough-scoped by default to the current borough.
  String recentActivitySummary({int hours = 24}) {
    final borough = _profile.currentBorough;
    final recent = recentSignals(hours: hours, borough: borough);
    if (recent.isEmpty) return 'No recent activity in ${borough ?? "any borough"}.';

    final counts = <String, int>{};
    for (final s in recent) {
      final key = '${s.source.name}/${s.action}';
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final parts = counts.entries
        .map((e) => '${e.key}: ${e.value}')
        .take(8)
        .toList();

    return 'Recent (${hours}h) in ${borough ?? "borough"}: ${parts.join(", ")}';
  }

  /// Get the borough engagement stats for the current borough.
  BoroughEngagementStats? get currentBoroughStats {
    final borough = _profile.currentBorough;
    if (borough == null) return null;
    return _profile.boroughStats[borough];
  }

  /// Get borough engagement stats for a specific borough.
  BoroughEngagementStats? getBoroughStats(String borough) {
    return _profile.boroughStats[borough];
  }

  /// Get the global event preferences.
  GlobalEventPreferences get eventPreferences => _profile.eventPreferences;

  // ── DAILY REFRESH ──────────────────────────────────────────────────────

  Future<void> runDailyRefresh() async {
    _syncFromOnboarding();
    _applyDecay();
    _recomputeInferredInterests();
    _profile.eventPreferences.recomputePreferred();
    _updateEngagementTrend();
    _profile.lastRefreshed = DateTime.now();
    await _persist();
    _log('Daily refresh complete. Borough: ${_profile.currentBorough}, '
        'Borough maturity: ${_profile.currentBoroughMaturity.name}');
  }

  /// Check if daily refresh is needed (> 24h since last refresh)
  bool get needsDailyRefresh {
    return DateTime.now().difference(_profile.lastRefreshed).inHours >= 24;
  }

  // ── PRIVATE: PROFILE MANAGEMENT ────────────────────────────────────────

  void _syncFromOnboarding() {
    _profile.userName = _onboarding.name;
    _profile.parentType = _onboarding.parentType;
    _profile.stagesOfLife = _onboarding.stagesOfLife;
    _profile.children = _onboarding.children;
    _profile.dueDate = _onboarding.dueDate;

    // Resolve borough from postcode
    final pc = _onboarding.postcode;
    if (pc != null && pc.isNotEmpty) {
      final newBorough =
          _postcode.getBoroughFromPostcode(pc) ?? _profile.currentBorough;

      // Detect borough change
      if (_profile.currentBorough != null &&
          newBorough != null &&
          _profile.currentBorough != newBorough) {
        _profile.previousBorough = _profile.currentBorough;
        _profile.boroughChangedAt = DateTime.now();
        _log('BOROUGH CHANGE detected: '
            '${_profile.previousBorough} -> $newBorough');
      }

      _profile.currentBorough = newBorough;
    }

    _profile.isDadEngaged = _onboarding.parentType == 'dad';
  }

  void _applyDecay() {
    final now = DateTime.now();
    for (final affinity in _profile.topicAffinities.values) {
      final daysSince = now.difference(affinity.lastSeen).inDays;
      if (daysSince > 0) {
        affinity.score *= pow(_decayFactor, daysSince).toDouble();
        if (affinity.score < 0.01) affinity.score = 0.0;
      }
    }

    // Remove zero-score topics if over limit
    if (_profile.topicAffinities.length > _maxTopics) {
      final sorted = _profile.topicAffinities.entries.toList()
        ..sort((a, b) => b.value.score.compareTo(a.value.score));
      _profile.topicAffinities = Map.fromEntries(sorted.take(_maxTopics));
    }
  }

  void _boostTopic(String rawTopic, double weight) {
    final topic = rawTopic.toLowerCase().trim();
    if (topic.isEmpty) return;

    final existing = _profile.topicAffinities[topic];
    if (existing != null) {
      existing.score = (existing.score + weight * 0.15).clamp(0.0, 1.0);
      existing.signalCount++;
      existing.lastSeen = DateTime.now();
    } else {
      _profile.topicAffinities[topic] = TopicAffinity(
        topic: topic,
        score: (weight * 0.1).clamp(0.0, 1.0),
        signalCount: 1,
      );
    }
  }

  void _updateFormatPreference(SignalSource source, double weight) {
    final fp = _profile.formatPreference;
    const lr = 0.05; // learning rate

    switch (source) {
      case SignalSource.knowledgeBase:
        fp.articleAffinity =
            (fp.articleAffinity + weight * lr).clamp(0.0, 1.0);
        break;
      case SignalSource.feed:
        fp.quickTipAffinity =
            (fp.quickTipAffinity + weight * lr).clamp(0.0, 1.0);
        break;
      case SignalSource.group:
      case SignalSource.chat:
      case SignalSource.matchmaker:
        fp.socialAffinity =
            (fp.socialAffinity + weight * lr).clamp(0.0, 1.0);
        break;
      case SignalSource.meetup:
      case SignalSource.event:
        fp.eventAffinity =
            (fp.eventAffinity + weight * lr).clamp(0.0, 1.0);
        break;
      case SignalSource.marketplace:
        fp.marketplaceAffinity =
            (fp.marketplaceAffinity + weight * lr).clamp(0.0, 1.0);
        break;
      case SignalSource.copilot:
        fp.aiCopilotAffinity =
            (fp.aiCopilotAffinity + weight * lr).clamp(0.0, 1.0);
        break;
      case SignalSource.profile:
      case SignalSource.offers:
      case SignalSource.supportOrg:
        break; // no specific format mapping
    }
  }

  /// Update the BOROUGH-SCOPED counters for a signal.
  void _updateBoroughCounters(
    BoroughEngagementStats stats,
    SignalSource source,
    String action,
  ) {
    switch (source) {
      case SignalSource.group:
        if (action == 'join') stats.groupsJoined++;
        break;
      case SignalSource.meetup:
        if (action == 'rsvp') stats.meetupsAttended++;
        if (action == 'created') stats.meetupsCreated++;
        break;
      case SignalSource.chat:
        if (action == 'group_message') stats.chatMessagesSent++;
        if (action == 'dm_sent') stats.dmConversations++;
        break;
      case SignalSource.marketplace:
        if (action == 'listing_created') stats.marketplaceListings++;
        if (action == 'item_viewed') stats.marketplaceViews++;
        if (action == 'item_bought') stats.marketplaceItemsBought++;
        break;
      case SignalSource.matchmaker:
        if (action == 'match_accepted') stats.matchesAccepted++;
        if (action == 'match_dismissed') stats.matchesDismissed++;
        break;
      default:
        break;
    }
  }

  /// Update GLOBAL event preferences (UK-wide, not borough-scoped).
  void _updateEventPreferences(
    String action,
    Map<String, dynamic> data,
    String? eventBorough,
  ) {
    final prefs = _profile.eventPreferences;
    if (action == 'rsvp') prefs.eventsRsvpd++;
    if (action == 'view') prefs.eventsViewed++;

    final category = data['category'] as String?;
    if (category != null) {
      prefs.eventCategoryCount[category] =
          (prefs.eventCategoryCount[category] ?? 0) + 1;
    }
    if (eventBorough != null) {
      prefs.eventBoroughCount[eventBorough] =
          (prefs.eventBoroughCount[eventBorough] ?? 0) + 1;
    }
    prefs.recomputePreferred();
  }

  /// Update global counters (copilot, feed, articles, profile — not borough-partitioned).
  void _updateGlobalCounters(SignalSource source, String action) {
    switch (source) {
      case SignalSource.copilot:
        _profile.copilotQueries++;
        if (action == 'query') _profile.copilotConversations++;
        break;
      case SignalSource.feed:
        if (action == 'nudge_tapped') _profile.feedNudgesTapped++;
        if (action == 'nudge_dismissed') _profile.feedNudgesDismissed++;
        break;
      case SignalSource.knowledgeBase:
        _profile.articlesRead++;
        break;
      case SignalSource.profile:
        _profile.profileUpdates++;
        break;
      default:
        break; // Borough-scoped counters handled in _updateBoroughCounters
    }
  }

  void _updateMeetupPreferences(
      String category, bool isIndoor, bool isFree) {
    // Track meetup type frequency from signals in CURRENT BOROUGH only
    final currentBorough = _profile.currentBorough;
    final catLower = category.toLowerCase();
    final typeCounts = <String, int>{};

    for (final s in _signalLog.where((s) =>
        s.source == SignalSource.meetup &&
        s.action == 'rsvp' &&
        s.borough == currentBorough)) {
      final cat = (s.data['category'] as String?)?.toLowerCase() ?? '';
      typeCounts[cat] = (typeCounts[cat] ?? 0) + 1;
    }
    typeCounts[catLower] = (typeCounts[catLower] ?? 0) + 1;

    if (typeCounts.isNotEmpty) {
      final sorted = typeCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _profile.preferredMeetupType = sorted.first.key;
    }

    // Update indoor/free preferences via running average (current borough)
    final boroughMeetups = _signalLog.where((s) =>
        s.source == SignalSource.meetup && s.borough == currentBorough);

    final indoorCount =
        boroughMeetups.where((s) => s.data['isIndoor'] == true).length;
    final totalMeetups = boroughMeetups.length + 1;
    _profile.prefersIndoor = indoorCount > totalMeetups / 2;

    final freeCount =
        boroughMeetups.where((s) => s.data['isFree'] == true).length;
    _profile.prefersFree = freeCount > totalMeetups / 2;

    // Update preferred meetup time (current borough)
    final meetupHours = boroughMeetups.map((s) => s.timestamp.hour).toList();
    if (meetupHours.isNotEmpty) {
      final avgHour =
          meetupHours.reduce((a, b) => a + b) / meetupHours.length;
      if (avgHour < 12) {
        _profile.preferredMeetupTime = 'morning';
      } else if (avgHour < 17) {
        _profile.preferredMeetupTime = 'afternoon';
      } else {
        _profile.preferredMeetupTime = 'evening';
      }
    }
  }

  void _updateEngagement(DateTime now) {
    // Simple engagement score: signals per day over last 7 days
    final weekAgo = now.subtract(const Duration(days: 7));
    final recentCount =
        _signalLog.where((s) => s.timestamp.isAfter(weekAgo)).length;
    // Normalise: expect ~5 signals/day for "highly active" => 35/week
    _profile.dailyEngagementScore =
        (recentCount / 35.0).clamp(0.0, 1.0);

    // Consecutive active days
    if (_profile.lastActiveAt != null) {
      final daysSince = now.difference(_profile.lastActiveAt!).inDays;
      if (daysSince <= 1) {
        _profile.consecutiveActiveDays++;
      } else if (daysSince > 1) {
        _profile.consecutiveActiveDays = 1;
      }
    } else {
      _profile.consecutiveActiveDays = 1;
    }
  }

  void _updateEngagementTrend() {
    // Compare this week vs last week
    final now = DateTime.now();
    final thisWeek = now.subtract(const Duration(days: 7));
    final lastWeek = now.subtract(const Duration(days: 14));

    final thisWeekCount =
        _signalLog.where((s) => s.timestamp.isAfter(thisWeek)).length;
    final lastWeekCount = _signalLog
        .where((s) =>
            s.timestamp.isAfter(lastWeek) &&
            s.timestamp.isBefore(thisWeek))
        .length;

    if (lastWeekCount == 0) {
      _profile.weeklyEngagementTrend = thisWeekCount > 0 ? 1.0 : 0.0;
    } else {
      final change = (thisWeekCount - lastWeekCount) / lastWeekCount;
      _profile.weeklyEngagementTrend = change.clamp(-1.0, 1.0);
    }
  }

  void _recomputeInferredInterests() {
    final topTopics = _profile.topTopics(10);
    _profile.inferredInterests = topTopics
        .where((t) => t.score > 0.05)
        .map((t) => t.topic)
        .toList();
  }

  // ── TOPIC EXTRACTION ───────────────────────────────────────────────────

  List<String> _extractTopics(String text) {
    final lower = text.toLowerCase();
    final topics = <String>[];

    const keywords = {
      'sleep': 'sleep',
      'nap': 'sleep',
      'bedtime': 'sleep',
      'wean': 'weaning',
      'food': 'feeding',
      'feed': 'feeding',
      'formula': 'feeding',
      'breastfeed': 'breastfeeding',
      'nursery': 'nurseries',
      'nurseries': 'nurseries',
      'childcare': 'childcare',
      'school': 'education',
      'milestone': 'development',
      'development': 'development',
      'crawl': 'development',
      'walking': 'development',
      'talk': 'development',
      'teething': 'teething',
      'vaccine': 'vaccination',
      'vaccination': 'vaccination',
      'jab': 'vaccination',
      'rash': 'health',
      'fever': 'health',
      'ill': 'health',
      'sick': 'health',
      'doctor': 'health',
      'gp': 'health',
      'nhs': 'health',
      'mental health': 'mental_health',
      'anxiety': 'mental_health',
      'lonely': 'mental_health',
      'depression': 'mental_health',
      'postnatal': 'postnatal',
      'sell': 'marketplace',
      'buy': 'marketplace',
      'preloved': 'marketplace',
      'market': 'marketplace',
      'meetup': 'meetups',
      'meet': 'social',
      'friend': 'social',
      'coffee': 'coffee_mornings',
      'walk': 'walks',
      'park': 'parks',
      'swim': 'swimming',
      'music': 'music_classes',
      'playdate': 'playdates',
      'soft play': 'soft_play',
      'travel': 'travel',
      'holiday': 'travel',
      'yoga': 'fitness',
      'exercise': 'fitness',
      'buggy': 'buggies',
      'pram': 'buggies',
      'nappy': 'nappies',
      'potty': 'potty_training',
      'tantrum': 'tantrums',
      'dad': 'dad_specific',
    };

    for (final entry in keywords.entries) {
      if (lower.contains(entry.key) && !topics.contains(entry.value)) {
        topics.add(entry.value);
      }
    }

    return topics;
  }

  // ── PERSISTENCE ────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    try {
      final json = await BrowserStorage.getString(_profileKey);
      if (json != null) {
        _profile = UserLearningProfile.fromJson(jsonDecode(json));
        _log('Profile loaded (${_profile.totalSignals} signals, '
            'borough: ${_profile.currentBorough}, '
            'borough maturity: ${_profile.currentBoroughMaturity.name})');
      }
    } catch (e) {
      _log('Failed to load profile: $e');
      _profile = UserLearningProfile();
    }
  }

  Future<void> _loadSignalLog() async {
    try {
      final json = await BrowserStorage.getString(_signalLogKey);
      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        _signalLog = list
            .map((s) => UserSignal.fromJson(s as Map<String, dynamic>))
            .toList();
        _log('Signal log loaded (${_signalLog.length} signals)');
      }
    } catch (e) {
      _log('Failed to load signal log: $e');
      _signalLog = [];
    }
  }

  Future<void> _persist() async {
    try {
      await BrowserStorage.setString(
          _profileKey, jsonEncode(_profile.toJson()));
      await BrowserStorage.setString(
        _signalLogKey,
        jsonEncode(_signalLog.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      _log('Persist error: $e');
    }
  }

  /// Force-clear all learning data (for testing / user request)
  Future<void> resetAllData() async {
    _profile = UserLearningProfile();
    _signalLog = [];
    await BrowserStorage.remove(_profileKey);
    await BrowserStorage.remove(_signalLogKey);
    _syncFromOnboarding();
    _log('All learning data reset');
  }

  // ── DEBUG ──────────────────────────────────────────────────────────────

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('LearningEngine: $message');
    }
  }

  /// Print a debug summary of the current learning profile
  void printDebugSummary() {
    if (kDebugMode) {
      debugPrint('=== Learning Engine Summary (Hyperlocal) ===');
      debugPrint('Borough: ${_profile.currentBorough}');
      debugPrint(
          'Borough maturity: ${_profile.currentBoroughMaturity.name} '
          '(${_profile.currentBoroughStats.totalBoroughSignals} signals)');
      if (kDebugMode) {
        debugPrint(
        'Global maturity: ${_profile.globalMaturity.name} '
        '(${_profile.totalSignals} signals)');
      }
      debugPrint(
          'Engagement: ${_profile.engagementLevel} '
          '(${_profile.dailyEngagementScore.toStringAsFixed(2)})');
      if (kDebugMode) {
        debugPrint(
        'Trend: ${_profile.weeklyEngagementTrend > 0 ? "+" : ""}'
        '${_profile.weeklyEngagementTrend.toStringAsFixed(2)}');
      }
      if (kDebugMode) debugPrint('Peak: ${_profile.peakPeriod} (hour ${_profile.peakHour})');
      if (kDebugMode) debugPrint(
          'Top topics: ${_profile.inferredInterests.take(5).join(", ")}');
      if (kDebugMode) {
        debugPrint('Format: ${_profile.formatPreference.dominantFormat}');
      }
      if (kDebugMode) {
        debugPrint(
        'Meetup pref: ${_profile.preferredMeetupType ?? "none"} '
        '/ ${_profile.preferredMeetupTime ?? "any"}');
      }

      // Borough-scoped stats
      final bStats = _profile.currentBoroughStats;
      if (kDebugMode) debugPrint('--- Borough Stats (${_profile.currentBorough}) ---');
      if (kDebugMode) debugPrint(
          '  Groups: ${bStats.groupsJoined}, '
          'Meetups: ${bStats.meetupsAttended}, '
          'DMs: ${bStats.dmConversations}');
      if (kDebugMode) {
        debugPrint(
        '  Marketplace: ${bStats.marketplaceListings} listings, '
        '${bStats.marketplaceViews} views');
      }
      if (kDebugMode) {
        debugPrint(
        '  Matches: ${bStats.matchesAccepted} accepted, '
        '${bStats.matchesDismissed} dismissed');
      }

      // Global event stats
      if (kDebugMode) {
        debugPrint('--- Events (UK-wide) ---');
      }
      if (kDebugMode) debugPrint(
          '  RSVP\'d: ${_profile.eventPreferences.eventsRsvpd}, '
          'Viewed: ${_profile.eventPreferences.eventsViewed}');
      if (kDebugMode) {
        debugPrint(
        '  Categories: ${_profile.eventPreferences.preferredCategories.join(", ")}');
      }
      if (kDebugMode) debugPrint(
          '  Explored boroughs: ${_profile.eventPreferences.exploredBoroughs.take(5).join(", ")}');

      // All borough stats
      if (_profile.boroughStats.length > 1) {
        if (kDebugMode) {
          debugPrint('--- All Borough History ---');
        }
        for (final entry in _profile.boroughStats.entries) {
          if (kDebugMode) debugPrint(
              '  ${entry.key}: ${entry.value.totalBoroughSignals} signals '
              '(${entry.value.maturity.name})');
        }
      }

      if (kDebugMode) debugPrint('Copilot queries: ${_profile.copilotQueries}');
      if (_profile.previousBorough != null) {
        if (kDebugMode) debugPrint(
            'Previous borough: ${_profile.previousBorough} '
            '(changed ${_profile.boroughChangedAt})');
      }
      if (kDebugMode) {
        debugPrint('================================================');
      }
    }
  }
}
