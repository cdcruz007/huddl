// ═══════════════════════════════════════════════════════════════════════════════
// Authentication Middleware — Firebase ID Token Verification
// ═══════════════════════════════════════════════════════════════════════════════
//
// Exports two middleware functions:
//
//  authMiddleware          — Firebase ID token only. Used by all existing routes.
//                            Sets req.userId, req.userEmail, req.userPhone.
//
//  serviceOrAuthMiddleware — NOTIFY-SPOOF-1 / Stage 2a-i.
//                            Accepts EITHER:
//                            (a) X-Service-Auth header === INTERNAL_SERVICE_SECRET
//                                → req.isService = true, req.userId = null
//                            (b) Firebase ID token (falls through to authMiddleware
//                                logic) → req.isService = false, req.userId = uid
//                            If INTERNAL_SERVICE_SECRET is unset, path (a) is
//                            simply unavailable — only user tokens work (fail-safe).
//
// Usage:
//   router.post('/endpoint', authMiddleware, handler);          // existing routes
//   router.post('/endpoint', serviceOrAuthMiddleware, handler); // service-aware routes
//
// The Flutter app sends:
//   Authorization: Bearer <Firebase ID token from FirebaseAuth.currentUser.getIdToken()>
//
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const { admin } = require('../services/firebase-service');

/**
 * Express middleware that verifies a Firebase ID token.
 * Sets req.userId and req.userEmail on success.
 */
async function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      error: 'Missing or invalid Authorization header. Expected: Bearer <token>',
    });
  }

  const idToken = authHeader.split('Bearer ')[1];

  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    req.userId = decodedToken.uid;
    req.userEmail = decodedToken.email || null;
    req.userPhone = decodedToken.phone_number || null;
    next();
  } catch (err) {
    console.error('Auth middleware: token verification failed:', err.message);

    if (err.code === 'auth/id-token-expired') {
      return res.status(401).json({ error: 'Token expired. Please sign in again.' });
    }
    if (err.code === 'auth/id-token-revoked') {
      return res.status(401).json({ error: 'Token revoked. Please sign in again.' });
    }

    return res.status(401).json({ error: 'Invalid authentication token.' });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// serviceOrAuthMiddleware  (NOTIFY-SPOOF-1 — Stage 2a-i)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Dual-path middleware used exclusively on /notify-dm (and future service-owned
// routes). Accepts either a service secret header or a Firebase user token.
//
// Path (a) — service secret:
//   Header: X-Service-Auth: <INTERNAL_SERVICE_SECRET>
//   Sets:   req.isService = true, req.userId = null
//   When:   INTERNAL_SERVICE_SECRET env var is set and non-empty only.
//           If the env var is absent, this path is disabled — fail-safe.
//
// Path (b) — Firebase user token:
//   Header: Authorization: Bearer <ID token>
//   Sets:   req.isService = false, req.userId = uid
//   Same verification logic as authMiddleware.

/**
 * Middleware that accepts either a valid INTERNAL_SERVICE_SECRET header (service
 * path) or a Firebase ID token (user path). Routes that need NOTIFY-SPOOF-1
 * hardening should use this instead of authMiddleware.
 */
async function serviceOrAuthMiddleware(req, res, next) {
  // ── Path (a): service secret ─────────────────────────────────────────────
  const serviceSecret = process.env.INTERNAL_SERVICE_SECRET;
  const serviceHeader = req.headers['x-service-auth'];

  // Only honour the service path when the env var is set and non-empty.
  // An empty/unset INTERNAL_SERVICE_SECRET means the path is unavailable —
  // a missing secret must never accidentally grant service privileges.
  if (serviceSecret && serviceHeader && serviceHeader === serviceSecret) {
    req.isService = true;
    req.userId    = null;
    return next();
  }

  // ── Path (b): Firebase ID token ────────────────────────────────────────
  req.isService = false;

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      error: 'Missing or invalid Authorization header. Expected: Bearer <token>',
    });
  }

  const idToken = authHeader.split('Bearer ')[1];
  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    req.userId    = decodedToken.uid;
    req.userEmail = decodedToken.email || null;
    req.userPhone = decodedToken.phone_number || null;
    next();
  } catch (err) {
    console.error('serviceOrAuthMiddleware: token verification failed:', err.message);
    if (err.code === 'auth/id-token-expired') {
      return res.status(401).json({ error: 'Token expired. Please sign in again.' });
    }
    if (err.code === 'auth/id-token-revoked') {
      return res.status(401).json({ error: 'Token revoked. Please sign in again.' });
    }
    return res.status(401).json({ error: 'Invalid authentication token.' });
  }
}

module.exports = { authMiddleware, serviceOrAuthMiddleware };
