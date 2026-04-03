class Group {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final int memberCount;
  final String category;
  final bool isJoined;
  final String? lastMessage;
  final String? lastSenderName;
  final DateTime? lastMessageTime;
  final int? unreadCount;
  /// When true the group image is set by the system and cannot be changed
  /// by any member, including group admins. Used for default borough groups.
  final bool isImageLocked;

  /// Target audience for the group (e.g. 'Aspiring parents', 'Mums', 'Dads')
  final List<String> targetAudience;

  /// When true, the group is private — not listed on the Discover tab.
  /// Members must be invited and accept the invite to join.
  final bool isPrivate;

  /// Creator identification — used for borough matching and admin rights
  final String? creatorId;
  final String? creatorName;
  final String? creatorBorough;

  Group({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.memberCount,
    required this.category,
    this.isJoined = false,
    this.lastMessage,
    this.lastSenderName,
    this.lastMessageTime,
    this.unreadCount,
    this.isImageLocked = false,
    this.targetAudience = const [],
    this.isPrivate = false,
    this.creatorId,
    this.creatorName,
    this.creatorBorough,
  });
  
  // JSON serialization for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'memberCount': memberCount,
      'category': category,
      'isJoined': isJoined,
      'lastMessage': lastMessage,
      'lastSenderName': lastSenderName,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
      'isImageLocked': isImageLocked,
      'targetAudience': targetAudience,
      'isPrivate': isPrivate,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'creatorBorough': creatorBorough,
    };
  }
  
  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      imageUrl: json['imageUrl'] as String,
      memberCount: json['memberCount'] as int,
      category: json['category'] as String,
      isJoined: json['isJoined'] as bool? ?? false,
      lastMessage: json['lastMessage'] as String?,
      lastSenderName: json['lastSenderName'] as String?,
      lastMessageTime: json['lastMessageTime'] != null 
          ? DateTime.parse(json['lastMessageTime'] as String)
          : null,
      unreadCount: json['unreadCount'] as int?,
      isImageLocked: json['isImageLocked'] as bool? ?? false,
      targetAudience: (json['targetAudience'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      isPrivate: json['isPrivate'] as bool? ?? false,
      creatorId: json['creatorId'] as String?,
      creatorName: json['creatorName'] as String?,
      creatorBorough: json['creatorBorough'] as String?,
    );
  }

  Group copyWith({
    String? id,
    String? name,
    String? description,
    String? imageUrl,
    int? memberCount,
    String? category,
    bool? isJoined,
    String? lastMessage,
    String? lastSenderName,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isImageLocked,
    List<String>? targetAudience,
    bool? isPrivate,
    String? creatorId,
    String? creatorName,
    String? creatorBorough,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      memberCount: memberCount ?? this.memberCount,
      category: category ?? this.category,
      isJoined: isJoined ?? this.isJoined,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSenderName: lastSenderName ?? this.lastSenderName,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isImageLocked: isImageLocked ?? this.isImageLocked,
      targetAudience: targetAudience ?? this.targetAudience,
      isPrivate: isPrivate ?? this.isPrivate,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      creatorBorough: creatorBorough ?? this.creatorBorough,
    );
  }
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String message;
  final DateTime timestamp;
  final bool isMe;
  final bool isSystem; // for join/leave system messages
  final String? replyToText;
  final String? replyToSender;
  final bool isMeetupCard; // meetup invite card message
  final Map<String, dynamic>? meetupData; // full meetup data for card rendering

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.message,
    required this.timestamp,
    this.isMe = false,
    this.isSystem = false,
    this.replyToText,
    this.replyToSender,
    this.isMeetupCard = false,
    this.meetupData,
  });
}
