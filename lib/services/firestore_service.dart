// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — FIRESTORE SERVICE  (FUTURE / NOT ACTIVE)
// ═══════════════════════════════════════════════════════════════════════════════
//
// ⚠️  STORAGE ARCHITECTURE — READ BEFORE USING ⚠️
//
// CURRENT DESIGN: All user-generated content is stored exclusively on the
// USER'S OWN DEVICE using BrowserStorage (SharedPreferences). Nothing is
// sent to or read from a remote server unless explicitly required.
//
// DATA STORED ON-DEVICE (SharedPreferences):
//   • Group & DM messages (text, media refs, reactions, thread replies)
//   • Polls (per group)
//   • Meetups (user-created)
//   • Events (bookmarks, drafts)
//   • Profile / onboarding data (name, postcode, children, bio, preferences)
//   • Saved messages & bookmarks
//   • Group memberships, pins, mutes
//   • Blocked users list
//   • Notification preferences
//   • Subscription state
//   • AI behaviour settings
//
// DATA THAT MANDATORILY REQUIRES BACKEND (minimum set):
//   • Authentication tokens only (Firebase Auth — login/logout/OTP)
//   • Subscription purchase receipts (Stripe/Apple/Google — payment verification)
//   • GDPR deletion requests (must be server-side confirmed)
//
// THIS FILE: Implements the complete Firestore gateway for when/if the app
// is extended to a multi-device/server-backed architecture. It is NOT
// currently imported or instantiated by any screen or service.
// DO NOT import this file into screens unless intentionally migrating a
// specific feature to cloud storage.
//
// Collections (when active):
//   users, groups, group_messages, conversations, direct_messages,
//   meetups, marketplace, subscriptions, notifications
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/group.dart';
import '../models/subscription.dart';
import 'backend_api_service.dart';
import 'default_group_service.dart';
import 'huddl_notification_service.dart';
import 'subscription_service.dart';

class FirestoreService {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final FirestoreService _instance = FirestoreService._();
  factory FirestoreService() => _instance;
  FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ═════════════════════════════════════════════════════════════════════════
  // USER PROFILE
  // ═════════════════════════════════════════════════════════════════════════

  /// Get the current user's Firestore profile.
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final uid = _uid;
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  /// Get a user profile by ID.
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final doc = await _db.collection('users_public').doc(userId).get();
    return doc.exists ? doc.data() : null;
  }

  /// Stream the current user's profile (for real-time updates).
  Stream<Map<String, dynamic>?> userProfileStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(null);
    return _db.collection('users').doc(uid).snapshots().map(
          (snap) => snap.exists ? snap.data() : null,
        );
  }

  /// Update user profile fields.
  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    final uid = _uid;
    if (uid == null) return;
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('users').doc(uid).update(data);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // GROUPS
  // ═════════════════════════════════════════════════════════════════════════

  /// Get all groups the current user is a member of.
  Future<List<Group>> getMyGroups() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .get();
    return snap.docs.map((d) => _groupFromFirestore(d)).toList()
      ..sort((a, b) =>
          (b.lastMessageTime ?? DateTime(2000)).compareTo(a.lastMessageTime ?? DateTime(2000)));
  }

  /// Real-time stream of groups the [uid] belongs to.
  /// Fires whenever any group's lastMessage / lastMessageTime changes so the
  /// groups list re-sorts instantly when another user sends a message.
  Stream<List<Group>> myGroupsStream(String uid) {
    return _db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => _groupFromFirestore(d)).toList());
  }

  /// Get all public groups (for Discover tab).
  Future<List<Group>> getDiscoverGroups() async {
    final snap = await _db
        .collection('groups')
        .where('privacy', isEqualTo: 'public')
        .get();
    return snap.docs.map((d) => _groupFromFirestore(d)).toList()
      ..sort((a, b) => b.memberCount.compareTo(a.memberCount));
  }

  /// Get a single group by ID.
  Future<Group?> getGroup(String groupId) async {
    final doc = await _db.collection('groups').doc(groupId).get();
    return doc.exists ? _groupFromFirestore(doc) : null;
  }

  /// Stream a group for real-time updates (member count, last message, etc.).
  Stream<Group?> groupStream(String groupId) {
    return _db.collection('groups').doc(groupId).snapshots().map(
          (snap) => snap.exists ? _groupFromFirestore(snap) : null,
        );
  }

  /// Join a group — keeps memberIds[] and members[] in sync.
  Future<void> joinGroup(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('groups').doc(groupId).update({
      'memberIds': FieldValue.arrayUnion([uid]),
      'members':   FieldValue.arrayUnion([uid]),
      'memberCount': FieldValue.increment(1),
    });
  }

  /// Leave a group — keeps memberIds[] and members[] in sync.
  Future<void> leaveGroup(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('groups').doc(groupId).update({
      'memberIds': FieldValue.arrayRemove([uid]),
      'members':   FieldValue.arrayRemove([uid]),
      'memberCount': FieldValue.increment(-1),
    });
  }

  /// Create a new group.
  Future<String> createGroup(Map<String, dynamic> groupData) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    groupData['creatorId'] = uid;
    // Canonical read field used everywhere in the codebase
    groupData['memberIds'] = [uid];
    // Unified write: keep members[] in sync with memberIds[] from the start
    // (the admin-role system reads members[], legacy reads use memberIds[])
    groupData['members'] = groupData['members'] ?? [uid];
    groupData['createdAt'] = FieldValue.serverTimestamp();
    groupData['lastMessageTime'] = FieldValue.serverTimestamp();
    final ref = await _db.collection('groups').add(groupData);
    // Also set the document ID inside the document
    await ref.update({'id': ref.id});
    return ref.id;
  }

  /// Returns the correct image URL for a group loaded from Firestore.
  ///
  /// For default borough groups (isImageLocked=true) the imageUrl stored in
  /// Firestore may be stale — written by older builds that used a broken
  /// year-based rotation causing multiple groups to share the same photo.
  ///
  /// If the stored URL is already a local assets/ path we trust it only if
  /// it was written by the current build. Since we can't tell which build wrote
  /// it, we always re-derive from the group name so the result is deterministic
  /// and consistent, then let DefaultGroupService's sequential counter handle
  /// uniqueness during local creation.
  ///
  /// For user-created groups (isImageLocked=false) Firestore is the source
  /// of truth — the image was chosen by the user.
  static String _resolveGroupImageUrl(
      String groupId, String name, String storedUrl, bool isImageLocked) {
    if (!isImageLocked) return storedUrl;
    // Always re-derive from group name for locked default groups.
    // _migrateImageUrl is deterministic per name so the same group always
    // gets the same image across devices and sessions.
    return DefaultGroupService.correctImageUrl(name, storedUrl);
  }

  Group _groupFromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final uid = _uid;
    final memberIds = List<String>.from(d['memberIds'] ?? []);
    final isJoined = uid != null && memberIds.contains(uid);

    DateTime? lastMsgTime;
    final lmt = d['lastMessageTime'];
    if (lmt is Timestamp) {
      lastMsgTime = lmt.toDate();
    } else if (lmt is String) {
      lastMsgTime = DateTime.tryParse(lmt);
    }

    return Group(
      id: doc.id,
      name: d['name'] as String? ?? '',
      description: d['description'] as String? ?? '',
      // For default borough groups (isImageLocked=true), always re-derive the
      // image from the group name. This corrects any stale URL written by older
      // builds that used a broken year-based rotation system where multiple
      // groups visible to the same user shared the same photo.
      imageUrl: _resolveGroupImageUrl(
        doc.id,
        d['name'] as String? ?? '',
        d['imageUrl'] as String? ?? '',
        d['isImageLocked'] as bool? ?? false,
      ),
      memberCount: memberIds.isNotEmpty ? memberIds.length : (d['memberCount'] as int? ?? 0),
      category: d['category'] as String? ?? 'General',
      isJoined: isJoined,
      lastMessage: d['lastMessage'] as String?,
      lastSenderName: d['lastSenderName'] as String?,
      lastMessageTime: lastMsgTime,
      unreadCount: 0, // Real unread count would use per-user subcollection
      isImageLocked: d['isImageLocked'] as bool? ?? false,
      targetAudience: List<String>.from(d['targetAudience'] ?? []),
      privacy: _parseGroupPrivacy(d['privacy'] as String?),
      parentGroupId: d['parentGroupId'] as String?,
      parentGroupName: d['parentGroupName'] as String?,
      creatorId: d['creatorId'] as String?,
      creatorName: d['creatorName'] as String?,
      creatorBorough: d['borough'] as String?      // canonical
          ?? d['creatorBorough'] as String?,         // legacy fallback
      invitedMemberIds: List<String>.from(d['invitedMemberIds'] ?? []),
    );
  }

  /// Resolves a display name from a Firestore user profile map.
  /// Priority: firstName+lastName → name field → empty string.
  /// Callers use `.isNotEmpty ? name : 'Anonymous'` where needed.
  String _resolveDisplayName(Map<String, dynamic>? profile) {
    if (profile == null) return '';
    final first = (profile['firstName'] as String? ?? '').trim();
    final last  = (profile['lastName']  as String? ?? '').trim();
    final full  = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    // Fallback: single 'name' field (used on some profile paths)
    return (profile['name'] as String? ?? '').trim();
  }

  GroupPrivacy _parseGroupPrivacy(String? val) {
    switch (val) {
      case 'private_':
      case 'private':
        return GroupPrivacy.private_;
      case 'group':
        return GroupPrivacy.group;
      default:
        return GroupPrivacy.public;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // GROUP MESSAGES
  // ═════════════════════════════════════════════════════════════════════════

  /// Stream messages for a group in real-time (ordered newest-first).
  /// NOTE: No orderBy to avoid requiring a composite Firestore index —
  /// sorting is done in the app after fetching.
  Stream<List<Map<String, dynamic>>> groupMessagesStream(String groupId) {
    return _db
        .collection('group_messages')
        .where('groupId', isEqualTo: groupId)
        .limit(100)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            // Convert Timestamp to ISO string for model compatibility
            if (data['timestamp'] is Timestamp) {
              data['timestamp'] =
                  (data['timestamp'] as Timestamp).toDate().toIso8601String();
            }
            return data;
          }).toList();
          // Sort oldest-first in app (avoids composite Firestore index requirement)
          list.sort((a, b) {
            final ta = a['timestamp'] as String? ?? '';
            final tb = b['timestamp'] as String? ?? '';
            return ta.compareTo(tb);
          });
          return list;
        });
  }

  /// Send a message to a group.
  /// Send a message to a group and return the real Firestore document ID.
  /// Callers MUST use the returned ID to key the local optimistic message so
  /// that emoji reactions (which write to group_messages/{docId}) work correctly
  /// on the sender's own device.
  Future<String> sendGroupMessage({
    required String groupId,
    required String message,
    String? replyToText,
    String? replyToSender,
    String? audioUrl,
    int? audioDuration,
    String? type,
    // Image / location fields
    String? imageUrl,
    double? latitude,
    double? longitude,
    String? locationLabel,
    String? liveUntil,    // ISO-8601 expiry for live_location type
    // Contact fields
    String? contactName,
    String? contactPhone,
    // Document fields
    String? documentUrl,
    String? documentName,
    int? documentSize,
    String? documentMimeType,
    // Poll fields
    String? pollQuestion,
    List<String>? pollOptions,
    bool? pollAllowMultiple,
    String? pollExpiresAt,
    bool? pollIsCalendarMode,
    /// The `polls/{pollId}` document ID — written back to the group_messages
    /// doc after the poll/ doc is created, so other devices can resolve it.
    String? pollFirestoreId,
  }) async {
    final uid = _uid;
    if (uid == null) return '';
    final profile = await getCurrentUserProfile();
    final senderName = _resolveDisplayName(profile);

    final msgData = {
      'groupId': groupId,
      'senderId': uid,
      'senderName': senderName.isNotEmpty ? senderName : 'Anonymous',
      'senderAvatar': profile?['photoUrl'] ?? '',
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'reactions': <String, dynamic>{},
      'pinned': false,
      'isSystem': false,
      'isMeetupCard': false,
      'attachments': <String>[],
      'replyToText': replyToText,
      'replyToSender': replyToSender,
      'meetupData': null,
      'type': type ?? 'text',
      'audioUrl': audioUrl,
      'audioDuration': audioDuration,
      // Image / location — null fields omitted so Firestore docs stay lean
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationLabel != null) 'locationLabel': locationLabel,
      if (liveUntil != null) 'liveUntil': liveUntil,
      'liveExpired': false,
      // Contact
      if (contactName != null) 'contactName': contactName,
      if (contactPhone != null) 'contactPhone': contactPhone,
      // Document
      if (documentUrl != null) 'documentUrl': documentUrl,
      if (documentName != null) 'documentName': documentName,
      if (documentSize != null) 'documentSize': documentSize,
      if (documentMimeType != null) 'documentMimeType': documentMimeType,
      // Poll
      if (pollQuestion != null) 'pollQuestion': pollQuestion,
      if (pollOptions != null) 'pollOptions': pollOptions,
      if (pollAllowMultiple != null) 'pollAllowMultiple': pollAllowMultiple,
      if (pollExpiresAt != null) 'pollExpiresAt': pollExpiresAt,
      if (pollIsCalendarMode != null) 'pollIsCalendarMode': pollIsCalendarMode,
      if (pollFirestoreId != null) 'pollFirestoreId': pollFirestoreId,
    };

    final ref = await _db.collection('group_messages').add(msgData);
    await ref.update({'id': ref.id});

    // Update the group's last message
    await _db.collection('groups').doc(groupId).update({
      'lastMessage': message,
      'lastSenderName': senderName,
      'lastMessageTime': FieldValue.serverTimestamp(),
    });

    // ── Fan-out push + in-app notifications to group members ─────────────
    try {
      final groupSnap = await _db.collection('groups').doc(groupId).get();
      final groupData = groupSnap.data() ?? {};
      final groupName = groupData['name'] as String? ?? 'Group message';
      final groupImageUrl = groupData['imageUrl'] as String? ?? '';
      final displayName = senderName.isNotEmpty ? senderName : 'Someone';
      final memberIds = List<String>.from(groupData['memberIds'] ?? []);
      final otherMembers = memberIds.where((id) => id != uid).toList();

      // Push notification via backend
      unawaited(
        BackendApiService().notifyGroupMessage(
          groupId: groupId,
          groupName: groupName,
          senderName: displayName,
          messagePreview: message,
        ),
      );

      // In-app Firestore notification
      if (otherMembers.isNotEmpty) {
        final isVoice = (type == 'voice_note') ||
            (audioUrl != null && audioUrl.isNotEmpty);
        final senderPhotoUrl =
            (profile?['photoUrl'] as String? ?? '').isNotEmpty
                ? profile!['photoUrl'] as String
                : null;
        if (isVoice) {
          unawaited(
            HuddlNotificationService().voiceMessageGroup(
              recipientIds: otherMembers,
              senderName: displayName,
              groupName: groupName,
              groupId: groupId,
              groupImageUrl: groupImageUrl.isNotEmpty ? groupImageUrl : null,
              senderPhotoUrl: senderPhotoUrl,
            ),
          );
        } else if (otherMembers.length == 1) {
          // Group has exactly 2 members total (sender + one other) — this is
          // a brand-new or very small group. Use the warmer first-message copy
          // to give the recipient a better first impression.
          unawaited(
            HuddlNotificationService().firstGroupMessage(
              recipientId: otherMembers.first,
              senderName: displayName,
              groupName: groupName,
              groupId: groupId,
              messagePreview: message,
            ),
          );
        } else {
          unawaited(
            HuddlNotificationService().newGroupMessage(
              recipientIds: otherMembers,
              senderName: displayName,
              groupName: groupName,
              groupId: groupId,
              messagePreview: message,
              groupImageUrl: groupImageUrl.isNotEmpty ? groupImageUrl : null,
              senderPhotoUrl: senderPhotoUrl,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[FirestoreService] push notify error: $e');
      }
    }

    return ref.id;
  }

  /// Patches latitude/longitude on an existing live_location message doc.
  /// Called every ~5 seconds by the sender's GPS stream.
  Future<void> updateGroupMessageLocation({
    required String messageId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _db.collection('group_messages').doc(messageId).update({
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[FirestoreService] live location update error: $e');
      }
    }
  }

  /// Marks a live_location message as expired (stops remote viewers tracking).
  Future<void> expireLiveLocationMessage(String messageId) async {
    try {
      await _db.collection('group_messages').doc(messageId).update({
        'liveExpired': true,
      });
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[FirestoreService] expire live location error: $e');
      }
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DM CONVERSATIONS & MESSAGES
  // ═════════════════════════════════════════════════════════════════════════

  /// Get all DM conversations for the current user.
  Future<List<Map<String, dynamic>>> getMyConversations() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _db
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .get();

    final list = snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      // Convert timestamps
      if (data['lastMessageAt'] is Timestamp) {
        data['lastMessageAt'] =
            (data['lastMessageAt'] as Timestamp).toDate().toIso8601String();
      }
      if (data['createdAt'] is Timestamp) {
        data['createdAt'] =
            (data['createdAt'] as Timestamp).toDate().toIso8601String();
      }
      return data;
    }).toList();

    // Sort by lastMessageAt descending
    list.sort((a, b) {
      final aTime = DateTime.tryParse(a['lastMessageAt'] ?? '') ?? DateTime(2000);
      final bTime = DateTime.tryParse(b['lastMessageAt'] ?? '') ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    return list;
  }

  /// Stream DM messages for a conversation.
  Stream<List<Map<String, dynamic>>> dmMessagesStream(String conversationId) {
    return _db
        .collection('direct_messages')
        .where('conversationId', isEqualTo: conversationId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              if (data['timestamp'] is Timestamp) {
                data['timestamp'] =
                    (data['timestamp'] as Timestamp).toDate().toIso8601String();
              }
              return data;
            }).toList());
  }

  /// Send a direct message.
  Future<void> sendDirectMessage({
    required String conversationId,
    required String message,
    String? replyToText,
    String? replyToSender,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final profile = await getCurrentUserProfile();
    final senderName = _resolveDisplayName(profile);

    final msgData = {
      'conversationId': conversationId,
      'senderId': uid,
      'senderName': senderName.isNotEmpty ? senderName : 'Anonymous',
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
      'type': 'text',
      'reactions': <String, dynamic>{},
      'replyToText': replyToText,
      'replyToSender': replyToSender,
      'imageUrl': null,
      'documentName': null,
      'documentSize': null,
      'latitude': null,
      'longitude': null,
      'locationLabel': null,
      'contactName': null,
      'contactPhone': null,
      'meetupData': null,
      'readAt': null,
    };

    final ref = await _db.collection('direct_messages').add(msgData);
    await ref.update({'id': ref.id});

    // Update conversation's last message
    await _db.collection('conversations').doc(conversationId).update({
      'lastMessage': message,
      'lastSenderId': uid,
      'lastSenderName': senderName,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  /// Create a new DM conversation (or return existing one).
  Future<String> getOrCreateConversation({
    required String otherUserId,
    required String otherUserName,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final profile = await getCurrentUserProfile();
    final myName = _resolveDisplayName(profile);

    // Check if conversation already exists
    final existing = await _db
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .get();

    for (final doc in existing.docs) {
      final participants = List<String>.from(doc.data()['participants'] ?? []);
      if (participants.contains(otherUserId) && participants.length == 2) {
        return doc.id;
      }
    }

    // Create new conversation
    final ref = await _db.collection('conversations').add({
      'participants': [uid, otherUserId],
      'participantNames': {uid: myName, otherUserId: otherUserName},
      'lastMessage': '',
      'lastSenderId': '',
      'lastSenderName': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'unreadCount': {uid: 0, otherUserId: 0},
      'isMuted': {uid: false, otherUserId: false},
    });
    await ref.update({'id': ref.id});
    return ref.id;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MEETUPS
  // ═════════════════════════════════════════════════════════════════════════

  /// Get all upcoming meetups.
  Future<List<Map<String, dynamic>>> getMeetups() async {
    final snap = await _db.collection('meetups').get();

    final list = snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      if (data['createdAt'] is Timestamp) {
        data['createdAt'] =
            (data['createdAt'] as Timestamp).toDate().toIso8601String();
      }
      return data;
    }).toList();

    // Sort by dateTime ascending (upcoming first)
    list.sort((a, b) {
      final aTime = DateTime.tryParse(a['dateTime'] ?? '') ?? DateTime(2099);
      final bTime = DateTime.tryParse(b['dateTime'] ?? '') ?? DateTime(2099);
      return aTime.compareTo(bTime);
    });

    return list;
  }

  /// Get meetups the current user is attending.
  Future<List<Map<String, dynamic>>> getMyMeetups() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _db
        .collection('meetups')
        .where('attendeeIds', arrayContains: uid)
        .get();

    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      if (data['createdAt'] is Timestamp) {
        data['createdAt'] =
            (data['createdAt'] as Timestamp).toDate().toIso8601String();
      }
      return data;
    }).toList();
  }

  /// RSVP to a meetup.
  Future<void> rsvpMeetup(String meetupId, {bool going = true}) async {
    final uid = _uid;
    if (uid == null) return;
    final profile = await getCurrentUserProfile();
    final name = _resolveDisplayName(profile);

    if (going) {
      await _db.collection('meetups').doc(meetupId).update({
        'attendeeIds': FieldValue.arrayUnion([uid]),
        'attendeeNames': FieldValue.arrayUnion([name]),
        'attendeeCount': FieldValue.increment(1),
      });

      // ── Notify organiser of new RSVP (fire-and-forget) ────────────────
      try {
        final meetupSnap = await _db.collection('meetups').doc(meetupId).get();
        final meetupData = meetupSnap.data() ?? {};
        final organiserId = meetupData['organiserId'] as String? ?? '';
        final meetupTitle = meetupData['title'] as String? ?? 'Meetup';
        if (organiserId.isNotEmpty && organiserId != uid) {
          unawaited(
            HuddlNotificationService().meetupRsvp(
              organiserId: organiserId,
              attendeeName: name.isNotEmpty ? name : 'Someone',
              meetupTitle: meetupTitle,
              meetupId: meetupId,
            ),
          );
        }
      } catch (e) {
        if (kDebugMode) {
          if (kDebugMode) debugPrint('[FirestoreService] meetupRsvp notif error: $e');
        }
      }
    } else {
      await _db.collection('meetups').doc(meetupId).update({
        'attendeeIds': FieldValue.arrayRemove([uid]),
        'attendeeNames': FieldValue.arrayRemove([name]),
        'attendeeCount': FieldValue.increment(-1),
      });
    }
  }

  /// Create a new meetup.
  Future<String> createMeetup(Map<String, dynamic> meetupData) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    meetupData['organiserId'] = uid;
    meetupData['createdAt'] = FieldValue.serverTimestamp();
    meetupData['attendeeIds'] = [uid];
    final ref = await _db.collection('meetups').add(meetupData);
    await ref.update({'id': ref.id});

    // ── Notify borough members about new meetup (fire-and-forget) ─────────
    try {
      final borough = meetupData['borough'] as String? ?? '';
      final meetupTitle = meetupData['title'] as String? ?? 'New meetup';
      final meetupDate = meetupData['date'] as String? ?? '';
      final meetupLocation = meetupData['location'] as String? ?? '';
      if (borough.isNotEmpty) {
        final usersSnap = await _db
            .collection('users')
            .where('borough', isEqualTo: borough)
            .get();
        final boroughUserIds =
            usersSnap.docs.map((d) => d.id).toList();
        if (boroughUserIds.isNotEmpty) {
          unawaited(
            HuddlNotificationService().newMeetupNearby(
              boroughUserIds: boroughUserIds,
              meetupTitle: meetupTitle,
              meetupId: ref.id,
              meetupDate: meetupDate,
              meetupLocation: meetupLocation,
              organiserId: uid,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[FirestoreService] newMeetupNearby notif error: $e');
      }
    }

    return ref.id;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MARKETPLACE
  // ═════════════════════════════════════════════════════════════════════════

  /// Get all active marketplace listings.
  Future<List<Map<String, dynamic>>> getMarketplaceListings() async {
    final snap = await _db
        .collection('marketplace')
        .where('status', isEqualTo: 'active')
        .get();

    final list = snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      if (data['createdAt'] is Timestamp) {
        data['createdAt'] =
            (data['createdAt'] as Timestamp).toDate().toIso8601String();
      }
      if (data['updatedAt'] is Timestamp) {
        data['updatedAt'] =
            (data['updatedAt'] as Timestamp).toDate().toIso8601String();
      }
      return data;
    }).toList();

    // Sort by createdAt descending (newest first)
    list.sort((a, b) {
      final aTime = DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime(2000);
      final bTime = DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    return list;
  }

  /// Get current user's marketplace listings.
  Future<List<Map<String, dynamic>>> getMyListings() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _db
        .collection('marketplace')
        .where('sellerId', isEqualTo: uid)
        .get();

    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  /// Create a marketplace listing.
  Future<String> createListing(Map<String, dynamic> listingData) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final profile = await getCurrentUserProfile();
    listingData['sellerId'] = uid;
    listingData['sellerName'] = _resolveDisplayName(profile);
    listingData['borough']       = profile?['borough'] ?? '';  // canonical field going forward
    listingData['sellerBorough']  = profile?['borough'] ?? '';  // legacy dual-write; remove after backfill
    listingData['status'] = 'active';
    listingData['viewCount'] = 0;
    listingData['favouriteCount'] = 0;
    listingData['createdAt'] = FieldValue.serverTimestamp();
    listingData['updatedAt'] = FieldValue.serverTimestamp();
    // ── Set listing expiry based on subscription tier ───────────────────────
    final ss = SubscriptionService();
    final durationDays = ss.listingDurationDays;
    if (!TierLimits.isUnlimited(durationDays)) {
      // Plus = 60 days, Free = 7 days; Partner = 999 (unlimited, no expiry set)
      listingData['expiresAt'] = Timestamp.fromDate(
        DateTime.now().add(Duration(days: durationDays)),
      );
    }
    // ───────────────────────────────────────────────────────────────────────
    final ref = await _db.collection('marketplace').add(listingData);
    await ref.update({'id': ref.id});
    return ref.id;
  }

  /// Increment view count on a listing.
  Future<void> incrementListingViews(String listingId) async {
    await _db.collection('marketplace').doc(listingId).update({
      'viewCount': FieldValue.increment(1),
    });
  }

  /// Update mutable fields on a listing (title, description, price, condition,
  /// category, ageStage, imageUrls).  Sets updatedAt to server timestamp.
  Future<void> updateListing(
      String listingId, Map<String, dynamic> fields) async {
    fields['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('marketplace').doc(listingId).update(fields);
  }

  /// Mark a listing as sold.
  Future<void> markListingSold(String listingId) async {
    await _db.collection('marketplace').doc(listingId).update({
      'status': 'sold',
      'soldAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Relist a previously sold listing (set status back to active).
  Future<void> relistListing(String listingId) async {
    await _db.collection('marketplace').doc(listingId).update({
      'status': 'active',
      'soldAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Hard-delete a listing document.
  Future<void> deleteListing(String listingId) async {
    await _db.collection('marketplace').doc(listingId).delete();
  }

  // ── Saved / favourites ──────────────────────────────────────────────────

  /// Toggle saved state for a listing.  Uses a `saved_items` subcollection
  /// on the user doc so it's per-user and doesn't pollute the listing doc.
  /// Returns the new isSaved state (true = saved, false = removed).
  Future<bool> toggleSavedItem(String listingId) async {
    final uid = _uid;
    if (uid == null) return false;
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('saved_items')
        .doc(listingId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      // Decrement listing's favouriteCount (best-effort, ignore errors)
      _db.collection('marketplace').doc(listingId).update({
        'favouriteCount': FieldValue.increment(-1),
      }).catchError((_) {});
      return false;
    } else {
      await ref.set({
        'listingId': listingId,
        'savedAt': FieldValue.serverTimestamp(),
      });
      _db.collection('marketplace').doc(listingId).update({
        'favouriteCount': FieldValue.increment(1),
      }).catchError((_) {});
      return true;
    }
  }

  /// Load the set of listing IDs saved by the current user.
  Future<Set<String>> loadMySavedListingIds() async {
    final uid = _uid;
    if (uid == null) return {};
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('saved_items')
        .get();
    return snap.docs.map((d) => d.id).toSet();
  }

  // ── Offers ──────────────────────────────────────────────────────────────

  /// Write a new offer to `marketplace/{listingId}/offers/{offerId}`.
  /// Also increments `offerCount` on the listing document.
  Future<void> submitOffer({
    required String listingId,
    required String offerId,
    required String itemTitle,
    required String buyerId,
    required String buyerName,
    required double amount,
    String? note,
  }) async {
    final batch = _db.batch();

    final offerRef = _db
        .collection('marketplace')
        .doc(listingId)
        .collection('offers')
        .doc(offerId);
    batch.set(offerRef, {
      'id': offerId,
      'itemId': listingId,
      'itemTitle': itemTitle,
      'buyerId': buyerId,
      'buyerName': buyerName,
      'amount': amount,
      'status': 'pending',
      'note': note ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final listingRef = _db.collection('marketplace').doc(listingId);
    batch.update(listingRef, {
      'offerCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Load all offers on a specific listing (seller view).
  Future<List<Map<String, dynamic>>> getOffersForListing(
      String listingId) async {
    final snap = await _db
        .collection('marketplace')
        .doc(listingId)
        .collection('offers')
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      if (data['createdAt'] is Timestamp) {
        data['createdAt'] =
            (data['createdAt'] as Timestamp).toDate().toIso8601String();
      }
      return data;
    }).toList();
  }

  /// Load all offers made by the current user across all listings (buyer view).
  Future<List<Map<String, dynamic>>> getMyOffers() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _db
        .collectionGroup('offers')
        .where('buyerId', isEqualTo: uid)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      if (data['createdAt'] is Timestamp) {
        data['createdAt'] =
            (data['createdAt'] as Timestamp).toDate().toIso8601String();
      }
      return data;
    }).toList();
  }

  /// Update the status of an offer (accepted / declined) and optionally
  /// record the seller's response message.
  Future<void> updateOfferStatus(
    String listingId,
    String offerId, {
    required String status, // 'accepted' | 'declined'
    String? responseMessage,
  }) async {
    await _db
        .collection('marketplace')
        .doc(listingId)
        .collection('offers')
        .doc(offerId)
        .update({
      'status': status,
      if (responseMessage != null && responseMessage.isNotEmpty)
        'responseMessage': responseMessage,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Load all offers for every listing owned by the current user (sell tab).
  Future<List<Map<String, dynamic>>> getOffersForMyListings() async {
    final uid = _uid;
    if (uid == null) return [];
    // Fetch own listing IDs first
    final listingSnap = await _db
        .collection('marketplace')
        .where('sellerId', isEqualTo: uid)
        .get();
    final ids = listingSnap.docs.map((d) => d.id).toList();
    if (ids.isEmpty) return [];

    // Fetch offers for each listing (batched in groups of 10 for Firestore `in` limit)
    final offers = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 < ids.length ? i + 10 : ids.length);
      for (final listingId in chunk) {
        final snap = await _db
            .collection('marketplace')
            .doc(listingId)
            .collection('offers')
            .get();
        for (final d in snap.docs) {
          final data = d.data();
          data['id'] = d.id;
          if (data['createdAt'] is Timestamp) {
            data['createdAt'] =
                (data['createdAt'] as Timestamp).toDate().toIso8601String();
          }
          offers.add(data);
        }
      }
    }
    return offers;
  }

  /// Returns the list of user IDs who have saved [listingId].
  ///
  /// Uses a collectionGroup query across all `users/{uid}/saved_items`
  /// subcollections filtered by `listingId`.  The parent document ID of each
  /// result is the user UID.
  Future<List<String>> getSavedByUserIds(String listingId) async {
    final snap = await _db
        .collectionGroup('saved_items')
        .where('listingId', isEqualTo: listingId)
        .get();
    return snap.docs
        .map((d) => d.reference.parent.parent?.id ?? '')
        .where((uid) => uid.isNotEmpty)
        .toList();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // NOTIFICATIONS
  // ═════════════════════════════════════════════════════════════════════════

  /// Get notifications for the current user.
  Future<List<Map<String, dynamic>>> getMyNotifications() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _db
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .get();

    final list = snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      if (data['createdAt'] is Timestamp) {
        data['createdAt'] =
            (data['createdAt'] as Timestamp).toDate().toIso8601String();
      }
      return data;
    }).toList();

    // Sort by createdAt descending
    list.sort((a, b) {
      final aTime = DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime(2000);
      final bTime = DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    return list;
  }

  /// Stream notifications for real-time updates.
  Stream<List<Map<String, dynamic>>> notificationsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              if (data['createdAt'] is Timestamp) {
                data['createdAt'] =
                    (data['createdAt'] as Timestamp).toDate().toIso8601String();
              }
              return data;
            }).toList());
  }

  /// Mark a notification as read.
  Future<void> markNotificationRead(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).update({
      'read': true,
    });
  }

  /// Get unread notification count.
  Future<int> getUnreadNotificationCount() async {
    final uid = _uid;
    if (uid == null) return 0;
    final snap = await _db
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .get();
    return snap.size;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SUBSCRIPTIONS
  // ═════════════════════════════════════════════════════════════════════════

  /// Get the current user's subscription.
  Future<Map<String, dynamic>?> getMySubscription() async {
    final uid = _uid;
    if (uid == null) return null;

    // Try direct document (Step 4 stores sub with userId as doc ID)
    final doc = await _db.collection('subscriptions').doc(uid).get();
    if (doc.exists) return doc.data();

    // Fallback: query by userId field (seed data uses random doc IDs)
    final snap = await _db
        .collection('subscriptions')
        .where('userId', isEqualTo: uid)
        .get();

    if (snap.docs.isNotEmpty) return snap.docs.first.data();
    return null;
  }

  /// Stream the current user's subscription for real-time updates.
  Stream<Map<String, dynamic>?> subscriptionStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(null);
    return _db.collection('subscriptions').doc(uid).snapshots().map(
          (snap) => snap.exists ? snap.data() : null,
        );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // COMMUNITY FEED (aggregated)
  // ═════════════════════════════════════════════════════════════════════════

  /// Build a community feed from recent groups, meetups, marketplace items.
  Future<List<Map<String, dynamic>>> getCommunityFeed() async {
    final feed = <Map<String, dynamic>>[];

    // Recent groups (last 10)
    final groups = await _db
        .collection('groups')
        .get();
    for (final doc in groups.docs.take(5)) {
      final d = doc.data();
      feed.add({
        'feedType': 'group',
        'id': doc.id,
        'title': d['name'] ?? '',
        'subtitle': '${d['memberCount'] ?? 0} members \u2022 ${d['borough'] ?? ''}',
        'imageUrl': d['imageUrl'] ?? '',
        'createdAt': d['createdAt'],
      });
    }

    // Upcoming meetups
    final meetups = await _db
        .collection('meetups')
        .get();
    for (final doc in meetups.docs.take(5)) {
      final d = doc.data();
      feed.add({
        'feedType': 'meetup',
        'id': doc.id,
        'title': d['title'] ?? '',
        'subtitle': '${d['dateDisplay'] ?? ''} \u2022 ${d['location'] ?? ''}',
        'imageUrl': d['imageUrl'] ?? '',
        'createdAt': d['createdAt'],
      });
    }

    // Recent marketplace items
    final items = await _db
        .collection('marketplace')
        .where('status', isEqualTo: 'active')
        .get();
    for (final doc in items.docs.take(5)) {
      final d = doc.data();
      final price = d['isFree'] == true
          ? 'Free'
          : '\u00a3${(d['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}';
      feed.add({
        'feedType': 'marketplace',
        'id': doc.id,
        'title': d['title'] ?? '',
        'subtitle': '$price \u2022 ${d['condition'] ?? ''}',
        'imageUrl': (d['images'] as List?)?.first ?? d['imageUrl'] ?? '',
        'createdAt': d['createdAt'],
      });
    }

    // Sort by createdAt descending
    feed.sort((a, b) {
      DateTime getTime(dynamic t) {
        if (t is Timestamp) return t.toDate();
        if (t is String) return DateTime.tryParse(t) ?? DateTime(2000);
        return DateTime(2000);
      }
      return getTime(b['createdAt']).compareTo(getTime(a['createdAt']));
    });

    return feed;
  }

  // ── Emoji reactions (cross-device) ───────────────────────────────────────

  /// Write a user's reaction onto the message doc.
  /// reactions field: { "emoji": count, ... }  — stored on group_messages doc.
  /// [reactorUid] is stored so we can track per-user reactions.
  Future<void> updateMessageReaction({
    required String messageId,
    required String emoji,
    required bool adding, // true = add, false = remove
  }) async {
    final uid = _uid;
    if (uid == null) return;
    // Guard: local optimistic IDs (msg_*, vm_*, local_pending_*, gm_contact_*,
    // sys_*, fs_poll_*, poll_*) are never real Firestore doc IDs — writing to
    // them would silently create phantom documents or throw.  Reactions on
    // messages whose ID hasn't been reconciled yet are skipped; the sender will
    // need to re-tap once the message has a real Firestore ID.
    final localPrefixes = [
      'msg_', 'vm_', 'local_pending_', 'gm_contact_',
      'sys_', 'fs_poll_', 'poll_',
    ];
    if (localPrefixes.any((p) => messageId.startsWith(p))) {
      if (kDebugMode) {
        if (kDebugMode) {
          debugPrint('[FirestoreService] updateMessageReaction: skipped local id $messageId');
        }
      }
      return;
    }
    try {
      final ref = _db.collection('group_messages').doc(messageId);
      if (adding) {
        // set(merge:true) never throws on a missing doc (belt-and-suspenders).
        await ref.set({
          'reactions': {emoji: FieldValue.increment(1)},
          'reactionUsers': {uid: emoji},
        }, SetOptions(merge: true));
      } else {
        await ref.update({
          'reactions.$emoji': FieldValue.increment(-1),
          'reactionUsers.$uid': FieldValue.delete(),
        });
      }
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[FirestoreService] updateMessageReaction error: $e');
      }
    }
  }

  // ── RSVP persistence (survives reinstall / cross-device) ─────────────────

  /// Write or remove a user's RSVP for a meetup.
  /// Collection: user_rsvps/{uid}/meetups/{meetupId}
  Future<void> saveRsvp(String meetupId, {required bool going}) async {
    final uid = _uid;
    if (uid == null) return;
    final ref = _db
        .collection('user_rsvps')
        .doc(uid)
        .collection('meetups')
        .doc(meetupId);
    if (going) {
      await ref.set({'meetupId': meetupId, 'going': true, 'updatedAt': FieldValue.serverTimestamp()});
    } else {
      await ref.delete();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // POLL FIRESTORE METHODS
  // Collection: polls/{pollId}
  //   question       : string
  //   pollType       : 'single' | 'multiple'
  //   createdByUid   : string
  //   createdByName  : string
  //   groupId        : string
  //   groupMsgId     : string  ← the group_messages doc ID (dedup key)
  //   createdAt      : timestamp
  //   closesAt       : timestamp | null
  //   isCalendarMode : bool
  //   options        : [ { id: string, label: string, voteCount: int } ]
  //   voters         : { uid: [optionId, …] }
  // ══════════════════════════════════════════════════════════════════════════

  /// Create a new poll document in `polls/` and return its ID.
  Future<String> createPoll({
    required String groupId,
    required String groupMsgId,
    required String question,
    required List<String> options,
    required bool allowMultiple,
    required bool isCalendarMode,
    DateTime? closesAt,
  }) async {
    final uid = _uid;
    if (uid == null) return '';
    final profile = await getCurrentUserProfile();
    final name = _resolveDisplayName(profile);

    final optionDocs = options.asMap().entries.map((e) => {
          'id': 'opt_${e.key}',
          'label': e.value,
          'voteCount': 0,
        }).toList();

    final data = <String, dynamic>{
      'question': question,
      'pollType': allowMultiple ? 'multiple' : 'single',
      'createdByUid': uid,
      'createdByName': name.isNotEmpty ? name : 'Anonymous',
      'groupId': groupId,
      'groupMsgId': groupMsgId,
      'createdAt': FieldValue.serverTimestamp(),
      'closesAt': closesAt != null ? Timestamp.fromDate(closesAt) : null,
      'isCalendarMode': isCalendarMode,
      'options': optionDocs,
      'voters': <String, dynamic>{},
    };

    final ref = await _db.collection('polls').add(data);
    await ref.update({'id': ref.id});
    return ref.id;
  }

  /// Stream a single poll document for real-time updates.
  Stream<DocumentSnapshot<Map<String, dynamic>>> pollStream(String pollId) =>
      _db.collection('polls').doc(pollId).snapshots();

  /// Submit or update a user's vote using a Firestore transaction.
  /// [selectedOptionIds] is a list of option IDs (e.g. ['opt_0', 'opt_2']).
  /// For single-choice polls, the list has exactly one element.
  Future<void> submitPollVote({
    required String pollId,
    required String uid,
    required List<String> selectedOptionIds,
  }) async {
    final ref = _db.collection('polls').doc(pollId);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;

      // Previous votes for this user
      final voters = Map<String, dynamic>.from(data['voters'] as Map? ?? {});
      final prevIds = List<String>.from(voters[uid] as List? ?? []);

      // Current options
      final rawOptions = List<Map<String, dynamic>>.from(
        (data['options'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      // Decrement counts for previously selected options
      for (final optId in prevIds) {
        final idx = rawOptions.indexWhere((o) => o['id'] == optId);
        if (idx >= 0) {
          final current = (rawOptions[idx]['voteCount'] as num).toInt();
          rawOptions[idx]['voteCount'] = (current - 1).clamp(0, 9999);
        }
      }

      // Increment counts for newly selected options
      for (final optId in selectedOptionIds) {
        final idx = rawOptions.indexWhere((o) => o['id'] == optId);
        if (idx >= 0) {
          final current = (rawOptions[idx]['voteCount'] as num).toInt();
          rawOptions[idx]['voteCount'] = current + 1;
        }
      }

      // Write updated voters map and options array
      voters[uid] = selectedOptionIds;
      txn.update(ref, {
        'options': rawOptions,
        'voters': voters,
      });
    });
  }

  /// Patch the `pollFirestoreId` field back onto a group_messages doc.
  /// Called from _openCreatePoll() after the polls/ doc is created, so that
  /// other devices can resolve the Firestore poll ID from the message doc.
  Future<void> patchGroupMessagePollId({
    required String groupMsgId,
    required String pollFirestoreId,
  }) async {
    if (groupMsgId.isEmpty || pollFirestoreId.isEmpty) return;
    try {
      await _db
          .collection('group_messages')
          .doc(groupMsgId)
          .update({'pollFirestoreId': pollFirestoreId});
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) {
          debugPrint('[FirestoreService] patchGroupMessagePollId error: $e');
        }
      }
    }
  }

  /// Soft-delete a poll (only poll creator should call this).
  Future<void> deletePoll(String pollId) async {
    try {
      await _db.collection('polls').doc(pollId).update({'deleted': true});
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[FirestoreService] deletePoll error: $e');
      }
    }
  }

  /// Return the set of meetup IDs this user has RSVP'd "going" to.
  Future<Set<String>> loadMyRsvpIds() async {
    final uid = _uid;
    if (uid == null) return {};
    try {
      final snap = await _db
          .collection('user_rsvps')
          .doc(uid)
          .collection('meetups')
          .where('going', isEqualTo: true)
          .get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (e) {
      if (kDebugMode) debugPrint('[FirestoreService] loadMyRsvpIds error: $e');
      return {};
    }
  }
}
