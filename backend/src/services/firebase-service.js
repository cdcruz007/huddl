// ═══════════════════════════════════════════════════════════════════════════════
// Firebase Admin SDK — Firestore access for the backend
// Supports three credential sources (in priority order):
//   1. FIREBASE_SERVICE_ACCOUNT_JSON  — full JSON string (base64 or raw) — ideal
//      for cloud platforms (Railway, Render) where secrets are env vars.
//   2. FIREBASE_SERVICE_ACCOUNT_PATH  — path to a .json file on disk.
//   3. Default fallback              — ../../config/firebase-admin-sdk.json
//      relative to this file (works in local dev / sandbox).
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const admin = require('firebase-admin');
const path  = require('path');
const fs    = require('fs');

let _db = null;
let _messaging = null;

/**
 * Initialize Firebase Admin SDK.
 * Safe to call multiple times — idempotent.
 */
function initializeFirebase() {
  if (admin.apps.length > 0) return;

  let credential;

  try {
    // ── Option 1: JSON string env var (Railway / Render / Heroku) ──────────
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      let raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON.trim();
      // Detect base64: no { at start
      if (!raw.startsWith('{')) {
        raw = Buffer.from(raw, 'base64').toString('utf8');
      }
      const serviceAccount = JSON.parse(raw);
      credential = admin.credential.cert(serviceAccount);
      console.log('Firebase: using FIREBASE_SERVICE_ACCOUNT_JSON env var');

    // ── Option 2: Path env var ──────────────────────────────────────────────
    } else if (process.env.FIREBASE_SERVICE_ACCOUNT_PATH) {
      const resolvedPath = path.isAbsolute(process.env.FIREBASE_SERVICE_ACCOUNT_PATH)
        ? process.env.FIREBASE_SERVICE_ACCOUNT_PATH
        : path.resolve(process.cwd(), process.env.FIREBASE_SERVICE_ACCOUNT_PATH);
      const serviceAccount = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
      credential = admin.credential.cert(serviceAccount);
      console.log('Firebase: using FIREBASE_SERVICE_ACCOUNT_PATH:', resolvedPath);

    // ── Option 3: Default local file ────────────────────────────────────────
    } else {
      const defaultPath = path.join(__dirname, '../../config/firebase-admin-sdk.json');
      const serviceAccount = JSON.parse(fs.readFileSync(defaultPath, 'utf8'));
      credential = admin.credential.cert(serviceAccount);
      console.log('Firebase: using default config file');
    }

    admin.initializeApp({
      credential,
      projectId: process.env.FIREBASE_PROJECT_ID || 'huddl-connect',
    });
    console.log('Firebase Admin SDK initialized ✓');

  } catch (err) {
    console.error('Firebase init error:', err.message);
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
const Timestamp  = admin.firestore.Timestamp;

module.exports = {
  initializeFirebase,
  getDb,
  getMessaging,
  admin,
  FieldValue,
  Timestamp,
};
