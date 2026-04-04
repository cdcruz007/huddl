// ═══════════════════════════════════════════════════════════════════════════════
// Firebase Admin SDK — Firestore access for the backend
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const admin = require('firebase-admin');
const path = require('path');

let _db = null;
let _messaging = null;

/**
 * Initialize Firebase Admin SDK using the service-account JSON.
 * Safe to call multiple times — idempotent.
 */
function initializeFirebase() {
  if (admin.apps.length > 0) return;

  const serviceAccountPath =
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH ||
    path.join(__dirname, '../../config/firebase-admin-sdk.json');

  try {
    admin.initializeApp({
      credential: admin.credential.cert(require(serviceAccountPath)),
      projectId: process.env.FIREBASE_PROJECT_ID || 'huddl-connect',
    });
    console.log('Firebase Admin SDK initialized');
  } catch (err) {
    console.error('Firebase init error:', err.message);
    // In development, allow running without Firebase for Stripe-only testing
    if (process.env.NODE_ENV === 'production') {
      throw err;
    }
  }
}

/** Firestore database reference */
function getDb() {
  if (!_db) {
    _db = admin.firestore();
  }
  return _db;
}

/** Firebase Cloud Messaging reference */
function getMessaging() {
  if (!_messaging) {
    _messaging = admin.messaging();
  }
  return _messaging;
}

/** FieldValue helpers */
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;

module.exports = {
  initializeFirebase,
  getDb,
  getMessaging,
  admin,
  FieldValue,
  Timestamp,
};
