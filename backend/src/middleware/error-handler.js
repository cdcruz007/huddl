// ═══════════════════════════════════════════════════════════════════════════════
// Global Error Handler
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

/**
 * Express global error handler.
 * Catches all unhandled errors and returns a consistent JSON response.
 */
function errorHandler(err, req, res, _next) {
  console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err.message);

  if (process.env.NODE_ENV !== 'production') {
    console.error(err.stack);
  }

  // Stripe-specific errors
  if (err.type === 'StripeCardError') {
    return res.status(402).json({ error: err.message });
  }
  if (err.type === 'StripeInvalidRequestError') {
    return res.status(400).json({ error: err.message });
  }

  // Validation errors
  if (err.isJoi || err.name === 'ValidationError') {
    return res.status(400).json({ error: err.message });
  }

  // Default 500
  const statusCode = err.statusCode || err.status || 500;
  res.status(statusCode).json({
    error:
      process.env.NODE_ENV === 'production'
        ? 'Internal server error'
        : err.message,
  });
}

module.exports = { errorHandler };
