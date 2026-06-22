// ═══════════════════════════════════════════════════════════════════════════════
// Webhook Routes — Stripe, Apple, Google
// ═══════════════════════════════════════════════════════════════════════════════
//
// IMPORTANT: These routes are mounted BEFORE express.json() in server.js
// because Stripe webhook signature verification requires the raw body.
//
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const express = require('express');
const router = express.Router();
const { stripe, handleWebhookEvent } = require('../services/stripe-service');
const {
  handleAppleNotification,
  handleGoogleNotification,
} = require('../services/receipt-verification-service');
const {
  sendSubscriptionConfirmation,
  sendPaymentReceipt,
  sendPaymentFailedWarning,
  sendCancellationConfirmation,
  sendSubscriptionRenewed,
} = require('../services/email-service');
const { sendToUser } = require('../services/notification-service');
const { getDb } = require('../services/firebase-service');
const { OAuth2Client } = require('google-auth-library');

// Shared OAuth2Client instance for OIDC token verification (stateless — no client ID needed).
const _googleOAuth2Client = new OAuth2Client();

/**
 * Verify the Google OIDC JWT attached by Pub/Sub to authenticated push requests.
 *
 * Google Pub/Sub adds: Authorization: Bearer <OIDC JWT>
 * where the JWT is signed by Google, iss = 'accounts.google.com' (or
 * 'https://accounts.google.com'), and email = the push subscription's SA.
 *
 * Returns the verified LoginTicket payload, or throws on any failure.
 *
 * CONFIG: set GOOGLE_PUBSUB_SA_EMAIL in Railway to the service-account email
 * configured on the Pub/Sub push subscription, AND enable authentication on
 * the push subscription itself. Until GOOGLE_PUBSUB_SA_EMAIL is set the
 * /google handler falls through with a warning (fail-open) so the route
 * remains operational during initial deployment.
 */
async function _verifyGooglePubSubToken(authHeader) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('Missing or malformed Authorization header');
  }
  const token = authHeader.slice('Bearer '.length);

  // verifyIdToken with no audience checks signature + expiry via Google certs.
  // We do NOT pass an audience here because Pub/Sub push audiences vary by
  // subscription config; the SA email check below is the binding constraint.
  const ticket = await _googleOAuth2Client.verifyIdToken({ idToken: token });
  const payload = ticket.getPayload();

  // Validate issuer
  const iss = payload.iss || '';
  if (iss !== 'accounts.google.com' && iss !== 'https://accounts.google.com') {
    throw new Error(`Unexpected OIDC issuer: ${iss}`);
  }

  // Validate the token belongs to the configured push-subscription SA
  const expectedSA = process.env.GOOGLE_PUBSUB_SA_EMAIL;
  if (payload.email !== expectedSA) {
    throw new Error(`OIDC email mismatch: got ${payload.email}, expected ${expectedSA}`);
  }

  // Google-issued tokens for SAs always have email_verified = true; guard anyway.
  if (!payload.email_verified) {
    throw new Error('OIDC email_verified is false');
  }

  return payload;
}

// ── POST /api/webhooks/stripe ───────────────────────────────────────────────
// Stripe sends events here. Must verify the signature using the raw body.
//
// Setup:
//   1. Stripe Dashboard > Developers > Webhooks > Add endpoint
//   2. URL: https://api.huddlapp.co.uk/api/webhooks/stripe
//   3. Events: checkout.session.completed, invoice.payment_succeeded,
//              invoice.payment_failed, customer.subscription.updated,
//              customer.subscription.deleted
//   4. Copy signing secret → STRIPE_WEBHOOK_SECRET in .env
//
// Local testing:
//   stripe listen --forward-to localhost:3000/api/webhooks/stripe
router.post(
  '/stripe',
  express.raw({ type: 'application/json' }),
  async (req, res) => {
    const sig = req.headers['stripe-signature'];
    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;

    let event;
    try {
      event = stripe.webhooks.constructEvent(req.body, sig, webhookSecret);
    } catch (err) {
      console.error('Stripe webhook signature verification failed:', err.message);
      return res.status(400).json({ error: `Webhook Error: ${err.message}` });
    }

    try {
      // Process the Stripe event (updates Firestore)
      await handleWebhookEvent(event);

      // ── Send transactional emails & push notifications ──────────────
      await _handleStripeEmailAndPush(event);

      res.json({ received: true });
    } catch (err) {
      console.error('Stripe webhook processing error:', err);
      // Return 200 anyway to prevent Stripe from retrying
      res.json({ received: true, warning: err.message });
    }
  }
);

/**
 * Send emails and push notifications based on Stripe events.
 */
async function _handleStripeEmailAndPush(event) {
  const db = getDb();
  const obj = event.data.object;

  switch (event.type) {
    case 'checkout.session.completed': {
      const userId = obj.metadata?.userId;
      if (!userId) return;
      const userDoc = await db.collection('users').doc(userId).get();
      const user = userDoc.data() || {};
      // tier is the Firestore key = Flutter SubscriptionTier enum .name
      const tier = obj.metadata?.tier || 'welcome';  // TIER-FALLBACK-1
      const billingPeriod = obj.metadata?.billingPeriod || 'monthly';

      // Derive display name and price from the Firestore tier key
      const tierDisplayName = tier === 'partner' ? 'Partner' : 'Plus';
      const price = billingPeriod === 'annual'
        ? (tier === 'partner' ? '199.00' : '39.99')
        : (tier === 'partner' ? '24.99' : '4.99');

      await sendSubscriptionConfirmation({
        email: user.email || obj.customer_details?.email,
        firstName: user.firstName,
        tier,
        billingPeriod,
        price,
      });

      await sendToUser(userId, 'subscription_activated', {
        tierName: tierDisplayName,
      });
      break;
    }

    case 'invoice.payment_succeeded': {
      const customerId = obj.customer;
      if (!customerId) return;
      const userSnap = await db.collection('users')
        .where('stripeCustomerId', '==', customerId).limit(1).get();
      if (userSnap.empty) return;
      const userId = userSnap.docs[0].id;
      const user = userSnap.docs[0].data();

      await sendPaymentReceipt({
        email: user.email || obj.customer_email,
        firstName: user.firstName,
        tier: user.subscriptionTier || 'welcome',  // TIER-FALLBACK-1
        amount: (obj.amount_paid / 100).toFixed(2),
        currency: (obj.currency || 'gbp').toUpperCase(),
        invoiceId: obj.id,
        date: new Date(obj.created * 1000).toLocaleDateString('en-GB'),
      });
      break;
    }

    case 'invoice.payment_failed': {
      const customerId = obj.customer;
      if (!customerId) return;
      const userSnap = await db.collection('users')
        .where('stripeCustomerId', '==', customerId).limit(1).get();
      if (userSnap.empty) return;
      const userId = userSnap.docs[0].id;
      const user = userSnap.docs[0].data();

      await sendPaymentFailedWarning({
        email: user.email || obj.customer_email,
        firstName: user.firstName,
      });
      await sendToUser(userId, 'payment_failed');
      break;
    }

    case 'customer.subscription.deleted': {
      const userId = obj.metadata?.userId;
      if (!userId) return;
      const userDoc = await db.collection('users').doc(userId).get();
      const user = userDoc.data() || {};

      await sendCancellationConfirmation({
        email: user.email,
        firstName: user.firstName,
        tier: obj.metadata?.tier || 'welcome',  // TIER-FALLBACK-1
      });
      await sendToUser(userId, 'subscription_cancelled');
      break;
    }
  }
}

// ── POST /api/webhooks/apple ────────────────────────────────────────────────
// Apple App Store Server Notifications v2.
//
// Setup:
//   App Store Connect > App > General > App Store Server Notifications
//   URL: https://api.huddlapp.co.uk/api/webhooks/apple
//   Version: Version 2
router.post('/apple', express.json(), async (req, res) => {
  try {
    const { signedPayload } = req.body;
    if (!signedPayload) {
      return res.status(400).json({ error: 'Missing signedPayload' });
    }

    await handleAppleNotification(signedPayload);
    res.json({ received: true });
  } catch (err) {
    console.error('Apple webhook error:', err);
    res.json({ received: true, warning: err.message });
  }
});

// ── POST /api/webhooks/google ───────────────────────────────────────────────
// Google Play Real-Time Developer Notifications (RTDN) via Pub/Sub.
//
// Setup:
//   1. Google Cloud Console > Pub/Sub > Create topic
//   2. Create push subscription → URL: https://api.huddlapp.co.uk/api/webhooks/google
//      Enable authentication and set service account → set GOOGLE_PUBSUB_SA_EMAIL in Railway.
//   3. Google Play Console > Monetization > Monetization setup > Real-time notifications
//      → Set topic to the Pub/Sub topic
//   URL: https://api.huddlapp.co.uk/api/webhooks/google
//
// SECURITY (H2): verifies the Google OIDC token in Authorization: Bearer.
//   - GOOGLE_PUBSUB_SA_EMAIL set   → fail-CLOSED: 401 on bad/missing token.
//   - GOOGLE_PUBSUB_SA_EMAIL unset → fail-OPEN with warning (not yet configured).
router.post('/google', express.json(), async (req, res) => {
  // ── OIDC token verification ─────────────────────────────────────────────
  const expectedSA = process.env.GOOGLE_PUBSUB_SA_EMAIL;
  if (expectedSA) {
    try {
      await _verifyGooglePubSubToken(req.headers.authorization);
    } catch (err) {
      console.warn('[google-webhook] OIDC verification failed:', err.message);
      return res.status(401).send();
    }
  } else {
    console.warn(
      '[google-webhook] GOOGLE_PUBSUB_SA_EMAIL not set — skipping OIDC check (fail-open). ' +
      'Set this env var + enable Pub/Sub push authentication to harden this endpoint.'
    );
  }

  try {
    const message = req.body.message;
    if (!message || !message.data) {
      return res.status(400).json({ error: 'Missing Pub/Sub message' });
    }

    await handleGoogleNotification(message);
    res.status(200).send(); // Acknowledge Pub/Sub message
  } catch (err) {
    console.error('Google webhook error:', err);
    res.status(200).send(); // Ack anyway to prevent infinite retries
  }
});

module.exports = router;
