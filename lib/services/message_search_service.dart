import 'dart:async';
import '../models/direct_message.dart';
import '../models/group.dart';
import 'dm_service.dart';

/// A single search result representing a message match within a conversation.
class MessageSearchResult {
  final String conversationId;
  final String conversationName;
  final bool isGroup;

  /// For groups: imageUrl; for DMs: empty
  final String imageUrl;

  /// For DMs: avatar hex color
  final String avatarColor;

  /// The matched message text
  final String messageText;

  /// Sender of the matched message
  final String senderName;

  /// Timestamp of the matched message
  final DateTime timestamp;

  /// The original message id (useful for scrolling to it)
  final String messageId;

  /// For DMs: recipientId; for groups: groupId
  final String targetId;

  /// Extra DM fields for navigation
  final String? recipientAvatarColor;

  MessageSearchResult({
    required this.conversationId,
    required this.conversationName,
    required this.isGroup,
    required this.imageUrl,
    required this.avatarColor,
    required this.messageText,
    required this.senderName,
    required this.timestamp,
    required this.messageId,
    required this.targetId,
    this.recipientAvatarColor,
  });
}

/// Service that performs deep search across DMs and group chats.
class MessageSearchService {
  static final MessageSearchService _instance = MessageSearchService._internal();
  factory MessageSearchService() => _instance;
  MessageSearchService._internal();

  final DMService _dmService = DMService();

  /// Generates demo messages for a group so we can search within them.
  /// These match the demo data generated in GroupChatScreen._generateDemoMessages.
  List<ChatMessage> _getDemoGroupMessages(String groupId, String groupName) {
    final now = DateTime.now();
    final avatarColors = [
      '#FF975C',
      '#3580F0',
      '#199A85',
      '#A16AE9',
      '#5B9DFF',
      '#E8A838'
    ];

    // Return contextual demo messages based on group name for richer search
    if (groupName.toLowerCase().contains('parent')) {
      return [
        ChatMessage(
          id: '${groupId}_msg_1',
          senderId: 'user_emma',
          senderName: 'Emma',
          senderAvatar: avatarColors[0],
          message:
              'Good morning everyone! Has anyone tried the new cafe near the river?',
          timestamp: now.subtract(const Duration(hours: 2, minutes: 30)),
        ),
        ChatMessage(
          id: '${groupId}_msg_2',
          senderId: 'user_sophie',
          senderName: 'Sophie',
          senderAvatar: avatarColors[1],
          message:
              'Yes! We went last weekend. They have a great kids\' menu and a lovely play area outside.',
          timestamp: now.subtract(const Duration(hours: 2, minutes: 25)),
        ),
        ChatMessage(
          id: '${groupId}_msg_3',
          senderId: 'user_kate',
          senderName: 'Kate',
          senderAvatar: avatarColors[2],
          message: 'That sounds lovely! Is it buggy-friendly?',
          timestamp: now.subtract(const Duration(hours: 2, minutes: 20)),
        ),
        ChatMessage(
          id: '${groupId}_msg_4',
          senderId: 'user_sophie',
          senderName: 'Sophie',
          senderAvatar: avatarColors[1],
          message:
              'Absolutely! Wide doors, ramp access, and they even have highchairs.',
          timestamp: now.subtract(const Duration(hours: 2, minutes: 18)),
        ),
        ChatMessage(
          id: '${groupId}_msg_5',
          senderId: 'user_lucy',
          senderName: 'Lucy',
          senderAvatar: avatarColors[3],
          message:
              'Anyone fancy a group outing there this Thursday? Weather looks good!',
          timestamp: now.subtract(const Duration(hours: 1, minutes: 45)),
        ),
        ChatMessage(
          id: '${groupId}_msg_6',
          senderId: 'user_emma',
          senderName: 'Emma',
          senderAvatar: avatarColors[0],
          message: 'Count me in! What time works for everyone?',
          timestamp: now.subtract(const Duration(hours: 1, minutes: 40)),
        ),
        ChatMessage(
          id: '${groupId}_msg_7',
          senderId: 'user_james',
          senderName: 'James',
          senderAvatar: avatarColors[4],
          message: '10:30am would be ideal before the lunch rush.',
          timestamp: now.subtract(const Duration(hours: 1, minutes: 35)),
        ),
        ChatMessage(
          id: '${groupId}_msg_8',
          senderId: 'user_anna',
          senderName: 'Anna',
          senderAvatar: avatarColors[5],
          message: 'Perfect timing! See you all there.',
          timestamp: now.subtract(const Duration(hours: 1, minutes: 30)),
        ),
      ];
    } else if (groupName.toLowerCase().contains('toddler') ||
        groupName.toLowerCase().contains('activit')) {
      return [
        ChatMessage(
          id: '${groupId}_msg_1',
          senderId: 'user_kate',
          senderName: 'Kate',
          senderAvatar: avatarColors[2],
          message: 'Storytime at the library is brilliant on Tuesdays!',
          timestamp: now.subtract(const Duration(hours: 3)),
        ),
        ChatMessage(
          id: '${groupId}_msg_2',
          senderId: 'user_emma',
          senderName: 'Emma',
          senderAvatar: avatarColors[0],
          message: 'We love soft play at the leisure centre too.',
          timestamp: now.subtract(const Duration(hours: 2, minutes: 50)),
        ),
        ChatMessage(
          id: '${groupId}_msg_3',
          senderId: 'user_lucy',
          senderName: 'Lucy',
          senderAvatar: avatarColors[3],
          message: 'Has anyone tried the nature trail at Wandlebury?',
          timestamp: now.subtract(const Duration(hours: 2, minutes: 30)),
        ),
      ];
    } else if (groupName.toLowerCase().contains('sleep')) {
      return [
        ChatMessage(
          id: '${groupId}_msg_1',
          senderId: 'user_anna',
          senderName: 'Anna',
          senderAvatar: avatarColors[5],
          message: 'We finally got 6 hours straight last night!',
          timestamp: now.subtract(const Duration(hours: 4)),
        ),
        ChatMessage(
          id: '${groupId}_msg_2',
          senderId: 'user_sophie',
          senderName: 'Sophie',
          senderAvatar: avatarColors[1],
          message: 'That\'s amazing! What changed for you?',
          timestamp: now.subtract(const Duration(hours: 3, minutes: 45)),
        ),
        ChatMessage(
          id: '${groupId}_msg_3',
          senderId: 'user_anna',
          senderName: 'Anna',
          senderAvatar: avatarColors[5],
          message:
              'We started a consistent bedtime routine - bath, story, lullaby.',
          timestamp: now.subtract(const Duration(hours: 3, minutes: 30)),
        ),
      ];
    } else {
      return [
        ChatMessage(
          id: '${groupId}_msg_1',
          senderId: 'user_emma',
          senderName: 'Emma',
          senderAvatar: avatarColors[0],
          message: 'Hello everyone! Great to be in this group.',
          timestamp: now.subtract(const Duration(hours: 5)),
        ),
        ChatMessage(
          id: '${groupId}_msg_2',
          senderId: 'user_james',
          senderName: 'James',
          senderAvatar: avatarColors[4],
          message: 'Welcome! Looking forward to chatting with you all.',
          timestamp: now.subtract(const Duration(hours: 4, minutes: 50)),
        ),
        ChatMessage(
          id: '${groupId}_msg_3',
          senderId: 'user_lucy',
          senderName: 'Lucy',
          senderAvatar: avatarColors[3],
          message: 'Does anyone know about upcoming events in the area?',
          timestamp: now.subtract(const Duration(hours: 4, minutes: 30)),
        ),
      ];
    }
  }

  /// Search across all DM conversations and group chats.
  ///
  /// [query] - the search term
  /// [groups] - list of groups with their metadata (id, name, imageUrl)
  /// [dmConversations] - list of DM conversations
  ///
  /// Returns a list of MessageSearchResult sorted by relevance (most recent first).
  Future<List<MessageSearchResult>> searchAll({
    required String query,
    required List<Map<String, dynamic>> groups,
    required List<DMConversation> dmConversations,
  }) async {
    if (query.trim().isEmpty) return [];

    final q = query.toLowerCase().trim();
    final results = <MessageSearchResult>[];

    // 1. Search within DM messages
    await _dmService.initialize();
    for (final dm in dmConversations) {
      final messages = await _dmService.getMessages(dm.id);
      for (final msg in messages) {
        if (msg.message.toLowerCase().contains(q)) {
          results.add(MessageSearchResult(
            conversationId: dm.id,
            conversationName: dm.recipientName,
            isGroup: false,
            imageUrl: '',
            avatarColor: dm.recipientAvatarColor,
            messageText: msg.message,
            senderName: msg.isMe ? 'You' : msg.senderName,
            timestamp: msg.timestamp,
            messageId: msg.id,
            targetId: dm.recipientId,
            recipientAvatarColor: dm.recipientAvatarColor,
          ));
        }
      }
    }

    // 2. Search within group chat messages (demo data)
    for (final group in groups) {
      final groupId = group['id'] as String;
      final groupName = group['name'] as String;
      final groupImageUrl = group['imageUrl'] as String? ?? '';
      final demoMessages = _getDemoGroupMessages(groupId, groupName);

      for (final msg in demoMessages) {
        if (msg.message.toLowerCase().contains(q)) {
          results.add(MessageSearchResult(
            conversationId: groupId,
            conversationName: groupName,
            isGroup: true,
            imageUrl: groupImageUrl,
            avatarColor: '',
            messageText: msg.message,
            senderName: msg.senderName,
            timestamp: msg.timestamp,
            messageId: msg.id,
            targetId: groupId,
          ));
        }
      }
    }

    // Sort by most recent first
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return results;
  }
}
