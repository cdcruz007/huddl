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
const { sendWelcomeEmail, sendVerificationEmail } = require('../services/email-service');

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
    const { email, firstName } = req.body;
    const db     = getDb();
    const userId = req.userId;

    const userRef  = db.collection('users').doc(userId);
    const userDoc  = await userRef.get();
    const userData = userDoc.data() || {};
    const result   = { success: true };

    if (userData.emailVerified) {
      result.emailSkipped = 'already verified';
      return res.json(result);
    }

    const resolvedEmail = (email || userData.email || '').trim().toLowerCase();
    if (!resolvedEmail) {
      result.emailSkipped = 'no email address';
      return res.json(result);
    }

    // ── Atomic dedupe via Firestore transaction ───────────────────────────────
    // Two concurrent requests both reaching this point would race on the
    // read→check→write sequence.  A transaction serialises that: only the first
    // committer wins; the second sees the timestamp written by the first and
    // bails out immediately.
    let shouldSend = false;
    let token, expiry;

    await db.runTransaction(async (txn) => {
      const snap     = await txn.get(userRef);
      const data     = snap.data() || {};
      const sentAt   = data.verificationEmailSentAt;
      const lastSent = sentAt
        ? (sentAt.toMillis?.() ?? new Date(sentAt).getTime())
        : 0;

      if (lastSent && (Date.now() - lastSent) < 120000) {
        // A send already happened (or is in-flight) — do nothing inside txn.
        shouldSend = false;
        return;
      }

      // Claim the send slot atomically.
      txn.update(userRef, {
        verificationEmailSentAt: FieldValue.serverTimestamp(),
        email:                   resolvedEmail,
        updatedAt:               FieldValue.serverTimestamp(),
      });
      shouldSend = true;
    });

    if (!shouldSend) {
      result.emailSkipped = 'recently sent';
      return res.json(result);
    }

    // Transaction committed — we are the sole winner. Issue token and send.
    ({ token, expiry } = await _issueVerifyToken(db, userId));

    const verifyUrl   = _verifyUrl(userId, token);
    const emailResult = await sendVerificationEmail({
      email:     resolvedEmail,
      firstName: firstName || userData.firstName,
      verifyUrl,
    });

    result.email             = emailResult;
    result.verifyTokenExpiry = expiry;
    console.log(`[welcome] verification email sent to ${resolvedEmail} for user ${userId}`);
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

    const emailResult = await sendVerificationEmail({
      email,
      firstName: userData.firstName,
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

    // Fire the welcome beat exactly once, now that they're verified.
    if (!data.welcomeEmailSent) {
      await userRef.update({
        welcomeEmailSent:   true,
        welcomeEmailSentAt: FieldValue.serverTimestamp(),
      });
      sendWelcomeEmail({
        email:     data.email,
        firstName: data.firstName,
        borough:   data.borough,
        // no verifyUrl -> welcome template omits the verify CTA automatically
      }).catch(e => console.warn('[verify-email] welcome email failed:', e.message));
      sendToUser(uid, 'welcome', {
        groupCount: data.assignedGroupCount || 0,
      }).catch(e => console.warn('[FCM] welcome push failed:', e.message));
    }

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

// ── Real Huddl logo — same base64 as in email-service.js ───────────────────
const HUDDL_LOGO = 'data:image/png;base64,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';

function _verifyPage(type, message) {
  const isOk = type === 'success' || type === 'already';

  // Inline SVG status mark — teal tick for success, soft amber/red ring otherwise.
  const okMark = `
    <svg width="56" height="56" viewBox="0 0 56 56" fill="none"
         xmlns="http://www.w3.org/2000/svg" style="display:block;margin:0 auto 16px;">
      <circle cx="28" cy="28" r="28" fill="#E6F5F3"/>
      <path d="M17 28.5l7 7 15-15" stroke="#199A85" stroke-width="3.5"
            stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`;
  const warnMark = `
    <svg width="56" height="56" viewBox="0 0 56 56" fill="none"
         xmlns="http://www.w3.org/2000/svg" style="display:block;margin:0 auto 16px;">
      <circle cx="28" cy="28" r="28" fill="#FEF3C7"/>
      <path d="M28 16v16" stroke="#F59E0B" stroke-width="3.5" stroke-linecap="round"/>
      <circle cx="28" cy="40" r="2.5" fill="#F59E0B"/>
    </svg>`;

  const heading = isOk ? "You're all set" : 'We hit a snag';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <meta name="color-scheme" content="light only"/>
  <title>Email verification — Huddl</title>
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600;700;800;900&display=swap" rel="stylesheet"/>
  <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{background:#FFF3ED;
         font-family:'Poppins',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,
         Helvetica,Arial,sans-serif;
         display:flex;align-items:center;justify-content:center;
         min-height:100vh;padding:24px;}
    .wrap{width:100%;max-width:460px;text-align:center;}
    .logo{margin-bottom:20px;}
    .logo img{width:140px;height:auto;display:block;margin:0 auto;}
    .card{background:#fff;border-radius:20px;padding:40px 32px;
          box-shadow:0 2px 16px rgba(26,26,26,0.06);}
    h1{font-size:23px;font-weight:800;color:#1A1A1A;margin-bottom:10px;line-height:1.3;}
    p{font-size:15px;color:#43464D;line-height:1.6;margin-bottom:24px;}
    .btn{display:inline-block;background:#FF965C;color:#fff;font-weight:800;
         font-size:15px;padding:14px 40px;border-radius:50px;text-decoration:none;
         letter-spacing:0.3px;}
    .hint{font-size:13px;color:#6C6C6C;margin:0;}
    .foot{margin-top:20px;font-size:12px;color:#6C6C6C;}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="logo"><img src="${HUDDL_LOGO}" alt="huddl"/></div>
    <div class="card">
      ${isOk ? okMark : warnMark}
      <h1>${heading}</h1>
      <p>${message}</p>
      ${isOk
        ? `<a href="${FRONTEND_URL}" class="btn">Open Huddl</a>`
        : `<p class="hint">Return to the Huddl app and tap
             <strong>&ldquo;Resend email&rdquo;</strong> to get a fresh link.</p>`
      }
    </div>
    <div class="foot">Cruzen Ltd &middot; London, UK</div>
  </div>
</body>
</html>`;
}


module.exports = router;
