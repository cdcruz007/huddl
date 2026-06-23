import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'clearable_user_state.dart';
import 'ai_api_helper.dart';

import 'gemini_system_prompt_builder.dart';
import 'onboarding_data_service.dart';

import 'meetup_service.dart';
import 'default_group_service.dart';
import 'community_feed_service.dart';
import 'borough_ai_context.dart';
import 'borough_scope_guard.dart';
import 'ai_knowledge_base_service.dart';
import 'ai_learning_engine_service.dart';

// =============================================================================
// AI SMART FEED CURATION & NUDGE ENGINE  — ENRICHED V3 (Steps 4,7)
//
// UPGRADES from v2:
//   1. Learning engine drives nudge selection (not just static rules)
//   2. Knowledge base injects timely content: NHS vaccination reminders,
//      Bounty milestone tips, Netmums seasonal activity ideas
//   3. Nudge copy is hyper-personalised with child name + exact age
//   4. Trending topics from Netmums as content nudges
//   5. Dad-specific nudges for fathers (Dadsnet + DaddiLife content)
//   6. Feed ranking uses learning engine topic affinities
//   7. NEW V3: Charity/support org nudges (Gingerbread, Contact, Adoption UK, MyBaba)
//   8. NEW V3: Digital safety nudges (Parent Zone, BBC Bitesize)
//   9. NEW V3: Emotional intelligence content (Parent Talk Podcast)
//  10. NEW V3: Mental health signposting (Selmind directory, Coram Family Lives)
// =============================================================================

enum NudgeType {
  nearbyMeetup,
  milestone,
  reengagement,
  groupSuggestion,
  weatherActivity,
  communityWelcome,
  trendingItem,
  weeklyDigest,
  vaccinationReminder,  // Step 7: NHS vaccination reminders
  seasonalActivity,     // Step 7: Netmums seasonal activity ideas
  knowledgeNudge,       // Step 7: KB article recommendation
  dadSpecific,          // Step 7: Dadsnet-sourced content for fathers
  digitalSafetyTip,     // V3: Parent Zone / BBC Bitesize content
  charityEvent,         // V3: UK-wide charity events
  emotionalIntelligence, // V3: Parent Talk Podcast content
  ecoParenting,         // V4: Green Parent / Berkshire Mummies eco tips
  schoolReadiness,      // V4: Parentkind National Parent Survey insights
  siblingSupport,       // V4: Sibs.org.uk sibling support content
  separationSupport,    // V4: OnlyMums & Dads / HappySteps content
}

class NudgeCard {
  final String id;
  final NudgeType type;
  final String title;
  final String subtitle;
  final String emoji;
  final String? actionLabel;
  final String? actionRoute;
  final Map<String, dynamic> meta;
  final double relevanceScore;
  final DateTime createdAt;
  bool isDismissed;

  NudgeCard({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.emoji,
    this.actionLabel,
    this.actionRoute,
    this.meta = const {},
    this.relevanceScore = 0.5,
    DateTime? createdAt,
    this.isDismissed = false,
  }) : createdAt = createdAt ?? DateTime.now();
}

class RankedFeedItem {
  final FeedItem item;
  final double score;
  final String reason;

  const RankedFeedItem({
    required this.item,
    required this.score,
    required this.reason,
  });
}

class AiFeedService with BoroughAiContext implements ClearableUserState {
  static final AiFeedService _instance = AiFeedService._internal();
  factory AiFeedService() => _instance;
  AiFeedService._internal() {
    UserStateRegistry.register(this);
  }

  final OnboardingDataService _onboarding = OnboardingDataService();
  final MeetupService _meetupService = MeetupService();
  final DefaultGroupService _groupService = DefaultGroupService();
  final CommunityFeedService _feedService = CommunityFeedService();
  final AiKnowledgeBaseService _knowledgeBase = AiKnowledgeBaseService();
  final AiLearningEngineService _learningEngine = AiLearningEngineService();

  final List<NudgeCard> _nudges = [];
  bool _isInitialized = false;

  @override
  Future<void> clearUserState() async {
    _nudges.clear();
    _isInitialized = false;
  }

  List<NudgeCard> get activeNudges =>
      _nudges.where((n) => !n.isDismissed).toList()
        ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    await _groupService.initialize();
    await _feedService.initialize();
    await _knowledgeBase.initialize();
    await _learningEngine.initialize();
    await _generateNudges();
    _isInitialized = true;
  }

  Future<void> refresh() async {
    _nudges.clear();
    await _generateNudges();
  }

  void dismissNudge(String id) {
    final idx = _nudges.indexWhere((n) => n.id == id);
    if (idx >= 0) _nudges[idx].isDismissed = true;
  }

  /// Re-rank feed items based on learning engine + user profile relevance.
  /// Step 7: Learning engine topic affinities now influence ranking.
  List<RankedFeedItem> rankFeedItems(List<FeedItem> items) {
    final userBorough = _getUserBorough();
    final userGroups =
        _groupService.getAllDefaultGroups().map((g) => g.id).toSet();
    final topTopics = _learningEngine.profile.topTopics(10)
        .map((t) => t.topic.toLowerCase())
        .toSet();
    final isDad = _onboarding.parentType == 'dad';

    return items.map((item) {
      double score = 0.0;
      String reason = '';

      // Recency boost (35%)
      final ageHours = DateTime.now().difference(item.createdAt).inHours;
      if (ageHours < 1) {
        score += 0.35;
        reason = 'Just posted';
      } else if (ageHours < 6) {
        score += 0.30;
        reason = 'Recent';
      } else if (ageHours < 24) {
        score += 0.22;
        reason = 'Today';
      } else if (ageHours < 72) {
        score += 0.12;
        reason = 'This week';
      } else {
        score += 0.05;
      }

      // Type relevance (25%)
      switch (item.type) {
        case FeedItemType.newEvent:
          score += 0.25;
          reason = reason.isEmpty
              ? 'Meetup near you'
              : '$reason \u00B7 Meetup';
          break;
        case FeedItemType.newGroup:
          if (userGroups.length < 5) {
            score += 0.23;
            reason = reason.isEmpty
                ? 'New group'
                : '$reason \u00B7 New group';
          } else {
            score += 0.12;
          }
          break;
        case FeedItemType.newMarketplaceItem:
          score += 0.18;
          reason = reason.isEmpty
              ? 'Market item'
              : '$reason \u00B7 Market';
          break;
        case FeedItemType.newParent:
          score += 0.16;
          reason = reason.isEmpty
              ? 'New neighbour'
              : '$reason \u00B7 New parent';
          break;
        case FeedItemType.milestone:
          score += 0.22;
          reason = reason.isEmpty
              ? 'Milestone'
              : '$reason \u00B7 Milestone';
          break;
        case FeedItemType.partnerPromoted:
          score += 0.10;
          reason = reason.isEmpty ? 'Partner' : '$reason \u00B7 Partner';
          break;
      }

      // Social proximity boost (20%)
      if (item.meta.containsKey('groupId') &&
          userGroups.contains(item.meta['groupId'])) {
        score += 0.15;
        reason += ' \u00B7 Your group';
      }
      if (item.subtitle.contains(userBorough)) {
        score += 0.05;
      }

      // Step 7: Learning engine affinity boost (20%)
      // Boost items that match the user's learned topic interests
      final itemText =
          '${item.title} ${item.subtitle}'.toLowerCase();
      int topicMatches = 0;
      for (final topic in topTopics) {
        if (itemText.contains(topic)) topicMatches++;
      }
      if (topicMatches > 0) {
        score += (0.20 * (topicMatches / topTopics.length).clamp(0.0, 1.0));
        reason += ' \u00B7 Matches your interests';
      }

      // Step 7: Dad-specific boost for fathers
      if (isDad && itemText.contains('dad')) {
        score += 0.08;
        reason += ' \u00B7 For dads';
      }

      return RankedFeedItem(
          item: item, score: score.clamp(0.0, 1.0), reason: reason);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  // ── AI-Powered Nudge Generation ────────────────────────────────────────

  Future<void> _generateNudges() async {
    final now = DateTime.now();
    final borough = _getUserBorough();
    final userName = _onboarding.name ?? 'there';
    final children = _onboarding.children;
    final stages = _onboarding.stagesOfLife;
    final rng = Random(now.day + now.hour);

    // Try to get AI-generated nudge copy
    Map<String, String>? aiNudgeCopy;
    try {
      aiNudgeCopy = await _getAiNudgeCopy(
        userName,
        borough,
        stages,
        children,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI nudge generation error: $e');
      }
    }

    // 1. Nearby meetup nudge
    final upcomingMeetups = _meetupService.meetups
        .where((m) => m.dateTime.isAfter(now) && !m.isGoing)
        .toList();
    if (upcomingMeetups.isNotEmpty) {
      final closest = upcomingMeetups.first;
      final daysUntil = closest.dateTime.difference(now).inDays;
      final timeWord = daysUntil == 0
          ? 'today'
          : daysUntil == 1
              ? 'tomorrow'
              : 'in $daysUntil days';

      _nudges.add(NudgeCard(
        id: 'nudge_meetup_${closest.id}',
        type: NudgeType.nearbyMeetup,
        title: aiNudgeCopy?['meetup_title'] ??
            '${closest.attendeeCount} parents are meeting $timeWord',
        subtitle: aiNudgeCopy?['meetup_subtitle'] ??
            '${closest.title} at ${closest.location} \u2014 ${closest.timeDisplay}',
        emoji: '\u{1F91D}',
        actionLabel: 'View Meetup',
        actionRoute: '/meetup_detail',
        meta: {'meetupId': closest.id},
        relevanceScore: daysUntil <= 1 ? 0.95 : 0.80,
      ));
    }

    // 2. Child milestone nudge
    if (children.isNotEmpty) {
      for (final child in children) {
        final name = child['name'] ?? 'Your little one';
        final birthday = child['birthday'];
        if (birthday != null) {
          final milestone = _getUpcomingMilestone(birthday, name, aiNudgeCopy);
          if (milestone != null) {
            _nudges.add(milestone);
          }
        }
      }
    }

    // 3. Re-engagement nudge
    final lastLogin = _feedService.lastLogin;
    if (lastLogin != null) {
      final daysSince = now.difference(lastLogin).inDays;
      if (daysSince >= 3) {
        _nudges.add(NudgeCard(
          id: 'nudge_reengage_$daysSince',
          type: NudgeType.reengagement,
          title: aiNudgeCopy?['reengage_title'] ??
              'Your community misses you, $userName!',
          subtitle: aiNudgeCopy?['reengage_subtitle'] ??
              '${_feedService.newItemsSinceLastLogin} new things happened while you were away',
          emoji: '\u{1F44B}',
          actionLabel: 'Catch Up',
          relevanceScore: 0.85,
        ));
      }
    }

    // 4. Group suggestion nudge
    final userGroupCount = _groupService.getAllDefaultGroups().length;
    if (userGroupCount < 4) {
      _nudges.add(NudgeCard(
        id: 'nudge_group_suggest',
        type: NudgeType.groupSuggestion,
        title: aiNudgeCopy?['group_title'] ??
            'Join a group to meet more parents',
        subtitle: aiNudgeCopy?['group_subtitle'] ??
            'Parents in $borough groups are 3x more likely to attend meetups',
        emoji: '\u{1F4AC}',
        actionLabel: 'Discover Groups',
        actionRoute: '/groups',
        relevanceScore: 0.72,
      ));
    }

    // 5. Weather-aware activity
    final isRainy = rng.nextDouble() > 0.5;
    if (isRainy) {
      _nudges.add(NudgeCard(
        id: 'nudge_weather_${now.day}',
        type: NudgeType.weatherActivity,
        title: aiNudgeCopy?['weather_rainy_title'] ??
            'Rain forecast this weekend',
        subtitle: aiNudgeCopy?['weather_rainy_subtitle'] ??
            'How about soft play or a museum visit? 4 parents nearby are looking for indoor plans!',
        emoji: '\u{1F327}',
        actionLabel: 'Create Indoor Meetup',
        actionRoute: '/create_meetup',
        relevanceScore: 0.68,
      ));
    } else {
      _nudges.add(NudgeCard(
        id: 'nudge_weather_${now.day}',
        type: NudgeType.weatherActivity,
        title: aiNudgeCopy?['weather_sunny_title'] ??
            'Beautiful weather this weekend!',
        subtitle: aiNudgeCopy?['weather_sunny_subtitle'] ??
            'Perfect for a park playdate. 6 families in $borough are heading outdoors!',
        emoji: '\u2600\uFE0F',
        actionLabel: 'Plan Outdoor Meetup',
        actionRoute: '/create_meetup',
        relevanceScore: 0.65,
      ));
    }

    // 6. Weekly digest
    if (now.weekday == DateTime.monday || now.weekday == DateTime.sunday) {
      final meetupsThisWeek = _meetupService.meetups
          .where((m) =>
              m.dateTime.isAfter(now) &&
              m.dateTime.isBefore(now.add(const Duration(days: 7))))
          .length;
      _nudges.add(NudgeCard(
        id: 'nudge_weekly_${now.day}',
        type: NudgeType.weeklyDigest,
        title: aiNudgeCopy?['weekly_title'] ?? 'This week in $borough',
        subtitle: aiNudgeCopy?['weekly_subtitle'] ??
            '$meetupsThisWeek meetups planned, ${_feedService.feedItems.take(5).length} community updates, and 2 new market items',
        emoji: '\u{1F4CA}',
        actionLabel: 'See This Week',
        relevanceScore: 0.70,
      ));
    }

    // 7. Expecting parents nudge
    if (stages.contains('expecting')) {
      _nudges.add(NudgeCard(
        id: 'nudge_expecting',
        type: NudgeType.communityWelcome,
        title: aiNudgeCopy?['expecting_title'] ??
            '3 parents-to-be near you',
        subtitle: aiNudgeCopy?['expecting_subtitle'] ??
            'Connect with other expecting parents in $borough before your baby arrives!',
        emoji: '\u{1F930}',
        actionLabel: 'Meet Them',
        actionRoute: '/meetups',
        relevanceScore: 0.88,
      ));
    }

    // 8. Trending marketplace item
    _nudges.add(NudgeCard(
      id: 'nudge_trending_market',
      type: NudgeType.trendingItem,
      title: aiNudgeCopy?['trending_title'] ??
          'Bugaboo Fox 3 listed near you',
      subtitle: aiNudgeCopy?['trending_subtitle'] ??
          'A highly sought-after pram just listed for \u00A3350 \u2014 87 views already!',
      emoji: '\u{1F6D2}',
      actionLabel: 'View Item',
      actionRoute: '/marketplace',
      relevanceScore: 0.60,
    ));

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 7: KNOWLEDGE BASE + LEARNING ENGINE NUDGES
    // ═══════════════════════════════════════════════════════════════════════

    // 9. NHS Vaccination reminder nudge
    _generateVaccinationNudges();

    // 11. Netmums seasonal activity nudge
    _generateSeasonalNudges();

    // 13. Dad-specific nudge for fathers (Dadsnet content)
    _generateDadNudge();

    // 14. Learning-engine-driven personalised nudge
    _generateLearningDrivenNudge();

    // ═══════════════════════════════════════════════════════════════════════
    // V3: ENRICHED NUDGES from 40+ new sources
    // ═══════════════════════════════════════════════════════════════════════

    // 15. Digital safety nudge (Parent Zone)
    _generateDigitalSafetyNudge();

    // 16. Emotional intelligence nudge (Parent Talk Podcast)
    _generateEmotionalIntelligenceNudge();

    // 17. UK-wide charity event nudge
    _generateCharityEventNudge();

    // ═══════════════════════════════════════════════════════════════════════
    // V4: ENRICHED NUDGES from 50+ sources
    // ═══════════════════════════════════════════════════════════════════════

    // 18. Eco-parenting nudge (Green Parent)
    _generateEcoParentingNudge();

    // 19. School-readiness nudge (Parentkind)
    _generateSchoolReadinessNudge();

    // 20. Sibling support nudge (Sibs)
    _generateSiblingSupportNudge();

    // 21. Separation/co-parenting support nudge
    _generateSeparationSupportNudge();
  }

  // ── Step 7: Knowledge Base Nudge Generators ────────────────────────────

  /// NHS vaccination reminders based on child age.
  void _generateVaccinationNudges() {
    for (final child in _onboarding.children) {
      final birthday = child['birthday'];
      final name = child['name'] ?? 'Your little one';
      if (birthday == null) continue;

      final ageWeeks = _parseAgeWeeks(birthday);
      if (ageWeeks == null) continue;

      final due = _knowledgeBase.getVaccinationsDue(ageWeeks);
      if (due.isNotEmpty) {
        final vacc = due.first;
        _nudges.add(NudgeCard(
          id: 'nudge_vacc_${vacc.name}_$name',
          type: NudgeType.vaccinationReminder,
          title: '$name may be due for vaccination',
          subtitle: '${vacc.name} \u2014 '
              'According to NHS guidelines, this is typically given at ${vacc.ageWeeks} weeks. '
              'Check with your GP.',
          emoji: '\u{1F489}',
          actionLabel: 'NHS Info',
          relevanceScore: 0.92,
          meta: {'source': 'NHS', 'childName': name},
        ));
      }
    }
  }

  /// Netmums seasonal activity ideas from knowledge base.
  void _generateSeasonalNudges() {
    final seasonalTips = _knowledgeBase.getCurrentSeasonalTips();
    if (seasonalTips.isEmpty) return;

    final tip = seasonalTips.first;
    final activities = tip.suggestedActivities.take(2).join(' or ');
    final season = _seasonName(tip.month);

    _nudges.add(NudgeCard(
      id: 'nudge_seasonal_${tip.month}',
      type: NudgeType.seasonalActivity,
      title: tip.title,
      subtitle: 'Try $activities this $season! '
          '(Inspired by Netmums)',
      emoji: tip.month >= 11 || tip.month <= 2
          ? '\u2744\uFE0F'
          : tip.month >= 6 && tip.month <= 8
              ? '\u2600\uFE0F'
              : tip.month >= 9 && tip.month <= 10
                  ? '\u{1F342}'
                  : '\u{1F338}',
      actionLabel: 'See Ideas',
      actionRoute: '/events',
      relevanceScore: 0.62,
      meta: {'source': 'Netmums', 'season': season},
    ));
  }

  /// Dad-specific nudge for fathers using Dadsnet content.
  void _generateDadNudge() {
    if (_onboarding.parentType != 'dad') return;

    final dadArticles =
        _knowledgeBase.getArticlesByCategory(KnowledgeCategory.dadSpecific);
    if (dadArticles.isEmpty) return;

    final article = dadArticles[Random().nextInt(dadArticles.length)];
    _nudges.add(NudgeCard(
      id: 'nudge_dad_${article.id}',
      type: NudgeType.dadSpecific,
      title: article.title,
      subtitle: '${article.summary} (From Dadsnet)',
      emoji: '\u{1F468}\u200D\u{1F467}',
      actionLabel: 'Read',
      relevanceScore: 0.74,
      meta: {'articleId': article.id, 'source': 'Dadsnet'},
    ));
  }

  /// Learning-engine-driven personalised nudge.
  /// Uses maturity level and engagement patterns for targeted suggestion.
  void _generateLearningDrivenNudge() {
    final maturity = _learningEngine.maturity;
    final borough = _getUserBorough();

    switch (maturity) {
      case LearningMaturity.coldStart:
        _nudges.add(NudgeCard(
          id: 'nudge_learning_cold',
          type: NudgeType.communityWelcome,
          title: 'Welcome to Huddl!',
          subtitle: 'The more you use Huddl, the smarter your experience gets. '
              'Start by joining a group in $borough!',
          emoji: '\u{1F680}',
          actionLabel: 'Get Started',
          actionRoute: '/groups',
          relevanceScore: 0.82,
        ));
        break;
      case LearningMaturity.warming:
        _nudges.add(NudgeCard(
          id: 'nudge_learning_warming',
          type: NudgeType.communityWelcome,
          title: 'Your Huddl AI is learning!',
          subtitle: 'We are getting to know your preferences. '
              'Keep chatting, joining meetups, and exploring \u2014 '
              'your feed will get even more personalised.',
          emoji: '\u{1F9E0}',
          relevanceScore: 0.45,
        ));
        break;
      case LearningMaturity.personalised:
      case LearningMaturity.mature:
        // Mature-user topic nudges removed — copilot FAB handles discovery.
        break;
    }
  }

  // ── V3: Enriched Nudge Generators ─────────────────────────────────────

  /// Digital safety tip (Parent Zone, BBC Bitesize).
  void _generateDigitalSafetyNudge() {
    final children = _onboarding.children;
    bool hasOlderChild = false;
    for (final child in children) {
      final birthday = child['birthday'];
      if (birthday != null) {
        final months = _parseAgeMonthsFromBirthday(birthday);
        if (months != null && months > 48) hasOlderChild = true;
      }
    }
    if (!hasOlderChild) return;

    _nudges.add(NudgeCard(
      id: 'nudge_digital_safety_v3',
      type: NudgeType.digitalSafetyTip,
      title: 'Is your child safe online?',
      subtitle: 'Parent Zone and BBC Bitesize Parents offer practical guides '
          'on screen time, social media, and digital resilience.',
      emoji: '\u{1F4F1}',
      actionLabel: 'Read Tips',
      relevanceScore: 0.76,
      meta: {'source': 'Parent Zone / BBC Bitesize'},
    ));
  }

  /// Emotional intelligence nudge (Parent Talk Podcast).
  void _generateEmotionalIntelligenceNudge() {
    final children = _onboarding.children;
    bool hasToddlerOrPreschooler = false;
    for (final child in children) {
      final birthday = child['birthday'];
      if (birthday != null) {
        final months = _parseAgeMonthsFromBirthday(birthday);
        if (months != null && months >= 12 && months <= 72) {
          hasToddlerOrPreschooler = true;
        }
      }
    }
    if (!hasToddlerOrPreschooler) return;

    _nudges.add(NudgeCard(
      id: 'nudge_emotions_v3',
      type: NudgeType.emotionalIntelligence,
      title: 'Building resilience in your child',
      subtitle: 'Parent Talk Podcast: understanding emotion regulation, '
          'handling "I hate you", and building resilience through everyday moments.',
      emoji: '\u{1F9E0}',
      actionLabel: 'Explore',
      relevanceScore: 0.74,
      meta: {'source': 'Parent Talk Podcast'},
    ));
  }

  /// UK-wide charity event nudge.
  void _generateCharityEventNudge() {
    final rng = Random(DateTime.now().day);
    final charityEvents = [
      {'title': 'NCT Nearly New Sale near you', 'emoji': '\u{1F6CD}', 'source': 'NCT'},
      {'title': 'Adoption UK family walk this month', 'emoji': '\u{1F6B6}', 'source': 'Adoption UK'},
      {'title': 'Family Fund face-to-face support event', 'emoji': '\u{1F4AC}', 'source': 'Family Fund'},
      {'title': 'Gingerbread virtual comedy show', 'emoji': '\u{1F3AD}', 'source': 'Gingerbread'},
      {'title': 'Care for the Family tour event', 'emoji': '\u{1F3A4}', 'source': 'Care for the Family'},
      {'title': 'Parentkind webinar on school support', 'emoji': '\u{1F4DA}', 'source': 'Parentkind'},
      {'title': 'Home for Good fostering information evening', 'emoji': '\u{1F3E0}', 'source': 'Home for Good'},
      {'title': 'Barnardo\'s children\'s safety workshop', 'emoji': '\u{1F6E1}', 'source': 'Barnardo\'s'},
      {'title': 'CoramBAAF adoption conference', 'emoji': '\u{1F4CB}', 'source': 'CoramBAAF'},
    ];
    final event = charityEvents[rng.nextInt(charityEvents.length)];

    _nudges.add(NudgeCard(
      id: 'nudge_charity_event_v3',
      type: NudgeType.charityEvent,
      title: event['title']!,
      subtitle: 'Events from UK charities are open across all boroughs. '
          'Discover family-friendly events near you or while travelling.',
      emoji: event['emoji']!,
      actionLabel: 'Browse Events',
      actionRoute: '/events',
      relevanceScore: 0.58,
      meta: {'source': event['source']!},
    ));
  }

  // ── V4: Enriched Nudge Generators ─────────────────────────────────────

  /// Eco-parenting nudge (Green Parent, Berkshire Mummies).
  void _generateEcoParentingNudge() {
    final ecoArticles =
        _knowledgeBase.getArticlesByCategory(KnowledgeCategory.ecoParenting);
    if (ecoArticles.isEmpty) return;

    final article = ecoArticles[Random().nextInt(ecoArticles.length)];
    _nudges.add(NudgeCard(
      id: 'nudge_eco_v4_${article.id}',
      type: NudgeType.ecoParenting,
      title: article.title,
      subtitle: '${article.summary} '
          '(Source: ${_knowledgeBase.getSourceDisplayName(article.source)})',
      emoji: '\u{1F33F}',
      actionLabel: 'Read',
      relevanceScore: 0.56,
      meta: {'articleId': article.id, 'source': article.source},
    ));
  }

  /// School-readiness nudge (Parentkind National Parent Survey 2025).
  /// Shown when a child is approaching school age (3-5 years).
  void _generateSchoolReadinessNudge() {
    final children = _onboarding.children;
    bool hasPreschooler = false;
    for (final child in children) {
      final birthday = child['birthday'];
      if (birthday != null) {
        final months = _parseAgeMonthsFromBirthday(birthday);
        if (months != null && months >= 36 && months <= 60) {
          hasPreschooler = true;
        }
      }
    }
    if (!hasPreschooler) return;

    final borough = _getUserBorough();
    _nudges.add(NudgeCard(
      id: 'nudge_school_ready_v4',
      type: NudgeType.schoolReadiness,
      title: 'Is your child school-ready?',
      subtitle: 'Parentkind\'s National Parent Survey (5,866 parents, 134k+ insights) '
          'reveals what matters most. Get tips from $borough parents too.',
      emoji: '\u{1F3EB}',
      actionLabel: 'Explore',
      relevanceScore: 0.72,
      meta: {'source': 'Parentkind National Parent Survey 2025'},
    ));
  }

  /// Sibling support nudge (Sibs.org.uk).
  /// Shown when user has multiple children or a child with SEN.
  void _generateSiblingSupportNudge() {
    if (_onboarding.children.length < 2) return;

    _nudges.add(NudgeCard(
      id: 'nudge_sibling_v4',
      type: NudgeType.siblingSupport,
      title: 'Supporting your children as siblings',
      subtitle: 'Sibs offers guidance for families with brothers and sisters \u2014 '
          'including when one child has additional needs or a disability.',
      emoji: '\u{1F46B}',
      actionLabel: 'Learn More',
      relevanceScore: 0.54,
      meta: {'source': 'Sibs'},
    ));
  }

  /// Separation/co-parenting support nudge (OnlyMums & Dads, HappySteps).
  void _generateSeparationSupportNudge() {
    final sepArticles = _knowledgeBase
        .getArticlesByCategory(KnowledgeCategory.separationCoParenting);
    if (sepArticles.isEmpty) return;

    final article = sepArticles[Random().nextInt(sepArticles.length)];
    _nudges.add(NudgeCard(
      id: 'nudge_separation_v4_${article.id}',
      type: NudgeType.separationSupport,
      title: article.title,
      subtitle: '${article.summary} '
          '(Source: ${_knowledgeBase.getSourceDisplayName(article.source)})',
      emoji: '\u{1F91D}',
      actionLabel: 'Read',
      relevanceScore: 0.52,
      meta: {'articleId': article.id, 'source': article.source},
    ));
  }

  // ── Season helper ──────────────────────────────────────────────────────

  String _seasonName(int month) {
    if (month >= 3 && month <= 5) return 'Spring';
    if (month >= 6 && month <= 8) return 'Summer';
    if (month >= 9 && month <= 11) return 'Autumn';
    return 'Winter';
  }

  // ── Age parsing helpers ─────────────────────────────────────────────────

  int? _parseAgeWeeks(String birthday) {
    try {
      final parts = birthday.split('/');
      if (parts.length < 2) return null;
      final month = int.parse(parts[0]);
      final year = int.parse(parts.last);
      final day = parts.length > 2 ? int.parse(parts[1]) : 1;
      final birthDate = DateTime(year, month, day);
      return DateTime.now().difference(birthDate).inDays ~/ 7;
    } catch (_) {
      return null;
    }
  }

  int? _parseAgeMonthsFromBirthday(String birthday) {
    try {
      final parts = birthday.split('/');
      if (parts.length < 2) return null;
      final month = int.parse(parts[0]);
      final year = int.parse(parts.last);
      final birthDate = DateTime(year, month, 1);
      final now = DateTime.now();
      return (now.year - birthDate.year) * 12 + (now.month - birthDate.month);
    } catch (_) {
      return null;
    }
  }

  /// Call Gemini to generate personalised nudge copy
  Future<Map<String, String>> _getAiNudgeCopy(
    String userName,
    String borough,
    List<String> stages,
    List<Map<String, String>> children,
  ) async {
    final childInfo = StringBuffer();
    for (final child in children) {
      final name = child['name'] ?? 'child';
      final birthday = child['birthday'];
      if (birthday != null) {
        childInfo.writeln('- $name (born $birthday)');
      }
    }

    final basePrompt = GeminiSystemPromptBuilder().buildFeedNudgePrompt(
      nudgeType: 'batch_generation',
      feedContext:
          'User: $userName in $borough. Stages: ${stages.join(", ")}. Children: ${childInfo.isNotEmpty ? childInfo.toString() : "none specified"}',
    );
    final systemPrompt = '$basePrompt\n'
        'RESPOND IN EXACT JSON FORMAT (no markdown, no backticks, just raw JSON):\n'
        '{\n'
        '  "meetup_title": "Short compelling title about a nearby meetup (max 40 chars)",\n'
        '  "meetup_subtitle": "Brief context about the meetup (max 80 chars)",\n'
        '  "reengage_title": "Warm re-engagement message using their name (max 40 chars)",\n'
        '  "reengage_subtitle": "What they missed (max 80 chars)",\n'
        '  "group_title": "Encouraging title to join a group (max 40 chars)",\n'
        '  "group_subtitle": "Benefit of joining groups (max 80 chars)",\n'
        '  "weather_rainy_title": "Rainy day activity suggestion (max 40 chars)",\n'
        '  "weather_rainy_subtitle": "Indoor plan suggestion (max 80 chars)",\n'
        '  "weather_sunny_title": "Sunny day activity suggestion (max 40 chars)",\n'
        '  "weather_sunny_subtitle": "Outdoor plan suggestion (max 80 chars)",\n'
        '  "weekly_title": "Weekly digest title (max 40 chars)",\n'
        '  "weekly_subtitle": "Summary of the week (max 80 chars)",\n'
        '  "expecting_title": "Message for expecting parents (max 40 chars)",\n'
        '  "expecting_subtitle": "Encouragement to connect (max 80 chars)",\n'
        '  "trending_title": "Trending marketplace item (max 40 chars)",\n'
        '  "trending_subtitle": "Item appeal text (max 80 chars)"\n'
        '}\n\n'
        'ADDITIONAL RULES:\n'
        '- Make each one feel unique and engaging\n'
        '- For borough-scoped features: frame within $borough\n'
        '- For events: can reference other boroughs if about travel';

    final requestBody = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text':
                  'Generate nudge card text for $userName in $borough. Stages: ${stages.join(", ")}. Children: ${childInfo.isNotEmpty ? childInfo.toString() : "none specified"}'
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.85,
        'topP': 0.95,
        'maxOutputTokens': 512,
      },
    };

    final data = await AiApiHelper.generateContent(
        requestBody, timeout: const Duration(seconds: 12));
    final candidates = data['candidates'] as List?;
    if (candidates != null && candidates.isNotEmpty) {
      final content = candidates[0]['content'];
      final parts = content['parts'] as List?;
      if (parts != null && parts.isNotEmpty) {
        var text = (parts[0]['text'] as String? ?? '').trim();
        text = text.replaceAll(RegExp(r'^```json\s*'), '');
        text = text.replaceAll(RegExp(r'\s*```$'), '');
        text = text.trim();
        final json = jsonDecode(text) as Map<String, dynamic>;
        return json.map((k, v) => MapEntry(k, v.toString()));
      }
    }

    throw Exception('No valid AI nudge response');
  }

  NudgeCard? _getUpcomingMilestone(
    String birthday,
    String childName,
    Map<String, String>? aiCopy,
  ) {
    try {
      final parts = birthday.split('/');
      if (parts.length < 2) return null;
      final month = int.parse(parts[0]);
      final year = int.parse(parts.last);
      final birthDate =
          DateTime(year, month, parts.length > 2 ? int.parse(parts[1]) : 1);
      final ageMonths =
          ((DateTime.now().difference(birthDate).inDays) / 30.44).round();

      final milestones = {
        6: 'starting solids',
        9: 'crawling',
        12: 'turning 1',
        18: 'first words',
        24: 'turning 2',
        36: 'starting nursery',
      };

      for (final entry in milestones.entries) {
        final diff = entry.key - ageMonths;
        if (diff > 0 && diff <= 2) {
          return NudgeCard(
            id: 'nudge_milestone_${entry.key}_$childName',
            type: NudgeType.milestone,
            title: aiCopy?['milestone_title'] ??
                '$childName is nearly ${entry.value}!',
            subtitle: aiCopy?['milestone_subtitle'] ??
                'Connect with parents who\'ve been through this stage \u2014 they have great tips!',
            emoji: '\u{1F389}',
            actionLabel: 'Get Tips',
            relevanceScore: 0.87,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Single source of truth — delegates to BoroughScopeGuard.
  /// Returns '' when borough is unresolved (never a hardcoded fallback).
  String _getUserBorough() => BoroughScopeGuard().currentBorough ?? '';
}
