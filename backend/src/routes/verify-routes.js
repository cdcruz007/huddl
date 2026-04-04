// ═══════════════════════════════════════════════════════════════════════════════
// Receipt Verification Routes — Apple & Google
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth-middleware');
const {
  verifyAppleReceipt,
  verifyGoogleReceipt,
} = require('../services/receipt-verification-service');

// ── POST /api/verify/apple ──────────────────────────────────────────────────
// Verify an Apple App Store receipt (iOS in-app purchase).
//
// Body:
//   {
//     receiptData:   <base64 receipt>,
//     productId:     'huddl_neighbourhood_monthly',
//     transactionId: 'original_transaction_id'
//   }
//
// Headers:
//   Authorization: Bearer <Firebase ID token>
//
// Returns:
//   { valid: true, subscription: { tier, billingPeriod, isActive, expiresDate } }
//   { valid: false, error: '...' }
router.post('/apple', authMiddleware, async (req, res, next) => {
  try {
    const { receiptData, productId, transactionId } = req.body;

    if (!receiptData || !productId) {
      return res
        .status(400)
        .json({ error: 'receiptData and productId are required' });
    }

    const result = await verifyAppleReceipt({
      userId: req.userId,
      receiptData,
      productId,
      transactionId,
    });

    if (result.valid) {
      res.json(result);
    } else {
      res.status(422).json(result);
    }
  } catch (err) {
    next(err);
  }
});

// ── POST /api/verify/google ─────────────────────────────────────────────────
// Verify a Google Play subscription purchase token (Android in-app purchase).
//
// Body:
//   {
//     purchaseToken: '<token from Google Play>',
//     productId:     'huddl_neighbourhood_monthly'
//   }
//
// Headers:
//   Authorization: Bearer <Firebase ID token>
//
// Returns:
//   { valid: true, subscription: { tier, billingPeriod, isActive, expiresDate, autoRenewing } }
//   { valid: false, error: '...' }
router.post('/google', authMiddleware, async (req, res, next) => {
  try {
    const { purchaseToken, productId } = req.body;

    if (!purchaseToken || !productId) {
      return res
        .status(400)
        .json({ error: 'purchaseToken and productId are required' });
    }

    const result = await verifyGoogleReceipt({
      userId: req.userId,
      purchaseToken,
      productId,
    });

    if (result.valid) {
      res.json(result);
    } else {
      res.status(422).json(result);
    }
  } catch (err) {
    next(err);
  }
});

module.exports = router;
