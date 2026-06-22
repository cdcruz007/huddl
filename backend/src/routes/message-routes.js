// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — MESSAGE NOTIFICATION ROUTES
// ═══════════════════════════════════════════════════════════════════════════════
//
// POST /api/messages/notify-group   — push to all group members except sender
// POST /api/messages/notify-dm      — push to the other DM participant
//
// Both endpoints are called by the Flutter client immediately after writing
// a message to Firestore.  The server fans out FCM pushes to every recipient
// whose notifPrefs allow it, while respecting lockScreenAlerts (Android APNS
// visibility / iOS foregroundPresentationOptions).
//
// Body for notify-group:
//   { groupId, groupName, messagePreview }   (senderName derived server-side)
//
// Body for notify-dm:
//   { conversationId, recipientId, senderName, messagePreview }
//
// Auth: Bearer <Firebase ID token>  (sender's token)
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const express = require('express');
const router  = express.Router();
const { authMiddleware } = require('../middleware/auth-middleware');
const { getDb, getMessaging, FieldValue } = require('../services/firebase-service');

// ─────────────────────────────────────────────────────────────────────────────
// Helper: build an FCM message object for a single token
// ─────────────────────────────────────────────────────────────────────────────
function _buildFcmMessage(token, title, body, data, lockScreenAlerts) {
  return {
    token,
    notification: { title, body },
    data: Object.fromEntries(
      Object.entries(data).map(([k, v]) => [k, String(v)])
    ),
    android: {
      priority: 'high',
      notification: {
        channelId: 'huddl_messages',
        icon: 'ic_notification',
        color: '#3580F0',
        // If user disabled lock-screen alerts, use PRIVATE visibility so
        // Android hides the content on the lock screen.
        visibility: lockScreenAlerts ? 'PUBLIC' : 'PRIVATE',
        sound: 'default',
      },
    },
    apns: {
      payload: {
        aps: {
          badge: 1,
          sound: 'default',
          'mutable-content': 1,
          // If lock-screen alerts are off, suppress banner on iOS lock screen
          // by using a background-only category hint.
          ...(lockScreenAlerts ? {} : { 'interruption-level': 'passive' }),
        },
      },
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
      },
    },
    webpush: {
      notification: {
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-48.png',
      },
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: send a push to one user and log the result
// ─────────────────────────────────────────────────────────────────────────────
async function _sendToRecipient(db, messaging, userId, title, body, data, senderId = null) {
  if (senderId) {
    try {
      const blk = await db.collection('users').doc(userId).collection('blocks').doc(senderId).get();
      if (blk.exists) {
        console.log(`[_sendToRecipient] recipient ${userId} has blocked sender ${senderId} — skipping push`);
        return;
      }
    } catch (e) {
      console.error('[_sendToRecipient] block-check failed, proceeding with send:', e);
    }
  }

  try {
    const userSnap = await db.collection('users').doc(userId).get();
    if (!userSnap.exists) return;

    const userData   = userSnap.data() || {};
    const fcmToken   = userData.fcmToken;
    if (!fcmToken) {
      console.log(`[msg-notify] No FCM token for ${userId} — skipping`);
      return;
    }

    // ── Respect notification preferences ──────────────────────────────────
    const prefs = userData.notifPrefs || {};

    // Master push toggle
    if (prefs.pushEnabled === false) {
      console.log(`[msg-notify] Push disabled for ${userId} — skipping`);
      return;
    }

    // Per-type toggles
    const type = data.type;
    if (type === 'new_group_message' && prefs.groupMessages === false) {
      console.log(`[msg-notify] groupMessages disabled for ${userId} — skipping`);
      return;
    }
    if (type === 'new_dm' && prefs.dmMessages === false) {
      console.log(`[msg-notify] dmMessages disabled for ${userId} — skipping`);
      return;
    }

    const lockScreenAlerts = prefs.lockScreenAlerts !== false; // default true

    const msg = _buildFcmMessage(fcmToken, title, body, data, lockScreenAlerts);
    const response = await messaging.send(msg);
    console.log(`[msg-notify] Push sent to ${userId}: ${response}`);

    // Store in notifications collection so the app can show an inbox
    await db.collection('notifications').add({
      userId,
      type,
      title,
      body,
      read: false,
      data,
      createdAt: FieldValue.serverTimestamp(),
    });

  } catch (err) {
    // Remove stale/invalid tokens automatically
    if (
      err.code === 'messaging/invalid-registration-token' ||
      err.code === 'messaging/registration-token-not-registered'
    ) {
      await db.collection('users').doc(userId).update({ fcmToken: '' });
      console.log(`[msg-notify] Removed invalid FCM token for ${userId}`);
    } else {
      console.error(`[msg-notify] Error pushing to ${userId}:`, err.message);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/messages/notify-group
// ─────────────────────────────────────────────────────────────────────────────
// Fan-out a push to every group member except the sender.
// Body: { groupId, groupName, messagePreview }
//   (senderName is DERIVED server-side — body.senderName is ignored, M3+NOTIFY-SPOOF-1)
//
// M3 membership gate: caller (req.userId) must be in groups/{groupId}.memberIds.
//   Returns 403 if not a member — prevents any authenticated user blasting
//   arbitrary-text notifications to groups they don't belong to.
//
// Spoofing hardening: senderName derived from users/{senderId}.name, not from
//   req.body. A legitimate member cannot impersonate another user's display name.
router.post('/notify-group', authMiddleware, async (req, res, next) => {
  try {
    const senderId = req.userId;
    const { groupId, groupName, messagePreview } = req.body;

    if (!groupId || !groupName) {
      return res.status(400).json({ error: 'groupId and groupName are required' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    // Load group from Firestore
    const groupSnap = await db.collection('groups').doc(groupId).get();
    if (!groupSnap.exists) {
      return res.status(404).json({ error: 'Group not found' });
    }

    // ── M3: membership gate — caller must be a member ────────────────────────
    // Prevents any authenticated non-member from blasting the group.
    const allMemberIds = groupSnap.data().memberIds || [];
    if (!allMemberIds.includes(senderId)) {
      return res.status(403).json({ error: 'Caller is not a member of this group' });
    }

    // Exclude the sender from recipients
    const memberIds = allMemberIds.filter(uid => uid !== senderId);

    // ── Derive senderName server-side — NEVER trust body.senderName ──────────
    // Kills impersonation: a member cannot claim another user's display name
    // by supplying a fake senderName in the request body (NOTIFY-SPOOF-1).
    const senderSnap = await db.collection('users').doc(senderId).get();
    const senderName = (senderSnap.exists && senderSnap.data().name)
      ? senderSnap.data().name
      : 'Someone';

    const preview = (messagePreview || '').substring(0, 100);
    const title   = groupName;
    const body    = `${senderName}: ${preview}`;
    const data    = {
      type:           'new_group_message',
      groupId,
      route:          `/groups/${groupId}`,
    };

    // Fan-out in parallel — block-check (BLOCK-1) wired via senderId arg
    await Promise.all(
      memberIds.map(uid => _sendToRecipient(db, messaging, uid, title, body, data, senderId))
    );

    res.json({ success: true, recipientCount: memberIds.length });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/messages/notify-dm
// ─────────────────────────────────────────────────────────────────────────────
// Push to the other participant in a 1-to-1 conversation.
// Body: { conversationId, recipientId, messagePreview }
//       senderName is DERIVED server-side from users/{senderId}.name (NOTIFY-SPOOF-1).
//
// Auth: serviceOrAuthMiddleware — accepts either:
//   (a) X-Service-Auth header (future Stage 2a-ii trigger) — trusts body fully.
//   (b) Firebase ID token (current client path) — validates participants + derives senderName.
router.post('/notify-dm', serviceOrAuthMiddleware, async (req, res, next) => {
  try {
    const { conversationId, recipientId, messagePreview } = req.body;

    // ── Service path: body is trusted (trigger already server-derived everything) ──
    if (req.isService) {
      const { senderName: serviceSenderName } = req.body;
      if (!recipientId || !serviceSenderName) {
        return res.status(400).json({ error: 'recipientId and senderName are required' });
      }
      const db        = getDb();
      const messaging = getMessaging();
      const preview   = (messagePreview || '').substring(0, 100);
      const data      = {
        type:           'new_dm',
        conversationId: conversationId || '',
        route:          `/dm/${conversationId || ''}`,
      };
      await _sendToRecipient(db, messaging, recipientId, serviceSenderName, preview, data);
      return res.json({ success: true });
    }

    // ── User-token path: validate + derive senderName server-side ───────────
    const senderId = req.userId;

    // conversationId is required for participant validation
    if (!conversationId) {
      return res.status(400).json({ error: 'conversationId is required' });
    }
    if (!recipientId) {
      return res.status(400).json({ error: 'recipientId is required' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    // ── Participant check: sender must be in the conversation ────────────────
    const convSnap = await db.collection('conversations').doc(conversationId).get();
    if (!convSnap.exists) {
      return res.status(403).json({ error: 'Not a participant' });
    }
    const participants = convSnap.data().participants || [];
    if (!participants.includes(senderId)) {
      return res.status(403).json({ error: 'Not a participant' });
    }

    // ── Recipient check: recipientId must also be a participant ──────────────
    // Prevents notifying arbitrary users outside the conversation.
    if (!participants.includes(recipientId)) {
      return res.status(403).json({ error: 'Recipient is not a participant' });
    }

    // Self-skip (same guard as before)
    if (recipientId === senderId) {
      return res.json({ success: true, skipped: 'self-message' });
    }

    // ── Derive senderName server-side — NEVER trust body.senderName ─────────
    // Kills impersonation: a user cannot claim to be someone else by
    // supplying a fake senderName in the request body (NOTIFY-SPOOF-1).
    const senderSnap = await db.collection('users').doc(senderId).get();
    const senderName = (senderSnap.exists && senderSnap.data().name)
      ? senderSnap.data().name
      : 'Someone';

    const preview = (messagePreview || '').substring(0, 100);
    const data    = {
      type:           'new_dm',
      conversationId,
      route:          `/dm/${conversationId}`,
    };

    await _sendToRecipient(db, messaging, recipientId, senderName, preview, data, senderId);

    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/messages/notify-offer
// ─────────────────────────────────────────────────────────────────────────────
// Notify the seller when a buyer makes an offer on their listing.
// Body: { itemId, offerId, offerAmount, notePreview?, itemImageUrl? }
//
// NOTIFY-SPOOF-1b: Caller (req.userId) MUST be the offer's buyerId.
//   - Reads marketplace/{itemId}/offers/{offerId} → verifies offer.buyerId === req.userId.
//   - Reads marketplace/{itemId} → derives sellerId (recipient) server-side.
//   - Derives buyerName from users/{req.userId}.name — body.buyerName is ignored.
//   - 403 on any role/doc mismatch; 404 if item or offer missing.
router.post('/notify-offer', authMiddleware, async (req, res, next) => {
  try {
    const callerId = req.userId;
    const { itemId, offerId, offerAmount, notePreview, itemImageUrl } = req.body;

    if (!itemId || !offerId) {
      return res.status(400).json({ error: 'itemId and offerId are required' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    // ── Verify caller is the actual buyer ────────────────────────────────────
    const offerSnap = await db.collection('marketplace').doc(itemId)
                              .collection('offers').doc(offerId).get();
    if (!offerSnap.exists) {
      return res.status(404).json({ error: 'Offer not found' });
    }
    const offerData = offerSnap.data();
    if (offerData.buyerId !== callerId) {
      return res.status(403).json({ error: 'Caller is not the buyer for this offer' });
    }

    // ── Verify item exists and derive seller (recipient) server-side ─────────
    const itemSnap = await db.collection('marketplace').doc(itemId).get();
    if (!itemSnap.exists) {
      return res.status(404).json({ error: 'Item not found' });
    }
    const itemData  = itemSnap.data();
    const sellerId  = itemData.sellerId;
    const itemTitle = itemData.title || offerData.itemTitle || '';
    if (!sellerId) {
      return res.status(403).json({ error: 'Item has no seller' });
    }

    // ── Derive buyerName server-side — NEVER trust body.buyerName ────────────
    const buyerSnap = await db.collection('users').doc(callerId).get();
    const buyerName = (buyerSnap.exists && buyerSnap.data().name)
      ? buyerSnap.data().name
      : 'A buyer';

    const body = notePreview
      ? `${buyerName} offered ${offerAmount || ''} · "${notePreview.substring(0, 60)}"`
      : `${buyerName} offered ${offerAmount || ''} for your ${itemTitle}`;

    const data = {
      type:      'offer_received',
      itemId,
      itemTitle,
      offerId,
      route:     '/marketplace',
      tab:       'sell',
    };

    await _sendToRecipient(db, messaging, sellerId, `New offer on "${itemTitle}"`, body, data, callerId);
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/messages/notify-offer-response
// ─────────────────────────────────────────────────────────────────────────────
// Notify the buyer when the seller accepts or declines their offer.
// Body: { itemId, offerId, accepted, responseMessage?, itemImageUrl? }
//
// NOTIFY-SPOOF-1b: Caller (req.userId) MUST be the item's sellerId.
//   - Reads marketplace/{itemId} → verifies item.sellerId === req.userId.
//   - Reads marketplace/{itemId}/offers/{offerId} → derives buyerId (recipient).
//   - Derives sellerName from users/{req.userId}.name — body.sellerName is ignored.
//   - 403 on any role/doc mismatch; 404 if item or offer missing.
router.post('/notify-offer-response', authMiddleware, async (req, res, next) => {
  try {
    const callerId = req.userId;
    const { itemId, offerId, accepted, responseMessage, itemImageUrl } = req.body;

    if (!itemId || !offerId) {
      return res.status(400).json({ error: 'itemId and offerId are required' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    // ── Verify caller is the item's seller ───────────────────────────────────
    const itemSnap = await db.collection('marketplace').doc(itemId).get();
    if (!itemSnap.exists) {
      return res.status(404).json({ error: 'Item not found' });
    }
    const itemData  = itemSnap.data();
    const itemTitle = itemData.title || '';
    if (itemData.sellerId !== callerId) {
      return res.status(403).json({ error: 'Caller is not the seller of this item' });
    }

    // ── Derive buyerId (recipient) from the offer doc ────────────────────────
    const offerSnap = await db.collection('marketplace').doc(itemId)
                              .collection('offers').doc(offerId).get();
    if (!offerSnap.exists) {
      return res.status(404).json({ error: 'Offer not found' });
    }
    const buyerId = offerSnap.data().buyerId;
    if (!buyerId) {
      return res.status(403).json({ error: 'Offer has no buyerId' });
    }

    // ── Derive sellerName server-side — NEVER trust body.sellerName ──────────
    const sellerSnap = await db.collection('users').doc(callerId).get();
    const sellerName = (sellerSnap.exists && sellerSnap.data().name)
      ? sellerSnap.data().name
      : 'The seller';

    const type  = accepted ? 'offer_accepted' : 'offer_declined';
    const title = accepted ? 'Offer accepted! 🤝' : 'Offer not accepted';
    const body  = responseMessage
      ? `${sellerName}: "${responseMessage.substring(0, 80)}"`
      : accepted
        ? `${sellerName} accepted your offer for "${itemTitle}"`
        : `${sellerName} declined your offer for "${itemTitle}"`;

    const data = {
      type,
      itemId,
      itemTitle,
      sellerId:   callerId,
      sellerName,
      route:      '/marketplace',
      tab:        'buy',
      action:     accepted ? 'open_seller_chat' : '',
    };

    await _sendToRecipient(db, messaging, buyerId, title, body, data, callerId);
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/messages/notify-item-sold
// ─────────────────────────────────────────────────────────────────────────────
// Notify other pending buyers when an item is marked as sold.
// Body: { itemId, otherBuyerIds?, itemImageUrl? }
//
// NOTIFY-SPOOF-1b: Caller (req.userId) MUST be the item's sellerId.
//   - Reads marketplace/{itemId} → verifies item.sellerId === req.userId.
//   - Filters otherBuyerIds to ONLY uids with a real offer doc under
//     marketplace/{itemId}/offers/{uid} — drops arbitrary injected ids.
//   - Derives any display names server-side.
//   - 403 on role mismatch; 404 if item missing.
router.post('/notify-item-sold', authMiddleware, async (req, res, next) => {
  try {
    const callerId = req.userId;
    const { itemId, otherBuyerIds, itemImageUrl } = req.body;

    if (!itemId) {
      return res.status(400).json({ error: 'itemId is required' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    // ── Verify caller is the item's seller ───────────────────────────────────
    const itemSnap = await db.collection('marketplace').doc(itemId).get();
    if (!itemSnap.exists) {
      return res.status(404).json({ error: 'Item not found' });
    }
    const itemData  = itemSnap.data();
    const itemTitle = itemData.title || '';
    if (itemData.sellerId !== callerId) {
      return res.status(403).json({ error: 'Caller is not the seller of this item' });
    }

    // ── Notify other interested buyers (offer-verified only) ─────────────────
    // For each uid in otherBuyerIds, verify an offer doc exists before notifying.
    // This prevents a seller from pushing arbitrary notifications to any uid.
    if (Array.isArray(otherBuyerIds) && otherBuyerIds.length > 0) {
      // Fetch all offer docs for this item in one query, then filter in-memory.
      const offersSnap = await db.collection('marketplace').doc(itemId)
                                 .collection('offers').get();
      const verifiedBuyerIds = new Set(
        offersSnap.docs
          .map(d => d.data().buyerId)
          .filter(Boolean)
      );

      for (const uid of otherBuyerIds) {
        // Only notify uids that actually have an offer on this item.
        if (!verifiedBuyerIds.has(uid)) {
          console.log(`[msg-notify] notify-item-sold: skipping ${uid} — no offer doc for item ${itemId}`);
          continue;
        }
        await _sendToRecipient(db, messaging, uid,
          'Item no longer available',
          `"${itemTitle}" you offered on has been sold`,
          { type: 'saved_item_sold', itemId, itemTitle, route: '/marketplace', tab: 'buy' },
          callerId
        );
      }
    }

    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});
module.exports = router;
