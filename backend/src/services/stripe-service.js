// ═══════════════════════════════════════════════════════════════════════════════
// Stripe Service — Checkout, Customer Portal, Subscription Management
// ═══════════════════════════════════════════════════════════════════════════════
//
// Maps Huddl product IDs to Stripe Price IDs and manages the full Stripe
// lifecycle: Checkout Session creation, Customer Portal, webhook event
// processing, and subscription state synchronization with Firestore.
//
// TIERS (updated — no founding member):
//   welcome  (free)           — no paid subscription
//   plus     (Huddl Plus)    — £4.99/mo | £39.99/yr
//   partner  (Huddl Partner) — £24.99/mo | £199/yr
//
// PRODUCT ID MAPPING (must match Flutter HuddlProductIds + App/Play Store)
// ──────────────────
//   App product ID              → Stripe Price ID env var
//   huddl_plus_monthly          → STRIPE_PRICE_PLUS_MONTHLY
//   huddl_plus_annual           → STRIPE_PRICE_PLUS_ANNUAL
//   huddl_partner_monthly       → STRIPE_PRICE_PARTNER_MONTHLY
//   huddl_partner_annual        → STRIPE_PRICE_PARTNER_ANNUAL
//
// TIER KEYS in Firestore (= Flutter SubscriptionTier enum .name values):
//   'welcome' → Welcome (free)
//   'plus'    → Huddl Plus paid tier
//   'partner' → Huddl Partner paid tier
//
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const Stripe = require('stripe');
const { getDb, FieldValue, admin } = require('./firebase-service');

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
  apiVersion: '2024-04-10',
});

// ── Helper: get human-readable display name from internal tier key ────────────
// tier is the Firestore key, which equals Flutter's SubscriptionTier enum .name:
//   'plus'    → 'Plus'    (SubscriptionTier.plus)
//   'partner' → 'Partner' (SubscriptionTier.partner)
//   'welcome' → 'Free'    (SubscriptionTier.welcome)
function tierDisplayName(tier) {
  switch (tier) {
    case 'plus':          return 'Plus';
    case 'partner':       return 'Partner';
    case 'welcome':       return 'Free';
    // Legacy SKU aliases (pre-TIER-KEY-1) — Flutter enum back-compat shim handles client side
    case 'innerCircle':   return 'Plus';
    case 'neighbour':     return 'Plus';
    case 'circle':        return 'Plus';
    default:              return 'Plus';
  }
}

// ── Entitlement claim: mirror the Stripe-authoritative tier onto a Firebase
//    Auth custom claim. Rules check request.auth.token.partner — the client
//    cannot set this; only the Admin SDK here can. (Audit: SUB-2/3, LSS-1, ANN-1, FEED-1.)
async function _syncPartnerClaim(userId, tier) {
  if (!userId) return;
  try {
    const isPartner = tier === 'partner';
    // Read existing claims so we don't clobber other claims (e.g. admin).
    const user = await admin.auth().getUser(userId);
    const existing = user.customClaims || {};
    // No-op if already correct (avoids needless token churn / revocation).
    if (!!existing.partner === isPartner) return;
    await admin.auth().setCustomUserClaims(userId, {
      ...existing,
      partner: isPartner,
    });
    console.log(`[claim] partner=${isPartner} set for ${userId}`);
  } catch (e) {
    // Best-effort: claim sync must NEVER break the webhook / subscription write.
    console.error(`[claim] failed to sync partner claim for ${userId}:`, e.message);
  }
}

// ── Product ID ↔ Stripe Price ID mapping ────────────────────────────────────
// Product IDs match Flutter's HuddlProductIds constants exactly.
const PRICE_MAP = {
  // Current product IDs
  huddl_plus_monthly:
    process.env.STRIPE_PRICE_PLUS_MONTHLY    || 'price_1TaagGGb8Lg9FVI5f2SrV5nv',
  huddl_plus_annual:
    process.env.STRIPE_PRICE_PLUS_ANNUAL     || 'price_1TaagHGb8Lg9FVI5k1BKNlqv',
  huddl_partner_monthly:
    process.env.STRIPE_PRICE_PARTNER_MONTHLY || 'price_1TaagHGb8Lg9FVI5bgzTWFLU',
  huddl_partner_annual:
    process.env.STRIPE_PRICE_PARTNER_ANNUAL  || 'price_1TaagIGb8Lg9FVI54eBr0Qgo',
};

// Reverse mapping: Stripe Price ID → App product ID
const REVERSE_PRICE_MAP = Object.fromEntries(
  Object.entries(PRICE_MAP).map(([k, v]) => [v, k])
);

// App product ID → { tier (Firestore key = Flutter SubscriptionTier enum .name), billingPeriod }
// CRITICAL: tier values MUST match Flutter's enum .name exactly:
//   SubscriptionTier.plus.name    == 'plus'     (TIER-KEY-1)
//   SubscriptionTier.partner.name == 'partner'
//   SubscriptionTier.welcome.name == 'welcome'  (free)
const PRODUCT_TIER_MAP = {
  huddl_plus_monthly:    { tier: 'plus',    billingPeriod: 'monthly' },
  huddl_plus_annual:     { tier: 'plus',    billingPeriod: 'annual'  },
  huddl_partner_monthly: { tier: 'partner', billingPeriod: 'monthly' },
  huddl_partner_annual:  { tier: 'partner', billingPeriod: 'annual'  },
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
      tier: tierInfo?.tier || 'welcome',
      billingPeriod: tierInfo?.billingPeriod || 'monthly',
    },
    subscription_data: {
      metadata: {
        userId,
        productId,
        tier: tierInfo?.tier || 'welcome',
      },
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

  // ── Idempotency guard ──────────────────────────────────────────────────────
  // Stripe can deliver the same webhook event multiple times (network retries,
  // Stripe's at-least-once delivery guarantee).  We deduplicate by writing the
  // event ID to `stripe_processed_events/{eventId}` before processing.
  //
  // Using a Firestore transaction (create-only) ensures atomicity:
  //   • First delivery  → document created, processing continues.
  //   • Duplicate       → create throws ALREADY_EXISTS, we return early.
  //
  // The document is written with a TTL field so a Cloud Firestore TTL policy
  // can auto-delete records older than 30 days and keep the collection lean.
  const eventRef = db.collection('stripe_processed_events').doc(event.id);
  try {
    await db.runTransaction(async (txn) => {
      const snap = await txn.get(eventRef);
      if (snap.exists) {
        // Already processed — signal early exit via a sentinel error.
        throw Object.assign(new Error('DUPLICATE_EVENT'), { code: 'DUPLICATE_EVENT' });
      }
      txn.create(eventRef, {
        eventId:   event.id,
        eventType: event.type,
        processedAt: FieldValue.serverTimestamp(),
        // TTL field: set to 30 days from now so a Firestore TTL policy can
        // auto-delete old records.  Enable via:
        //   Firebase Console → Firestore → TTL policies → collection=stripe_processed_events, field=expireAt
        expireAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      });
    });
  } catch (err) {
    if (err.code === 'DUPLICATE_EVENT') {
      console.log(`[Stripe] Duplicate event skipped: ${event.id} (${event.type})`);
      return; // ← early return, no double-processing
    }
    // Any other transaction error (Firestore unavailable, etc.) — log and
    // continue processing so the user's subscription still gets activated.
    // Accepting the small risk of a duplicate write is better than silently
    // dropping a legitimate payment event.
    console.warn(`[Stripe] Idempotency write failed (continuing): ${err.message}`);
  }
  // ── End idempotency guard ──────────────────────────────────────────────────

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
    tier: tierInfo.tier || 'welcome',
    billingPeriod: tierInfo.billingPeriod || 'monthly',
    isActive: true,
    isTrial: false,
    trialDaysRemaining: 0,
    startDate: now.toISOString(),
    renewalDate: renewalDate.toISOString(),
    stripeSubscriptionId: subscriptionId,
    stripeCustomerId: customerId,
    platform: 'web',
    updatedAt: FieldValue.serverTimestamp(),
  };

  const subRef = db.collection('subscriptions').doc(userId);
  await subRef.set(subData, { merge: true });
  await _syncPartnerClaim(userId, tierInfo.tier || 'welcome');

  await db.collection('users').doc(userId).update({
    stripeCustomerId: customerId,
    subscriptionTier: tierInfo.tier || 'welcome',
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

  const isTrial = false; // No free trials offered
  const isActive = subscription.status === 'active';
  const trialDaysRemaining = 0;

  await db.collection('subscriptions').doc(userId).update({
    tier: tierInfo.tier || 'welcome',
    billingPeriod: tierInfo.billingPeriod || 'monthly',
    isActive,
    isTrial,
    trialDaysRemaining,
    stripeStatus: subscription.status,
    cancelAtPeriodEnd: subscription.cancel_at_period_end || false,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await _syncPartnerClaim(userId, tierInfo.tier || 'welcome');

  console.log(`Subscription updated for user ${userId}: ${subscription.status}`);
}

async function _handleSubscriptionDeleted(db, subscription) {
  const userId = subscription.metadata?.userId;
  if (!userId) return;

  // Downgrade to Welcome (free) tier  (TIER-FALLBACK-1)
  await db.collection('subscriptions').doc(userId).set({
    tier: 'welcome',
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
  await _syncPartnerClaim(userId, 'welcome');  // clears the partner claim

  await db.collection('users').doc(userId).update({
    subscriptionTier: 'welcome',
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

  console.log(`Subscription cancelled for user ${userId} — downgraded to Welcome (free)`);
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
      tier: 'welcome',
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
