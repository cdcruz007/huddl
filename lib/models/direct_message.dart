/// Message delivery / read status — mirrors WhatsApp-style ticks
enum MessageStatus {
  /// Message is being sent (clock icon)
  sending,

  /// Message was sent to the server (single grey tick)
  sent,

  /// Message was delivered to the recipient's device (double grey ticks)
  delivered,

  /// Message was read by the recipient (double blue ticks)
  read,

  /// Message failed to send (red exclamation)
  error,
}

/// A single direct message between two users.
class DirectMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final DateTime timestamp;
  final bool isMe;
  final MessageStatus status;

  DirectMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
    this.isMe = false,
    this.status = MessageStatus.sent,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
        'isMe': isMe,
        'status': status.name,
      };

  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    return DirectMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isMe: json['isMe'] as bool? ?? false,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? 'sent'),
        orElse: () => MessageStatus.sent,
      ),
    );
  }

  DirectMessage copyWith({MessageStatus? status}) {
    return DirectMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      message: message,
      timestamp: timestamp,
      isMe: isMe,
      status: status ?? this.status,
    );
  }
}

/// Represents an ongoing DM conversation between the current user and another.
class DMConversation {
  final String id; // unique key, e.g. "dm_<memberId>"
  final String recipientId;
  final String recipientName;
  final String recipientAvatarColor; // hex colour string
  final String? lastMessage;
  final String? lastSenderName;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isTyping; // whether the recipient is typing

  DMConversation({
    required this.id,
    required this.recipientId,
    required this.recipientName,
    required this.recipientAvatarColor,
    this.lastMessage,
    this.lastSenderName,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isTyping = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'recipientId': recipientId,
        'recipientName': recipientName,
        'recipientAvatarColor': recipientAvatarColor,
        'lastMessage': lastMessage,
        'lastSenderName': lastSenderName,
        'lastMessageTime': lastMessageTime?.toIso8601String(),
        'unreadCount': unreadCount,
      };

  factory DMConversation.fromJson(Map<String, dynamic> json) {
    return DMConversation(
      id: json['id'] as String,
      recipientId: json['recipientId'] as String,
      recipientName: json['recipientName'] as String,
      recipientAvatarColor: json['recipientAvatarColor'] as String? ?? '#FF975C',
      lastMessage: json['lastMessage'] as String?,
      lastSenderName: json['lastSenderName'] as String?,
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.parse(json['lastMessageTime'] as String)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }

  DMConversation copyWith({
    String? lastMessage,
    String? lastSenderName,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isTyping,
  }) {
    return DMConversation(
      id: id,
      recipientId: recipientId,
      recipientName: recipientName,
      recipientAvatarColor: recipientAvatarColor,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSenderName: lastSenderName ?? this.lastSenderName,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isTyping: isTyping ?? this.isTyping,
    );
  }
}
