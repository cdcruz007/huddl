/// Represents a message saved by the user from a group or DM conversation.
class SavedMessage {
  final String id;
  final String messageId; // original message id
  final String message; // message text
  final String senderName; // who sent the message
  final DateTime timestamp; // when the message was originally sent
  final DateTime savedAt; // when the user saved it
  final bool isFromGroup; // true = group, false = DM
  // Source info for groups
  final String? groupId;
  final String? groupName;
  final String? groupImageUrl;
  // Source info for DMs
  final String? dmRecipientId;
  final String? dmRecipientName;
  final String? dmRecipientAvatarColor;
  final String? dmConversationId;

  SavedMessage({
    required this.id,
    required this.messageId,
    required this.message,
    required this.senderName,
    required this.timestamp,
    required this.savedAt,
    required this.isFromGroup,
    this.groupId,
    this.groupName,
    this.groupImageUrl,
    this.dmRecipientId,
    this.dmRecipientName,
    this.dmRecipientAvatarColor,
    this.dmConversationId,
  });

  String get sourceName => isFromGroup ? (groupName ?? 'Group') : (dmRecipientName ?? 'DM');

  Map<String, dynamic> toJson() => {
        'id': id,
        'messageId': messageId,
        'message': message,
        'senderName': senderName,
        'timestamp': timestamp.toIso8601String(),
        'savedAt': savedAt.toIso8601String(),
        'isFromGroup': isFromGroup,
        'groupId': groupId,
        'groupName': groupName,
        'groupImageUrl': groupImageUrl,
        'dmRecipientId': dmRecipientId,
        'dmRecipientName': dmRecipientName,
        'dmRecipientAvatarColor': dmRecipientAvatarColor,
        'dmConversationId': dmConversationId,
      };

  factory SavedMessage.fromJson(Map<String, dynamic> json) {
    return SavedMessage(
      id: json['id'] as String,
      messageId: json['messageId'] as String,
      message: json['message'] as String,
      senderName: json['senderName'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      savedAt: DateTime.parse(json['savedAt'] as String),
      isFromGroup: json['isFromGroup'] as bool? ?? true,
      groupId: json['groupId'] as String?,
      groupName: json['groupName'] as String?,
      groupImageUrl: json['groupImageUrl'] as String?,
      dmRecipientId: json['dmRecipientId'] as String?,
      dmRecipientName: json['dmRecipientName'] as String?,
      dmRecipientAvatarColor: json['dmRecipientAvatarColor'] as String?,
      dmConversationId: json['dmConversationId'] as String?,
    );
  }
}

/// Represents an entire saved reply thread stored under a topic name.
class SavedThread {
  final String id;
  final String topicName; // user-given topic name
  final DateTime savedAt;
  // The original (root) message
  final String rootMessageId;
  final String rootMessageText;
  final String rootSenderName;
  final DateTime rootTimestamp;
  // All replies in the thread
  final List<SavedThreadMessage> replies;
  // Source group info — enables direct navigation back
  final String groupId;
  final String groupName;
  final String groupImageUrl;

  SavedThread({
    required this.id,
    required this.topicName,
    required this.savedAt,
    required this.rootMessageId,
    required this.rootMessageText,
    required this.rootSenderName,
    required this.rootTimestamp,
    required this.replies,
    required this.groupId,
    required this.groupName,
    required this.groupImageUrl,
  });

  int get totalMessages => 1 + replies.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'topicName': topicName,
        'savedAt': savedAt.toIso8601String(),
        'rootMessageId': rootMessageId,
        'rootMessageText': rootMessageText,
        'rootSenderName': rootSenderName,
        'rootTimestamp': rootTimestamp.toIso8601String(),
        'replies': replies.map((r) => r.toJson()).toList(),
        'groupId': groupId,
        'groupName': groupName,
        'groupImageUrl': groupImageUrl,
      };

  factory SavedThread.fromJson(Map<String, dynamic> json) {
    return SavedThread(
      id: json['id'] as String,
      topicName: json['topicName'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      rootMessageId: json['rootMessageId'] as String,
      rootMessageText: json['rootMessageText'] as String,
      rootSenderName: json['rootSenderName'] as String,
      rootTimestamp: DateTime.parse(json['rootTimestamp'] as String),
      replies: (json['replies'] as List<dynamic>?)
              ?.map((r) =>
                  SavedThreadMessage.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      groupId: json['groupId'] as String,
      groupName: json['groupName'] as String,
      groupImageUrl: json['groupImageUrl'] as String? ?? '',
    );
  }
}

/// A single message within a saved thread.
class SavedThreadMessage {
  final String messageId;
  final String message;
  final String senderName;
  final DateTime timestamp;
  final bool isMe;

  SavedThreadMessage({
    required this.messageId,
    required this.message,
    required this.senderName,
    required this.timestamp,
    this.isMe = false,
  });

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'message': message,
        'senderName': senderName,
        'timestamp': timestamp.toIso8601String(),
        'isMe': isMe,
      };

  factory SavedThreadMessage.fromJson(Map<String, dynamic> json) {
    return SavedThreadMessage(
      messageId: json['messageId'] as String,
      message: json['message'] as String,
      senderName: json['senderName'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isMe: json['isMe'] as bool? ?? false,
    );
  }
}
