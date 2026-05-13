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
import 'backend_api_service.dart';
import 'huddl_notification_service.dart';

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
    final doc = await _db.collection('users').doc(userId).get();
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

  /// Join a group.
  Future<void> joinGroup(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('groups').doc(groupId).update({
      'memberIds': FieldValue.arrayUnion([uid]),
      'memberCount': FieldValue.increment(1),
    });
  }

  /// Leave a group.
  Future<void> leaveGroup(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('groups').doc(groupId).update({
      'memberIds': FieldValue.arrayRemove([uid]),
      'memberCount': FieldValue.increment(-1),
    });
  }

  /// Create a new group.
  Future<String> createGroup(Map<String, dynamic> groupData) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    groupData['creatorId'] = uid;
    groupData['memberIds'] = [uid];
    groupData['createdAt'] = FieldValue.serverTimestamp();
    groupData['lastMessageTime'] = FieldValue.serverTimestamp();
    final ref = await _db.collection('groups').add(groupData);
    // Also set the document ID inside the document
    await ref.update({'id': ref.id});
    return ref.id;
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
      imageUrl: d['imageUrl'] as String? ?? '',
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
      creatorBorough: d['creatorBorough'] as String?,
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
  Future<void> sendGroupMessage({
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
    // Contact fields
    String? contactName,
    String? contactPhone,
    // Document fields
    String? documentUrl,
    String? documentName,
    int? documentSize,
    // Poll fields
    String? pollQuestion,
    List<String>? pollOptions,
    bool? pollAllowMultiple,
    String? pollExpiresAt,
    bool? pollIsCalendarMode,
  }) async {
    final uid = _uid;
    if (uid == null) return;
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
      // Contact
      if (contactName != null) 'contactName': contactName,
      if (contactPhone != null) 'contactPhone': contactPhone,
      // Document
      if (documentUrl != null) 'documentUrl': documentUrl,
      if (documentName != null) 'documentName': documentName,
      if (documentSize != null) 'documentSize': documentSize,
      // Poll
      if (pollQuestion != null) 'pollQuestion': pollQuestion,
      if (pollOptions != null) 'pollOptions': pollOptions,
      if (pollAllowMultiple != null) 'pollAllowMultiple': pollAllowMultiple,
      if (pollExpiresAt != null) 'pollExpiresAt': pollExpiresAt,
      if (pollIsCalendarMode != null) 'pollIsCalendarMode': pollIsCalendarMode,
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
      if (kDebugMode) debugPrint('[FirestoreService] push notify error: $e');
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
        if (kDebugMode) debugPrint('[FirestoreService] meetupRsvp notif error: $e');
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
              organiserId: uid,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FirestoreService] newMeetupNearby notif error: $e');
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
    listingData['sellerBorough'] = profile?['borough'] ?? '';
    listingData['status'] = 'active';
    listingData['viewCount'] = 0;
    listingData['favouriteCount'] = 0;
    listingData['createdAt'] = FieldValue.serverTimestamp();
    listingData['updatedAt'] = FieldValue.serverTimestamp();
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
    try {
      final ref = _db.collection('group_messages').doc(messageId);
      if (adding) {
        await ref.update({
          'reactions.$emoji': FieldValue.increment(1),
          'reactionUsers.$uid': emoji, // tracks which emoji this user picked
        });
      } else {
        await ref.update({
          'reactions.$emoji': FieldValue.increment(-1),
          'reactionUsers.$uid': FieldValue.delete(),
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FirestoreService] updateMessageReaction error: $e');
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
