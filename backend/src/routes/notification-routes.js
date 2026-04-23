// ═══════════════════════════════════════════════════════════════════════════════
// Notification Routes — FCM token registration & trial cron
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth-middleware');
const { getDb, FieldValue } = require('../services/firebase-service');
const { processTrialReminders } = require('../services/notification-service');

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

module.exports = router;
