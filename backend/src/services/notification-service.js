// ═══════════════════════════════════════════════════════════════════════════════
// Push Notification Service — Firebase Cloud Messaging (FCM)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Sends targeted push notifications via FCM for:
//   1. Trial reminders (Day 5, Day 7)
//   2. Subscription events (activation, renewal, failure, cancellation)
//   3. Welcome nudges
//   4. Community engagement (new group messages, meetup reminders)
//
// Requires:
//   - Firebase Admin SDK initialized (see firebase-service.js)
//   - FCM tokens stored in Firestore users collection (field: fcmToken)
//   - Firebase Cloud Messaging enabled in Firebase Console
//
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const { getMessaging, getDb, FieldValue } = require('./firebase-service');

// ── Notification templates ──────────────────────────────────────────────────

const TEMPLATES = {
  // ── Subscription ──────────────────────────────────────────────────────
  subscription_activated: {
    title: 'Welcome to Huddl {tierName}!',
    body: 'Your {tierName} subscription is active. Enjoy unlimited groups, messaging, and more.',
    data: { route: '/home', type: 'subscription_activated' },
  },
  subscription_renewed: {
    title: 'Subscription renewed',
    body: 'Your Huddl {tierName} subscription has been renewed. Thank you for being part of the community!',
    data: { route: '/home', type: 'subscription_renewed' },
  },
  payment_failed: {
    title: 'Payment issue',
    body: 'We couldn\'t process your payment. Update your payment method to keep your benefits.',
    data: { route: '/subscription/manage', type: 'payment_failed' },
  },
  subscription_cancelled: {
    title: 'Subscription cancelled',
    body: 'Your subscription will end at the current billing period. You can resubscribe anytime.',
    data: { route: '/subscription/upgrade', type: 'subscription_cancelled' },
  },

  // ── Engagement ────────────────────────────────────────────────────────
  welcome: {
    title: 'Welcome to Huddl!',
    body: 'You\'ve been added to {groupCount} local groups. Say hello to your neighbours!',
    data: { route: '/home', type: 'welcome' },
  },
  new_meetup_nearby: {
    title: 'New meetup near you',
    body: '{meetupTitle} — {meetupDate}',
    data: { route: '/meetups', type: 'new_meetup' },
  },
  meetup_reminder: {
    title: 'Meetup tomorrow!',
    body: '{meetupTitle} at {meetupLocation} — {meetupTime}',
    data: { route: '/meetups/{meetupId}', type: 'meetup_reminder' },
  },

  // ── Messaging ─────────────────────────────────────────────────────────
  new_group_message: {
    title: '{groupName}',
    body: '{senderName}: {messagePreview}',
    data: { route: '/groups/{groupId}', type: 'new_group_message', groupId: '{groupId}' },
  },
  new_dm: {
    title: '{senderName}',
    body: '{messagePreview}',
    data: { route: '/dm/{conversationId}', type: 'new_dm', conversationId: '{conversationId}' },
  },
};

// ═════════════════════════════════════════════════════════════════════════════
// SEND FUNCTIONS
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Send a push notification to a specific user.
 *
 * @param {string} userId    - Firebase UID
 * @param {string} template  - Template key from TEMPLATES
 * @param {Object} [vars]    - Template variable replacements (e.g. { tierName: 'Neighbour' })
 * @returns {Object} { success, messageId?, error? }
 */
async function sendToUser(userId, template, vars = {}) {
  const db = getDb();

  // Get user's FCM token
  const userDoc = await db.collection('users').doc(userId).get();
  const fcmToken = userDoc.data()?.fcmToken;

  if (!fcmToken) {
    console.log(`No FCM token for user ${userId} — skipping push`);
    return { success: false, error: 'No FCM token' };
  }

  const tmpl = TEMPLATES[template];
  if (!tmpl) {
    return { success: false, error: `Unknown template: ${template}` };
  }

  // Replace template variables
  let title = tmpl.title;
  let body = tmpl.body;
  const data = { ...tmpl.data };

  for (const [key, value] of Object.entries(vars)) {
    title = title.replace(`{${key}}`, String(value));
    body = body.replace(`{${key}}`, String(value));
    for (const dk of Object.keys(data)) {
      data[dk] = data[dk].replace(`{${key}}`, String(value));
    }
  }

  try {
    const messaging = getMessaging();
    const response = await messaging.send({
      token: fcmToken,
      notification: { title, body },
      data,
      android: {
        priority: 'high',
        notification: {
          channelId: 'huddl_default',
          icon: 'ic_notification',
          color: '#6C63FF',
        },
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default',
            'mutable-content': 1,
          },
        },
      },
      webpush: {
        notification: {
          icon: '/icons/Icon-192.png',
          badge: '/icons/Icon-48.png',
        },
      },
    });

    // Also store in Firestore notifications collection
    await db.collection('notifications').add({
      userId,
      type: template,
      title,
      body,
      read: false,
      data,
      createdAt: FieldValue.serverTimestamp(),
    });

    console.log(`Push sent to ${userId}: ${template} (${response})`);
    return { success: true, messageId: response };
  } catch (err) {
    console.error(`Push error for ${userId}:`, err.message);

    // If token is invalid, remove it
    if (
      err.code === 'messaging/invalid-registration-token' ||
      err.code === 'messaging/registration-token-not-registered'
    ) {
      await db.collection('users').doc(userId).update({ fcmToken: '' });
      console.log(`Removed invalid FCM token for user ${userId}`);
    }

    return { success: false, error: err.message };
  }
}

/**
 * Send a push notification to multiple users.
 */
async function sendToUsers(userIds, template, vars = {}) {
  const results = [];
  for (const userId of userIds) {
    const result = await sendToUser(userId, template, vars);
    results.push({ userId, ...result });
  }
  return results;
}

// ═════════════════════════════════════════════════════════════════════════════
module.exports = {
  TEMPLATES,
  sendToUser,
  sendToUsers,
};
