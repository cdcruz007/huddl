// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL CONNECT — REALTIME DM SERVICE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Replaces the local BrowserStorage DM system with Firestore-backed real-time
// messaging between two real users.
//
// Firestore schema:
//
//   conversations/{conversationId}
//     participants: [uid1, uid2]          -- array for arrayContains queries
//     participantNames: {uid: name, ...}
//     participantAvatars: {uid: url, ...}
//     lastMessage: String
//     lastSenderId: String
//     lastSenderName: String
//     lastMessageAt: Timestamp
//     unreadCount: {uid: int, ...}
//     borough: String                     -- hyperlocal enforcement
//     createdAt: Timestamp
//
//   conversations/{conversationId}/messages/{messageId}
//     senderId: String
//     senderName: String
//     message: String
//     timestamp: Timestamp
//     type: String ('text','image','document','location','contact','meetupInvite')
//     status: String ('sent','delivered','read')
//     reactions: {emoji: int, ...}
//     replyToText: String?
//     replyToSender: String?
//     imageUrl: String?
//     meetupData: Map?
//     groupData: Map?
//     itemData: Map?
//     eventData: Map?
//
// HYPERLOCAL RULE: conversations have a borough field set at creation time.
// Only users with the same borough can create a conversation (enforced in
// getOrCreateConversation). The security rules further enforce this.
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'huddl_user_service.dart';
import 'postcode_service.dart';
import 'onboarding_data_service.dart';

class RealtimeDMService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final RealtimeDMService _instance = RealtimeDMService._internal();
  factory RealtimeDMService() => _instance;
  RealtimeDMService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final HuddlUserService _userService = HuddlUserService();
  final PostcodeService _postcodeService = PostcodeService();
  final OnboardingDataService _onboarding = OnboardingDataService();

  String? get _uid => _auth.currentUser?.uid;

  // ── Get or create a conversation ──────────────────────────────────────────

  /// Returns the conversationId for a DM between the current user and
  /// [otherUserId]. Creates the conversation document if it doesn't exist.
  /// Enforces the borough-match rule.
  Future<String?> getOrCreateConversation(String otherUserId) async {
    final uid = _uid;
    if (uid == null) {
      _log('getOrCreateConversation: not authenticated');
      return null;
    }

    try {
      // Check for existing conversation
      final existing = await _findExistingConversation(uid, otherUserId);
      if (existing != null) {
        _log('Found existing conversation: $existing');
        return existing;
      }

      // Look up both users
      final me = await _userService.getUser(uid);
      final other = await _userService.getUser(otherUserId);

      if (me == null || other == null) {
        _log('getOrCreateConversation: user profile missing — me=${me?.uid} other=${other?.uid}');
        return null;
      }

      // ── HYPERLOCAL GATE ──────────────────────────────────────────────────
      // Both users must be in the same borough to start a DM.
      // We resolve borough from onboarding as fallback if Firestore profile
      // has an empty borough (e.g. profile was created before borough sync).
      String myBorough = me.borough;
      if (myBorough.isEmpty) {
        await _onboarding.initialize();
        myBorough = _postcodeService.getBoroughFromPostcode(_onboarding.postcode) ?? '';
      }

      final otherBorough = other.borough;

      if (myBorough.isNotEmpty &&
          otherBorough.isNotEmpty &&
          myBorough.toLowerCase() != otherBorough.toLowerCase()) {
        _log('BLOCKED: cross-borough DM attempt ($myBorough vs $otherBorough)');
        return 'blocked';
      }

      // Create conversation
      final conversationId = _conversationId(uid, otherUserId);
      await _db.collection('conversations').doc(conversationId).set({
        'id': conversationId,
        'participants': [uid, otherUserId],
        'participantNames': {uid: me.name, otherUserId: other.name},
        'participantAvatars': {uid: me.photoUrl, otherUserId: other.photoUrl},
        'lastMessage': '',
        'lastSenderId': '',
        'lastSenderName': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'borough': myBorough,
        'unreadCount': {uid: 0, otherUserId: 0},
      });

      _log('Created conversation $conversationId ($myBorough)');
      return conversationId;
    } catch (e) {
      _log('ERROR getOrCreateConversation: $e');
      return null;
    }
  }

  /// Deterministic conversation ID — same regardless of who initiates.
  String _conversationId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return 'conv_${sorted[0]}_${sorted[1]}';
  }

  Future<String?> _findExistingConversation(
      String uid, String otherUserId) async {
    // Use the deterministic ID first (fast path)
    final deterministic = _conversationId(uid, otherUserId);
    final doc = await _db.collection('conversations').doc(deterministic).get();
    if (doc.exists) return deterministic;

    // Fallback: query (handles legacy conversations)
    try {
      final snap = await _db
          .collection('conversations')
          .where('participants', arrayContains: uid)
          .get();

      for (final d in snap.docs) {
        final participants = List<String>.from(d.data()['participants'] ?? []);
        if (participants.contains(otherUserId) && participants.length == 2) {
          return d.id;
        }
      }
    } catch (e) {
      _log('_findExistingConversation query failed: $e');
    }
    return null;
  }

  // ── Send a message ─────────────────────────────────────────────────────────

  Future<bool> sendMessage({
    required String conversationId,
    required String message,
    String type = 'text',
    String? replyToText,
    String? replyToSender,
    String? imageUrl,
    String? documentName,
    int? documentSize,
    double? latitude,
    double? longitude,
    String? locationLabel,
    String? contactName,
    String? contactPhone,
    Map<String, dynamic>? meetupData,
    Map<String, dynamic>? groupData,
    Map<String, dynamic>? itemData,
    Map<String, dynamic>? eventData,
  }) async {
    final uid = _uid;
    if (uid == null) return false;

    try {
      final me = await _userService.getUser(uid);
      final senderName = me?.name ?? 'Unknown';

      final msgRef = _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(); // auto-ID

      final msgData = <String, dynamic>{
        'id': msgRef.id,
        'senderId': uid,
        'senderName': senderName,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'type': type,
        'status': 'sent',
        'reactions': <String, dynamic>{},
        'replyToText': replyToText,
        'replyToSender': replyToSender,
        'imageUrl': imageUrl,
        'documentName': documentName,
        'documentSize': documentSize,
        'latitude': latitude,
        'longitude': longitude,
        'locationLabel': locationLabel,
        'contactName': contactName,
        'contactPhone': contactPhone,
        'meetupData': meetupData,
        'groupData': groupData,
        'itemData': itemData,
        'eventData': eventData,
      };

      // Write message in subcollection
      await msgRef.set(msgData);

      // Build display text for conversation summary
      String displayText = message;
      if (groupData != null) {
        displayText = '👥 Group: ${groupData['name'] ?? 'Group'}';
      } else if (itemData != null) {
        displayText = '📦 Item: ${itemData['title'] ?? 'Item'}';
      } else if (meetupData != null) {
        displayText = '📅 Meetup: ${meetupData['title'] ?? 'Meetup'}';
      } else if (eventData != null) {
        displayText = '📅 Event: ${eventData['title'] ?? 'Event'}';
      } else if (type == 'image') {
        displayText = '📷 Photo';
      } else if (type == 'document') {
        displayText = '📄 ${documentName ?? 'Document'}';
      } else if (type == 'location') {
        displayText = '📍 Location';
      }

      // Update conversation summary (with unread increment for the OTHER participant)
      final convSnap = await _db.collection('conversations').doc(conversationId).get();
      final participants = List<String>.from(convSnap.data()?['participants'] ?? []);

      Map<String, dynamic> unreadUpdate = {};
      for (final p in participants) {
        if (p != uid) {
          unreadUpdate['unreadCount.$p'] = FieldValue.increment(1);
        }
      }

      await _db.collection('conversations').doc(conversationId).update({
        'lastMessage': displayText,
        'lastSenderId': uid,
        'lastSenderName': senderName,
        'lastMessageAt': FieldValue.serverTimestamp(),
        ...unreadUpdate,
      });

      _log('sendMessage: sent in $conversationId');
      return true;
    } catch (e) {
      _log('ERROR sendMessage: $e');
      return false;
    }
  }

  // ── Real-time message stream ───────────────────────────────────────────────

  /// Returns a real-time stream of messages for a conversation,
  /// ordered by timestamp ascending (oldest first).
  Stream<List<RealtimeDMMessage>> messagesStream(String conversationId) {
    return _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) {
      final uid = _uid ?? '';
      return snap.docs.map((doc) {
        return RealtimeDMMessage.fromFirestore(doc.data(), doc.id, uid);
      }).toList();
    });
  }

  // ── Real-time conversation list stream ────────────────────────────────────

  /// Returns a real-time stream of all conversations for the current user.
  Stream<List<RealtimeDMConversation>> conversationsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) =>
                RealtimeDMConversation.fromFirestore(doc.data(), doc.id, uid))
            .toList());
  }

  // ── Mark messages as read ─────────────────────────────────────────────────

  Future<void> markConversationRead(String conversationId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.collection('conversations').doc(conversationId).update({
        'unreadCount.$uid': 0,
      });
    } catch (e) {
      _log('ERROR markConversationRead: $e');
    }
  }

  // ── Toggle reaction ───────────────────────────────────────────────────────

  Future<void> toggleReaction(
      String conversationId, String messageId, String emoji) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final msgRef = _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId);

      final doc = await msgRef.get();
      final reactions =
          Map<String, dynamic>.from(doc.data()?['reactions'] ?? {});
      final key = '$emoji:$uid';

      if (reactions.containsKey(key)) {
        reactions.remove(key);
      } else {
        reactions[key] = true;
      }
      await msgRef.update({'reactions': reactions});
    } catch (e) {
      _log('ERROR toggleReaction: $e');
    }
  }

  // ── Logging ───────────────────────────────────────────────────────────────

  void _log(String msg) {
    if (kDebugMode) debugPrint('[RealtimeDMService] $msg');
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═════════════════════════════════════════════════════════════════════════════

class RealtimeDMMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final DateTime timestamp;
  final bool isMe;
  final String type;
  final String status;
  final Map<String, dynamic> reactions;
  final String? replyToText;
  final String? replyToSender;
  final String? imageUrl;
  final String? documentName;
  final int? documentSize;
  final double? latitude;
  final double? longitude;
  final String? locationLabel;
  final String? contactName;
  final String? contactPhone;
  final Map<String, dynamic>? meetupData;
  final Map<String, dynamic>? groupData;
  final Map<String, dynamic>? itemData;
  final Map<String, dynamic>? eventData;

  const RealtimeDMMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
    required this.isMe,
    required this.type,
    required this.status,
    required this.reactions,
    this.replyToText,
    this.replyToSender,
    this.imageUrl,
    this.documentName,
    this.documentSize,
    this.latitude,
    this.longitude,
    this.locationLabel,
    this.contactName,
    this.contactPhone,
    this.meetupData,
    this.groupData,
    this.itemData,
    this.eventData,
  });

  factory RealtimeDMMessage.fromFirestore(
      Map<String, dynamic> data, String id, String currentUid) {
    DateTime ts = DateTime.now();
    final rawTs = data['timestamp'];
    if (rawTs is Timestamp) {
      ts = rawTs.toDate();
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? ts;
    }

    return RealtimeDMMessage(
      id: id,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      message: data['message'] as String? ?? '',
      timestamp: ts,
      isMe: (data['senderId'] as String? ?? '') == currentUid,
      type: data['type'] as String? ?? 'text',
      status: data['status'] as String? ?? 'sent',
      reactions: Map<String, dynamic>.from(data['reactions'] ?? {}),
      replyToText: data['replyToText'] as String?,
      replyToSender: data['replyToSender'] as String?,
      imageUrl: data['imageUrl'] as String?,
      documentName: data['documentName'] as String?,
      documentSize: data['documentSize'] as int?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      locationLabel: data['locationLabel'] as String?,
      contactName: data['contactName'] as String?,
      contactPhone: data['contactPhone'] as String?,
      meetupData: data['meetupData'] != null
          ? Map<String, dynamic>.from(data['meetupData'])
          : null,
      groupData: data['groupData'] != null
          ? Map<String, dynamic>.from(data['groupData'])
          : null,
      itemData: data['itemData'] != null
          ? Map<String, dynamic>.from(data['itemData'])
          : null,
      eventData: data['eventData'] != null
          ? Map<String, dynamic>.from(data['eventData'])
          : null,
    );
  }
}

class RealtimeDMConversation {
  final String id;
  final String otherUserId;
  final String otherUserName;
  final String otherUserPhotoUrl;
  final String lastMessage;
  final String lastSenderName;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final String borough;

  const RealtimeDMConversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserPhotoUrl,
    required this.lastMessage,
    required this.lastSenderName,
    this.lastMessageAt,
    required this.unreadCount,
    required this.borough,
  });

  factory RealtimeDMConversation.fromFirestore(
      Map<String, dynamic> data, String id, String currentUid) {
    final participants = List<String>.from(data['participants'] ?? []);
    final otherUid = participants.firstWhere(
      (p) => p != currentUid,
      orElse: () => '',
    );
    final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
    final avatars = Map<String, dynamic>.from(data['participantAvatars'] ?? {});
    final unread = Map<String, dynamic>.from(data['unreadCount'] ?? {});

    DateTime? lastAt;
    final rawLat = data['lastMessageAt'];
    if (rawLat is Timestamp) {
      lastAt = rawLat.toDate();
    } else if (rawLat is String) {
      lastAt = DateTime.tryParse(rawLat);
    }

    return RealtimeDMConversation(
      id: id,
      otherUserId: otherUid,
      otherUserName: names[otherUid] as String? ?? 'Unknown',
      otherUserPhotoUrl: avatars[otherUid] as String? ?? '',
      lastMessage: data['lastMessage'] as String? ?? '',
      lastSenderName: data['lastSenderName'] as String? ?? '',
      lastMessageAt: lastAt,
      unreadCount: (unread[currentUid] as int?) ?? 0,
      borough: data['borough'] as String? ?? '',
    );
  }
}
