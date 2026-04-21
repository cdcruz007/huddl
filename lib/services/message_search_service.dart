import 'dart:async';
import '../models/direct_message.dart';
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

    // 2. Group chat messages are stored in BrowserStorage under
    //    'group_messages_<groupId>'. Only real user-sent messages are
    //    persisted there — no dummy data is injected.
    //    (Searching persisted group messages is a future enhancement;
    //    for now search only returns DM results to avoid fake data.)

    // Sort by most recent first
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return results;
  }
}
