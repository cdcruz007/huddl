// ═══════════════════════════════════════════════════════════════════════════════
// Subscription Management Routes
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth-middleware');
const {
  getSubscriptionStatus,
  cancelSubscription,
} = require('../services/stripe-service');

// ── GET /api/subscription/:userId ───────────────────────────────────────────
// Get the current subscription status for a user.
// In production, only allow a user to query their own subscription.
//
// Returns:
//   { tier, billingPeriod, isActive, isTrial, platform, ... }
router.get('/:userId', authMiddleware, async (req, res, next) => {
  try {
    const { userId } = req.params;

    // Security: users can only query their own subscription
    if (req.userId !== userId) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const status = await getSubscriptionStatus(userId);
    res.json(status);
  } catch (err) {
    next(err);
  }
});

// ── POST /api/subscription/cancel ───────────────────────────────────────────
// Initiate subscription cancellation (cancel at period end).
// Optionally pause for 1 month instead of full cancellation.
//
// Body:
//   { reason?: 'too_expensive', pauseMonths?: 1 }
//
// Returns:
//   { status: 'cancelling', cancelAtPeriodEnd: true }
//   { status: 'paused', resumesAt: '2025-...' }
router.post('/cancel', authMiddleware, async (req, res, next) => {
  try {
    const { reason, pauseMonths } = req.body;
    const result = await cancelSubscription(req.userId, {
      reason,
      pauseMonths,
    });
    res.json(result);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
