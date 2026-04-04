// ═══════════════════════════════════════════════════════════════════════════════
// Rate Limiting Middleware
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

const rateLimit = require('express-rate-limit');

/**
 * General API rate limiter: 100 requests per 15 minutes per IP.
 */
const rateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Too many requests. Please try again in a few minutes.',
  },
});

/**
 * Stricter limiter for sensitive endpoints (auth, payment).
 */
const strictLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Too many attempts. Please wait before trying again.',
  },
});

module.exports = { rateLimiter, strictLimiter };
