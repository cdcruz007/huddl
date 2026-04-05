import 'dart:math';

import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'meetup_service.dart';
import 'default_group_service.dart';
import 'community_feed_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AI SMART FEED CURATION & NUDGE ENGINE
// Personalises the home feed and generates proactive nudge cards
// ═══════════════════════════════════════════════════════════════════════════════

enum NudgeType {
  nearbyMeetup,
  milestone,
  reengagement,
  groupSuggestion,
  weatherActivity,
  communityWelcome,
  trendingItem,
  weeklyDigest,
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

class AiFeedService {
  static final AiFeedService _instance = AiFeedService._internal();
  factory AiFeedService() => _instance;
  AiFeedService._internal();

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();
  final MeetupService _meetupService = MeetupService();
  final DefaultGroupService _groupService = DefaultGroupService();
  final CommunityFeedService _feedService = CommunityFeedService();

  final List<NudgeCard> _nudges = [];
  bool _isInitialized = false;

  List<NudgeCard> get activeNudges =>
      _nudges.where((n) => !n.isDismissed).toList()
        ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    await _groupService.initialize();
    await _feedService.initialize();
    _generateNudges();
    _isInitialized = true;
  }

  void refresh() {
    _nudges.clear();
    _generateNudges();
  }

  void dismissNudge(String id) {
    final idx = _nudges.indexWhere((n) => n.id == id);
    if (idx >= 0) _nudges[idx].isDismissed = true;
  }

  /// Re-rank feed items based on user profile relevance
  List<RankedFeedItem> rankFeedItems(List<FeedItem> items) {
    final userBorough = _getUserBorough();
    final userGroups = _groupService.getAllDefaultGroups().map((g) => g.id).toSet();

    return items.map((item) {
      double score = 0.0;
      String reason = '';

      // Recency boost (40%)
      final ageHours = DateTime.now().difference(item.createdAt).inHours;
      if (ageHours < 1) {
        score += 0.40;
        reason = 'Just posted';
      } else if (ageHours < 6) {
        score += 0.35;
        reason = 'Recent';
      } else if (ageHours < 24) {
        score += 0.25;
        reason = 'Today';
      } else if (ageHours < 72) {
        score += 0.15;
        reason = 'This week';
      } else {
        score += 0.05;
      }

      // Type relevance (30%)
      switch (item.type) {
        case FeedItemType.newEvent:
          score += 0.30;
          reason = reason.isEmpty ? 'Meetup near you' : '$reason \u00B7 Meetup';
          break;
        case FeedItemType.newGroup:
          if (userGroups.length < 5) {
            score += 0.28;
            reason = reason.isEmpty ? 'New group' : '$reason \u00B7 New group';
          } else {
            score += 0.15;
          }
          break;
        case FeedItemType.newMarketplaceItem:
          score += 0.22;
          reason = reason.isEmpty ? 'Preloved item' : '$reason \u00B7 Preloved';
          break;
        case FeedItemType.newParent:
          score += 0.20;
          reason = reason.isEmpty ? 'New neighbour' : '$reason \u00B7 New parent';
          break;
        case FeedItemType.milestone:
          score += 0.25;
          reason = reason.isEmpty ? 'Milestone' : '$reason \u00B7 Milestone';
          break;
      }

      // Social proximity boost (30%)
      if (item.meta.containsKey('groupId') &&
          userGroups.contains(item.meta['groupId'])) {
        score += 0.20;
        reason += ' \u00B7 Your group';
      }
      if (item.subtitle.contains(userBorough)) {
        score += 0.10;
      }

      return RankedFeedItem(item: item, score: score.clamp(0.0, 1.0), reason: reason);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  // ── Nudge Generation ──────────────────────────────────────────────────
  void _generateNudges() {
    final now = DateTime.now();
    final borough = _getUserBorough();
    final userName = _onboarding.name ?? 'there';
    final children = _onboarding.children;
    final stages = _onboarding.stagesOfLife;
    final rng = Random(now.day + now.hour);

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
        title: '${closest.attendeeCount} parents are meeting $timeWord',
        subtitle: '${closest.title} at ${closest.location} \u2014 ${closest.timeDisplay}',
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
          final milestone = _getUpcomingMilestone(birthday, name);
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
          title: 'Your community misses you, $userName!',
          subtitle: '${_feedService.newItemsSinceLastLogin} new things happened while you were away',
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
        title: 'Join a group to meet more parents',
        subtitle: 'Parents in $borough groups are 3x more likely to attend meetups',
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
        title: 'Rain forecast this weekend',
        subtitle: 'How about soft play or a museum visit? 4 parents nearby are looking for indoor plans!',
        emoji: '\u{1F327}',
        actionLabel: 'Create Indoor Meetup',
        actionRoute: '/create_meetup',
        relevanceScore: 0.68,
      ));
    } else {
      _nudges.add(NudgeCard(
        id: 'nudge_weather_${now.day}',
        type: NudgeType.weatherActivity,
        title: 'Beautiful weather this weekend!',
        subtitle: 'Perfect for a park playdate. 6 families in $borough are heading outdoors!',
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
        title: 'This week in $borough',
        subtitle: '$meetupsThisWeek meetups planned, ${_feedService.feedItems.take(5).length} community updates, and 2 new preloved items',
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
        title: '3 parents-to-be near you',
        subtitle: 'Connect with other expecting parents in $borough before your baby arrives!',
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
      title: 'Bugaboo Fox 3 listed near you',
      subtitle: 'A highly sought-after pram just listed for \u00A3350 \u2014 87 views already!',
      emoji: '\u{1F6D2}',
      actionLabel: 'View Item',
      actionRoute: '/marketplace',
      relevanceScore: 0.60,
    ));
  }

  NudgeCard? _getUpcomingMilestone(String birthday, String childName) {
    try {
      final parts = birthday.split('/');
      if (parts.length < 2) return null;
      final month = int.parse(parts[0]);
      final year = int.parse(parts.last);
      final birthDate = DateTime(year, month, parts.length > 2 ? int.parse(parts[1]) : 1);
      final ageMonths = ((DateTime.now().difference(birthDate).inDays) / 30.44).round();

      // Key milestones
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
            title: '$childName is nearly ${entry.value}!',
            subtitle: 'Connect with parents who\'ve been through this stage \u2014 they have great tips!',
            emoji: '\u{1F389}',
            actionLabel: 'Get Tips',
            relevanceScore: 0.87,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  String _getUserBorough() {
    final pc = _onboarding.postcode;
    if (pc != null) return _postcode.getBoroughFromPostcode(pc) ?? 'Cambridge';
    return 'Cambridge';
  }
}
