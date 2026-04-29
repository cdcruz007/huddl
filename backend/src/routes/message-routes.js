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
//   { groupId, groupName, senderName, messagePreview }
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
async function _sendToRecipient(db, messaging, userId, title, body, data) {
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
// Body: { groupId, groupName, senderName, messagePreview }
router.post('/notify-group', authMiddleware, async (req, res, next) => {
  try {
    const senderId = req.userId;
    const { groupId, groupName, senderName, messagePreview } = req.body;

    if (!groupId || !groupName || !senderName) {
      return res.status(400).json({ error: 'groupId, groupName and senderName are required' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    // Load group members from Firestore
    const groupSnap = await db.collection('groups').doc(groupId).get();
    if (!groupSnap.exists) {
      return res.status(404).json({ error: 'Group not found' });
    }

    const memberIds = (groupSnap.data().memberIds || [])
      .filter(uid => uid !== senderId);

    const preview = (messagePreview || '').substring(0, 100);
    const title   = groupName;
    const body    = `${senderName}: ${preview}`;
    const data    = {
      type:           'new_group_message',
      groupId,
      route:          `/groups/${groupId}`,
    };

    // Fan-out in parallel (fire-and-forget each, results collected for logging)
    await Promise.all(
      memberIds.map(uid => _sendToRecipient(db, messaging, uid, title, body, data))
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
// Body: { conversationId, recipientId, senderName, messagePreview }
router.post('/notify-dm', authMiddleware, async (req, res, next) => {
  try {
    const senderId = req.userId;
    const { conversationId, recipientId, senderName, messagePreview } = req.body;

    if (!recipientId || !senderName) {
      return res.status(400).json({ error: 'recipientId and senderName are required' });
    }

    if (recipientId === senderId) {
      return res.json({ success: true, skipped: 'self-message' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    const preview = (messagePreview || '').substring(0, 100);
    const title   = senderName;
    const body    = preview;
    const data    = {
      type:           'new_dm',
      conversationId: conversationId || '',
      route:          `/dm/${conversationId || ''}`,
    };

    await _sendToRecipient(db, messaging, recipientId, title, body, data);

    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/messages/notify-offer
// ─────────────────────────────────────────────────────────────────────────────
// Notify the seller when a buyer makes an offer on their listing.
// Body: { sellerId, buyerName, itemTitle, itemId, offerId, offerAmount, notePreview?, itemImageUrl? }
router.post('/notify-offer', authMiddleware, async (req, res, next) => {
  try {
    const { sellerId, buyerName, itemTitle, itemId, offerId, offerAmount, notePreview, itemImageUrl } = req.body;
    if (!sellerId || !buyerName || !itemTitle) {
      return res.status(400).json({ error: 'sellerId, buyerName and itemTitle are required' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    const body = notePreview
      ? `${buyerName} offered ${offerAmount} · "${notePreview.substring(0, 60)}"`
      : `${buyerName} offered ${offerAmount} for your ${itemTitle}`;

    const data = {
      type:      'offer_received',
      itemId:    itemId    || '',
      itemTitle,
      offerId:   offerId   || '',
      route:     '/marketplace',
      tab:       'sell',
    };

    await _sendToRecipient(db, messaging, sellerId, `New offer on "${itemTitle}"`, body, data);
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/messages/notify-offer-response
// ─────────────────────────────────────────────────────────────────────────────
// Notify the buyer when the seller accepts or declines their offer.
// Body: { buyerId, sellerName, itemTitle, itemId, accepted, responseMessage?, itemImageUrl? }
router.post('/notify-offer-response', authMiddleware, async (req, res, next) => {
  try {
    const { buyerId, sellerName, itemTitle, itemId, accepted, responseMessage, sellerId } = req.body;
    if (!buyerId || !sellerName || !itemTitle) {
      return res.status(400).json({ error: 'buyerId, sellerName and itemTitle are required' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    const type  = accepted ? 'offer_accepted' : 'offer_declined';
    const title = accepted ? 'Offer accepted! 🤝' : 'Offer not accepted';
    const body  = responseMessage
      ? `${sellerName}: "${responseMessage.substring(0, 80)}"`
      : accepted
        ? `${sellerName} accepted your offer for "${itemTitle}"`
        : `${sellerName} declined your offer for "${itemTitle}"`;

    const data = {
      type,
      itemId:     itemId   || '',
      itemTitle,
      sellerId:   sellerId || '',
      sellerName,
      route:      accepted ? '/marketplace' : '/marketplace',
      tab:        accepted ? 'buy'          : 'buy',
      action:     accepted ? 'open_seller_chat' : '',
    };

    await _sendToRecipient(db, messaging, buyerId, title, body, data);
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/messages/notify-item-sold
// ─────────────────────────────────────────────────────────────────────────────
// Notify the seller when their item is marked as sold.
// Also notifies other pending buyers that the item is gone.
// Body: { sellerId, buyerName, itemTitle, itemId, otherBuyerIds?, itemImageUrl? }
router.post('/notify-item-sold', authMiddleware, async (req, res, next) => {
  try {
    const { sellerId, buyerName, itemTitle, itemId, otherBuyerIds } = req.body;
    if (!sellerId || !itemTitle) {
      return res.status(400).json({ error: 'sellerId and itemTitle are required' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    // Notify seller
    await _sendToRecipient(db, messaging, sellerId,
      `"${itemTitle}" sold 🎉`,
      `Great sale to ${buyerName || 'a buyer'}! Your listing has been closed.`,
      { type: 'item_sold', itemId: itemId || '', itemTitle, route: '/marketplace', tab: 'sell' }
    );

    // Notify other interested buyers
    if (Array.isArray(otherBuyerIds)) {
      for (const uid of otherBuyerIds) {
        await _sendToRecipient(db, messaging, uid,
          'Item no longer available',
          `"${itemTitle}" you offered on has been sold`,
          { type: 'saved_item_sold', itemId: itemId || '', itemTitle, route: '/marketplace', tab: 'buy' }
        );
      }
    }

    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/messages/notify-group-event
// ─────────────────────────────────────────────────────────────────────────────
// Generic social event notifications (invitation, join, reaction, RSVP, poll).
// Body: { recipientIds[], type, title, body, data }
router.post('/notify-group-event', authMiddleware, async (req, res, next) => {
  try {
    const { recipientIds, type, title, body, data } = req.body;
    if (!Array.isArray(recipientIds) || !type || !title) {
      return res.status(400).json({ error: 'recipientIds, type and title are required' });
    }

    const db        = getDb();
    const messaging = getMessaging();

    const notifData = { type, ...(data || {}) };

    for (const uid of recipientIds) {
      await _sendToRecipient(db, messaging, uid, title, body || '', notifData);
    }

    res.json({ success: true, recipientCount: recipientIds.length });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
