// ═══════════════════════════════════════════════════════════════════════════════
// Notification Routes
// ═══════════════════════════════════════════════════════════════════════════════
//
// POST /api/notifications/register-token   — save FCM token
// POST /api/notifications/welcome          — send welcome email + verification token
// POST /api/notifications/resend-verification — resend verification email
// GET  /api/notifications/verify-email     — verify token, mark user verified
// GET  /api/notifications/check-verified   — app polls for verification status
// POST /api/notifications/test-email       — diagnostic (cron-secret protected)
// GET  /api/notifications/smtp-check       — SMTP/Resend diagnostic
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const express = require('express');
const router  = express.Router();
const { v4: uuidv4 } = require('uuid');
const { authMiddleware } = require('../middleware/auth-middleware');
const { getDb, FieldValue } = require('../services/firebase-service');
const { sendToUser }        = require('../services/notification-service');
const { sendWelcomeEmail }  = require('../services/email-service');

const API_BASE     = process.env.API_BASE_URL  || 'https://api.huddlapp.co.uk';
const FRONTEND_URL = process.env.FRONTEND_URL  || 'https://www.huddlapp.co.uk';

// Token validity window — 72 hours gives plenty of time without being a security risk
const TOKEN_TTL_MS = 72 * 60 * 60 * 1000;

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Generate a fresh email-verification token and store it on the user doc. */
async function _issueVerifyToken(db, userId) {
  const token  = uuidv4();
  const expiry = new Date(Date.now() + TOKEN_TTL_MS).toISOString();
  await db.collection('users').doc(userId).update({
    emailVerifyToken:  token,
    emailVerifyExpiry: expiry,
    emailVerified:     false,
    updatedAt:         FieldValue.serverTimestamp(),
  });
  return { token, expiry };
}

/** Build the verify URL embedded in the email. */
function _verifyUrl(userId, token) {
  return `${API_BASE}/api/notifications/verify-email?uid=${encodeURIComponent(userId)}&token=${encodeURIComponent(token)}`;
}

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/notifications/register-token
// ─────────────────────────────────────────────────────────────────────────────
// Register/update the user's FCM push token.
router.post('/register-token', authMiddleware, async (req, res, next) => {
  try {
    const { token, platform } = req.body;
    if (!token) return res.status(400).json({ error: 'token is required' });

    const db = getDb();
    await db.collection('users').doc(req.userId).update({
      fcmToken:      token,
      fcmPlatform:   platform || 'unknown',
      fcmUpdatedAt:  FieldValue.serverTimestamp(),
    });

    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/notifications/welcome
// ─────────────────────────────────────────────────────────────────────────────
// Called when "Let's go!" is tapped at end of onboarding.
// Sends the branded welcome email containing a Verify Email button.
// Generates a secure one-time token stored in Firestore.
//
// Body:   { email, firstName, borough }
// Auth:   Bearer <Firebase ID token>
router.post('/welcome', authMiddleware, async (req, res, next) => {
  try {
    const { email, firstName, borough } = req.body;
    const db     = getDb();
    const userId = req.userId;

    const userRef  = db.collection('users').doc(userId);
    const userDoc  = await userRef.get();
    const userData = userDoc.data() || {};

    const result = { success: true };

    // ── Send welcome push notification ───────────────────────────────────
    sendToUser(userId, 'welcome', {
      groupCount: userData.assignedGroupCount || 0,
    }).catch(e => console.warn('[FCM] welcome push failed:', e.message));

    // ── Send welcome email with verification link ─────────────────────────
    const resolvedEmail = (email || userData.email || '').trim().toLowerCase();

    if (!resolvedEmail) {
      result.emailSkipped = 'no email address';
      return res.json(result);
    }

    // Issue a fresh verification token every time this endpoint is hit
    // (idempotent — replaces any previous token)
    const { token, expiry } = await _issueVerifyToken(db, userId);

    // Persist email on user doc if not already there
    await userRef.set(
      { email: resolvedEmail, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );

    const verifyUrl   = _verifyUrl(userId, token);
    const emailResult = await sendWelcomeEmail({
      email:     resolvedEmail,
      firstName: firstName || userData.firstName,
      borough:   borough   || userData.borough,
      verifyUrl,             // ← passed to the template
    });

    // Mark that the welcome email was sent (prevents duplicate sends on retry)
    await userRef.update({
      welcomeEmailSent:    true,
      welcomeEmailSentAt:  FieldValue.serverTimestamp(),
    });

    result.email            = emailResult;
    result.verifyTokenExpiry = expiry;
    console.log(`[welcome] email + verify link sent to ${resolvedEmail} for user ${userId}`);
    res.json(result);

  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/notifications/resend-verification
// ─────────────────────────────────────────────────────────────────────────────
// User taps "Resend email" on the pending-verification screen.
// Issues a fresh token and resends the welcome / verify email.
//
// Auth:   Bearer <Firebase ID token>  (no body needed)
router.post('/resend-verification', authMiddleware, async (req, res, next) => {
  try {
    const db     = getDb();
    const userId = req.userId;

    const userDoc  = await db.collection('users').doc(userId).get();
    const userData = userDoc.data() || {};
    const email    = (userData.email || '').trim();

    if (!email) {
      return res.status(400).json({ error: 'No email address on file' });
    }

    if (userData.emailVerified) {
      return res.json({ success: true, alreadyVerified: true });
    }

    // Issue a fresh token
    const { token, expiry } = await _issueVerifyToken(db, userId);
    const verifyUrl         = _verifyUrl(userId, token);

    const emailResult = await sendWelcomeEmail({
      email,
      firstName: userData.firstName,
      borough:   userData.borough,
      verifyUrl,
    });

    console.log(`[resend-verification] new token issued and email resent to ${email} for user ${userId}`);
    res.json({ success: true, email: emailResult, verifyTokenExpiry: expiry });

  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /api/notifications/verify-email?uid=…&token=…
// ─────────────────────────────────────────────────────────────────────────────
// Browser endpoint — user clicks the Verify Email button in the email.
// Validates the token, marks emailVerified=true in Firestore, and
// returns a branded HTML confirmation page.
router.get('/verify-email', async (req, res) => {
  const { uid, token } = req.query;

  if (!uid || !token) {
    return res.status(400).send(_verifyPage('invalid', 'Invalid verification link.'));
  }

  try {
    const db      = getDb();
    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      return res.status(404).send(_verifyPage('error', 'Account not found.'));
    }

    const data = userDoc.data() || {};

    // Already verified — treat as success
    if (data.emailVerified) {
      return res.send(_verifyPage('already', 'Your email is already verified. You can return to the Huddl app.'));
    }

    // Token mismatch
    if (data.emailVerifyToken !== token) {
      return res.status(400).send(_verifyPage('invalid', 'This link is invalid. Please request a new one from the app.'));
    }

    // Token expired
    if (data.emailVerifyExpiry && new Date(data.emailVerifyExpiry) < new Date()) {
      return res.status(400).send(_verifyPage('expired', 'This link has expired. Please tap "Resend email" in the Huddl app to get a new one.'));
    }

    // ── All checks passed — mark verified ────────────────────────────────
    await userRef.update({
      emailVerified:       true,
      emailVerifiedAt:     FieldValue.serverTimestamp(),
      emailVerifyToken:    FieldValue.delete(),   // invalidate token after use
      emailVerifyExpiry:   FieldValue.delete(),
      updatedAt:           FieldValue.serverTimestamp(),
    });

    console.log(`[verify-email] email verified for user ${uid}`);
    return res.send(_verifyPage('success', `Email verified! Welcome to Huddl, ${data.firstName || 'there'}. You can now return to the app.`));

  } catch (err) {
    console.error('[verify-email] error:', err.message);
    return res.status(500).send(_verifyPage('error', 'Something went wrong. Please try again or contact support.'));
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /api/notifications/check-verified
// ─────────────────────────────────────────────────────────────────────────────
// App polls this every few seconds to detect when the user has clicked
// the Verify Email button in their email client.
//
// Auth:   Bearer <Firebase ID token>
router.get('/check-verified', authMiddleware, async (req, res, next) => {
  try {
    const db      = getDb();
    const userDoc = await db.collection('users').doc(req.userId).get();
    const data    = userDoc.data() || {};
    res.json({
      emailVerified: data.emailVerified === true,
      email:         data.email || '',
    });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// POST /api/notifications/test-email
// ─────────────────────────────────────────────────────────────────────────────
// Internal diagnostic: sends a test welcome email (no verification token).
// Protected by CRON_SECRET.
router.post('/test-email', async (req, res, next) => {
  try {
    const cronSecret = req.headers['x-cron-secret'];
    // LAYER-2-NODEENV-GATE-1: secret required UNCONDITIONALLY (was NODE_ENV-gated → fail-open on misconfig).
    // !CRON_SECRET clause: deny if secret is unset server-side (prevents undefined===undefined pass).
    if (!process.env.CRON_SECRET || cronSecret !== process.env.CRON_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'email is required' });

    const result = await sendWelcomeEmail({
      email,
      firstName: 'Test',
      borough:   'Cambridge',
      verifyUrl: `${API_BASE}/api/notifications/verify-email?uid=TEST_UID&token=TEST_TOKEN`,
    });

    console.log(`[test-email] Sent to ${email}:`, result);
    res.json({ success: true, email, result });
  } catch (err) {
    next(err);
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /api/notifications/smtp-check
// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic: Resend + SMTP connectivity check.
router.get('/smtp-check', async (req, res) => {
  const cronSecret = req.headers['x-cron-secret'];
  // LAYER-2-NODEENV-GATE-1: secret required UNCONDITIONALLY.
  // !CRON_SECRET clause: deny if secret is unset server-side (prevents undefined===undefined pass).
  if (!process.env.CRON_SECRET || cronSecret !== process.env.CRON_SECRET) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const config = {
    RESEND_API_KEY:    process.env.RESEND_API_KEY    ? `(set, length ${process.env.RESEND_API_KEY.length})` : '(NOT SET)',
    RESEND_FROM_EMAIL: process.env.RESEND_FROM_EMAIL || '(not set)',
    SMTP_HOST:         process.env.SMTP_HOST         || '(not set)',
    SMTP_PORT:         process.env.SMTP_PORT         || '(not set, defaulting to 465)',
    SMTP_USER:         process.env.SMTP_USER         || '(not set)',
    SMTP_PASS:         process.env.SMTP_PASS         ? `(set, length ${process.env.SMTP_PASS.length})` : '(NOT SET)',
  };

  const net  = require('net');
  const host = process.env.SMTP_HOST || 'smtp.hostinger.com';

  async function testPort(port) {
    return new Promise((resolve) => {
      const socket = new net.Socket();
      const timer  = setTimeout(() => {
        socket.destroy();
        resolve({ port, connected: false, error: `Timed out after 8s` });
      }, 8000);
      socket.connect(port, host, () => {
        clearTimeout(timer); socket.destroy();
        resolve({ port, connected: true });
      });
      socket.on('error', (err) => {
        clearTimeout(timer);
        resolve({ port, connected: false, error: err.code });
      });
    });
  }

  const [tcp465, tcp587] = await Promise.all([testPort(465), testPort(587)]);
  res.json({ config, tcp465, tcp587 });
});

// ─────────────────────────────────────────────────────────────────────────────
// Branded HTML page returned to the user's browser after clicking Verify Email
// ─────────────────────────────────────────────────────────────────────────────
function _verifyPage(type, message) {
  const icons = { success: '✅', already: '✅', expired: '⏳', invalid: '❌', error: '⚠️' };
  const icon  = icons[type] || '📧';
  const isOk  = type === 'success' || type === 'already';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Email Verification — Huddl</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{background:#FFF8F3;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
         display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px;}
    .card{background:#fff;border-radius:20px;padding:0;max-width:480px;width:100%;
          text-align:center;box-shadow:0 4px 24px rgba(53,128,240,0.10);overflow:hidden;}
    .header{background:#3580F0;padding:24px 32px 20px;}
    .logo{font-size:22px;font-weight:900;color:#FCA878;letter-spacing:-0.5px;
          background:#fff;border-radius:10px;display:inline-block;
          padding:6px 18px;line-height:1;}
    .tagline{color:rgba(255,255,255,0.85);font-size:12px;margin-top:8px;letter-spacing:0.4px;}
    .body{padding:36px 32px 28px;}
    .icon{font-size:56px;margin-bottom:16px;}
    h1{font-size:22px;font-weight:800;color:#1E2235;margin-bottom:12px;}
    p{font-size:15px;color:#4A4A5A;line-height:1.6;margin-bottom:24px;}
    .btn{display:inline-block;background:#FCA878;color:#fff;font-weight:800;font-size:15px;
         padding:14px 40px;border-radius:50px;text-decoration:none;letter-spacing:0.3px;}
    .footer-strip{background:#FFF0E6;border-top:1px solid #FFD4B2;padding:16px 32px;
                  font-size:12px;color:#9E9E9E;}
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <div class="logo">huddl</div>
      <div class="tagline">Your local parent community</div>
    </div>
    <div class="body">
      <div class="icon">${icon}</div>
      <h1>${isOk ? 'Email Verified!' : 'Verification Failed'}</h1>
      <p>${message}</p>
      ${isOk
        ? `<a href="${FRONTEND_URL}" class="btn">Open Huddl App</a>`
        : `<p style="font-size:13px;color:#9E9E9E;">
             Return to the app and tap <strong>&ldquo;Resend email&rdquo;</strong> to get a fresh link.
           </p>`
      }
    </div>
    <div class="footer-strip">Huddl &middot; Cambridge, UK</div>
  </div>
</body>
</html>`;
}

module.exports = router;
