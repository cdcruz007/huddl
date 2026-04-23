// ═══════════════════════════════════════════════════════════════════════════════
// Stripe Service — Checkout, Customer Portal, Subscription Management
// ═══════════════════════════════════════════════════════════════════════════════
//
// Maps Huddl product IDs to Stripe Price IDs and manages the full Stripe
// lifecycle: Checkout Session creation, Customer Portal, webhook event
// processing, and subscription state synchronization with Firestore.
//
// TIERS (3 tiers, no founding member):
//   welcome      — free, explorer enum key in Firestore
//   neighbour    — £5.99/mo | £49.99/yr
//   circle       — £12.99/mo | £99.99/yr
//
// PRODUCT ID MAPPING (must match Flutter HuddlProductIds + App/Play Store)
// ──────────────────
//   App product ID              → Stripe Price ID env var
//   huddl_neighbour_monthly     → STRIPE_PRICE_NEIGHBOUR_MONTHLY
//   huddl_neighbour_annual      → STRIPE_PRICE_NEIGHBOUR_ANNUAL
//   huddl_circle_monthly        → STRIPE_PRICE_CIRCLE_MONTHLY
//   huddl_circle_annual         → STRIPE_PRICE_CIRCLE_ANNUAL
//
// TIER KEYS in Firestore (= Flutter SubscriptionTier enum .name values):
//   'explorer'      → Welcome (free)
//   'neighbourhood' → Neighbour paid tier
//   'innerCircle'   → Circle paid tier
//
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const Stripe = require('stripe');
const { getDb, FieldValue } = require('./firebase-service');

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
  apiVersion: '2024-04-10',
});

// ── Helper: get human-readable display name from internal tier key ────────────
// tier is the Firestore key, which equals Flutter's SubscriptionTier enum .name:
//   'neighbourhood' → 'Neighbour'  (SubscriptionTier.neighbourhood)
//   'innerCircle'   → 'Circle'     (SubscriptionTier.innerCircle)
//   'explorer'      → 'Welcome'    (SubscriptionTier.explorer)
function tierDisplayName(tier) {
  switch (tier) {
    case 'neighbourhood': return 'Neighbour';
    case 'innerCircle':   return 'Circle';
    case 'explorer':      return 'Welcome';
    // Legacy fallbacks for any old data still using short keys
    case 'neighbour':     return 'Neighbour';
    case 'circle':        return 'Circle';
    default:              return 'Neighbour';
  }
}

// ── Product ID ↔ Stripe Price ID mapping ────────────────────────────────────
// Product IDs match Flutter's HuddlProductIds constants exactly.
const PRICE_MAP = {
  huddl_neighbour_monthly:
    process.env.STRIPE_PRICE_NEIGHBOUR_MONTHLY || 'price_1TPMiQGb8Lg9FVI5hzdkzA23',
  huddl_neighbour_annual:
    process.env.STRIPE_PRICE_NEIGHBOUR_ANNUAL  || 'price_1TPMjBGb8Lg9FVI5zZwvMgVe',
  huddl_circle_monthly:
    process.env.STRIPE_PRICE_CIRCLE_MONTHLY    || 'price_1TPUqjGb8Lg9FVI5uk3rAKlJ',
  huddl_circle_annual:
    process.env.STRIPE_PRICE_CIRCLE_ANNUAL     || 'price_1TPMl5Gb8Lg9FVI5YKuJNSRL',
};

// Reverse mapping: Stripe Price ID → App product ID
const REVERSE_PRICE_MAP = Object.fromEntries(
  Object.entries(PRICE_MAP).map(([k, v]) => [v, k])
);

// App product ID → { tier (Firestore key = Flutter SubscriptionTier enum .name), billingPeriod }
// CRITICAL: tier values MUST match Flutter's enum .name exactly:
//   SubscriptionTier.neighbourhood.name == 'neighbourhood'
//   SubscriptionTier.innerCircle.name   == 'innerCircle'
const PRODUCT_TIER_MAP = {
  huddl_neighbour_monthly: { tier: 'neighbourhood', billingPeriod: 'monthly' },
  huddl_neighbour_annual:  { tier: 'neighbourhood', billingPeriod: 'annual'  },
  huddl_circle_monthly:    { tier: 'innerCircle',   billingPeriod: 'monthly' },
  huddl_circle_annual:     { tier: 'innerCircle',   billingPeriod: 'annual'  },
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
 * @param {string} params.productId     - Huddl product ID (e.g. 'huddl_neighbour_monthly')
 * @param {string} [params.successUrl]  - Redirect URL on success
 * @param {string} [params.cancelUrl]   - Redirect URL on cancel
 * @returns {Object} { sessionId, url }
 */
async function createCheckoutSession({ userId, email, productId, successUrl, cancelUrl }) {
  const priceId = PRICE_MAP[productId];
  if (!priceId) {
    throw new Error(`Unknown product ID: ${productId}. Valid IDs: ${Object.keys(PRICE_MAP).join(', ')}`);
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
      `${process.env.STRIPE_SUCCESS_URL || 'https://huddlconnect.com/subscription/success'}?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url:
      cancelUrl ||
      `${process.env.STRIPE_CANCEL_URL || 'https://huddlconnect.com/subscription/cancel'}`,
    metadata: {
      userId,
      productId,
      tier: tierInfo?.tier || 'neighbourhood',
      billingPeriod: tierInfo?.billingPeriod || 'monthly',
    },
    subscription_data: {
      metadata: {
        userId,
        productId,
        tier: tierInfo?.tier || 'neighbourhood',
      },
      // 7-day free trial for new subscribers
      trial_period_days: 7,
    },
    automatic_tax: { enabled: true }, // Stripe Tax activated — handles UK VAT automatically
    allow_promotion_codes: true,
    locale: 'en-GB',
    // Omitting payment_method_types lets Stripe auto-present card, Apple Pay,
    // and Google Pay based on the user's device/browser — no manual list needed.
    billing_address_collection: 'required',
    customer_update: {
      address: 'auto', // Required for automatic_tax — persists billing address to customer
    },
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
    return_url: process.env.FRONTEND_URL || 'https://huddlconnect.com',
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

  if (userData.stripeCustomerId) {
    return userData.stripeCustomerId;
  }

  const customer = await stripe.customers.create({
    email: email || userData.email || `${userId}@huddl.app`,
    name: `${userData.firstName || ''} ${userData.lastName || ''}`.trim() || undefined,
    metadata: {
      firebaseUid: userId,
      borough: userData.borough || '',
    },
  });

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
    isTrial: true, // starts with 7-day trial
    trialDaysRemaining: 7,
    startDate: now.toISOString(),
    renewalDate: renewalDate.toISOString(),
    stripeSubscriptionId: subscriptionId,
    stripeCustomerId: customerId,
    platform: 'web',
    updatedAt: FieldValue.serverTimestamp(),
  };

  const subRef = db.collection('subscriptions').doc(userId);
  await subRef.set(subData, { merge: true });

  await db.collection('users').doc(userId).update({
    stripeCustomerId: customerId,
    subscriptionTier: tierInfo.tier || 'neighbourhood',
    updatedAt: FieldValue.serverTimestamp(),
  });

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

  const userSnap = await db.collection('users')
    .where('stripeCustomerId', '==', customerId)
    .limit(1)
    .get();

  if (userSnap.empty) {
    console.warn(`payment_succeeded: no user found for customer ${customerId}`);
    return;
  }

  const userId = userSnap.docs[0].id;

  await db.collection('subscriptions').doc(userId).update({
    isActive: true,
    isTrial: false,
    paymentFailed: false,
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

  await db.collection('subscriptions').doc(userId).update({
    paymentFailed: true,
    paymentFailedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

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

  // Downgrade to Welcome (free / explorer) tier
  await db.collection('subscriptions').doc(userId).set({
    tier: 'explorer',
    billingPeriod: 'monthly',
    isActive: true,
    isTrial: false,
    trialDaysRemaining: 0,
    startDate: new Date().toISOString(),
    renewalDate: null,
    stripeSubscriptionId: null,
    cancelledAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: false });

  await db.collection('users').doc(userId).update({
    subscriptionTier: 'explorer',
    updatedAt: FieldValue.serverTimestamp(),
  });

  await db.collection('notifications').add({
    userId,
    type: 'subscription_cancelled',
    title: 'Subscription Ended',
    body: 'Your subscription has ended. You\'ve been moved to the Welcome plan. Upgrade anytime to get back your features!',
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  console.log(`Subscription cancelled for user ${userId} — downgraded to Welcome (explorer)`);
}

// ═════════════════════════════════════════════════════════════════════════════
// SUBSCRIPTION QUERY
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Get the current subscription status for a user.
 * Returns explorer (Welcome) by default for new/unknown users.
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
 * Optionally pauses for pauseMonths instead of cancelling.
 */
async function cancelSubscription(userId, { reason, pauseMonths } = {}) {
  const db = getDb();
  const subDoc = await db.collection('subscriptions').doc(userId).get();
  const subData = subDoc.data();

  if (!subData?.stripeSubscriptionId) {
    throw new Error('No active Stripe subscription found');
  }

  if (pauseMonths && pauseMonths > 0) {
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
  tierDisplayName,
  createCheckoutSession,
  createPortalSession,
  findOrCreateCustomer,
  handleWebhookEvent,
  getSubscriptionStatus,
  cancelSubscription,
};
