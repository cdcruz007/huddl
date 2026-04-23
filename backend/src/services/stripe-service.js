// ═══════════════════════════════════════════════════════════════════════════════
// Stripe Service — Checkout, Customer Portal, Subscription Management
// ═══════════════════════════════════════════════════════════════════════════════
//
// Maps Huddl product IDs to Stripe Price IDs and manages the full Stripe
// lifecycle: Checkout Session creation, Customer Portal, webhook event
// processing, and subscription state synchronization with Firestore.
//
// PRODUCT ID MAPPING
// ──────────────────
//   App product ID                         → Stripe Price ID
//   huddl_neighbourhood_monthly            → price_neighbourhood_monthly
//   huddl_neighbourhood_annual             → price_neighbourhood_annual
//   huddl_neighbourhood_founding_monthly   → price_neighbourhood_founding
//   huddl_inner_circle_monthly             → price_inner_circle_monthly
//   huddl_inner_circle_annual              → price_inner_circle_annual
//
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const Stripe = require('stripe');
const { getDb, FieldValue } = require('./firebase-service');

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
  apiVersion: '2024-04-10',
});

// ── Product ID ↔ Stripe Price ID mapping ────────────────────────────────────
const PRICE_MAP = {
  huddl_neighbourhood_monthly:
    process.env.STRIPE_PRICE_NEIGHBOURHOOD_MONTHLY || 'price_1TPMiQGb8Lg9FVI5hzdkzA23',
  huddl_neighbourhood_annual:
    process.env.STRIPE_PRICE_NEIGHBOURHOOD_ANNUAL || 'price_1TPMjBGb8Lg9FVI5zZwvMgVe',
  huddl_neighbourhood_founding_monthly:
    process.env.STRIPE_PRICE_NEIGHBOURHOOD_FOUNDING || 'price_1TPMiQGb8Lg9FVI5hzdkzA23',
  huddl_inner_circle_monthly:
    process.env.STRIPE_PRICE_INNER_CIRCLE_MONTHLY || 'price_1TPMkPGb8Lg9FVI57ETC2lCH',
  huddl_inner_circle_annual:
    process.env.STRIPE_PRICE_INNER_CIRCLE_ANNUAL || 'price_1TPMl5Gb8Lg9FVI5YKuJNSRL',
};

// Reverse mapping: Stripe Price ID → App product ID
const REVERSE_PRICE_MAP = Object.fromEntries(
  Object.entries(PRICE_MAP).map(([k, v]) => [v, k])
);

// App product ID → { tier, billingPeriod }
const PRODUCT_TIER_MAP = {
  huddl_neighbourhood_monthly: { tier: 'neighbourhood', billingPeriod: 'monthly' },
  huddl_neighbourhood_annual: { tier: 'neighbourhood', billingPeriod: 'annual' },
  huddl_neighbourhood_founding_monthly: { tier: 'neighbourhood', billingPeriod: 'monthly', founding: true },
  huddl_inner_circle_monthly: { tier: 'innerCircle', billingPeriod: 'monthly' },
  huddl_inner_circle_annual: { tier: 'innerCircle', billingPeriod: 'annual' },
};

// ═════════════════════════════════════════════════════════════════════════════
// CHECKOUT SESSION
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Create a Stripe Checkout Session for a subscription purchase.
 *
 * @param {Object} params
 * @param {string} params.userId        - Firebase UID
 * @param {string} params.email         - User email for Stripe customer
 * @param {string} params.productId     - Huddl product ID (e.g. 'huddl_neighbourhood_monthly')
 * @param {string} [params.successUrl]  - Redirect URL on success
 * @param {string} [params.cancelUrl]   - Redirect URL on cancel
 * @returns {Object} { sessionId, url }
 */
async function createCheckoutSession({ userId, email, productId, successUrl, cancelUrl }) {
  const priceId = PRICE_MAP[productId];
  if (!priceId) {
    throw new Error(`Unknown product ID: ${productId}`);
  }

  const tierInfo = PRODUCT_TIER_MAP[productId];

  // Find or create a Stripe customer for this user
  const customerId = await findOrCreateCustomer(userId, email);

  const sessionParams = {
    mode: 'subscription',
    customer: customerId,
    line_items: [{ price: priceId, quantity: 1 }],
    success_url:
      successUrl ||
      `${process.env.STRIPE_SUCCESS_URL || 'https://huddlapp.co.uk/subscription/success'}?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url:
      cancelUrl ||
      `${process.env.STRIPE_CANCEL_URL || 'https://huddlapp.co.uk/subscription/cancel'}`,
    metadata: {
      userId,
      productId,
      tier: tierInfo?.tier || 'unknown',
      billingPeriod: tierInfo?.billingPeriod || 'unknown',
      founding: tierInfo?.founding ? 'true' : 'false',
    },
    subscription_data: {
      metadata: {
        userId,
        productId,
        tier: tierInfo?.tier || 'unknown',
      },
      // 7-day free trial for new subscribers
      trial_period_days: 7,
    },
    // Enable automatic tax calculation (UK VAT)
    automatic_tax: { enabled: false }, // Enable when Stripe Tax is configured
    // Allow promotion codes
    allow_promotion_codes: true,
    // Locale
    locale: 'en-GB',
    // Payment method types
    payment_method_types: ['card'],
    // Billing address collection
    billing_address_collection: 'required',
  };

  const session = await stripe.checkout.sessions.create(sessionParams);

  // Store session reference in Firestore for tracking
  const db = getDb();
  await db.collection('stripe_sessions').doc(session.id).set({
    userId,
    productId,
    tier: tierInfo?.tier,
    billingPeriod: tierInfo?.billingPeriod,
    status: 'pending',
    createdAt: FieldValue.serverTimestamp(),
  });

  return { sessionId: session.id, url: session.url };
}

// ═════════════════════════════════════════════════════════════════════════════
// CUSTOMER PORTAL
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Create a Stripe Customer Portal session for managing subscriptions.
 * Users can upgrade, downgrade, cancel, update payment method.
 *
 * @param {string} userId - Firebase UID
 * @returns {Object} { url }
 */
async function createPortalSession(userId) {
  const db = getDb();
  const userDoc = await db.collection('users').doc(userId).get();
  const stripeCustomerId = userDoc.data()?.stripeCustomerId;

  if (!stripeCustomerId) {
    throw new Error('No Stripe customer found for this user');
  }

  const session = await stripe.billingPortal.sessions.create({
    customer: stripeCustomerId,
    return_url: process.env.FRONTEND_URL || 'https://huddlapp.co.uk',
  });

  return { url: session.url };
}

// ═════════════════════════════════════════════════════════════════════════════
// CUSTOMER MANAGEMENT
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Find an existing Stripe customer by Firebase UID, or create a new one.
 */
async function findOrCreateCustomer(userId, email) {
  const db = getDb();
  const userRef = db.collection('users').doc(userId);
  const userDoc = await userRef.get();
  const userData = userDoc.data() || {};

  // If we already have a Stripe customer ID, return it
  if (userData.stripeCustomerId) {
    return userData.stripeCustomerId;
  }

  // Create a new Stripe customer
  const customer = await stripe.customers.create({
    email: email || userData.email || `${userId}@huddl.app`,
    name: `${userData.firstName || ''} ${userData.lastName || ''}`.trim() || undefined,
    metadata: {
      firebaseUid: userId,
      borough: userData.borough || '',
    },
  });

  // Store the Stripe customer ID in Firestore
  await userRef.update({
    stripeCustomerId: customer.id,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return customer.id;
}

// ═════════════════════════════════════════════════════════════════════════════
// WEBHOOK EVENT HANDLERS
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Process a verified Stripe webhook event.
 *
 * Events handled:
 *   checkout.session.completed     — first-time subscription activation
 *   invoice.payment_succeeded      — recurring payment success
 *   invoice.payment_failed         — payment failure (grace period)
 *   customer.subscription.updated  — plan change, trial end
 *   customer.subscription.deleted  — cancellation finalized
 */
async function handleWebhookEvent(event) {
  const db = getDb();

  switch (event.type) {
    case 'checkout.session.completed':
      await _handleCheckoutCompleted(db, event.data.object);
      break;

    case 'invoice.payment_succeeded':
      await _handlePaymentSucceeded(db, event.data.object);
      break;

    case 'invoice.payment_failed':
      await _handlePaymentFailed(db, event.data.object);
      break;

    case 'customer.subscription.updated':
      await _handleSubscriptionUpdated(db, event.data.object);
      break;

    case 'customer.subscription.deleted':
      await _handleSubscriptionDeleted(db, event.data.object);
      break;

    default:
      console.log(`Unhandled Stripe event: ${event.type}`);
  }
}

// ── Internal webhook handlers ───────────────────────────────────────────────

async function _handleCheckoutCompleted(db, session) {
  const userId = session.metadata?.userId;
  if (!userId) {
    console.error('checkout.session.completed: no userId in metadata');
    return;
  }

  const productId = session.metadata?.productId;
  const tierInfo = PRODUCT_TIER_MAP[productId] || {};

  const subscriptionId = session.subscription;
  const customerId = session.customer;

  // Update user's subscription in Firestore
  const now = new Date();
  const renewalDate = new Date(now);
  if (tierInfo.billingPeriod === 'annual') {
    renewalDate.setFullYear(renewalDate.getFullYear() + 1);
  } else {
    renewalDate.setMonth(renewalDate.getMonth() + 1);
  }

  const subData = {
    tier: tierInfo.tier || 'neighbourhood',
    billingPeriod: tierInfo.billingPeriod || 'monthly',
    isActive: true,
    isTrial: session.subscription ? true : false, // trial starts with subscription
    trialDaysRemaining: 7,
    isFoundingMember: tierInfo.founding || false,
    startDate: now.toISOString(),
    renewalDate: renewalDate.toISOString(),
    stripeSubscriptionId: subscriptionId,
    stripeCustomerId: customerId,
    platform: 'web',
    updatedAt: FieldValue.serverTimestamp(),
  };

  // Update or create the subscription document
  const subRef = db.collection('subscriptions').doc(userId);
  await subRef.set(subData, { merge: true });

  // Update user document with Stripe IDs
  await db.collection('users').doc(userId).update({
    stripeCustomerId: customerId,
    subscriptionTier: tierInfo.tier || 'neighbourhood',
    updatedAt: FieldValue.serverTimestamp(),
  });

  // Update checkout session tracking
  await db.collection('stripe_sessions').doc(session.id).update({
    status: 'completed',
    subscriptionId,
    completedAt: FieldValue.serverTimestamp(),
  });

  console.log(`Subscription activated for user ${userId}: ${tierInfo.tier} (${tierInfo.billingPeriod})`);
}

async function _handlePaymentSucceeded(db, invoice) {
  const customerId = invoice.customer;
  if (!customerId) return;

  // Find user by Stripe customer ID
  const userSnap = await db.collection('users')
    .where('stripeCustomerId', '==', customerId)
    .limit(1)
    .get();

  if (userSnap.empty) {
    console.warn(`payment_succeeded: no user found for customer ${customerId}`);
    return;
  }

  const userId = userSnap.docs[0].id;

  // Update subscription to active (in case it was in grace period)
  await db.collection('subscriptions').doc(userId).update({
    isActive: true,
    isTrial: false,
    lastPaymentAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  console.log(`Payment succeeded for user ${userId}`);
}

async function _handlePaymentFailed(db, invoice) {
  const customerId = invoice.customer;
  if (!customerId) return;

  const userSnap = await db.collection('users')
    .where('stripeCustomerId', '==', customerId)
    .limit(1)
    .get();

  if (userSnap.empty) return;

  const userId = userSnap.docs[0].id;

  // Mark as payment failed (grace period — Stripe retries automatically)
  await db.collection('subscriptions').doc(userId).update({
    paymentFailed: true,
    paymentFailedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  // Create a notification for the user
  await db.collection('notifications').add({
    userId,
    type: 'payment_failed',
    title: 'Payment Failed',
    body: 'We couldn\'t process your subscription payment. Please update your payment method to avoid losing access.',
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  console.log(`Payment failed for user ${userId}`);
}

async function _handleSubscriptionUpdated(db, subscription) {
  const userId = subscription.metadata?.userId;
  if (!userId) return;

  const priceId = subscription.items?.data?.[0]?.price?.id;
  const productId = REVERSE_PRICE_MAP[priceId];
  const tierInfo = productId ? PRODUCT_TIER_MAP[productId] : {};

  const isTrial = subscription.status === 'trialing';
  const isActive = ['active', 'trialing'].includes(subscription.status);

  let trialDaysRemaining = 0;
  if (isTrial && subscription.trial_end) {
    const trialEnd = new Date(subscription.trial_end * 1000);
    trialDaysRemaining = Math.max(0, Math.ceil((trialEnd - new Date()) / (1000 * 60 * 60 * 24)));
  }

  await db.collection('subscriptions').doc(userId).update({
    tier: tierInfo.tier || 'neighbourhood',
    billingPeriod: tierInfo.billingPeriod || 'monthly',
    isActive,
    isTrial,
    trialDaysRemaining,
    stripeStatus: subscription.status,
    cancelAtPeriodEnd: subscription.cancel_at_period_end || false,
    updatedAt: FieldValue.serverTimestamp(),
  });

  console.log(`Subscription updated for user ${userId}: ${subscription.status}`);
}

async function _handleSubscriptionDeleted(db, subscription) {
  const userId = subscription.metadata?.userId;
  if (!userId) return;

  // Downgrade to Explorer (free) tier
  await db.collection('subscriptions').doc(userId).set({
    tier: 'explorer',
    billingPeriod: 'monthly',
    isActive: true,
    isTrial: false,
    trialDaysRemaining: 0,
    isFoundingMember: false,
    startDate: new Date().toISOString(),
    renewalDate: null,
    stripeSubscriptionId: null,
    cancelledAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: false });

  // Update user tier
  await db.collection('users').doc(userId).update({
    subscriptionTier: 'explorer',
    updatedAt: FieldValue.serverTimestamp(),
  });

  // Notify user
  await db.collection('notifications').add({
    userId,
    type: 'subscription_cancelled',
    title: 'Subscription Ended',
    body: 'Your subscription has ended. You\'ve been moved to the free Explorer plan. Upgrade anytime to get back your features!',
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  console.log(`Subscription cancelled for user ${userId} — downgraded to Explorer`);
}

// ═════════════════════════════════════════════════════════════════════════════
// SUBSCRIPTION QUERY
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Get the current subscription status for a user.
 */
async function getSubscriptionStatus(userId) {
  const db = getDb();
  const subDoc = await db.collection('subscriptions').doc(userId).get();

  if (!subDoc.exists) {
    return {
      tier: 'explorer',
      billingPeriod: 'monthly',
      isActive: true,
      isTrial: false,
      platform: 'none',
    };
  }

  return subDoc.data();
}

/**
 * Cancel a subscription (marks as cancel-at-period-end in Stripe).
 */
async function cancelSubscription(userId, { reason, pauseMonths } = {}) {
  const db = getDb();
  const subDoc = await db.collection('subscriptions').doc(userId).get();
  const subData = subDoc.data();

  if (!subData?.stripeSubscriptionId) {
    throw new Error('No active Stripe subscription found');
  }

  if (pauseMonths && pauseMonths > 0) {
    // Pause instead of cancel (1-month pause on cancellation)
    const resumeDate = new Date();
    resumeDate.setMonth(resumeDate.getMonth() + pauseMonths);

    await stripe.subscriptions.update(subData.stripeSubscriptionId, {
      pause_collection: {
        behavior: 'void',
        resumes_at: Math.floor(resumeDate.getTime() / 1000),
      },
    });

    await subDoc.ref.update({
      paused: true,
      pausedUntil: resumeDate.toISOString(),
      cancelReason: reason || '',
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { status: 'paused', resumesAt: resumeDate.toISOString() };
  }

  // Cancel at end of billing period
  await stripe.subscriptions.update(subData.stripeSubscriptionId, {
    cancel_at_period_end: true,
  });

  await subDoc.ref.update({
    cancelAtPeriodEnd: true,
    cancelReason: reason || '',
    cancelRequestedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { status: 'cancelling', cancelAtPeriodEnd: true };
}

module.exports = {
  stripe,
  PRICE_MAP,
  REVERSE_PRICE_MAP,
  PRODUCT_TIER_MAP,
  createCheckoutSession,
  createPortalSession,
  findOrCreateCustomer,
  handleWebhookEvent,
  getSubscriptionStatus,
  cancelSubscription,
};
