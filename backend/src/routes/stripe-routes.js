// ═══════════════════════════════════════════════════════════════════════════════
// Stripe Routes — Checkout Session & Customer Portal
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth-middleware');
const {
  createCheckoutSession,
  createPortalSession,
} = require('../services/stripe-service');

// ── POST /api/stripe/create-checkout-session ────────────────────────────────
// Creates a Stripe Checkout session for a new subscription.
//
// Body:
//   { productId: 'huddl_neighbour_monthly', successUrl?, cancelUrl? }
//
// Headers:
//   Authorization: Bearer <Firebase ID token>
//
// Returns:
//   { sessionId, url }  — redirect user to `url` for Stripe Checkout
router.post('/create-checkout-session', authMiddleware, async (req, res, next) => {
  try {
    const { productId, successUrl, cancelUrl } = req.body;

    if (!productId) {
      return res.status(400).json({ error: 'productId is required' });
    }

    const { sessionId, url } = await createCheckoutSession({
      userId: req.userId,
      email: req.userEmail,
      productId,
      successUrl,
      cancelUrl,
    });

    res.json({ sessionId, url });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/stripe/customer-portal ────────────────────────────────────────
// Creates a Stripe Customer Portal session for managing subscriptions.
//
// Headers:
//   Authorization: Bearer <Firebase ID token>
//
// Returns:
//   { url }  — redirect user to Stripe Customer Portal
router.post('/customer-portal', authMiddleware, async (req, res, next) => {
  try {
    const { url } = await createPortalSession(req.userId);
    res.json({ url });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
