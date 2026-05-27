/// Represents a message saved by the user from a group or DM conversation.
///
/// [topicName] is a user-supplied label used *only* for visual grouping in the
/// Saved tab.  It is NOT a primary key — multiple SavedMessages may share the
/// same topicName.  The unique key is always [id] (auto-generated on save).
class SavedMessage {
  final String id;
  final String messageId; // original message id
  final String message; // message text
  final String senderName; // who sent the message
  final DateTime timestamp; // when the message was originally sent
  final DateTime savedAt; // when the user saved it
  final bool isFromGroup; // true = group, false = DM
  /// User-supplied grouping label — just a display field, never a PK.
  final String topicName;
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
    this.topicName = '',
    this.groupId,
    this.groupName,
    this.groupImageUrl,
    this.dmRecipientId,
    this.dmRecipientName,
    this.dmRecipientAvatarColor,
    this.dmConversationId,
  });

  String get sourceName => isFromGroup ? (groupName ?? 'Group') : (dmRecipientName ?? 'DM');

  /// Display label shown as the topic header.  Falls back to the source group /
  /// DM name so every message always has a non-empty group header.
  String get displayTopic => topicName.trim().isNotEmpty ? topicName.trim() : sourceName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'messageId': messageId,
        'message': message,
        'senderName': senderName,
        'timestamp': timestamp.toIso8601String(),
        'savedAt': savedAt.toIso8601String(),
        'isFromGroup': isFromGroup,
        'topicName': topicName,
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
      topicName: json['topicName'] as String? ?? '',
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
///
/// **Key design principle**: [topicName] is a display label only — it is NOT a
/// primary key.  Two threads saved with the same topic name are two distinct
/// records, each with their own unique [id].  No merging ever happens.
class SavedThread {
  final String id;
  /// User-supplied label — just for display / grouping.  Never used as a PK.
  final String topicName;
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
      topicName: json['topicName'] as String? ?? '',
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

// ─────────────────────────────────────────────────────────────────────────────
// Saved / bookmarked event
// ─────────────────────────────────────────────────────────────────────────────

/// Represents an event that the user bookmarked from the Events screen.
class SavedEvent {
  final String id;        // unique saved-record id
  final String eventId;   // original Event.id
  final String title;
  final String date;
  final String time;
  final String location;
  final String organiser;
  final String imageUrl;
  final bool isFree;
  final String price;
  final String category;
  final bool isOnline;
  final DateTime savedAt;

  SavedEvent({
    required this.id,
    required this.eventId,
    required this.title,
    required this.date,
    required this.time,
    required this.location,
    required this.organiser,
    required this.imageUrl,
    required this.isFree,
    required this.price,
    required this.category,
    required this.isOnline,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventId': eventId,
        'title': title,
        'date': date,
        'time': time,
        'location': location,
        'organiser': organiser,
        'imageUrl': imageUrl,
        'isFree': isFree,
        'price': price,
        'category': category,
        'isOnline': isOnline,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedEvent.fromJson(Map<String, dynamic> json) => SavedEvent(
        id: json['id'] as String,
        eventId: json['eventId'] as String? ?? '',
        title: json['title'] as String? ?? 'Event',
        date: json['date'] as String? ?? '',
        time: json['time'] as String? ?? '',
        location: json['location'] as String? ?? '',
        organiser: json['organiser'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        isFree: json['isFree'] as bool? ?? true,
        price: json['price'] as String? ?? '',
        category: json['category'] as String? ?? 'community',
        isOnline: json['isOnline'] as bool? ?? false,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
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
