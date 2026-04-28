// ═══════════════════════════════════════════════════════════════════════════════
// Notification Routes — FCM token registration & trial cron
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth-middleware');
const { getDb, FieldValue } = require('../services/firebase-service');
const { processTrialReminders, sendToUser } = require('../services/notification-service');
const { sendWelcomeEmail } = require('../services/email-service');

// ── POST /api/notifications/register-token ──────────────────────────────────
// Register/update the user's FCM token.
// Called when the app starts or when the token refreshes.
//
// Body:
//   { token: '<FCM registration token>', platform: 'android|ios|web' }
router.post('/register-token', authMiddleware, async (req, res, next) => {
  try {
    const { token, platform } = req.body;

    if (!token) {
      return res.status(400).json({ error: 'token is required' });
    }

    const db = getDb();
    await db.collection('users').doc(req.userId).update({
      fcmToken: token,
      fcmPlatform: platform || 'unknown',
      fcmUpdatedAt: FieldValue.serverTimestamp(),
    });

    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/notifications/process-trial-reminders ─────────────────────────
// Cron endpoint: process trial reminders (Day 5 and Day 7).
//
// In production, call this via:
//   - Google Cloud Scheduler → HTTPS target
//   - or a cron job running: curl -X POST https://api.huddlapp.co.uk/api/notifications/process-trial-reminders
//
// Security: In production, add a shared secret header for cron authentication.
router.post('/process-trial-reminders', async (req, res, next) => {
  try {
    // Simple shared-secret auth for cron jobs
    const cronSecret = req.headers['x-cron-secret'];
    if (
      process.env.NODE_ENV === 'production' &&
      cronSecret !== process.env.CRON_SECRET
    ) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const result = await processTrialReminders();
    res.json({ success: true, ...result });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/notifications/email-added ─────────────────────────────────────
// Called when a user adds their email address to their profile for the first time.
// Triggers the welcome email if it hasn't been sent yet.
//
// Body:
//   { email: 'user@example.com' }
//
// Headers:
//   Authorization: Bearer <Firebase ID token>
router.post('/email-added', authMiddleware, async (req, res, next) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'email is required' });

    const db = getDb();
    const userId = req.userId;
    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    const userData = userDoc.data() || {};

    if (userData.welcomeEmailSent) {
      return res.json({ success: true, skipped: true, reason: 'already sent' });
    }

    const emailResult = await sendWelcomeEmail({
      email,
      firstName: userData.firstName,
      borough: userData.borough,
    });

    // Persist the email on the user doc
    await userRef.update({
      email,
      welcomeEmailSent: true,
      welcomeEmailSentAt: FieldValue.serverTimestamp(),
    });

    console.log(`Welcome email sent (on email-added) to ${email} for user ${userId}`);
    res.json({ success: true, email: emailResult });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/notifications/welcome ─────────────────────────────────────────
// Triggered by the Flutter app immediately after a new user profile is created.
// Sends a welcome email and a welcome push notification.
//
// Body:
//   { email: 'user@example.com', firstName: 'Jane', borough: 'Cambridge' }
//
// Headers:
//   Authorization: Bearer <Firebase ID token>
router.post('/welcome', authMiddleware, async (req, res, next) => {
  try {
    const { email, firstName, borough } = req.body;
    const db = getDb();
    const userId = req.userId;

    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    const userData = userDoc.data() || {};

    const result = { success: true };

    // ── Send welcome push notification ───────────────────────────────────
    await sendToUser(userId, 'welcome', {
      groupCount: userData.assignedGroupCount || 0,
    });

    // ── Send welcome email if we have an address ─────────────────────────
    // Huddl uses phone-auth: email may come from onboarding update or later.
    const resolvedEmail = email || userData.email || '';
    if (resolvedEmail && !userData.welcomeEmailSent) {
      const emailResult = await sendWelcomeEmail({
        email: resolvedEmail,
        firstName: firstName || userData.firstName,
        borough: borough || userData.borough,
      });

      await userRef.update({
        welcomeEmailSent: true,
        welcomeEmailSentAt: FieldValue.serverTimestamp(),
      });

      result.email = emailResult;
      console.log(`Welcome email sent to ${resolvedEmail} for user ${userId}`);
    } else {
      result.emailSkipped = !resolvedEmail ? 'no email address' : 'already sent';
    }

    res.json(result);
  } catch (err) {
    next(err);
  }
});

// ── POST /api/notifications/test-email ──────────────────────────────────────
// Internal diagnostic endpoint — send a test welcome email to any address.
// Protected by the same CRON_SECRET used for cron jobs.
router.post('/test-email', async (req, res, next) => {
  try {
    const cronSecret = req.headers['x-cron-secret'];
    if (
      process.env.NODE_ENV === 'production' &&
      cronSecret !== process.env.CRON_SECRET
    ) {
      return res.status(401).json({ error: 'Unauthorized — x-cron-secret header required' });
    }

    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'email is required' });

    const result = await sendWelcomeEmail({
      email,
      firstName: 'Test',
      borough: 'Cambridge',
    });

    console.log(`[test-email] Sent to ${email}:`, result);
    res.json({ success: true, email, result });
  } catch (err) {
    next(err);
  }
});

// ── GET /api/notifications/smtp-check ───────────────────────────────────────
// Diagnostic: verify SMTP config & connectivity without sending an email.
// Protected by x-cron-secret header.
router.get('/smtp-check', async (req, res) => {
  const cronSecret = req.headers['x-cron-secret'];
  if (
    process.env.NODE_ENV === 'production' &&
    cronSecret !== process.env.CRON_SECRET
  ) {
    return res.status(401).json({ error: 'Unauthorized — x-cron-secret header required' });
  }

  const config = {
    SMTP_HOST: process.env.SMTP_HOST || '(not set)',
    SMTP_PORT: process.env.SMTP_PORT || '(not set, defaulting to 465)',
    SMTP_USER: process.env.SMTP_USER ? process.env.SMTP_USER : '(not set)',
    SMTP_PASS: process.env.SMTP_PASS ? `(set, length ${process.env.SMTP_PASS.length})` : '(NOT SET)',
  };

  // Try TCP connections to both SMTP ports with an 8-second timeout each
  const net = require('net');
  const host = process.env.SMTP_HOST || 'smtp.hostinger.com';

  async function testPort(port) {
    return new Promise((resolve) => {
      const socket = new net.Socket();
      const timer = setTimeout(() => {
        socket.destroy();
        resolve({ port, connected: false, error: `Timed out after 8s (Railway may be blocking port ${port})` });
      }, 8000);

      socket.connect(port, host, () => {
        clearTimeout(timer);
        socket.destroy();
        resolve({ port, connected: true, message: `TCP connection to ${host}:${port} OK` });
      });

      socket.on('error', (err) => {
        clearTimeout(timer);
        resolve({ port, connected: false, error: `${err.code || 'ERROR'}: ${err.message}` });
      });
    });
  }

  const [tcp465, tcp587] = await Promise.all([testPort(465), testPort(587)]);

  res.json({ config, tcp465, tcp587 });
});

module.exports = router;
