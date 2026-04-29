// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — BACKEND SERVER
// ═══════════════════════════════════════════════════════════════════════════════
//
// Express server providing:
//   1. Stripe Checkout session creation & Customer Portal
//   2. Stripe webhook processing (subscription lifecycle)
//   3. Apple App Store receipt verification (Server Notifications v2)
//   4. Google Play receipt verification (Real-Time Developer Notifications)
//   5. Transactional email (Hostinger SMTP) — welcome, receipt, cancellation
//   6. FCM push notifications — trial reminders, subscription events
//
// Endpoints:
//   POST /api/stripe/create-checkout-session
//   POST /api/stripe/customer-portal
//   POST /api/webhooks/stripe          (raw body — Stripe signature)
//   POST /api/verify/apple             (App Store receipt)
//   POST /api/verify/google            (Google Play purchase token)
//   POST /api/webhooks/apple           (App Store Server Notifications v2)
//   POST /api/webhooks/google          (Google Play RTDN)
//   GET  /api/subscription/:userId     (current subscription status)
//   POST /api/subscription/cancel      (initiate cancellation flow)
//   GET  /health                       (health check)
//
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const { initializeFirebase } = require('./services/firebase-service');
const stripeRoutes = require('./routes/stripe-routes');
const verifyRoutes = require('./routes/verify-routes');
const subscriptionRoutes = require('./routes/subscription-routes');
const webhookRoutes = require('./routes/webhook-routes');
const notificationRoutes = require('./routes/notification-routes');
const { errorHandler } = require('./middleware/error-handler');
const { rateLimiter } = require('./middleware/rate-limiter');

// ── Initialize Firebase Admin SDK ────────────────────────────────────────────
initializeFirebase();

const app = express();
const PORT = process.env.PORT || 3000;

// ── Global middleware ────────────────────────────────────────────────────────
app.use(helmet());
app.use(cors({
  origin: [
    process.env.FRONTEND_URL || 'http://localhost:5060',
    'https://huddlapp.co.uk',
    'https://www.huddlapp.co.uk',
    /\.huddlapp\.co\.uk$/,
  ],
  credentials: true,
}));
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));
app.use(rateLimiter);

// ── IMPORTANT: Stripe webhooks require raw body ─────────────────────────────
// Mount webhook routes BEFORE express.json() so they receive the raw body for
// Stripe signature verification.
app.use('/api/webhooks', webhookRoutes);

// ── JSON body parser (after webhooks) ───────────────────────────────────────
app.use(express.json({ limit: '5mb' }));
app.use(express.urlencoded({ extended: true }));

// ── API Routes ──────────────────────────────────────────────────────────────
app.use('/api/stripe', stripeRoutes);
app.use('/api/verify', verifyRoutes);
app.use('/api/subscription', subscriptionRoutes);
app.use('/api/notifications', notificationRoutes);

// ── Health check ────────────────────────────────────────────────────────────
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'huddl-connect-backend',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development',
  });
});

// ── 404 handler ─────────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found', path: req.originalUrl });
});

// ── Global error handler ────────────────────────────────────────────────────
app.use(errorHandler);

// ── Start server ────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`Huddl backend listening on port ${PORT})`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});

module.exports = app;
