import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import '../models/group.dart';

/// Represents a group invitation sent to a user
class GroupInvitation {
  final String id;
  final String groupId;
  final String groupName;
  final String groupDescription;
  final String groupImageUrl;
  final String invitedByName;
  final String invitedById; // ID of the person who sent the invite
  final String targetMemberId; // ID of the person invited (recipient)
  final DateTime sentAt;
  final String status; // 'pending', 'accepted', 'declined'

  GroupInvitation({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.groupDescription,
    required this.groupImageUrl,
    required this.invitedByName,
    this.invitedById = 'current_user',
    this.targetMemberId = '',
    required this.sentAt,
    this.status = 'pending',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'groupName': groupName,
        'groupDescription': groupDescription,
        'groupImageUrl': groupImageUrl,
        'invitedByName': invitedByName,
        'invitedById': invitedById,
        'targetMemberId': targetMemberId,
        'sentAt': sentAt.toIso8601String(),
        'status': status,
      };

  factory GroupInvitation.fromJson(Map<String, dynamic> json) {
    return GroupInvitation(
      id: json['id'] as String,
      groupId: json['groupId'] as String,
      groupName: json['groupName'] as String,
      groupDescription: json['groupDescription'] as String? ?? '',
      groupImageUrl: json['groupImageUrl'] as String? ?? '',
      invitedByName: json['invitedByName'] as String? ?? 'Someone',
      invitedById: json['invitedById'] as String? ?? 'current_user',
      targetMemberId: json['targetMemberId'] as String? ?? '',
      sentAt: DateTime.parse(json['sentAt'] as String),
      status: json['status'] as String? ?? 'pending',
    );
  }

  GroupInvitation copyWith({String? status}) {
    return GroupInvitation(
      id: id,
      groupId: groupId,
      groupName: groupName,
      groupDescription: groupDescription,
      groupImageUrl: groupImageUrl,
      invitedByName: invitedByName,
      invitedById: invitedById,
      targetMemberId: targetMemberId,
      sentAt: sentAt,
      status: status ?? this.status,
    );
  }
}

/// Represents a simulated borough member who can be invited
class BoroughMember {
  final String id;
  final String name;
  final String? avatarUrl;
  final String parentType; // 'mum' or 'dad'
  final List<String> stagesOfLife;

  const BoroughMember({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.parentType,
    required this.stagesOfLife,
  });
}

/// A system message stored per group (join / leave events)
class GroupSystemMessage {
  final String groupId;
  final String userName;
  final String type; // 'joined', 'left', 'removed'
  final DateTime timestamp;

  GroupSystemMessage({
    required this.groupId,
    required this.userName,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'userName': userName,
        'type': type,
        'timestamp': timestamp.toIso8601String(),
      };

  factory GroupSystemMessage.fromJson(Map<String, dynamic> json) {
    return GroupSystemMessage(
      groupId: json['groupId'] as String,
      userName: json['userName'] as String,
      type: json['type'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  String get displayText {
    switch (type) {
      case 'joined':
        return '$userName has joined the chat';
      case 'left':
        return '$userName has left the chat';
      case 'removed':
        return '$userName was removed from the group';
      default:
        return '$userName $type';
    }
  }
}

/// Manages group invitations, joined groups, and system messages.
///
/// In a real app these would be in Firestore / a backend.
/// Here we simulate with local storage so the demo flows end-to-end.
class InvitationService {
  static final InvitationService _instance = InvitationService._internal();
  factory InvitationService() => _instance;
  InvitationService._internal();

  static const String _invitationsKey = 'group_invitations_v1';
  static const String _joinedGroupsKey = 'joined_groups_v2';
  static const String _systemMessagesKey = 'group_system_messages_v1';
  bool _isInitialized = false;

  /// All invitations for the current user (demo: single-user device)
  List<GroupInvitation> _invitations = [];

  /// Groups the user has explicitly joined (from Discover or accepted invite)
  /// Stored as Group JSON for full data preservation
  List<Group> _joinedGroups = [];

  /// System messages per group (join/leave events)
  List<GroupSystemMessage> _systemMessages = [];

  List<GroupInvitation> get invitations => List.unmodifiable(_invitations);

  /// Pending invitations that are meant FOR the current user (not by the current user)
  List<GroupInvitation> get pendingInvitations =>
      _invitations.where((i) => i.status == 'pending' && i.invitedById != 'current_user').toList();

  /// Accepted invitations that are meant FOR the current user
  List<GroupInvitation> get acceptedInvitations =>
      _invitations.where((i) => i.status == 'accepted' && i.invitedById != 'current_user').toList();

  /// Invitations sent BY the current user (for display as "sent" confirmations)
  List<GroupInvitation> get sentByCurrentUser =>
      _invitations.where((i) => i.invitedById == 'current_user').toList();
  List<Group> get joinedGroups => List.unmodifiable(_joinedGroups);
  List<GroupSystemMessage> get systemMessages => List.unmodifiable(_systemMessages);

  /// Initialize and load from storage
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      // Load invitations
      final raw = await BrowserStorage.getString(_invitationsKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _invitations =
            decoded.map((j) => GroupInvitation.fromJson(j as Map<String, dynamic>)).toList();
      }

      // Load joined groups
      final joinedRaw = await BrowserStorage.getString(_joinedGroupsKey);
      if (joinedRaw != null) {
        final List<dynamic> decoded = json.decode(joinedRaw);
        _joinedGroups =
            decoded.map((j) => Group.fromJson(j as Map<String, dynamic>)).toList();
      }

      // Load system messages
      final sysRaw = await BrowserStorage.getString(_systemMessagesKey);
      if (sysRaw != null) {
        final List<dynamic> decoded = json.decode(sysRaw);
        _systemMessages =
            decoded.map((j) => GroupSystemMessage.fromJson(j as Map<String, dynamic>)).toList();
      }

      _isInitialized = true;
      _log('Loaded ${_invitations.length} invitation(s), ${_joinedGroups.length} joined group(s), ${_systemMessages.length} system message(s)');
    } catch (e) {
      _log('Error loading data: $e');
      _isInitialized = true;
    }
  }

  Future<void> _saveInvitations() async {
    await BrowserStorage.setString(
      _invitationsKey,
      json.encode(_invitations.map((i) => i.toJson()).toList()),
    );
  }

  Future<void> _saveJoinedGroups() async {
    await BrowserStorage.setString(
      _joinedGroupsKey,
      json.encode(_joinedGroups.map((g) => g.toJson()).toList()),
    );
  }

  Future<void> _saveSystemMessages() async {
    await BrowserStorage.setString(
      _systemMessagesKey,
      json.encode(_systemMessages.map((m) => m.toJson()).toList()),
    );
  }

  /// Send invitations for a newly-created private group.
  /// These invitations are directed at specific members (targetMemberId),
  /// created by the current user (invitedById = 'current_user').
  Future<void> sendInvitations({
    required Group group,
    required List<String> invitedMemberIds,
    required String creatorName,
  }) async {
    await initialize();
    for (final memberId in invitedMemberIds) {
      final inv = GroupInvitation(
        id: 'inv_${group.id}_$memberId',
        groupId: group.id,
        groupName: group.name,
        groupDescription: group.description,
        groupImageUrl: group.imageUrl,
        invitedByName: creatorName,
        invitedById: 'current_user',
        targetMemberId: memberId,
        sentAt: DateTime.now(),
        status: 'pending',
      );
      // Avoid duplicates
      _invitations.removeWhere((i) => i.id == inv.id);
      _invitations.add(inv);
    }
    await _saveInvitations();
    _log('Sent ${invitedMemberIds.length} invitation(s) for group "${group.name}"');
  }

  /// Accept an invitation — the group will now appear in Messages tab
  Future<void> acceptInvitation(String invitationId) async {
    await initialize();
    final idx = _invitations.indexWhere((i) => i.id == invitationId);
    if (idx != -1) {
      final inv = _invitations[idx];
      _invitations[idx] = inv.copyWith(status: 'accepted');
      await _saveInvitations();

      // Add system message for joining
      await addSystemMessage(
        groupId: inv.groupId,
        userName: 'You',
        type: 'joined',
      );

      _log('Accepted invitation: $invitationId');
    }
  }

  /// Decline an invitation — remove it entirely
  Future<void> declineInvitation(String invitationId) async {
    await initialize();
    _invitations.removeWhere((i) => i.id == invitationId);
    await _saveInvitations();
    _log('Declined invitation: $invitationId');
  }

  /// Join a public group from Discover — persists to Messages tab
  Future<void> joinPublicGroup(Group group, String userName) async {
    await initialize();
    // Avoid duplicates
    if (_joinedGroups.any((g) => g.id == group.id)) return;

    final joinedGroup = group.copyWith(
      isJoined: true,
      lastMessage: '$userName has joined the chat',
      lastSenderName: 'System',
      lastMessageTime: DateTime.now(),
      unreadCount: 0,
    );
    _joinedGroups.add(joinedGroup);
    await _saveJoinedGroups();

    // Add system message
    await addSystemMessage(
      groupId: group.id,
      userName: userName,
      type: 'joined',
    );

    _log('Joined public group: "${group.name}"');
  }

  /// Check if a group has been joined
  bool isGroupJoined(String groupId) {
    return _joinedGroups.any((g) => g.id == groupId) ||
        _invitations.any((i) => i.groupId == groupId && i.status == 'accepted');
  }

  /// Leave a group (works for both public and private)
  Future<void> leaveGroup(String groupId, String userName) async {
    await initialize();
    _joinedGroups.removeWhere((g) => g.id == groupId);
    // Also mark any accepted invitation as removed
    _invitations.removeWhere((i) => i.groupId == groupId);
    await _saveJoinedGroups();
    await _saveInvitations();

    // Add system message
    await addSystemMessage(
      groupId: groupId,
      userName: userName,
      type: 'left',
    );

    _log('Left group: $groupId');
  }

  /// Remove a member from a private group (only creator can do this)
  Future<void> removeMember(String groupId, String memberName) async {
    await initialize();

    // Add system message
    await addSystemMessage(
      groupId: groupId,
      userName: memberName,
      type: 'removed',
    );

    _log('Removed $memberName from group: $groupId');
  }

  /// Add a system message to a group
  Future<void> addSystemMessage({
    required String groupId,
    required String userName,
    required String type,
  }) async {
    await initialize();
    _systemMessages.add(GroupSystemMessage(
      groupId: groupId,
      userName: userName,
      type: type,
      timestamp: DateTime.now(),
    ));
    await _saveSystemMessages();
  }

  /// Get all system messages for a specific group
  List<GroupSystemMessage> getGroupSystemMessages(String groupId) {
    return _systemMessages.where((m) => m.groupId == groupId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Invite additional members to an existing private group (post-creation)
  Future<void> inviteToExistingGroup({
    required Group group,
    required List<String> memberIds,
    required String creatorName,
  }) async {
    await sendInvitations(
      group: group,
      invitedMemberIds: memberIds,
      creatorName: creatorName,
    );

    // Add system messages for each invited member
    for (final memberId in memberIds) {
      final member = getBoroughMembers(null).firstWhere(
        (m) => m.id == memberId,
        orElse: () => const BoroughMember(
          id: '', name: 'Unknown', parentType: 'mum', stagesOfLife: [],
        ),
      );
      await addSystemMessage(
        groupId: group.id,
        userName: member.name,
        type: 'joined',
      );
    }
  }

  /// Generate a list of simulated borough members for the member picker.
  /// In production this would come from a Firestore query filtered by postcode.
  static List<BoroughMember> getBoroughMembers(String? borough) {
    return [
      BoroughMember(
        id: 'mem_emma', name: 'Emma Thompson',
        parentType: 'mum',
        stagesOfLife: ['expecting'],
      ),
      BoroughMember(
        id: 'mem_sophie', name: 'Sophie Williams',
        parentType: 'mum',
        stagesOfLife: ['parent'],
      ),
      BoroughMember(
        id: 'mem_james', name: 'James Carter',
        parentType: 'dad',
        stagesOfLife: ['parent'],
      ),
      BoroughMember(
        id: 'mem_olivia', name: 'Olivia Brown',
        parentType: 'mum',
        stagesOfLife: ['aspiring'],
      ),
      BoroughMember(
        id: 'mem_luke', name: 'Luke Anderson',
        parentType: 'dad',
        stagesOfLife: ['expecting'],
      ),
      BoroughMember(
        id: 'mem_anna', name: 'Anna Mitchell',
        parentType: 'mum',
        stagesOfLife: ['parent', 'expecting'],
      ),
      BoroughMember(
        id: 'mem_kate', name: 'Kate Rogers',
        parentType: 'mum',
        stagesOfLife: ['parent'],
      ),
      BoroughMember(
        id: 'mem_david', name: 'David Harris',
        parentType: 'dad',
        stagesOfLife: ['parent'],
      ),
      BoroughMember(
        id: 'mem_lucy', name: 'Lucy Taylor',
        parentType: 'mum',
        stagesOfLife: ['parent'],
      ),
      BoroughMember(
        id: 'mem_mark', name: 'Mark Robinson',
        parentType: 'dad',
        stagesOfLife: ['aspiring'],
      ),
      BoroughMember(
        id: 'mem_sarah', name: 'Sarah Clarke',
        parentType: 'mum',
        stagesOfLife: ['expecting'],
      ),
      BoroughMember(
        id: 'mem_tom', name: 'Tom Evans',
        parentType: 'dad',
        stagesOfLife: ['parent'],
      ),
    ];
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('InvitationService: $message');
    }
  }

  /// Clear all invitation data — used for GDPR account deletion.
  Future<void> clearAll() async {
    await BrowserStorage.remove(_invitationsKey);
    await BrowserStorage.remove(_joinedGroupsKey);
    await BrowserStorage.remove(_systemMessagesKey);
  }
}
