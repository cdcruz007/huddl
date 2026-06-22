// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — GDPR ROUTES
// ═══════════════════════════════════════════════════════════════════════════════
//
// POST /api/gdpr/anonymize-stripe
//   Scrub PII from a Stripe customer while retaining transaction records.
//   Called service-to-service by the deleteUserData Cloud Function BEFORE
//   the users/{uid} Firestore doc is deleted (stripeCustomerId lives there).
//
// Auth: serviceOrAuthMiddleware (NOTIFY-SPOOF-1 dual-path):
//   (a) X-Service-Auth: <INTERNAL_SERVICE_SECRET>  — service path (CF → Railway)
//       userId taken from req.body.userId.
//   (b) Bearer <Firebase ID token>                 — user path (user erases self)
//       userId taken from req.userId (token); enforced === req.body.userId
//       so a user can only anonymize their OWN Stripe data.
//
// Response:
//   200  { anonymized: true,  customerId, subscriptionCancelled }
//   200  { anonymized: false, reason: 'no_customer' }         — not an error
//   400  { error: 'userId required' }
//   403  { error: 'Forbidden: ...' }                          — user path mismatch
//   500  { error: '...', details }                            — unexpected throw
//
// Audit: GDPR-STRIPE-1.
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const express = require('express');
const router  = express.Router();

const { serviceOrAuthMiddleware } = require('../middleware/auth-middleware');
const { anonymizeStripeCustomer } = require('../services/stripe-service');

// ─────────────────────────────────────────────────────────────────────────────
// POST /anonymize-stripe
// ─────────────────────────────────────────────────────────────────────────────
router.post('/anonymize-stripe', serviceOrAuthMiddleware, async (req, res) => {
  try {
    // ── Resolve userId ──────────────────────────────────────────────────────
    let userId;

    if (req.isService) {
      // Service path: CF sends userId in body; trust it fully (secret verified).
      userId = req.body && req.body.userId;
      if (!userId || typeof userId !== 'string') {
        return res.status(400).json({ error: 'userId required in body for service calls' });
      }
    } else {
      // User token path: user can only anonymize their own account.
      // req.userId is set by serviceOrAuthMiddleware from the verified token.
      userId = req.userId;
      if (!userId) {
        return res.status(401).json({ error: 'Authentication required' });
      }

      // If caller supplied body.userId, it must match the token uid.
      const bodyUserId = req.body && req.body.userId;
      if (bodyUserId && bodyUserId !== userId) {
        return res.status(403).json({
          error: 'Forbidden: you may only anonymize your own Stripe data',
        });
      }
    }

    // ── Delegate to service ─────────────────────────────────────────────────
    const result = await anonymizeStripeCustomer(userId);

    // anonymizeStripeCustomer never throws — it catches internally.
    // A { anonymized: false, reason: 'no_customer' } is a 200 (not an error).
    // A { anonymized: false, error: '...' } means Stripe itself errored;
    // we still return 200 so the calling CF continues with Firestore deletion.
    return res.status(200).json(result);

  } catch (err) {
    // Belt-and-suspenders: anonymizeStripeCustomer should not throw, but if
    // something unexpected escapes, log it and return a 500.
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`[gdpr/anonymize-stripe] Unexpected error: ${msg}`);
    return res.status(500).json({ error: 'Internal error during Stripe anonymization', details: msg });
  }
});

module.exports = router;
