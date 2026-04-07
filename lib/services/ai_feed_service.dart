import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';

import 'gemini_system_prompt_builder.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'meetup_service.dart';
import 'default_group_service.dart';
import 'community_feed_service.dart';

// =============================================================================
// AI SMART FEED CURATION & NUDGE ENGINE  — HYPERLOCAL EDITION
// Uses Gemini AI to generate personalised, context-aware nudge cards
// and intelligently rank community feed items
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

  // Gemini API configuration (centralised in GeminiConfig)

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

  /// Re-rank feed items based on user profile relevance
  List<RankedFeedItem> rankFeedItems(List<FeedItem> items) {
    final userBorough = _getUserBorough();
    final userGroups =
        _groupService.getAllDefaultGroups().map((g) => g.id).toSet();

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
          reason = reason.isEmpty
              ? 'Meetup near you'
              : '$reason \u00B7 Meetup';
          break;
        case FeedItemType.newGroup:
          if (userGroups.length < 5) {
            score += 0.28;
            reason = reason.isEmpty
                ? 'New group'
                : '$reason \u00B7 New group';
          } else {
            score += 0.15;
          }
          break;
        case FeedItemType.newMarketplaceItem:
          score += 0.22;
          reason = reason.isEmpty
              ? 'Market item'
              : '$reason \u00B7 Market';
          break;
        case FeedItemType.newParent:
          score += 0.20;
          reason = reason.isEmpty
              ? 'New neighbour'
              : '$reason \u00B7 New parent';
          break;
        case FeedItemType.milestone:
          score += 0.25;
          reason = reason.isEmpty
              ? 'Milestone'
              : '$reason \u00B7 Milestone';
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

    final url = Uri.parse(
        GeminiConfig.generateContentUrl);

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
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

  String _getUserBorough() {
    final pc = _onboarding.postcode;
    if (pc != null) {
      return _postcode.getBoroughFromPostcode(pc) ?? 'Cambridge';
    }
    return 'Cambridge';
  }
}
