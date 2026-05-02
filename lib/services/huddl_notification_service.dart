// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL NOTIFICATION SERVICE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Central service that writes every notification type to Firestore.
// The NotificationsSheet reads from this collection in real-time.
//
// Notification types (stored in 'type' field):
//   MESSAGING
//     new_dm                  — new direct message
//     new_group_message       — new group chat message
//     voice_message_dm        — voice note in DM
//     voice_message_group     — voice note in group
//     message_reaction        — someone reacted to your message
//     thread_reply            — someone replied in a thread
//
//   GROUPS & SOCIAL
//     group_invitation        — you were invited to a group
//     invitation_accepted     — your invitation was accepted
//     group_member_joined     — new member in a group you admin
//     post_liked              — someone liked your post
//     post_commented          — someone commented on your post
//     comment_replied         — someone replied to your comment
//     mention                 — you were mentioned
//     poll_created            — new poll in your group
//
//   EVENTS & MEETUPS
//     meetup_rsvp             — someone RSVP'd to your meetup
//     meetup_reminder         — reminder for upcoming meetup
//     new_meetup_nearby       — new meetup in your area
//     event_update            — an event you RSVP'd to was updated
//
//   MARKETPLACE
//     offer_received          — buyer made an offer on your listing
//     offer_accepted          — your offer was accepted
//     offer_declined          — your offer was declined
//     item_sold               — your listing sold
//     saved_item_sold         — a saved item is now sold
//     item_relisted           — a saved item was relisted
//
//   SYSTEM
//     subscription_activated  — subscription activated
//     payment_failed          — payment failed
//     welcome                 — welcome to Huddl
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class HuddlNotificationService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final HuddlNotificationService _instance =
      HuddlNotificationService._();
  factory HuddlNotificationService() => _instance;
  HuddlNotificationService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ═════════════════════════════════════════════════════════════════════════
  // CORE WRITE METHOD
  // ═════════════════════════════════════════════════════════════════════════

  /// Write a notification document to Firestore for [recipientId].
  /// All fields are stored so the sheet can render + deep-link correctly.
  Future<void> _write({
    required String recipientId,
    required String type,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    String? senderName,
    String? senderPhotoUrl,
    String? imageUrl,
  }) async {
    if (recipientId.isEmpty) return;
    // Never notify yourself
    final me = _uid;
    if (me != null && recipientId == me) return;

    try {
      await _db.collection('notifications').add({
        'userId': recipientId,
        'type': type,
        'title': title,
        'body': body,
        'read': false,
        'data': data,
        'senderName': senderName,
        'senderPhotoUrl': senderPhotoUrl,
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[HuddlNotif] write error: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MESSAGING
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> newDm({
    required String recipientId,
    required String senderName,
    required String messagePreview,
    required String conversationId,
    String? senderPhotoUrl,
  }) =>
      _write(
        recipientId: recipientId,
        type: 'new_dm',
        title: senderName,
        body: messagePreview,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        data: {
          'conversationId': conversationId,
          'recipientId': recipientId,
          'route': '/dm_chat',
        },
      );

  Future<void> newGroupMessage({
    required List<String> recipientIds,
    required String senderName,
    required String groupName,
    required String groupId,
    required String messagePreview,
    String? groupImageUrl,
  }) async {
    for (final id in recipientIds) {
      await _write(
        recipientId: id,
        type: 'new_group_message',
        title: groupName,
        body: '$senderName: $messagePreview',
        senderName: senderName,
        imageUrl: groupImageUrl,
        data: {
          'groupId': groupId,
          'groupName': groupName,
          'groupImageUrl': groupImageUrl ?? '',
          'route': '/group_chat',
        },
      );
    }
  }

  Future<void> voiceMessageDm({
    required String recipientId,
    required String senderName,
    required String conversationId,
    String? senderPhotoUrl,
  }) =>
      _write(
        recipientId: recipientId,
        type: 'voice_message_dm',
        title: senderName,
        body: '🎤 Sent you a voice message',
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        data: {
          'conversationId': conversationId,
          'recipientId': recipientId,
          'route': '/dm_chat',
        },
      );

  Future<void> voiceMessageGroup({
    required List<String> recipientIds,
    required String senderName,
    required String groupName,
    required String groupId,
    String? groupImageUrl,
  }) async {
    for (final id in recipientIds) {
      await _write(
        recipientId: id,
        type: 'voice_message_group',
        title: groupName,
        body: '$senderName sent a voice message 🎤',
        senderName: senderName,
        imageUrl: groupImageUrl,
        data: {
          'groupId': groupId,
          'groupName': groupName,
          'groupImageUrl': groupImageUrl ?? '',
          'route': '/group_chat',
        },
      );
    }
  }

  Future<void> messageReaction({
    required String recipientId,
    required String reactorName,
    required String emoji,
    required String messagePreview,
    required String contextType, // 'dm' or 'group'
    String? groupId,
    String? groupName,
    String? conversationId,
    String? reactorPhotoUrl,
  }) =>
      _write(
        recipientId: recipientId,
        type: 'message_reaction',
        title: '$reactorName reacted $emoji',
        body: '"$messagePreview"',
        senderName: reactorName,
        senderPhotoUrl: reactorPhotoUrl,
        data: {
          'contextType': contextType,
          'groupId': groupId ?? '',
          'groupName': groupName ?? '',
          'conversationId': conversationId ?? '',
          'route': contextType == 'group' ? '/group_chat' : '/dm_chat',
        },
      );

  Future<void> threadReply({
    required String recipientId,
    required String replierName,
    required String replyPreview,
    required String groupId,
    required String groupName,
    required String messageId,
    String? replierPhotoUrl,
    String? groupImageUrl,
  }) =>
      _write(
        recipientId: recipientId,
        type: 'thread_reply',
        title: '$replierName replied in $groupName',
        body: replyPreview,
        senderName: replierName,
        senderPhotoUrl: replierPhotoUrl,
        imageUrl: groupImageUrl,
        data: {
          'groupId': groupId,
          'groupName': groupName,
          'messageId': messageId,
          'route': '/group_chat',
        },
      );

  // ═════════════════════════════════════════════════════════════════════════
  // GROUPS & SOCIAL
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> groupInvitation({
    required String recipientId,
    required String invitedByName,
    required String groupName,
    required String groupId,
    String? groupImageUrl,
    String? inviterPhotoUrl,
  }) =>
      _write(
        recipientId: recipientId,
        type: 'group_invitation',
        title: 'Group invitation',
        body: '$invitedByName invited you to join $groupName',
        senderName: invitedByName,
        senderPhotoUrl: inviterPhotoUrl,
        imageUrl: groupImageUrl,
        data: {
          'groupId': groupId,
          'groupName': groupName,
          'groupImageUrl': groupImageUrl ?? '',
          'route': '/group_chat',
        },
      );

  Future<void> invitationAccepted({
    required String recipientId,
    required String acceptorName,
    required String groupName,
    required String groupId,
    String? groupImageUrl,
    String? acceptorPhotoUrl,
  }) =>
      _write(
        recipientId: recipientId,
        type: 'invitation_accepted',
        title: 'Invitation accepted',
        body: '$acceptorName joined $groupName',
        senderName: acceptorName,
        senderPhotoUrl: acceptorPhotoUrl,
        imageUrl: groupImageUrl,
        data: {
          'groupId': groupId,
          'groupName': groupName,
          'groupImageUrl': groupImageUrl ?? '',
          'route': '/group_chat',
        },
      );

  Future<void> groupMemberJoined({
    required String adminId,
    required String newMemberName,
    required String groupName,
    required String groupId,
    String? groupImageUrl,
    String? memberPhotoUrl,
  }) =>
      _write(
        recipientId: adminId,
        type: 'group_member_joined',
        title: 'New member',
        body: '$newMemberName joined $groupName',
        senderName: newMemberName,
        senderPhotoUrl: memberPhotoUrl,
        imageUrl: groupImageUrl,
        data: {
          'groupId': groupId,
          'groupName': groupName,
          'groupImageUrl': groupImageUrl ?? '',
          'route': '/group_chat',
        },
      );

  Future<void> postLiked({
    required String recipientId,
    required String likerName,
    required String postPreview,
    String? likerPhotoUrl,
  }) =>
      _write(
        recipientId: recipientId,
        type: 'post_liked',
        title: '$likerName liked your post',
        body: '"$postPreview"',
        senderName: likerName,
        senderPhotoUrl: likerPhotoUrl,
        data: {'route': '/home'},
      );

  Future<void> postCommented({
    required String recipientId,
    required String commenterName,
    required String commentPreview,
    required String postId,
    String? commenterPhotoUrl,
  }) =>
      _write(
        recipientId: recipientId,
        type: 'post_commented',
        title: '$commenterName commented',
        body: '"$commentPreview"',
        senderName: commenterName,
        senderPhotoUrl: commenterPhotoUrl,
        data: {'postId': postId, 'route': '/home'},
      );

  Future<void> commentReplied({
    required String recipientId,
    required String replierName,
    required String replyPreview,
    required String postId,
    String? replierPhotoUrl,
  }) =>
      _write(
        recipientId: recipientId,
        type: 'comment_replied',
        title: '$replierName replied to your comment',
        body: '"$replyPreview"',
        senderName: replierName,
        senderPhotoUrl: replierPhotoUrl,
        data: {'postId': postId, 'route': '/home'},
      );

  Future<void> pollCreated({
    required List<String> memberIds,
    required String creatorName,
    required String pollQuestion,
    required String groupId,
    required String groupName,
    String? groupImageUrl,
  }) async {
    for (final id in memberIds) {
      await _write(
        recipientId: id,
        type: 'poll_created',
        title: 'New poll in $groupName',
        body: '$creatorName asks: "$pollQuestion"',
        senderName: creatorName,
        imageUrl: groupImageUrl,
        data: {
          'groupId': groupId,
          'groupName': groupName,
          'route': '/group_chat',
        },
      );
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // EVENTS & MEETUPS
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> meetupRsvp({
    required String organiserId,
    required String attendeeName,
    required String meetupTitle,
    required String meetupId,
    String? attendeePhotoUrl,
  }) =>
      _write(
        recipientId: organiserId,
        type: 'meetup_rsvp',
        title: 'New RSVP',
        body: '$attendeeName is going to "$meetupTitle"',
        senderName: attendeeName,
        senderPhotoUrl: attendeePhotoUrl,
        data: {'meetupId': meetupId, 'meetupTitle': meetupTitle, 'route': '/meetups'},
      );

  Future<void> meetupReminder({
    required List<String> attendeeIds,
    required String meetupTitle,
    required String meetupId,
    required String meetupLocation,
    required String meetupTime,
  }) async {
    for (final id in attendeeIds) {
      await _write(
        recipientId: id,
        type: 'meetup_reminder',
        title: '📅 Meetup tomorrow!',
        body: '$meetupTitle at $meetupLocation — $meetupTime',
        data: {
          'meetupId': meetupId,
          'meetupTitle': meetupTitle,
          'route': '/meetups',
        },
      );
    }
  }

  Future<void> newMeetupNearby({
    required List<String> boroughUserIds,
    required String meetupTitle,
    required String meetupId,
    required String meetupDate,
    required String organiserId,
  }) async {
    for (final id in boroughUserIds) {
      if (id == organiserId) continue;
      await _write(
        recipientId: id,
        type: 'new_meetup_nearby',
        title: 'New meetup near you',
        body: '$meetupTitle — $meetupDate',
        data: {
          'meetupId': meetupId,
          'meetupTitle': meetupTitle,
          'route': '/meetups',
        },
      );
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MARKETPLACE
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> offerReceived({
    required String sellerId,
    required String buyerName,
    required String itemTitle,
    required String itemId,
    required String offerId,
    required String offerAmount,
    String? buyerPhotoUrl,
    String? itemImageUrl,
    String? notePreview,
  }) =>
      _write(
        recipientId: sellerId,
        type: 'offer_received',
        title: 'New offer on "$itemTitle"',
        body: notePreview != null && notePreview.isNotEmpty
            ? '$buyerName offered $offerAmount · "$notePreview"'
            : '$buyerName offered $offerAmount for your $itemTitle',
        senderName: buyerName,
        senderPhotoUrl: buyerPhotoUrl,
        imageUrl: itemImageUrl,
        data: {
          'itemId': itemId,
          'itemTitle': itemTitle,
          'offerId': offerId,
          'offerAmount': offerAmount,
          'route': '/marketplace',
          'tab': 'sell',
        },
      );

  Future<void> offerAccepted({
    required String buyerId,
    required String sellerName,
    required String itemTitle,
    required String itemId,
    required String sellerId,
    required String offerAmount,
    String? responseMessage,
    String? sellerPhotoUrl,
    String? itemImageUrl,
  }) =>
      _write(
        recipientId: buyerId,
        type: 'offer_accepted',
        title: 'Offer accepted! 🤝',
        body: responseMessage != null && responseMessage.isNotEmpty
            ? '$sellerName: "$responseMessage"'
            : '$sellerName accepted your $offerAmount offer for "$itemTitle"',
        senderName: sellerName,
        senderPhotoUrl: sellerPhotoUrl,
        imageUrl: itemImageUrl,
        data: {
          'itemId': itemId,
          'itemTitle': itemTitle,
          'sellerId': sellerId,
          'sellerName': sellerName,
          'route': '/item_detail',
          'action': 'open_seller_chat',
        },
      );

  Future<void> offerDeclined({
    required String buyerId,
    required String sellerName,
    required String itemTitle,
    required String itemId,
    String? responseMessage,
    String? sellerPhotoUrl,
    String? itemImageUrl,
  }) =>
      _write(
        recipientId: buyerId,
        type: 'offer_declined',
        title: 'Offer not accepted',
        body: responseMessage != null && responseMessage.isNotEmpty
            ? '$sellerName: "$responseMessage"'
            : '$sellerName declined your offer for "$itemTitle"',
        senderName: sellerName,
        senderPhotoUrl: sellerPhotoUrl,
        imageUrl: itemImageUrl,
        data: {
          'itemId': itemId,
          'itemTitle': itemTitle,
          'route': '/marketplace',
          'tab': 'buy',
        },
      );

  Future<void> itemSold({
    required String sellerId,
    required String itemTitle,
    required String itemId,
    required String buyerName,
    String? itemImageUrl,
  }) =>
      _write(
        recipientId: sellerId,
        type: 'item_sold',
        title: '"$itemTitle" sold 🎉',
        body: 'Great sale to $buyerName! Your listing has been closed.',
        imageUrl: itemImageUrl,
        data: {
          'itemId': itemId,
          'itemTitle': itemTitle,
          'route': '/marketplace',
          'tab': 'sell',
        },
      );

  Future<void> savedItemSold({
    required String savedByUserId,
    required String itemTitle,
    required String itemId,
    String? itemImageUrl,
  }) =>
      _write(
        recipientId: savedByUserId,
        type: 'saved_item_sold',
        title: 'Saved item sold',
        body: '"$itemTitle" has been marked as sold',
        imageUrl: itemImageUrl,
        data: {
          'itemId': itemId,
          'itemTitle': itemTitle,
          'route': '/marketplace',
          'tab': 'buy',
        },
      );

  Future<void> itemRelisted({
    required String savedByUserId,
    required String itemTitle,
    required String itemId,
    String? itemImageUrl,
  }) =>
      _write(
        recipientId: savedByUserId,
        type: 'item_relisted',
        title: '"$itemTitle" is available again',
        body: 'An item you saved has been relisted',
        imageUrl: itemImageUrl,
        data: {
          'itemId': itemId,
          'itemTitle': itemTitle,
          'route': '/item_detail',
        },
      );

  Future<void> offerOnOtherBuyerDeclined({
    required List<String> otherBuyerIds,
    required String itemTitle,
    required String itemId,
    String? itemImageUrl,
  }) async {
    for (final id in otherBuyerIds) {
      await _write(
        recipientId: id,
        type: 'saved_item_sold',
        title: 'Item no longer available',
        body: '"$itemTitle" you offered on has been sold',
        imageUrl: itemImageUrl,
        data: {
          'itemId': itemId,
          'itemTitle': itemTitle,
          'route': '/marketplace',
          'tab': 'buy',
        },
      );
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MARK ALL READ
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> markAllRead() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final snap = await _db
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      if (kDebugMode) debugPrint('[HuddlNotif] markAllRead error: $e');
    }
  }

  Future<void> markOneRead(String notificationId) async {
    try {
      await _db.collection('notifications').doc(notificationId).update({'read': true});
    } catch (e) {
      if (kDebugMode) debugPrint('[HuddlNotif] markOneRead error: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // STREAM (used by bell badge + sheet)
  // ═════════════════════════════════════════════════════════════════════════

  Stream<List<Map<String, dynamic>>> stream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    // NOTE: No .orderBy() here — adding orderBy('createdAt') alongside
    // where('userId') requires a composite Firestore index that may not exist,
    // causing the snapshot to error and return nothing (empty badge + list).
    // We sort in-memory below instead.
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .limit(60)
        .snapshots()
        .map((snap) {
          final docs = snap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            final ts = data['createdAt'];
            if (ts is Timestamp) {
              data['createdAt'] = ts.toDate().toIso8601String();
            }
            return data;
          }).toList();
          // Sort newest-first in memory (no index needed)
          docs.sort((a, b) {
            final aStr = a['createdAt'] as String? ?? '';
            final bStr = b['createdAt'] as String? ?? '';
            return bStr.compareTo(aStr);
          });
          return docs;
        });
  }
}
