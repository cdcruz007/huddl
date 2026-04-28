// ═══════════════════════════════════════════════════════════════════════════════
// Email Service — Resend (primary, HTTPS/443) → SMTP fallback → mock
// ═══════════════════════════════════════════════════════════════════════════════
//
// Transactional emails sent for:
//   1.  Welcome email             — on sign-up (once email is available)
//   2.  Subscription confirmation — on IAP purchase (Apple / Google)
//   3.  Payment receipt           — on each successful renewal (Apple / Google)
//   4.  Payment failure warning   — on failed billing (Apple / Google)
//   5.  Cancellation confirmation — on subscription cancellation (Apple / Google)
//   6.  Subscription reactivated  — when user resubscribes
//
// Provider priority:
//   1. Resend (RESEND_API_KEY set) — pure HTTPS port 443, works on Railway
//   2. Nodemailer SMTP (SMTP_HOST + SMTP_USER + SMTP_PASS set) — fallback
//   3. Mock logger — development / no credentials
//
// Branding tokens:
//   Primary:   #FCA878  (Huddl orange)
//   Dark:      #43464D
//   Text:      #6C6C6C
//   Light bg:  #FFF0E6  (peach light)
//   White:     #FFFFFF
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const nodemailer = require('nodemailer');

// ── Provider selection ────────────────────────────────────────────────────────
let resendClient = null;
let transporter  = null;

if (process.env.RESEND_API_KEY) {
  const { Resend } = require('resend');
  resendClient = new Resend(process.env.RESEND_API_KEY);
  console.log('Email provider: Resend ✓');
} else if (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) {
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
    if (err) console.error('[SMTP] Verification failed:', err.message);
    else console.log(`Email provider: Hostinger SMTP ✓ (${process.env.SMTP_HOST}:${smtpPort})`);
  });
} else {
  console.log('Email provider: mock (no credentials set)');
}

const FROM_EMAIL   = process.env.RESEND_FROM_EMAIL || process.env.SMTP_USER || 'welcome@huddlapp.co.uk';
const FROM_NAME    = 'Huddl Connect';
const FRONTEND_URL = process.env.FRONTEND_URL || 'https://www.huddlapp.co.uk';

// ── Brand tokens (match app HuddlColors exactly) ─────────────────────────────
const B = {
  primary:       '#FCA878',   // HuddlColors.primary / onboardingOrange
  primaryDark:   '#E8935E',   // HuddlColors.primaryDark
  primaryLight:  '#FFD4B2',   // lighter tint
  peachLight:    '#FFF0E6',   // HuddlColors.peachLight
  peachBg:       '#FFF8F3',   // very light peach for outer bg
  dark:          '#43464D',   // HuddlColors.textDark
  text:          '#6C6C6C',   // HuddlColors.textSecondary
  textLight:     '#9E9E9E',   // captions / footer
  white:         '#FFFFFF',
  success:       '#199A85',   // HuddlColors.success
  error:         '#E53935',
};

// ── Shared helpers ────────────────────────────────────────────────────────────

/** Wraps body HTML in the Huddl-branded email shell. */
function _wrap(title, bodyHtml) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <meta name="color-scheme" content="light"/>
  <title>${title}</title>
</head>
<body style="margin:0;padding:0;background:${B.peachBg};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">

  <!-- Outer wrapper -->
  <table width="100%" cellpadding="0" cellspacing="0" role="presentation"
         style="background:${B.peachBg};padding:40px 16px;">
    <tr>
      <td align="center">

        <!-- Card -->
        <table width="560" cellpadding="0" cellspacing="0" role="presentation"
               style="background:${B.white};border-radius:20px;overflow:hidden;
                      box-shadow:0 2px 20px rgba(252,168,120,0.12);">

          <!-- ── Header ── -->
          <tr>
            <td style="background:${B.primary};padding:28px 40px;text-align:center;">
              <!-- Logo mark: H glyph -->
              <table cellpadding="0" cellspacing="0" role="presentation"
                     style="margin:0 auto 10px;">
                <tr>
                  <td style="background:${B.white};border-radius:14px;
                              padding:8px 14px;display:inline-block;">
                    <span style="font-size:26px;font-weight:900;
                                 color:${B.primary};letter-spacing:-1px;
                                 font-family:-apple-system,BlinkMacSystemFont,sans-serif;">
                      &#x48;&#x0332; huddl
                    </span>
                  </td>
                </tr>
              </table>
              <p style="margin:0;color:rgba(255,255,255,0.9);font-size:13px;
                         letter-spacing:0.3px;">Your local parent community</p>
            </td>
          </tr>

          <!-- ── Body ── -->
          <tr>
            <td style="padding:36px 40px 28px;">
              ${bodyHtml}
            </td>
          </tr>

          <!-- ── Footer ── -->
          <tr>
            <td style="padding:20px 40px 28px;background:${B.peachLight};
                        border-top:1px solid #FFD4B2;text-align:center;">
              <p style="margin:0 0 6px;font-size:12px;color:${B.textLight};">
                Huddl Connect Ltd &middot; Cambridge, UK
              </p>
              <p style="margin:0;font-size:12px;color:${B.textLight};">
                <a href="${FRONTEND_URL}/privacy"
                   style="color:${B.primary};text-decoration:none;">Privacy Policy</a>
                &nbsp;&middot;&nbsp;
                <a href="${FRONTEND_URL}/terms"
                   style="color:${B.primary};text-decoration:none;">Terms of Service</a>
                &nbsp;&middot;&nbsp;
                <a href="${FRONTEND_URL}/settings/notifications"
                   style="color:${B.primary};text-decoration:none;">Manage Emails</a>
              </p>
              <p style="margin:8px 0 0;font-size:11px;color:${B.textLight};">
                You can unsubscribe from Huddl emails at any time from your inbox
                or in the app under Profile &rarr; Notifications.
              </p>
            </td>
          </tr>

        </table>
        <!-- /Card -->

      </td>
    </tr>
  </table>
</body>
</html>`;
}

/** Orange CTA button */
function _btn(label, url) {
  return `
    <table cellpadding="0" cellspacing="0" role="presentation" style="margin:24px 0;">
      <tr>
        <td style="background:${B.primary};border-radius:50px;padding:0;">
          <a href="${url}"
             style="display:inline-block;padding:14px 36px;color:${B.white};
                    font-weight:700;font-size:15px;text-decoration:none;
                    border-radius:50px;letter-spacing:0.2px;">${label}</a>
        </td>
      </tr>
    </table>`;
}

/** Peach info card (used for plan details, receipts etc.) */
function _card(rows) {
  // rows: Array of { label, value }
  const trs = rows.map(r => `
    <tr>
      <td style="padding:10px 0;font-size:14px;color:${B.text};
                  border-bottom:1px solid #FFD4B2;">${r.label}</td>
      <td style="padding:10px 0;font-size:14px;color:${B.dark};font-weight:600;
                  text-align:right;border-bottom:1px solid #FFD4B2;">${r.value}</td>
    </tr>`).join('');
  return `
    <table width="100%" cellpadding="0" cellspacing="0" role="presentation"
           style="background:${B.peachLight};border-radius:14px;
                  padding:4px 20px;margin:20px 0;">
      ${trs}
    </table>`;
}

/** Decorative divider used to separate sections */
function _divider() {
  return `<hr style="border:none;border-top:1px solid #FFD4B2;margin:24px 0;"/>`;
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. WELCOME EMAIL
// ─────────────────────────────────────────────────────────────────────────────
async function sendWelcomeEmail({ email, firstName, borough, verifyUrl }) {
  if (!email) return { success: false, error: 'no email address' };

  const name = firstName || 'there';

  // ── Verification button block — shown when a verifyUrl is supplied ────────
  const verifyBlock = verifyUrl ? `
    <!-- ══ EMAIL VERIFICATION CALLOUT ══════════════════════════════════════ -->
    <div style="background:linear-gradient(135deg,${B.primary},${B.primaryDark});
                border-radius:16px;padding:24px;margin:0 0 28px;text-align:center;">
      <p style="margin:0 0 6px;font-size:18px;font-weight:800;color:#ffffff;">
        One last step 🎉
      </p>
      <p style="margin:0 0 20px;font-size:14px;color:rgba(255,255,255,0.9);line-height:1.5;">
        Tap the button below to verify your email address and unlock full access to Huddl.
      </p>
      <table cellpadding="0" cellspacing="0" role="presentation" style="margin:0 auto;">
        <tr>
          <td style="background:#ffffff;border-radius:50px;padding:0;">
            <a href="${verifyUrl}"
               style="display:inline-block;padding:14px 40px;color:${B.primary};
                      font-weight:800;font-size:16px;text-decoration:none;
                      border-radius:50px;letter-spacing:0.3px;">
              Verify My Email &rarr;
            </a>
          </td>
        </tr>
      </table>
      <p style="margin:16px 0 0;font-size:12px;color:rgba(255,255,255,0.7);">
        This link expires in 72 hours. If you didn't create a Huddl account,
        you can safely ignore this email.
      </p>
    </div>
    <!-- ════════════════════════════════════════════════════════════════════ -->` : '';

  const body = `
    <div style="text-align:center;font-size:48px;margin-bottom:8px;">👋</div>

    <h2 style="margin:0 0 12px;font-size:22px;font-weight:800;
               color:${B.dark};text-align:center;">
      Welcome to Huddl, ${name}!
    </h2>

    <p style="color:${B.text};font-size:15px;line-height:1.65;text-align:center;
               margin:0 0 24px;">
      You've just joined your local parent community${borough ? ` in <strong>${borough}</strong>` : ''}.
      We're so glad you're here.
    </p>

    ${verifyBlock}

    <div style="background:${B.peachLight};border-radius:14px;padding:20px 24px;
                 margin:0 0 24px;border-left:4px solid ${B.primary};">
      <p style="margin:0;font-size:15px;color:${B.dark};font-weight:600;">
        You're on the <span style="color:${B.primary};">Welcome plan</span>
        &mdash; free forever, no card required.
      </p>
      <p style="margin:8px 0 0;font-size:14px;color:${B.text};line-height:1.55;">
        When you're ready for unlimited groups, direct messages, meetups and AI tools,
        upgrading to Neighbour or Circle takes just a few taps.
      </p>
    </div>

    <h3 style="margin:0 0 14px;font-size:16px;font-weight:700;color:${B.dark};">
      Here's what to do once you're in:
    </h3>
    <table width="100%" cellpadding="0" cellspacing="0" role="presentation">
      ${[
        ['🏘️', '<strong>Explore your local groups</strong>', "We've matched you with parents nearby"],
        ['👋', '<strong>Say hello</strong>', 'Introduce yourself in your first group chat'],
        ['📅', '<strong>Check the meetups</strong>', "There's always something happening this week"],
        ['🛒', '<strong>Browse the marketplace</strong>', "Find great deals on kids' gear"],
      ].map(([icon, title, sub]) => `
        <tr>
          <td width="40" valign="top" style="padding:8px 12px 8px 0;font-size:22px;">${icon}</td>
          <td style="padding:8px 0;vertical-align:top;">
            <p style="margin:0;font-size:14px;color:${B.dark};">${title}</p>
            <p style="margin:2px 0 0;font-size:13px;color:${B.text};">${sub}</p>
          </td>
        </tr>`).join('')}
    </table>

    <p style="margin:24px 0 0;font-size:12px;color:${B.textLight};text-align:center;">
      Upgrade anytime from the app to unlock unlimited features from &pound;5.99/month.
    </p>`;

  return _send(email, `Welcome to Huddl, ${name}! 🧡`, body);
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. SUBSCRIPTION CONFIRMATION  (Apple / Google IAP purchase)
// ─────────────────────────────────────────────────────────────────────────────
async function sendSubscriptionConfirmation({ email, firstName, tier, billingPeriod, price, platform }) {
  if (!email) return { success: false, error: 'no email address' };

  const tierName    = _tierDisplay(tier);
  const periodLabel = billingPeriod === 'annual' ? 'year' : 'month';
  const storeName   = platform === 'ios' ? 'Apple App Store' : 'Google Play';

  const body = `
    <div style="text-align:center;font-size:48px;margin-bottom:8px;">🎉</div>

    <h2 style="margin:0 0 12px;font-size:22px;font-weight:800;
               color:${B.dark};text-align:center;">
      You're now a <span style="color:${B.primary};">${tierName}</span> member!
    </h2>
    <p style="color:${B.text};font-size:15px;line-height:1.65;text-align:center;
               margin:0 0 24px;">
      Thanks for upgrading, ${firstName || 'there'}!
      Your <strong>Huddl ${tierName}</strong> subscription is now active.
    </p>

    ${_card([
      { label: 'Plan',     value: `Huddl ${tierName} (${billingPeriod})` },
      { label: 'Price',    value: price ? `&pound;${price}/${periodLabel}` : 'See your store receipt' },
      { label: 'Billed via', value: storeName },
      { label: 'Status',   value: `<span style="color:${B.success};">&#10003; Active</span>` },
    ])}

    <p style="color:${B.text};font-size:14px;line-height:1.6;margin:0 0 24px;">
      Your subscription auto-renews. You can manage or cancel it at any time in
      <strong>${storeName}</strong> under your account subscriptions.
    </p>

    ${_btn('Explore Your Benefits', `${FRONTEND_URL}/subscription`)}

    <p style="margin:0;font-size:12px;color:${B.textLight};text-align:center;">
      Manage your subscription via Profile &rarr; Subscription in the app.
    </p>`;

  return _send(email, `You're now a Huddl ${tierName} member! 🎉`, body);
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. PAYMENT RECEIPT  (Apple / Google renewal)
// ─────────────────────────────────────────────────────────────────────────────
async function sendPaymentReceipt({ email, firstName, tier, amount, currency, invoiceId, date, platform }) {
  if (!email) return { success: false, error: 'no email address' };

  const tierName       = _tierDisplay(tier);
  const symbol         = _currencySymbol(currency);
  const storeName      = platform === 'ios' ? 'Apple App Store' : 'Google Play';

  const body = `
    <div style="text-align:center;font-size:48px;margin-bottom:8px;">🧾</div>

    <h2 style="margin:0 0 12px;font-size:22px;font-weight:800;
               color:${B.dark};text-align:center;">Payment Receipt</h2>
    <p style="color:${B.text};font-size:15px;line-height:1.65;text-align:center;
               margin:0 0 24px;">
      Hi ${firstName || 'there'}, here's your receipt for your Huddl subscription renewal.
    </p>

    ${_card([
      { label: 'Plan',     value: `Huddl ${tierName}` },
      { label: 'Amount',   value: `${symbol}${amount}` },
      { label: 'Date',     value: date || new Date().toLocaleDateString('en-GB') },
      { label: 'Billed via', value: storeName },
      { label: 'Reference', value: invoiceId || '&mdash;' },
    ])}

    <p style="color:${B.text};font-size:14px;line-height:1.6;margin:0 0 24px;">
      This is a Huddl payment record. Your official tax receipt is available in
      <strong>${storeName}</strong> under your purchase history.
    </p>

    ${_btn('View Subscription', `${FRONTEND_URL}/subscription`)}

    <p style="margin:0;font-size:12px;color:${B.textLight};text-align:center;">
      Questions? Reply to this email or contact us at welcome@huddlapp.co.uk
    </p>`;

  return _send(email, `Huddl receipt &mdash; ${symbol}${amount}`, body);
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. PAYMENT FAILURE WARNING
// ─────────────────────────────────────────────────────────────────────────────
async function sendPaymentFailedWarning({ email, firstName, platform }) {
  if (!email) return { success: false, error: 'no email address' };

  const storeName = platform === 'ios' ? 'App Store' : 'Google Play';

  const body = `
    <div style="text-align:center;font-size:48px;margin-bottom:8px;">⚠️</div>

    <h2 style="margin:0 0 12px;font-size:22px;font-weight:800;
               color:${B.dark};text-align:center;">Payment issue with your subscription</h2>
    <p style="color:${B.text};font-size:15px;line-height:1.65;text-align:center;
               margin:0 0 24px;">
      Hi ${firstName || 'there'}, we couldn't process your latest subscription payment.
    </p>

    <div style="background:#FFF3E0;border-radius:14px;padding:20px 24px;
                 margin:0 0 24px;border-left:4px solid #E88730;">
      <p style="margin:0;font-size:14px;color:${B.dark};line-height:1.55;">
        Your subscription is managed by <strong>${storeName}</strong>.
        To fix this, please update your payment method in your ${storeName} account settings.
        Your access continues while we retry.
      </p>
    </div>

    ${_btn(`Update Payment in ${storeName}`,
      platform === 'ios'
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions')}

    <p style="margin:0;font-size:12px;color:${B.textLight};text-align:center;">
      If payment continues to fail, your subscription will automatically lapse
      after the store's grace period. You'll keep the Welcome plan for free.
    </p>`;

  return _send(email, 'Action needed: Update your payment method', body);
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. CANCELLATION CONFIRMATION
// ─────────────────────────────────────────────────────────────────────────────
async function sendCancellationConfirmation({ email, firstName, endDate, tier, platform }) {
  if (!email) return { success: false, error: 'no email address' };

  const tierName  = _tierDisplay(tier);
  const storeName = platform === 'ios' ? 'App Store' : 'Google Play';

  const body = `
    <div style="text-align:center;font-size:48px;margin-bottom:8px;">💛</div>

    <h2 style="margin:0 0 12px;font-size:22px;font-weight:800;
               color:${B.dark};text-align:center;">We're sorry to see you go</h2>
    <p style="color:${B.text};font-size:15px;line-height:1.65;text-align:center;
               margin:0 0 24px;">
      Hi ${firstName || 'there'}, your Huddl ${tierName} subscription has been cancelled.
    </p>

    ${_card([
      { label: 'Plan cancelled', value: `Huddl ${tierName}` },
      { label: 'Access until',  value: endDate || 'End of your billing period' },
      { label: 'After that',    value: 'Welcome plan (free forever)' },
    ])}

    <p style="color:${B.text};font-size:14px;line-height:1.6;margin:0 0 24px;">
      Your groups and conversations will still be there after your plan ends
      &mdash; you'll just have the Welcome plan limits. Resubscribe anytime to
      pick up right where you left off.
    </p>

    ${_divider()}

    <div style="text-align:center;margin-bottom:16px;">
      <p style="margin:0 0 6px;font-size:15px;font-weight:700;color:${B.dark};">
        Changed your mind?
      </p>
      <p style="margin:0 0 16px;font-size:14px;color:${B.text};">
        Resubscribe via the ${storeName} and you'll be back instantly.
      </p>
      ${_btn('Resubscribe', `${FRONTEND_URL}/subscription/upgrade`)}
    </div>

    <p style="margin:0;font-size:12px;color:${B.textLight};text-align:center;">
      We'd love to know why you left &mdash; reply to this email anytime.
    </p>`;

  return _send(email, `Your Huddl ${tierName} subscription has been cancelled`, body);
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. SUBSCRIPTION REACTIVATED / RENEWED
// ─────────────────────────────────────────────────────────────────────────────
async function sendSubscriptionRenewed({ email, firstName, tier, renewalDate, platform }) {
  if (!email) return { success: false, error: 'no email address' };

  const tierName  = _tierDisplay(tier);
  const storeName = platform === 'ios' ? 'Apple App Store' : 'Google Play';

  const body = `
    <div style="text-align:center;font-size:48px;margin-bottom:8px;">✅</div>

    <h2 style="margin:0 0 12px;font-size:22px;font-weight:800;
               color:${B.dark};text-align:center;">
      Your subscription has been renewed!
    </h2>
    <p style="color:${B.text};font-size:15px;line-height:1.65;text-align:center;
               margin:0 0 24px;">
      Hi ${firstName || 'there'}, your <strong>Huddl ${tierName}</strong>
      subscription is active and renewing automatically.
    </p>

    ${_card([
      { label: 'Plan',       value: `Huddl ${tierName}` },
      { label: 'Billed via', value: storeName },
      { label: 'Next renewal', value: renewalDate || 'See your store account' },
      { label: 'Status',     value: `<span style="color:${B.success};">&#10003; Active</span>` },
    ])}

    ${_btn('Open Huddl', FRONTEND_URL)}

    <p style="margin:0;font-size:12px;color:${B.textLight};text-align:center;">
      Manage your subscription in ${storeName} under your account subscriptions.
    </p>`;

  return _send(email, `Huddl ${tierName} renewed ✅`, body);
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Map Firestore tier key to a user-facing display name. */
function _tierDisplay(tier) {
  if (!tier) return 'Neighbour';
  const t = tier.toLowerCase();
  if (t === 'innercircle' || t === 'circle') return 'Circle';
  if (t === 'explorer' || t === 'welcome')   return 'Welcome';
  return 'Neighbour'; // neighbourhood / neighbour
}

function _currencySymbol(currency) {
  if (!currency) return '£';
  switch ((currency || '').toUpperCase()) {
    case 'GBP': return '&pound;';
    case 'EUR': return '&euro;';
    case 'USD': return '$';
    default:    return `${currency} `;
  }
}

// ── Core send function ────────────────────────────────────────────────────────
async function _send(to, subject, bodyHtml) {
  if (!to) return { success: false, error: 'no recipient address' };

  const html = _wrap(subject, bodyHtml);

  // 1. Resend (HTTPS — works on Railway)
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
      console.log(`[Resend] Sent to ${to}: "${subject}" (id: ${data?.id})`);
      return { success: true, id: data?.id };
    } catch (err) {
      console.error(`[Resend] Exception sending to ${to}:`, err.message);
      return { success: false, error: err.message };
    }
  }

  // 2. Nodemailer SMTP fallback
  if (transporter) {
    try {
      const raceResult = await Promise.race([
        transporter.sendMail({
          from: `"${FROM_NAME}" <${FROM_EMAIL}>`,
          to,
          subject,
          html,
        }),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error('SMTP sendMail timed out after 20 seconds')), 20000)
        ),
      ]);
      console.log(`[SMTP] Sent to ${to}: "${subject}"`);
      return { success: true };
    } catch (err) {
      console.error(`[SMTP] Error (${to}):`, err.message);
      return { success: false, error: err.message };
    }
  }

  // 3. Mock (development)
  console.log(`[EMAIL MOCK] To: ${to} | Subject: ${subject}`);
  return { success: true, mock: true };
}

module.exports = {
  sendWelcomeEmail,
  sendSubscriptionConfirmation,
  sendPaymentReceipt,
  sendPaymentFailedWarning,
  sendCancellationConfirmation,
  sendSubscriptionRenewed,
};
