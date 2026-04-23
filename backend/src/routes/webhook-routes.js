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
} = require('../services/email-service');
const { sendToUser } = require('../services/notification-service');
const { getDb } = require('../services/firebase-service');

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
      const tier = obj.metadata?.tier || 'neighbourhood';
      const billingPeriod = obj.metadata?.billingPeriod || 'monthly';

      // Derive display name and price from the Firestore tier key
      const tierDisplayName = tier === 'innerCircle' ? 'Circle' : 'Neighbour';
      const price = billingPeriod === 'annual'
        ? (tier === 'innerCircle' ? '99.99' : '49.99')
        : (tier === 'innerCircle' ? '12.99' : '5.99');

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
        tier: user.subscriptionTier || 'neighbourhood',
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
        tier: obj.metadata?.tier || 'neighbourhood',
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
//   3. Google Play Console > Monetization > Monetization setup > Real-time notifications
//      → Set topic to the Pub/Sub topic
//   URL: https://api.huddlapp.co.uk/api/webhooks/google
router.post('/google', express.json(), async (req, res) => {
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
