// ═══════════════════════════════════════════════════════════════════════════════
// Email Service — Resend (primary, HTTPS/443) → SMTP fallback → mock
// ═══════════════════════════════════════════════════════════════════════════════
//
// Sends branded HTML emails for:
//   1. Welcome email (on sign-up)
//   2. Subscription confirmation (on purchase)
//   3. Payment receipt (on each payment)
//   4. Payment failure warning
//   5. Trial ending reminder (Day 5)
//   6. Cancellation confirmation
//   7. Win-back / re-engagement
//
// Provider priority:
//   1. Resend (RESEND_API_KEY set) — uses HTTPS port 443, works on Railway
//   2. Nodemailer SMTP (SMTP_HOST + SMTP_USER + SMTP_PASS set) — fallback
//   3. Mock logger — development / no credentials
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const nodemailer = require('nodemailer');

// ── Provider selection ────────────────────────────────────────────────────────
let resendClient = null;
let transporter  = null;

if (process.env.RESEND_API_KEY) {
  // Primary: Resend — pure HTTPS, no SMTP port issues on Railway
  const { Resend } = require('resend');
  resendClient = new Resend(process.env.RESEND_API_KEY);
  console.log('Email provider: Resend ✓');
} else if (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) {
  // Fallback: Nodemailer SMTP (Hostinger)
  const smtpPort = parseInt(process.env.SMTP_PORT || '465');
  transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: smtpPort,
    secure: smtpPort === 465,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
    connectionTimeout: 10000,
    greetingTimeout:   10000,
    socketTimeout:     30000,
    family: 4,
  });
  transporter.verify((err) => {
    if (err) {
      console.error('[SMTP] Connection verification failed:', err.message);
    } else {
      console.log(`Email provider: Hostinger SMTP ✓ (${process.env.SMTP_HOST}:${smtpPort})`);
    }
  });
} else {
  console.log('Email provider: mock (no credentials set)');
}

const FROM_EMAIL   = process.env.RESEND_FROM_EMAIL || process.env.SMTP_USER || 'welcome@huddlapp.co.uk';
const FROM_NAME    = 'Huddl Connect';
const FRONTEND_URL = process.env.FRONTEND_URL || 'https://www.huddlapp.co.uk';

// ── Brand colours & styles ──────────────────────────────────────────────────
const BRAND = {
  primary: '#6C63FF',
  secondary: '#FF6584',
  accent: '#43B581',
  dark: '#2D2D3F',
  light: '#F8F9FE',
  text: '#4A4A5A',
};

function _baseTemplate(title, bodyHtml) {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${title}</title>
</head>
<body style="margin:0; padding:0; background:${BRAND.light}; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND.light}; padding:40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff; border-radius:16px; overflow:hidden; box-shadow:0 4px 24px rgba(0,0,0,0.06);">
          <!-- Header -->
          <tr>
            <td style="background:linear-gradient(135deg,${BRAND.primary},${BRAND.secondary}); padding:32px 40px; text-align:center;">
              <h1 style="margin:0; color:#ffffff; font-size:28px; font-weight:700; letter-spacing:-0.5px;">Huddl Connect</h1>
              <p style="margin:8px 0 0; color:rgba(255,255,255,0.85); font-size:14px;">Your local parent community</p>
            </td>
          </tr>
          <!-- Body -->
          <tr>
            <td style="padding:40px;">
              ${bodyHtml}
            </td>
          </tr>
          <!-- Footer -->
          <tr>
            <td style="padding:24px 40px; background:${BRAND.light}; text-align:center; border-top:1px solid #E8E8F0;">
              <p style="margin:0; font-size:12px; color:#9999AA;">
                Huddl Connect Ltd &middot; Cambridge, UK<br/>
                <a href="${FRONTEND_URL}/privacy" style="color:${BRAND.primary}; text-decoration:none;">Privacy Policy</a> &middot;
                <a href="${FRONTEND_URL}/terms" style="color:${BRAND.primary}; text-decoration:none;">Terms of Service</a> &middot;
                <a href="${FRONTEND_URL}/settings/notifications" style="color:${BRAND.primary}; text-decoration:none;">Manage Preferences</a>
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function _button(text, url) {
  return `
    <table cellpadding="0" cellspacing="0" style="margin:24px 0;">
      <tr>
        <td style="background:${BRAND.primary}; border-radius:12px; padding:14px 32px;">
          <a href="${url}" style="color:#ffffff; text-decoration:none; font-weight:600; font-size:16px; display:inline-block;">${text}</a>
        </td>
      </tr>
    </table>`;
}

// ═════════════════════════════════════════════════════════════════════════════
// EMAIL TEMPLATES
// ═════════════════════════════════════════════════════════════════════════════

async function sendWelcomeEmail({ email, firstName, borough }) {
  const body = `
    <h2 style="color:${BRAND.dark}; margin:0 0 16px; font-size:24px;">Welcome to Huddl, ${firstName || 'there'}!</h2>
    <p style="color:${BRAND.text}; font-size:16px; line-height:1.6;">
      You've just joined your local parent community${borough ? ` in <strong>${borough}</strong>` : ''}. 
      We're so glad you're here.
    </p>
    <p style="color:${BRAND.text}; font-size:16px; line-height:1.6;">
      You're on the <strong>Welcome plan</strong> — free forever, no card required. 
      When you're ready for unlimited groups, messaging, meetups and AI tools, 
      upgrading to Neighbour or Circle takes just a few taps.
    </p>
    <h3 style="color:${BRAND.dark}; margin:24px 0 12px; font-size:18px;">Here's what to do first:</h3>
    <ol style="color:${BRAND.text}; font-size:15px; line-height:1.8; padding-left:20px;">
      <li><strong>Explore your local groups</strong> — we've matched you with parents nearby</li>
      <li><strong>Say hello</strong> — introduce yourself in your first group chat</li>
      <li><strong>Check the meetups</strong> — there's always something happening this week</li>
      <li><strong>Browse the marketplace</strong> — find great deals on kids' gear</li>
    </ol>
    ${_button('Open Huddl', FRONTEND_URL)}
    <p style="color:#9999AA; font-size:13px; margin-top:24px;">
      Upgrade anytime from the app to unlock unlimited features from £5.99/month.
    </p>`;

  return _send(email, `Welcome to Huddl, ${firstName || 'there'}!`, body);
}

async function sendSubscriptionConfirmation({ email, firstName, tier, billingPeriod, price }) {
  // Map internal Firestore tier keys to display names
  // Firestore tier keys match Flutter SubscriptionTier enum .name:
  //   'neighbourhood' → 'Neighbour', 'innerCircle' → 'Circle', 'explorer' → 'Welcome'
  // Legacy keys ('neighbour', 'circle') also handled for safety
  const tierName = (tier === 'innerCircle' || tier === 'circle') ? 'Circle' : 'Neighbour';
  const periodLabel = billingPeriod === 'annual' ? 'year' : 'month';

  const body = `
    <h2 style="color:${BRAND.dark}; margin:0 0 16px; font-size:24px;">You're a ${tierName} member!</h2>
    <p style="color:${BRAND.text}; font-size:16px; line-height:1.6;">
      Thanks for upgrading, ${firstName || 'there'}! Your <strong>Huddl ${tierName}</strong> 
      subscription is now active.
    </p>
    <div style="background:${BRAND.light}; border-radius:12px; padding:20px; margin:20px 0;">
      <table width="100%" cellpadding="0" cellspacing="0">
        <tr><td style="padding:8px 0; color:${BRAND.text}; font-size:14px;">Plan</td><td style="padding:8px 0; color:${BRAND.dark}; font-weight:600; text-align:right;">${tierName} (${billingPeriod})</td></tr>
        <tr><td style="padding:8px 0; color:${BRAND.text}; font-size:14px;">Price</td><td style="padding:8px 0; color:${BRAND.dark}; font-weight:600; text-align:right;">&pound;${price}/${periodLabel}</td></tr>
        <tr><td style="padding:8px 0; color:${BRAND.text}; font-size:14px;">Status</td><td style="padding:8px 0; color:${BRAND.accent}; font-weight:600; text-align:right;">Active</td></tr>
      </table>
    </div>
    ${_button('Explore Your Benefits', `${FRONTEND_URL}/subscription`)}
    <p style="color:#9999AA; font-size:13px; margin-top:24px;">
      Manage your subscription anytime in the app under Profile &gt; Subscription.
    </p>`;

  return _send(email, `Welcome to Huddl ${tierName}!`, body);
}

async function sendPaymentReceipt({ email, firstName, tier, amount, currency, invoiceId, date }) {
  // tier key: 'neighbourhood' → 'Neighbour', 'innerCircle'/'circle' → 'Circle'
  const tierName = (tier === 'innerCircle' || tier === 'circle') ? 'Circle' : 'Neighbour';
  const currencySymbol = currency === 'GBP' ? '&pound;' : currency === 'EUR' ? '&euro;' : '$';

  const body = `
    <h2 style="color:${BRAND.dark}; margin:0 0 16px; font-size:24px;">Payment Receipt</h2>
    <p style="color:${BRAND.text}; font-size:16px; line-height:1.6;">
      Hi ${firstName || 'there'}, here's your receipt for your Huddl subscription payment.
    </p>
    <div style="background:${BRAND.light}; border-radius:12px; padding:20px; margin:20px 0;">
      <table width="100%" cellpadding="0" cellspacing="0">
        <tr><td style="padding:8px 0; color:${BRAND.text}; font-size:14px;">Plan</td><td style="padding:8px 0; color:${BRAND.dark}; font-weight:600; text-align:right;">Huddl ${tierName}</td></tr>
        <tr><td style="padding:8px 0; color:${BRAND.text}; font-size:14px;">Amount</td><td style="padding:8px 0; color:${BRAND.dark}; font-weight:600; text-align:right;">${currencySymbol}${amount}</td></tr>
        <tr><td style="padding:8px 0; color:${BRAND.text}; font-size:14px;">Date</td><td style="padding:8px 0; color:${BRAND.dark}; font-weight:600; text-align:right;">${date || new Date().toLocaleDateString('en-GB')}</td></tr>
        <tr><td style="padding:8px 0; color:${BRAND.text}; font-size:14px;">Invoice</td><td style="padding:8px 0; color:${BRAND.dark}; font-weight:600; text-align:right;">${invoiceId || 'N/A'}</td></tr>
      </table>
    </div>
    <p style="color:#9999AA; font-size:13px; margin-top:24px;">
      This payment was processed securely. If you have questions, contact us at welcome@huddlapp.co.uk.
    </p>`;

  return _send(email, `Huddl payment receipt — ${currencySymbol}${amount}`, body);
}

async function sendPaymentFailedWarning({ email, firstName }) {
  const body = `
    <h2 style="color:${BRAND.dark}; margin:0 0 16px; font-size:24px;">Payment issue</h2>
    <p style="color:${BRAND.text}; font-size:16px; line-height:1.6;">
      Hi ${firstName || 'there'}, we couldn't process your latest subscription payment. 
      Don't worry — your access continues while we retry.
    </p>
    <p style="color:${BRAND.text}; font-size:16px; line-height:1.6;">
      Please update your payment method to avoid any interruption to your Huddl experience.
    </p>
    ${_button('Update Payment Method', `${FRONTEND_URL}/subscription/manage`)}
    <p style="color:#9999AA; font-size:13px; margin-top:24px;">
      We'll retry the payment automatically. If the issue persists, your subscription 
      may be paused after 7 days.
    </p>`;

  return _send(email, 'Action needed: Update your payment method', body);
}

async function sendTrialEndingReminder({ email, firstName, daysRemaining }) {
  const body = `
    <h2 style="color:${BRAND.dark}; margin:0 0 16px; font-size:24px;">Your trial ends in ${daysRemaining} day${daysRemaining !== 1 ? 's' : ''}</h2>
    <p style="color:${BRAND.text}; font-size:16px; line-height:1.6;">
      Hi ${firstName || 'there'}! You've been making the most of Huddl Neighbour — 
      keep the features you love by upgrading before your trial ends.
    </p>
    <div style="background:linear-gradient(135deg,${BRAND.light},#E8F5E9); border-radius:12px; padding:20px; margin:20px 0; text-align:center;">
      <p style="color:${BRAND.primary}; font-size:32px; font-weight:700; margin:0;">Don't lose access</p>
      <p style="color:${BRAND.text}; font-size:16px; margin:8px 0 0;">
        Upgrade to keep unlimited groups, messaging, meetups, and your Neighbour badge.
      </p>
    </div>
    <div style="background:${BRAND.light}; border-radius:12px; padding:20px; margin:20px 0;">
      <table width="100%" cellpadding="0" cellspacing="0">
        <tr><td style="padding:8px 0; color:${BRAND.text}; font-size:14px;">Neighbour</td><td style="padding:8px 0; color:${BRAND.dark}; font-weight:600; text-align:right;">&pound;5.99/month or &pound;49.99/year</td></tr>
        <tr><td style="padding:8px 0; color:${BRAND.text}; font-size:14px;">Circle</td><td style="padding:8px 0; color:${BRAND.dark}; font-weight:600; text-align:right;">&pound;12.99/month or &pound;99.99/year</td></tr>
      </table>
    </div>
    ${_button('Upgrade Now', `${FRONTEND_URL}/subscription/upgrade`)}
    <p style="color:#9999AA; font-size:13px; margin-top:24px;">
      After your trial, you'll move to the free Welcome plan (2 groups, 5 DMs, 2 meetups/month).
    </p>`;

  return _send(email, `Your Huddl trial ends in ${daysRemaining} day${daysRemaining !== 1 ? 's' : ''}`, body);
}

async function sendCancellationConfirmation({ email, firstName, endDate, tier }) {
  // tier key: 'neighbourhood' → 'Neighbour', 'innerCircle'/'circle' → 'Circle'
  const tierName = (tier === 'innerCircle' || tier === 'circle') ? 'Circle' : 'Neighbour';

  const body = `
    <h2 style="color:${BRAND.dark}; margin:0 0 16px; font-size:24px;">We're sorry to see you go</h2>
    <p style="color:${BRAND.text}; font-size:16px; line-height:1.6;">
      Hi ${firstName || 'there'}, your Huddl ${tierName} subscription has been cancelled. 
      You'll keep your benefits until <strong>${endDate || 'the end of your billing period'}</strong>.
    </p>
    <p style="color:${BRAND.text}; font-size:16px; line-height:1.6;">
      After that, you'll move to the free Welcome plan. Your groups and conversations will 
      still be there — you just won't be able to create new ones beyond the free limits.
    </p>
    <div style="background:${BRAND.light}; border-radius:12px; padding:20px; margin:20px 0; text-align:center;">
      <p style="color:${BRAND.dark}; font-size:18px; font-weight:600; margin:0 0 8px;">Changed your mind?</p>
      <p style="color:${BRAND.text}; font-size:15px; margin:0;">
        You can resubscribe anytime and pick up right where you left off.
      </p>
    </div>
    ${_button('Resubscribe', `${FRONTEND_URL}/subscription/upgrade`)}
    <p style="color:#9999AA; font-size:13px; margin-top:24px;">
      We'd love to hear why you cancelled — reply to this email or take our 
      <a href="${FRONTEND_URL}/feedback" style="color:${BRAND.primary};">30-second survey</a>.
    </p>`;

  return _send(email, `Your Huddl ${tierName} subscription has been cancelled`, body);
}

// ── Internal send helper ────────────────────────────────────────────────────

async function _send(to, subject, bodyHtml) {
  const html = _baseTemplate(subject, bodyHtml);

  // ── 1. Resend (HTTPS — works on Railway) ────────────────────────────────────
  if (resendClient) {
    try {
      const { data, error } = await resendClient.emails.send({
        from: `${FROM_NAME} <${FROM_EMAIL}>`,
        to,
        subject,
        html,
      });
      if (error) {
        console.error(`[Resend] Error sending to ${to}:`, error);
        return { success: false, error: error.message || JSON.stringify(error) };
      }
      console.log(`[Resend] Email sent to ${to}: ${subject} (id: ${data?.id})`);
      return { success: true, id: data?.id };
    } catch (err) {
      console.error(`[Resend] Exception sending to ${to}:`, err.message);
      return { success: false, error: err.message };
    }
  }

  // ── 2. Nodemailer SMTP fallback ─────────────────────────────────────────────
  if (transporter) {
    try {
      const sendPromise = transporter.sendMail({
        from: `"${FROM_NAME}" <${FROM_EMAIL}>`,
        to,
        subject,
        html,
      });
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('SMTP sendMail timed out after 20 seconds')), 20000)
      );
      await Promise.race([sendPromise, timeoutPromise]);
      console.log(`[SMTP] Email sent to ${to}: ${subject}`);
      return { success: true };
    } catch (err) {
      console.error(`[SMTP] Email error (${to}):`, err.message);
      return { success: false, error: err.message };
    }
  }

  // ── 3. Mock fallback ────────────────────────────────────────────────────────
  console.log(`[EMAIL MOCK] To: ${to} | Subject: ${subject}`);
  return { success: true, mock: true };
}

module.exports = {
  sendWelcomeEmail,
  sendSubscriptionConfirmation,
  sendPaymentReceipt,
  sendPaymentFailedWarning,
  sendTrialEndingReminder,
  sendCancellationConfirmation,
};
