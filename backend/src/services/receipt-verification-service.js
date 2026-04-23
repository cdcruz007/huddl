// ═══════════════════════════════════════════════════════════════════════════════
// Receipt Verification Service
// ═══════════════════════════════════════════════════════════════════════════════
//
// Server-side receipt verification for:
//   1. Apple App Store (StoreKit receipts via App Store Server API v2)
//   2. Google Play (purchase tokens via Google Play Developer API v3)
//
// WHY SERVER-SIDE VERIFICATION?
// ─────────────────────────────
// - Client-side verification can be bypassed by jailbroken/rooted devices
// - Apple REQUIRES server-side verification for auto-renewable subscriptions
// - Google Play strongly recommends it for subscription fraud prevention
// - Allows you to maintain a single source of truth (Firestore) for sub status
//
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const { google } = require('googleapis');
const fs = require('fs');
const path = require('path');
const jwt = require('jsonwebtoken');
const { getDb, FieldValue } = require('./firebase-service');

// ═════════════════════════════════════════════════════════════════════════════
// APPLE APP STORE VERIFICATION
// ═════════════════════════════════════════════════════════════════════════════
//
// Uses App Store Server API v2 (replaces deprecated verifyReceipt endpoint).
//
// Setup required:
//   1. App Store Connect > Users and Access > Keys > In-App Purchase
//   2. Generate an API key — save the .p8 file
//   3. Note: Issuer ID, Key ID
//   4. Store in .env: APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY_PATH
//
// Flow:
//   App sends receipt → backend verifies via App Store Server API →
//   updates Firestore subscription → returns result to app
//
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Verify an Apple App Store receipt and update subscription in Firestore.
 *
 * @param {Object} params
 * @param {string} params.userId          - Firebase UID
 * @param {string} params.receiptData     - Base64-encoded receipt from StoreKit
 * @param {string} params.productId       - Huddl product ID
 * @param {string} params.transactionId   - Original transaction ID
 * @returns {Object} { valid, subscription, error }
 */
async function verifyAppleReceipt({ userId, receiptData, productId, transactionId }) {
  try {
    // ── Step 1: Generate signed JWT for App Store Server API ───────────
    const token = _generateAppleJWT();

    // ── Step 2: Look up subscription status via transaction ID ─────────
    // App Store Server API v2: GET /inApps/v1/subscriptions/{transactionId}
    const apiBase = process.env.NODE_ENV === 'production'
      ? 'https://api.storekit.itunes.apple.com'
      : 'https://api.storekit-sandbox.itunes.apple.com';

    const response = await fetch(
      `${apiBase}/inApps/v1/subscriptions/${transactionId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
      }
    );

    if (!response.ok) {
      const errorBody = await response.text();
      console.error('Apple verification failed:', response.status, errorBody);
      return {
        valid: false,
        error: `Apple verification failed: ${response.status}`,
      };
    }

    const data = await response.json();

    // ── Step 3: Parse the subscription status ─────────────────────────
    // The response contains signed transactions in JWS format
    const subscriptionGroup = data.data?.[0];
    if (!subscriptionGroup) {
      return { valid: false, error: 'No subscription data found' };
    }

    const lastTransaction = subscriptionGroup.lastTransactions?.[0];
    if (!lastTransaction) {
      return { valid: false, error: 'No transaction history found' };
    }

    // Decode the signed transaction info (JWS)
    const transactionInfo = _decodeJWS(lastTransaction.signedTransactionInfo);
    const renewalInfo = _decodeJWS(lastTransaction.signedRenewalInfo);

    const isActive = lastTransaction.status === 1; // 1 = active
    const expiresDate = transactionInfo?.expiresDate
      ? new Date(transactionInfo.expiresDate)
      : null;

    // ── Step 4: Map Apple product ID to Huddl tier ────────────────────
    const tierMapping = _mapAppleProductToTier(
      transactionInfo?.productId || productId
    );

    // ── Step 5: Update Firestore subscription ─────────────────────────
    const db = getDb();
    const subData = {
      tier: tierMapping.tier,
      billingPeriod: tierMapping.billingPeriod,
      isActive,
      isTrial: transactionInfo?.offerType === 1, // 1 = introductory/trial
      trialDaysRemaining: 0,
      platform: 'ios',
      appleTransactionId: transactionId,
      appleProductId: transactionInfo?.productId || productId,
      renewalDate: expiresDate?.toISOString() || null,
      autoRenewing: renewalInfo?.autoRenewStatus === 1,
      updatedAt: FieldValue.serverTimestamp(),
    };

    await db.collection('subscriptions').doc(userId).set(subData, { merge: true });

    // Update user document
    await db.collection('users').doc(userId).update({
      subscriptionTier: tierMapping.tier,
      updatedAt: FieldValue.serverTimestamp(),
    });

    console.log(`Apple receipt verified for user ${userId}: ${tierMapping.tier} (active: ${isActive})`);

    return {
      valid: true,
      subscription: {
        tier: tierMapping.tier,
        billingPeriod: tierMapping.billingPeriod,
        isActive,
        expiresDate: expiresDate?.toISOString(),
        autoRenewing: renewalInfo?.autoRenewStatus === 1,
      },
    };
  } catch (err) {
    console.error('Apple receipt verification error:', err);
    return { valid: false, error: err.message };
  }
}

/**
 * Generate a signed JWT for Apple App Store Server API authentication.
 */
function _generateAppleJWT() {
  const privateKeyPath =
    process.env.APPLE_PRIVATE_KEY_PATH ||
    path.join(__dirname, '../../config/apple-subscription-key.p8');

  let privateKey;
  try {
    privateKey = fs.readFileSync(privateKeyPath, 'utf8');
  } catch (err) {
    throw new Error(
      `Cannot read Apple private key at ${privateKeyPath}. ` +
      'Download it from App Store Connect > Users and Access > Keys > In-App Purchase.'
    );
  }

  const now = Math.floor(Date.now() / 1000);

  return jwt.sign(
    {
      iss: process.env.APPLE_ISSUER_ID,
      iat: now,
      exp: now + 3600, // 1 hour
      aud: 'appstoreconnect-v1',
      bid: process.env.APPLE_BUNDLE_ID || 'com.huddlconnect.huddlConnect',
    },
    privateKey,
    {
      algorithm: 'ES256',
      keyid: process.env.APPLE_KEY_ID,
    }
  );
}

/**
 * Decode a JWS (JSON Web Signature) token — extracts the payload without
 * verifying Apple's signature (signature was already verified by the API).
 */
function _decodeJWS(jws) {
  if (!jws) return null;
  try {
    const parts = jws.split('.');
    if (parts.length !== 3) return null;
    const payload = Buffer.from(parts[1], 'base64url').toString('utf8');
    return JSON.parse(payload);
  } catch {
    return null;
  }
}

/**
 * Map an Apple product ID to a Huddl subscription tier.
 * Apple product IDs mirror the Huddl product IDs.
 */
function _mapAppleProductToTier(appleProductId) {
  // CRITICAL: tier values MUST match Flutter's SubscriptionTier enum .name exactly:
  //   'neighbourhood' = SubscriptionTier.neighbourhood (displays as 'Neighbour')
  //   'innerCircle'   = SubscriptionTier.innerCircle   (displays as 'Circle')
  //   'explorer'      = SubscriptionTier.explorer      (displays as 'Welcome')
  const mapping = {
    // Current product IDs (matching Flutter HuddlProductIds + App/Play Store)
    huddl_neighbour_monthly: { tier: 'neighbourhood', billingPeriod: 'monthly' },
    huddl_neighbour_annual:  { tier: 'neighbourhood', billingPeriod: 'annual'  },
    huddl_circle_monthly:    { tier: 'innerCircle',   billingPeriod: 'monthly' },
    huddl_circle_annual:     { tier: 'innerCircle',   billingPeriod: 'annual'  },
    // Legacy product IDs (kept for existing subscribers migrating from old store entries)
    huddl_neighbourhood_monthly:          { tier: 'neighbourhood', billingPeriod: 'monthly' },
    huddl_neighbourhood_annual:           { tier: 'neighbourhood', billingPeriod: 'annual'  },
    huddl_neighbourhood_founding_monthly: { tier: 'neighbourhood', billingPeriod: 'monthly' },
    huddl_inner_circle_monthly:           { tier: 'innerCircle',   billingPeriod: 'monthly' },
    huddl_inner_circle_annual:            { tier: 'innerCircle',   billingPeriod: 'annual'  },
  };
  return mapping[appleProductId] || { tier: 'explorer', billingPeriod: 'monthly' };
}

// ═════════════════════════════════════════════════════════════════════════════
// GOOGLE PLAY VERIFICATION
// ═════════════════════════════════════════════════════════════════════════════
//
// Uses Google Play Developer API v3 (androidpublisher).
//
// Setup required:
//   1. Google Cloud Console > enable "Google Play Android Developer API"
//   2. Use the Firebase service account (must have "View financial data" and
//      "Manage orders" permissions in Google Play Console > Users & Permissions)
//   3. Link the Google Cloud project to your Play Console
//
// Flow:
//   App sends purchaseToken → backend verifies via Google Play API →
//   updates Firestore subscription → returns result to app
//
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Verify a Google Play subscription purchase token and update Firestore.
 *
 * @param {Object} params
 * @param {string} params.userId         - Firebase UID
 * @param {string} params.purchaseToken  - Google Play purchase token
 * @param {string} params.productId      - Huddl product ID (= Google SKU)
 * @returns {Object} { valid, subscription, error }
 */
async function verifyGoogleReceipt({ userId, purchaseToken, productId }) {
  try {
    const packageName =
      process.env.GOOGLE_PLAY_PACKAGE_NAME || 'com.huddlconnect.huddl_connect';

    // ── Step 1: Authenticate with Google APIs ─────────────────────────
    const auth = new google.auth.GoogleAuth({
      keyFile:
        process.env.FIREBASE_SERVICE_ACCOUNT_PATH ||
        path.join(__dirname, '../../config/firebase-admin-sdk.json'),
      scopes: ['https://www.googleapis.com/auth/androidpublisher'],
    });

    const androidPublisher = google.androidpublisher({
      version: 'v3',
      auth,
    });

    // ── Step 2: Verify the subscription purchase ──────────────────────
    const response = await androidPublisher.purchases.subscriptions.get({
      packageName,
      subscriptionId: productId,
      token: purchaseToken,
    });

    const purchase = response.data;

    // ── Step 3: Parse purchase status ─────────────────────────────────
    // paymentState: 0=pending, 1=received, 2=free_trial, 3=deferred
    // cancelReason: 0=user, 1=system(billing), 2=replaced, 3=developer
    const isActive =
      purchase.expiryTimeMillis &&
      parseInt(purchase.expiryTimeMillis) > Date.now() &&
      purchase.paymentState !== undefined;

    const isTrial = purchase.paymentState === 2; // free trial

    const expiresDate = purchase.expiryTimeMillis
      ? new Date(parseInt(purchase.expiryTimeMillis))
      : null;

    // ── Step 4: Map to Huddl tier ─────────────────────────────────────
    const tierMapping = _mapAppleProductToTier(productId); // same mapping

    // ── Step 5: Update Firestore ──────────────────────────────────────
    const db = getDb();
    const subData = {
      tier: tierMapping.tier,
      billingPeriod: tierMapping.billingPeriod,
      isActive: !!isActive,
      isTrial,
      trialDaysRemaining: 0,
      platform: 'android',
      googlePurchaseToken: purchaseToken,
      googleOrderId: purchase.orderId || null,
      renewalDate: expiresDate?.toISOString() || null,
      autoRenewing: purchase.autoRenewing || false,
      updatedAt: FieldValue.serverTimestamp(),
    };

    await db.collection('subscriptions').doc(userId).set(subData, { merge: true });

    await db.collection('users').doc(userId).update({
      subscriptionTier: tierMapping.tier,
      updatedAt: FieldValue.serverTimestamp(),
    });

    // ── Step 6: Acknowledge the purchase ──────────────────────────────
    // Google requires acknowledgement within 3 days or purchase is refunded
    if (purchase.acknowledgementState === 0) {
      await androidPublisher.purchases.subscriptions.acknowledge({
        packageName,
        subscriptionId: productId,
        token: purchaseToken,
      });
      console.log(`Google Play purchase acknowledged for user ${userId}`);
    }

    console.log(`Google receipt verified for user ${userId}: ${tierMapping.tier} (active: ${isActive})`);

    return {
      valid: true,
      subscription: {
        tier: tierMapping.tier,
        billingPeriod: tierMapping.billingPeriod,
        isActive: !!isActive,
        expiresDate: expiresDate?.toISOString(),
        autoRenewing: purchase.autoRenewing || false,
        isTrial,
      },
    };
  } catch (err) {
    console.error('Google receipt verification error:', err);
    return { valid: false, error: err.message };
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// APPLE SERVER NOTIFICATIONS v2
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Handle Apple App Store Server Notifications v2.
 * Apple POSTs signed JWS payloads to our webhook endpoint.
 *
 * Notification types:
 *   DID_RENEW, DID_FAIL_TO_RENEW, DID_CHANGE_RENEWAL_STATUS,
 *   EXPIRED, REFUND, REVOKE, SUBSCRIBED, etc.
 */
async function handleAppleNotification(signedPayload) {
  const payload = _decodeJWS(signedPayload);
  if (!payload) {
    throw new Error('Invalid Apple notification: cannot decode JWS');
  }

  const notificationType = payload.notificationType;
  const subtype = payload.subtype;
  const transactionInfo = _decodeJWS(
    payload.data?.signedTransactionInfo
  );
  const renewalInfo = _decodeJWS(
    payload.data?.signedRenewalInfo
  );

  if (!transactionInfo) {
    console.warn('Apple notification: no transaction info');
    return;
  }

  const bundleId = transactionInfo.bundleId;
  const appleProductId = transactionInfo.productId;
  const originalTransactionId = transactionInfo.originalTransactionId;

  // Find user by Apple transaction ID
  const db = getDb();
  const subSnap = await db.collection('subscriptions')
    .where('appleTransactionId', '==', originalTransactionId)
    .limit(1)
    .get();

  if (subSnap.empty) {
    console.warn(`Apple notification: no user found for transaction ${originalTransactionId}`);
    return;
  }

  const userId = subSnap.docs[0].id;
  const tierMapping = _mapAppleProductToTier(appleProductId);

  switch (notificationType) {
    case 'SUBSCRIBED':
    case 'DID_RENEW':
      await db.collection('subscriptions').doc(userId).update({
        isActive: true,
        isTrial: notificationType === 'SUBSCRIBED' && subtype === 'INITIAL_BUY',
        tier: tierMapping.tier,
        billingPeriod: tierMapping.billingPeriod,
        renewalDate: transactionInfo.expiresDate
          ? new Date(transactionInfo.expiresDate).toISOString()
          : null,
        updatedAt: FieldValue.serverTimestamp(),
      });
      break;

    case 'DID_FAIL_TO_RENEW':
      await db.collection('subscriptions').doc(userId).update({
        paymentFailed: true,
        paymentFailedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      break;

    case 'EXPIRED':
    case 'REVOKE':
      await db.collection('subscriptions').doc(userId).set({
        tier: 'explorer',
        billingPeriod: 'monthly',
        isActive: true,
        isTrial: false,
        trialDaysRemaining: 0,
        platform: 'ios',
        cancelledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: false });
      await db.collection('users').doc(userId).update({
        subscriptionTier: 'explorer',
        updatedAt: FieldValue.serverTimestamp(),
      });
      break;

    case 'DID_CHANGE_RENEWAL_STATUS':
      const autoRenew = renewalInfo?.autoRenewStatus === 1;
      await db.collection('subscriptions').doc(userId).update({
        autoRenewing: autoRenew,
        cancelAtPeriodEnd: !autoRenew,
        updatedAt: FieldValue.serverTimestamp(),
      });
      break;

    default:
      console.log(`Unhandled Apple notification: ${notificationType} (${subtype})`);
  }

  console.log(`Apple notification processed: ${notificationType}/${subtype} for user ${userId}`);
}

// ═════════════════════════════════════════════════════════════════════════════
// GOOGLE PLAY REAL-TIME DEVELOPER NOTIFICATIONS (RTDN)
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Handle Google Play RTDN (Real-Time Developer Notifications).
 * Google sends Pub/Sub messages when subscription state changes.
 *
 * notificationType values:
 *   1=RECOVERED, 2=RENEWED, 3=CANCELED, 4=PURCHASED, 5=ON_HOLD,
 *   6=IN_GRACE_PERIOD, 7=RESTARTED, 8=PRICE_CHANGE_CONFIRMED,
 *   9=DEFERRED, 10=PAUSED, 11=PAUSE_SCHEDULE_CHANGED,
 *   12=REVOKED, 13=EXPIRED
 */
async function handleGoogleNotification(message) {
  // Decode Pub/Sub message
  const decoded = JSON.parse(
    Buffer.from(message.data, 'base64').toString('utf8')
  );

  const subscriptionNotification = decoded.subscriptionNotification;
  if (!subscriptionNotification) {
    console.log('Google RTDN: not a subscription notification');
    return;
  }

  const {
    notificationType,
    purchaseToken,
    subscriptionId, // = product ID / SKU
  } = subscriptionNotification;

  const packageName = decoded.packageName;

  // Re-verify the purchase to get current status
  // Find user by purchase token
  const db = getDb();
  const subSnap = await db.collection('subscriptions')
    .where('googlePurchaseToken', '==', purchaseToken)
    .limit(1)
    .get();

  if (subSnap.empty) {
    console.warn(`Google RTDN: no user found for token ${purchaseToken?.substring(0, 20)}...`);
    return;
  }

  const userId = subSnap.docs[0].id;

  // Re-verify to get latest state
  const result = await verifyGoogleReceipt({
    userId,
    purchaseToken,
    productId: subscriptionId,
  });

  const notificationTypeNames = {
    1: 'RECOVERED', 2: 'RENEWED', 3: 'CANCELED', 4: 'PURCHASED',
    5: 'ON_HOLD', 6: 'IN_GRACE_PERIOD', 7: 'RESTARTED',
    12: 'REVOKED', 13: 'EXPIRED',
  };

  // Handle specific notification types
  if ([3, 12, 13].includes(notificationType)) {
    // CANCELED, REVOKED, EXPIRED — downgrade to Explorer
    await db.collection('subscriptions').doc(userId).set({
      tier: 'explorer',
      billingPeriod: 'monthly',
      isActive: true,
      isTrial: false,
      trialDaysRemaining: 0,
      platform: 'android',
      cancelledAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: false });

    await db.collection('users').doc(userId).update({
      subscriptionTier: 'explorer',
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  console.log(
    `Google RTDN processed: ${notificationTypeNames[notificationType] || notificationType} for user ${userId}`
  );
}

module.exports = {
  verifyAppleReceipt,
  verifyGoogleReceipt,
  handleAppleNotification,
  handleGoogleNotification,
};
