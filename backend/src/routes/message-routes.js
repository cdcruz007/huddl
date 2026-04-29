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

module.exports = router;
