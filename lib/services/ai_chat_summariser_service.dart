import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import 'gemini_system_prompt_builder.dart';
import 'borough_ai_context.dart';

// =============================================================================
// AI CHAT MESSAGE SUMMARISER & CATCH-UP SERVICE  — HYPERLOCAL EDITION
// Uses Gemini AI to generate intelligent summaries of unread group messages
// System prompt now assembled by GeminiSystemPromptBuilder (Step 3)
// =============================================================================

class MessageSummaryPoint {
  final String text;
  final String? authorName;
  final String? messageId;
  final int? messageIndex;
  final String category; // 'recommendation', 'discussion', 'question', 'plan', 'share'

  const MessageSummaryPoint({
    required this.text,
    this.authorName,
    this.messageId,
    this.messageIndex,
    required this.category,
  });
}

class ChatSummary {
  final String groupId;
  final String groupName;
  final int unreadCount;
  final List<MessageSummaryPoint> keyPoints;
  final String overviewText;
  final DateTime generatedAt;
  final List<String> mentionedTopics;
  final bool hasActionItems;
  final String? upcomingPlanNote;
  bool isDismissed;

  ChatSummary({
    required this.groupId,
    required this.groupName,
    required this.unreadCount,
    required this.keyPoints,
    required this.overviewText,
    required this.mentionedTopics,
    this.hasActionItems = false,
    this.upcomingPlanNote,
    this.isDismissed = false,
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.now();
}

class AiChatSummariserService with BoroughAiContext {
  static final AiChatSummariserService _instance =
      AiChatSummariserService._internal();
  factory AiChatSummariserService() => _instance;
  AiChatSummariserService._internal();

  final GeminiSystemPromptBuilder _promptBuilder =
      GeminiSystemPromptBuilder();

  // Gemini API configuration (centralised in GeminiConfig)

  final Map<String, ChatSummary> _summaries = {};

  ChatSummary? getSummary(String groupId) => _summaries[groupId];
  bool hasSummary(String groupId) =>
      _summaries.containsKey(groupId) &&
      !(_summaries[groupId]?.isDismissed ?? true);

  void dismissSummary(String groupId) {
    if (_summaries.containsKey(groupId)) {
      _summaries[groupId]!.isDismissed = true;
    }
  }

  /// Generate a summary for a group's unread messages using Gemini AI
  Future<ChatSummary> generateSummary({
    required String groupId,
    required String groupName,
    required List<Map<String, dynamic>> messages,
    int lastReadIndex = 0,
  }) async {
    final unread = messages.length > lastReadIndex
        ? messages.sublist(lastReadIndex)
        : messages;

    if (unread.isEmpty) {
      return ChatSummary(
        groupId: groupId,
        groupName: groupName,
        unreadCount: 0,
        keyPoints: [],
        overviewText: 'No new messages since your last visit.',
        mentionedTopics: [],
      );
    }

    try {
      final aiSummary = await _callGeminiForSummary(groupName, unread);
      _summaries[groupId] = aiSummary;
      return aiSummary;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Gemini summariser error: $e');
      }
      // Fallback to local analysis
      final fallback =
          _generateLocalSummary(groupId, groupName, unread, lastReadIndex);
      _summaries[groupId] = fallback;
      return fallback;
    }
  }

  /// Call Gemini API to generate a message summary
  Future<ChatSummary> _callGeminiForSummary(
    String groupName,
    List<Map<String, dynamic>> unreadMessages,
  ) async {
    // Format messages for the prompt
    final messageText = StringBuffer();
    for (var i = 0; i < unreadMessages.length; i++) {
      final msg = unreadMessages[i];
      final author =
          (msg['senderName'] ?? msg['author'] ?? 'Someone') as String;
      final text = (msg['text'] ?? msg['content'] ?? '') as String;
      messageText.writeln('$author: $text');
    }

    final basePrompt = _promptBuilder.buildChatSummariserPrompt(
      chatType: 'group',
      groupName: groupName,
      messageCount: unreadMessages.length,
    );
    final systemPrompt = '$basePrompt\n'
        'RESPOND IN EXACT JSON FORMAT (no markdown, no backticks, just raw JSON):\n'
        '{\n'
        '  "overview": "A 1-2 sentence friendly summary starting with \'While you were away:\' that captures the conversation highlights",\n'
        '  "keyPoints": [\n'
        '    {\n'
        '      "text": "Brief summary of this point",\n'
        '      "authorName": "Author name if clear",\n'
        '      "category": "one of: recommendation, discussion, question, plan, share"\n'
        '    }\n'
        '  ],\n'
        '  "topics": ["topic1", "topic2", "topic3"],\n'
        '  "hasActionItems": true or false,\n'
        '  "upcomingPlan": "Description of any planned meetup/event discussed, or null"\n'
        '}\n\n'
        'ADDITIONAL RULES:\n'
        '- Maximum 5 key points, ordered by importance\n'
        '- Highlight plans, recommendations, questions, and shared experiences\n'
        '- Be warm and conversational in the overview\n'
        '- Detect any upcoming plans (meetups, playdates, events)\n'
        '- Extract 3-5 mentioned topics\n'
        '- Flag if there are action items the user should respond to';

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
                  'Summarise these ${unreadMessages.length} unread messages from the "$groupName" group:\n\n${messageText.toString()}'
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'topP': 0.9,
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
        .timeout(const Duration(seconds: 15));

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

          try {
            final json = jsonDecode(text) as Map<String, dynamic>;
            return _parseSummaryFromJson(json, groupName, unreadMessages.length);
          } catch (parseError) {
            if (kDebugMode) {
              debugPrint('Summary JSON parse error: $parseError');
              debugPrint('Raw: $text');
            }
            throw Exception('Failed to parse Gemini summary');
          }
        }
      }
      throw Exception('No content in Gemini response');
    } else {
      throw Exception('Gemini API error: ${response.statusCode}');
    }
  }

  /// Parse the Gemini JSON response into a ChatSummary
  ChatSummary _parseSummaryFromJson(
    Map<String, dynamic> json,
    String groupName,
    int unreadCount,
  ) {
    final overview =
        (json['overview'] ?? 'While you were away, the group was active.')
            as String;
    final hasActionItems = (json['hasActionItems'] ?? false) as bool;
    final upcomingPlan = json['upcomingPlan'] as String?;
    final topics = (json['topics'] as List<dynamic>?)
            ?.map((t) => t.toString())
            .toList() ??
        [];

    final keyPointsJson = json['keyPoints'] as List<dynamic>? ?? [];
    final keyPoints = keyPointsJson
        .take(5)
        .map((kp) => MessageSummaryPoint(
              text: (kp['text'] ?? '') as String,
              authorName: kp['authorName'] as String?,
              category: (kp['category'] ?? 'discussion') as String,
            ))
        .toList();

    return ChatSummary(
      groupId: groupName.toLowerCase().replaceAll(' ', '_'),
      groupName: groupName,
      unreadCount: unreadCount,
      keyPoints: keyPoints,
      overviewText: overview,
      mentionedTopics: topics,
      hasActionItems: hasActionItems,
      upcomingPlanNote: upcomingPlan,
    );
  }

  /// Generate sample summaries for demo groups using Gemini AI
  Future<Map<String, ChatSummary>> generateDemoSummaries() async {
    final demos = <String, ChatSummary>{};

    // Generate AI summaries for each demo group
    final demoGroups = {
      'new_parents_cambridge': {
        'name': 'Cambridge New Parents',
        'messages': [
          {'senderName': 'Sophie Williams', 'text': 'Has anyone tried Cherry Hinton Hall for playdates? I was thinking of organising one this Saturday at 10am if anyone fancies it?'},
          {'senderName': 'Emma Thompson', 'text': 'Ooh yes! We went to Little Bean Cafe on Mill Road yesterday \u2014 so buggy friendly and they have a proper baby changing room. Highly recommend!'},
          {'senderName': 'Kate Rogers', 'text': 'Can anyone recommend Newnham Nursery School? We\u2019re weighing it up against Little Owls and finding it hard to decide.'},
          {'senderName': 'Priya Mehta', 'text': 'We\u2019re at Little Owls and really happy. Newnham Nursery is great too though \u2014 slightly bigger classes but more outdoor space.'},
          {'senderName': 'Laura Chen', 'text': 'Just to add \u2014 Newnham has a much longer waiting list so apply early!'},
          {'senderName': 'Anna Mitchell', 'text': 'Has anyone used the NHS health visitor drop-in at Brookfields? Thinking of going on Tuesday for a weigh-in.'},
          {'senderName': 'Meg Hart', 'text': 'Yes! The Tuesday drop-in is great. Much less busy than the one at the Rosie. No appointment needed.'},
        ],
      },
      'dads_connect': {
        'name': 'Dads Connect',
        'messages': [
          {'senderName': 'James Carter', 'text': 'Right lads, I\u2019ve booked 4 tee times for this Sunday morning at Gog Magog Golf Course. 9am start. Who\u2019s in? 4 spots left!'},
          {'senderName': 'Mark Robinson', 'text': 'Count me in! Also wanted to share \u2014 we tried the gentle fade method for sleep training instead of CIO and it\u2019s been brilliant. Took a week but she sleeps through now.'},
          {'senderName': 'Tom Baker', 'text': 'That\u2019s great news Mark! We\u2019ve been struggling with night wakes. How old is she?'},
          {'senderName': 'Mark Robinson', 'text': '7 months. The key was moving bedtime 30 mins earlier and doing the same routine every night. Happy to share the approach in detail.'},
          {'senderName': 'Luke Anderson', 'text': 'Random one \u2014 any dads fancy putting a pub quiz team together? Thursday nights at The Eagle. My wife said she\u2019d do bedtime if I promise to be home by 10!'},
          {'senderName': 'James Carter', 'text': 'Pub quiz \u2014 100% in! Love it. Let\u2019s get a team of 4-5.'},
        ],
      },
      'toddler_adventures': {
        'name': 'Toddler Adventures',
        'messages': [
          {'senderName': 'Lucy Taylor', 'text': 'Just posted some photos from yesterday\u2019s picnic at Grantchester Meadows \u2014 it was absolutely gorgeous! The kids loved splashing in the river.'},
          {'senderName': 'Olivia Brown', 'text': 'Those photos are lovely Lucy! Also \u2014 I have a 20% off code for Monkey Music classes if anyone wants it: TODDLER20. Expires end of the month.'},
          {'senderName': 'Sarah Clarke', 'text': 'Has anyone tried the Yumbox bento lunchbox? I\u2019ve been looking for something truly toddler-proof. My current ones always leak.'},
          {'senderName': 'Lucy Taylor', 'text': 'Yes!! The Yumbox is amazing \u2014 completely leak-proof and dishwasher safe. We\u2019ve had ours for 8 months and it\u2019s still perfect.'},
          {'senderName': 'Anya Patel', 'text': 'Does anyone know a good swimming class for 2-year-olds? We tried Puddle Ducks but the times don\u2019t work for us.'},
        ],
      },
    };

    for (final entry in demoGroups.entries) {
      final groupId = entry.key;
      final groupInfo = entry.value;
      try {
        final summary = await generateSummary(
          groupId: groupId,
          groupName: groupInfo['name'] as String,
          messages: (groupInfo['messages'] as List)
              .cast<Map<String, dynamic>>(),
          lastReadIndex: 0,
        );
        demos[groupId] = summary;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Demo summary generation failed for $groupId: $e');
        }
        // Fallback for this specific group
        demos[groupId] = _generateLocalSummary(
          groupId,
          groupInfo['name'] as String,
          (groupInfo['messages'] as List).cast<Map<String, dynamic>>(),
          0,
        );
      }
    }

    for (final entry in demos.entries) {
      _summaries[entry.key] = entry.value;
    }

    return demos;
  }

  // ── Local fallback summary ────────────────────────────────────────────
  ChatSummary _generateLocalSummary(
    String groupId,
    String groupName,
    List<Map<String, dynamic>> unread,
    int lastReadIndex,
  ) {
    final authors = <String>{};
    final topics = <String>[];
    final recommendations = <MessageSummaryPoint>[];
    final plans = <MessageSummaryPoint>[];
    final questions = <MessageSummaryPoint>[];

    for (var i = 0; i < unread.length; i++) {
      final msg = unread[i];
      final text = (msg['text'] ?? msg['content'] ?? '') as String;
      final author =
          (msg['senderName'] ?? msg['author'] ?? 'Someone') as String;
      authors.add(author);
      final lower = text.toLowerCase();

      if (lower.contains('recommend') ||
          lower.contains('try ') ||
          lower.contains('love the') ||
          lower.contains('great for') ||
          lower.contains('best ') ||
          lower.contains('suggest')) {
        recommendations.add(MessageSummaryPoint(
          text: _truncate(text, 100),
          authorName: author,
          messageIndex: lastReadIndex + i,
          category: 'recommendation',
        ));
      }

      if (lower.contains('saturday') ||
          lower.contains('sunday') ||
          lower.contains('meet') ||
          lower.contains('join') ||
          lower.contains('this weekend') ||
          lower.contains('tomorrow') ||
          lower.contains('playdate') ||
          lower.contains('coffee')) {
        plans.add(MessageSummaryPoint(
          text: _truncate(text, 100),
          authorName: author,
          messageIndex: lastReadIndex + i,
          category: 'plan',
        ));
      }

      if (text.contains('?') ||
          lower.contains('anyone know') ||
          lower.contains('has anyone') ||
          lower.contains('advice')) {
        questions.add(MessageSummaryPoint(
          text: _truncate(text, 100),
          authorName: author,
          messageIndex: lastReadIndex + i,
          category: 'question',
        ));
      }

      _extractTopics(lower, topics);
    }

    final keyPoints = <MessageSummaryPoint>[];
    if (plans.isNotEmpty) keyPoints.add(plans.first);
    for (final r in recommendations.take(2)) {
      keyPoints.add(r);
    }
    for (final q in questions.take(1)) {
      keyPoints.add(q);
    }

    final overview = _buildOverview(
      groupName: groupName,
      unreadCount: unread.length,
      authors: authors,
      hasPlans: plans.isNotEmpty,
      hasRecommendations: recommendations.isNotEmpty,
      hasQuestions: questions.isNotEmpty,
      topics: topics,
    );

    return ChatSummary(
      groupId: groupId,
      groupName: groupName,
      unreadCount: unread.length,
      keyPoints: keyPoints,
      overviewText: overview,
      mentionedTopics: topics.toSet().take(5).toList(),
      hasActionItems: plans.isNotEmpty || questions.isNotEmpty,
      upcomingPlanNote: plans.isNotEmpty
          ? '${plans.first.authorName} mentioned plans: "${_truncate(plans.first.text, 60)}"'
          : null,
    );
  }

  String _buildOverview({
    required String groupName,
    required int unreadCount,
    required Set<String> authors,
    required bool hasPlans,
    required bool hasRecommendations,
    required bool hasQuestions,
    required List<String> topics,
  }) {
    final parts = <String>[];
    parts.add('While you were away:');
    if (hasRecommendations) {
      parts.add('${authors.first} shared a recommendation');
    }
    if (hasPlans) {
      parts.add('there\'s an upcoming plan being discussed');
    }
    if (hasQuestions) {
      parts.add('someone asked a question the community is answering');
    }
    if (topics.isNotEmpty) {
      parts.add('topics included ${topics.take(3).join(', ')}');
    }
    return '${parts.join(', ')}.';
  }

  void _extractTopics(String text, List<String> topics) {
    const keywords = {
      'nursery': 'nurseries',
      'school': 'schools',
      'sleep': 'sleep',
      'weaning': 'weaning',
      'teething': 'teething',
      'cafe': 'cafes',
      'restaurant': 'restaurants',
      'park': 'parks',
      'swim': 'swimming',
      'music': 'music classes',
      'playdate': 'playdates',
      'nappy': 'nappies',
      'breastfeed': 'breastfeeding',
      'formula': 'formula feeding',
      'buggy': 'buggies',
      'pram': 'prams',
    };

    for (final entry in keywords.entries) {
      if (text.contains(entry.key) && !topics.contains(entry.value)) {
        topics.add(entry.value);
      }
    }
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen - 3)}...';
  }
}
