// ═══════════════════════════════════════════════════════════════════════════════
// AI CHAT MESSAGE SUMMARISER & CATCH-UP SERVICE
// Generates intelligent summaries of unread group messages
// ═══════════════════════════════════════════════════════════════════════════════

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

class AiChatSummariserService {
  static final AiChatSummariserService _instance = AiChatSummariserService._internal();
  factory AiChatSummariserService() => _instance;
  AiChatSummariserService._internal();

  final Map<String, ChatSummary> _summaries = {};

  ChatSummary? getSummary(String groupId) => _summaries[groupId];
  bool hasSummary(String groupId) => _summaries.containsKey(groupId) &&
      !(_summaries[groupId]?.isDismissed ?? true);

  void dismissSummary(String groupId) {
    if (_summaries.containsKey(groupId)) {
      _summaries[groupId]!.isDismissed = true;
    }
  }

  /// Generate a summary for a group's unread messages
  ChatSummary generateSummary({
    required String groupId,
    required String groupName,
    required List<Map<String, dynamic>> messages,
    int lastReadIndex = 0,
  }) {
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

    // Analyse message patterns
    final authors = <String>{};
    final topics = <String>[];
    final recommendations = <MessageSummaryPoint>[];
    final discussions = <MessageSummaryPoint>[];
    final plans = <MessageSummaryPoint>[];
    final questions = <MessageSummaryPoint>[];

    for (var i = 0; i < unread.length; i++) {
      final msg = unread[i];
      final text = (msg['text'] ?? msg['content'] ?? '') as String;
      final author = (msg['senderName'] ?? msg['author'] ?? 'Someone') as String;
      authors.add(author);

      final lower = text.toLowerCase();

      // Detect recommendations
      if (lower.contains('recommend') || lower.contains('try ') ||
          lower.contains('love the') || lower.contains('great for') ||
          lower.contains('best ') || lower.contains('suggest')) {
        recommendations.add(MessageSummaryPoint(
          text: _truncate(text, 100),
          authorName: author,
          messageIndex: lastReadIndex + i,
          category: 'recommendation',
        ));
      }

      // Detect plans / meetup discussions
      if (lower.contains('saturday') || lower.contains('sunday') ||
          lower.contains('meet') || lower.contains('join') ||
          lower.contains('this weekend') || lower.contains('tomorrow') ||
          lower.contains('playdate') || lower.contains('coffee')) {
        plans.add(MessageSummaryPoint(
          text: _truncate(text, 100),
          authorName: author,
          messageIndex: lastReadIndex + i,
          category: 'plan',
        ));
      }

      // Detect questions
      if (text.contains('?') || lower.contains('anyone know') ||
          lower.contains('has anyone') || lower.contains('advice')) {
        questions.add(MessageSummaryPoint(
          text: _truncate(text, 100),
          authorName: author,
          messageIndex: lastReadIndex + i,
          category: 'question',
        ));
      }

      // Detect topic keywords
      _extractTopics(lower, topics);
    }

    // Build key points (max 5)
    final keyPoints = <MessageSummaryPoint>[];
    if (plans.isNotEmpty) keyPoints.add(plans.first);
    for (final r in recommendations.take(2)) {
      keyPoints.add(r);
    }
    for (final q in questions.take(1)) {
      keyPoints.add(q);
    }
    if (keyPoints.length < 5 && discussions.isNotEmpty) {
      keyPoints.add(discussions.first);
    }

    // Generate overview
    final overview = _buildOverview(
      groupName: groupName,
      unreadCount: unread.length,
      authors: authors,
      hasPlans: plans.isNotEmpty,
      hasRecommendations: recommendations.isNotEmpty,
      hasQuestions: questions.isNotEmpty,
      topics: topics,
    );

    final summary = ChatSummary(
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

    _summaries[groupId] = summary;
    return summary;
  }

  /// Generate sample summaries for demo groups
  Map<String, ChatSummary> generateDemoSummaries() {
    final demos = <String, ChatSummary>{};

    // Cambridge New Parents group
    demos['new_parents_cambridge'] = ChatSummary(
      groupId: 'new_parents_cambridge',
      groupName: 'Cambridge New Parents',
      unreadCount: 47,
      overviewText: 'While you were away: Emma shared a buggy-friendly cafe recommendation, 4 parents discussed the best nurseries in Newnham, and there\'s a playdate planned for Saturday at 10am.',
      keyPoints: [
        const MessageSummaryPoint(
          text: 'Sophie proposed a group playdate at Cherry Hinton Hall this Saturday at 10am',
          authorName: 'Sophie Williams',
          messageIndex: 12,
          category: 'plan',
        ),
        const MessageSummaryPoint(
          text: 'Emma recommended Little Bean Cafe \u2014 great for prams and has a baby changing room',
          authorName: 'Emma Thompson',
          messageIndex: 8,
          category: 'recommendation',
        ),
        const MessageSummaryPoint(
          text: '4 parents discussed Newnham Nursery School vs Little Owls \u2014 mixed reviews on both',
          authorName: 'Kate Rogers',
          messageIndex: 23,
          category: 'discussion',
        ),
        const MessageSummaryPoint(
          text: 'Anna asked: "Has anyone used the NHS health visitor drop-in at Brookfields?"',
          authorName: 'Anna Mitchell',
          messageIndex: 35,
          category: 'question',
        ),
      ],
      mentionedTopics: ['nurseries', 'cafes', 'playdate', 'health visitor'],
      hasActionItems: true,
      upcomingPlanNote: 'Sophie proposed a playdate this Saturday at Cherry Hinton Hall',
    );

    // Dads Connect group
    demos['dads_connect'] = ChatSummary(
      groupId: 'dads_connect',
      groupName: 'Dads Connect',
      unreadCount: 23,
      overviewText: 'James organised a golf morning next Sunday, Mark shared tips on baby sleep training, and 3 dads are planning a pub quiz team.',
      keyPoints: [
        const MessageSummaryPoint(
          text: 'James booked tee times for Sunday morning golf \u2014 4 spots left',
          authorName: 'James Carter',
          messageIndex: 5,
          category: 'plan',
        ),
        const MessageSummaryPoint(
          text: 'Mark shared his sleep training method: "Gentle fade works better than CIO for us"',
          authorName: 'Mark Robinson',
          messageIndex: 11,
          category: 'recommendation',
        ),
        const MessageSummaryPoint(
          text: 'Luke asked: "Any dads fancy a pub quiz team on Thursday nights?"',
          authorName: 'Luke Anderson',
          messageIndex: 18,
          category: 'question',
        ),
      ],
      mentionedTopics: ['golf', 'sleep training', 'pub quiz'],
      hasActionItems: true,
      upcomingPlanNote: 'James booked golf for Sunday \u2014 4 spots remain',
    );

    // Toddler Adventures group
    demos['toddler_adventures'] = ChatSummary(
      groupId: 'toddler_adventures',
      groupName: 'Toddler Adventures',
      unreadCount: 31,
      overviewText: 'Lucy shared photos from Grantchester Meadows picnic, Sarah recommended a toddler-proof lunchbox, and there\'s a music class discount code being passed around.',
      keyPoints: [
        const MessageSummaryPoint(
          text: 'Lucy posted photos from the Grantchester picnic \u2014 looks amazing!',
          authorName: 'Lucy Taylor',
          messageIndex: 3,
          category: 'share',
        ),
        const MessageSummaryPoint(
          text: 'Sarah recommended the Yumbox lunchbox: "Toddler-proof and dishwasher safe"',
          authorName: 'Sarah Clarke',
          messageIndex: 14,
          category: 'recommendation',
        ),
        const MessageSummaryPoint(
          text: 'Olivia shared 20% off code for Monkey Music classes: TODDLER20',
          authorName: 'Olivia Brown',
          messageIndex: 22,
          category: 'recommendation',
        ),
      ],
      mentionedTopics: ['picnic', 'lunchbox', 'music classes', 'discount'],
      hasActionItems: false,
    );

    for (final entry in demos.entries) {
      _summaries[entry.key] = entry.value;
    }

    return demos;
  }

  // ── Helpers ────────────────────────────────────────────────────────────
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
