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

/// The type of content a message carries.
enum MessageType {
  text,
  image,
  document,
  location,
  contact,
  meetupInvite,
}

/// Safe cast helper - converts any Map type to Map<String, dynamic>
Map<String, dynamic>? _safeMap(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
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
  final String? replyToText;
  final String? replyToSender;

  /// Extended fields for rich message types
  final MessageType type;
  final String? imageUrl;       // for image messages
  final String? documentName;   // for document messages
  final int? documentSize;      // bytes
  final double? latitude;       // for location messages
  final double? longitude;
  final String? locationLabel;
  final String? contactName;    // for contact sharing
  final String? contactPhone;
  final Map<String, int> reactions; // emoji → count
  final Map<String, dynamic>? meetupData; // for meetup invite cards
  final Map<String, dynamic>? groupData;  // for group invite cards
  final Map<String, dynamic>? itemData;   // for item invite cards

  DirectMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
    this.isMe = false,
    this.status = MessageStatus.sent,
    this.replyToText,
    this.replyToSender,
    this.type = MessageType.text,
    this.imageUrl,
    this.documentName,
    this.documentSize,
    this.latitude,
    this.longitude,
    this.locationLabel,
    this.contactName,
    this.contactPhone,
    this.reactions = const {},
    this.meetupData,
    this.groupData,
    this.itemData,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
        'isMe': isMe,
        'status': status.name,
        'replyToText': replyToText,
        'replyToSender': replyToSender,
        'type': type.name,
        'imageUrl': imageUrl,
        'documentName': documentName,
        'documentSize': documentSize,
        'latitude': latitude,
        'longitude': longitude,
        'locationLabel': locationLabel,
        'contactName': contactName,
        'contactPhone': contactPhone,
        'reactions': reactions,
        'meetupData': meetupData,
        'groupData': groupData,
        'itemData': itemData,
      };

  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    Map<String, int> rxn = {};
    if (json['reactions'] != null) {
      // Safe cast: avoid crash when JSON returns Map<dynamic,dynamic>
      final rawReactions = json['reactions'];
      final reactionsMap = (rawReactions is Map<String, dynamic>)
          ? rawReactions
          : Map<String, dynamic>.from(rawReactions as Map);
      reactionsMap.forEach((k, v) {
        rxn[k] = (v as num).toInt();
      });
    }
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
      replyToText: json['replyToText'] as String?,
      replyToSender: json['replyToSender'] as String?,
      type: MessageType.values.firstWhere(
        (e) => e.name == (json['type'] as String? ?? 'text'),
        orElse: () => MessageType.text,
      ),
      imageUrl: json['imageUrl'] as String?,
      documentName: json['documentName'] as String?,
      documentSize: json['documentSize'] as int?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      locationLabel: json['locationLabel'] as String?,
      contactName: json['contactName'] as String?,
      contactPhone: json['contactPhone'] as String?,
      reactions: rxn,
      meetupData: _safeMap(json['meetupData']),
      groupData:  _safeMap(json['groupData']),
      itemData:   _safeMap(json['itemData']),
    );
  }

  DirectMessage copyWith({
    MessageStatus? status,
    Map<String, int>? reactions,
    String? message,
  }) {
    return DirectMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      message: message ?? this.message,
      timestamp: timestamp,
      isMe: isMe,
      status: status ?? this.status,
      replyToText: replyToText,
      replyToSender: replyToSender,
      type: type,
      imageUrl: imageUrl,
      documentName: documentName,
      documentSize: documentSize,
      latitude: latitude,
      longitude: longitude,
      locationLabel: locationLabel,
      contactName: contactName,
      contactPhone: contactPhone,
      reactions: reactions ?? this.reactions,
      meetupData: meetupData,
      groupData: groupData,   // ← was missing — caused groupData loss on status update
      itemData: itemData,     // ← was missing — caused itemData loss on status update
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
  final bool isMuted;
  final bool isOnline;

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
    this.isMuted = false,
    this.isOnline = false,
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
        'isMuted': isMuted,
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
      isMuted: json['isMuted'] as bool? ?? false,
    );
  }

  DMConversation copyWith({
    String? lastMessage,
    String? lastSenderName,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isTyping,
    bool? isMuted,
    bool? isOnline,
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
      isMuted: isMuted ?? this.isMuted,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
