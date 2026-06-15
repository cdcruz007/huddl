/// Privacy level for a group — mirrors MeetupPrivacy for consistency.
enum GroupPrivacy { public, group, private_ }

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

  /// Privacy level: public / group (visible to members of a parent group) / private (invite-only)
  final GroupPrivacy privacy;

  /// Backward-compat getter so old code checking `isPrivate` still works.
  bool get isPrivate => privacy == GroupPrivacy.private_;

  /// When privacy == group, the parent group whose members can see this group.
  final String? parentGroupId;
  final String? parentGroupName;

  /// Creator identification — used for borough matching and admin rights
  final String? creatorId;
  final String? creatorName;
  final String? creatorBorough;

  /// IDs of members explicitly invited to a private group.
  /// Used to show private groups on the Discover tab only to those invitees.
  final List<String> invitedMemberIds;

  /// AI-generated one-line tagline derived from the creator's group description.
  /// Generated at creation time via Gemini/Vertex AI and stored on the document.
  /// Displayed beneath the group name in Discover cards.
  final String? aiTagline;

  /// Semantic group type: 'resident' for system-created cohort groups
  /// (borough + birth-year cohorts), 'interest' for user-created groups.
  /// Null on un-backfilled docs — callers must treat null as unknown, falling
  /// back to isImageLocked inference during the migration window.
  final String? groupType;

  /// Birth year of the cohort (resident groups only). Stored as int so it is
  /// directly sortable without string parsing. Null for interest groups or
  /// un-backfilled resident groups (use the name regex as fallback).
  final int? birthYear;

  /// Geographic level of this resident group.
  /// 'borough' — keyed on borough name (all existing groups).
  /// 'ward'    — keyed on ward name (sub-borough split by elastic engine).
  /// 'region'  — keyed on region name (roll-up above borough by elastic engine).
  /// Null on un-backfilled docs — callers must treat null as 'borough'
  /// during the migration window.
  final String? level;

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
    this.privacy = GroupPrivacy.public,
    this.parentGroupId,
    this.parentGroupName,
    this.creatorId,
    this.creatorName,
    this.creatorBorough,
    this.invitedMemberIds = const [],
    this.aiTagline,
    this.groupType,
    this.birthYear,
    this.level,
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
      'privacy': privacy.name, // 'public', 'group', or 'private_'
      'parentGroupId': parentGroupId,
      'parentGroupName': parentGroupName,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'borough': creatorBorough,        // canonical field going forward
      'creatorBorough': creatorBorough,  // legacy dual-write; remove after backfill
      'invitedMemberIds': invitedMemberIds,
      if (aiTagline != null && aiTagline!.isNotEmpty) 'aiTagline': aiTagline,
      if (groupType != null) 'groupType': groupType,
      if (birthYear != null) 'birthYear': birthYear,
      if (level != null) 'level': level,
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
      privacy: _parseGroupPrivacy(json),
      parentGroupId: json['parentGroupId'] as String?,
      parentGroupName: json['parentGroupName'] as String?,
      creatorId: json['creatorId'] as String?,
      creatorName: json['creatorName'] as String?,
      creatorBorough: json['borough'] as String?      // canonical
          ?? json['creatorBorough'] as String?,         // legacy fallback
      invitedMemberIds: (json['invitedMemberIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      aiTagline: json['aiTagline'] as String?,
      groupType: json['groupType'] as String?,
      birthYear: json['birthYear'] as int?,
      level: json['level'] as String?,
    );
  }

  /// Parse privacy from JSON supporting both new enum and legacy boolean
  static GroupPrivacy _parseGroupPrivacy(Map<String, dynamic> json) {
    final privacyStr = json['privacy'] as String?;
    if (privacyStr != null) {
      switch (privacyStr) {
        case 'group':
          return GroupPrivacy.group;
        case 'private_':
          return GroupPrivacy.private_;
        default:
          return GroupPrivacy.public;
      }
    }
    // Legacy: fall back to boolean isPrivate
    final legacy = json['isPrivate'] as bool? ?? false;
    return legacy ? GroupPrivacy.private_ : GroupPrivacy.public;
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
    GroupPrivacy? privacy,
    String? parentGroupId,
    String? parentGroupName,
    String? creatorId,
    String? creatorName,
    String? creatorBorough,
    List<String>? invitedMemberIds,
    String? aiTagline,
    String? groupType,
    int? birthYear,
    String? level,
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
      privacy: privacy ?? this.privacy,
      parentGroupId: parentGroupId ?? this.parentGroupId,
      parentGroupName: parentGroupName ?? this.parentGroupName,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      creatorBorough: creatorBorough ?? this.creatorBorough,
      invitedMemberIds: invitedMemberIds ?? this.invitedMemberIds,
      aiTagline: aiTagline ?? this.aiTagline,
      groupType: groupType ?? this.groupType,
      birthYear: birthYear ?? this.birthYear,
      level: level ?? this.level,
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
  final bool isGroupCard; // group invite card message
  final Map<String, dynamic>? groupData; // full group data for card rendering
  final bool isItemCard; // item for sale card message
  final Map<String, dynamic>? itemData; // full item data for card rendering
  final bool isEventCard; // event invite card message
  final Map<String, dynamic>? eventData; // full event data for card rendering
  final bool isVoiceNote; // voice note message
  final String? audioUrl;  // Firebase Storage URL for voice note
  final int? audioDuration; // voice note duration in seconds

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
    this.isGroupCard = false,
    this.groupData,
    this.isItemCard = false,
    this.itemData,
    this.isEventCard = false,
    this.eventData,
    this.isVoiceNote = false,
    this.audioUrl,
    this.audioDuration,
  });
}
