// ═══════════════════════════════════════════════════════════════════════════════
// Authentication Middleware — Firebase ID Token Verification
// ═══════════════════════════════════════════════════════════════════════════════
//
// Verifies the Firebase ID token sent in the Authorization header.
// Extracts userId and userEmail for downstream use.
//
// Usage:
//   router.post('/endpoint', authMiddleware, handler);
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

module.exports = { authMiddleware };
