#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════════
// Stripe Product Setup Script
// ═══════════════════════════════════════════════════════════════════════════════
//
// Run this script once to create all Huddl subscription products and prices
// in your Stripe dashboard.
//
// Usage:
//   STRIPE_SECRET_KEY=sk_test_xxx node scripts/setup-stripe-products.js
//
// After running, copy the price IDs into your .env file.
//
// ═══════════════════════════════════════════════════════════════════════════════

'use strict';

require('dotenv').config();

const Stripe = require('stripe');
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

async function main() {
  console.log('Creating Huddl Connect products in Stripe...\n');

  // ── 1. Neighbourhood tier ───────────────────────────────────────────────
  const neighbourhood = await stripe.products.create({
    name: 'Huddl Neighbourhood',
    description: 'Your full parent community, unlocked. Unlimited groups, messaging, meetups, private groups, ad-free, and more.',
    metadata: { tier: 'neighbourhood' },
  });
  console.log(`Product: ${neighbourhood.name} (${neighbourhood.id})`);

  const nhMonthly = await stripe.prices.create({
    product: neighbourhood.id,
    unit_amount: 599, // £5.99
    currency: 'gbp',
    recurring: { interval: 'month' },
    metadata: { productId: 'huddl_neighbourhood_monthly' },
    lookup_key: 'huddl_neighbourhood_monthly',
  });
  console.log(`  Monthly: £5.99/mo (${nhMonthly.id})`);

  const nhAnnual = await stripe.prices.create({
    product: neighbourhood.id,
    unit_amount: 4999, // £49.99
    currency: 'gbp',
    recurring: { interval: 'year' },
    metadata: { productId: 'huddl_neighbourhood_annual' },
    lookup_key: 'huddl_neighbourhood_annual',
  });
  console.log(`  Annual: £49.99/yr (${nhAnnual.id})`);

  const nhFounding = await stripe.prices.create({
    product: neighbourhood.id,
    unit_amount: 399, // £3.99 (founding member)
    currency: 'gbp',
    recurring: { interval: 'month' },
    metadata: {
      productId: 'huddl_neighbourhood_founding_monthly',
      founding: 'true',
    },
    lookup_key: 'huddl_neighbourhood_founding_monthly',
  });
  console.log(`  Founding: £3.99/mo (${nhFounding.id})`);

  // ── 2. Inner Circle tier ────────────────────────────────────────────────
  const innerCircle = await stripe.products.create({
    name: 'Huddl Inner Circle',
    description: 'Lead your community with superpowers. Everything in Neighbourhood plus analytics, promoted listings, priority support, and more.',
    metadata: { tier: 'innerCircle' },
  });
  console.log(`\nProduct: ${innerCircle.name} (${innerCircle.id})`);

  const icMonthly = await stripe.prices.create({
    product: innerCircle.id,
    unit_amount: 1199, // £11.99
    currency: 'gbp',
    recurring: { interval: 'month' },
    metadata: { productId: 'huddl_inner_circle_monthly' },
    lookup_key: 'huddl_inner_circle_monthly',
  });
  console.log(`  Monthly: £11.99/mo (${icMonthly.id})`);

  const icAnnual = await stripe.prices.create({
    product: innerCircle.id,
    unit_amount: 9999, // £99.99
    currency: 'gbp',
    recurring: { interval: 'year' },
    metadata: { productId: 'huddl_inner_circle_annual' },
    lookup_key: 'huddl_inner_circle_annual',
  });
  console.log(`  Annual: £99.99/yr (${icAnnual.id})`);

  // ── Summary ─────────────────────────────────────────────────────────────
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Copy these price IDs into your .env file:');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(`STRIPE_PRICE_NEIGHBOURHOOD_MONTHLY=${nhMonthly.id}`);
  console.log(`STRIPE_PRICE_NEIGHBOURHOOD_ANNUAL=${nhAnnual.id}`);
  console.log(`STRIPE_PRICE_NEIGHBOURHOOD_FOUNDING=${nhFounding.id}`);
  console.log(`STRIPE_PRICE_INNER_CIRCLE_MONTHLY=${icMonthly.id}`);
  console.log(`STRIPE_PRICE_INNER_CIRCLE_ANNUAL=${icAnnual.id}`);
  console.log('═══════════════════════════════════════════════════════════\n');

  // ── 3. Configure Customer Portal ──────────────────────────────────────
  console.log('Configuring Stripe Customer Portal...');
  await stripe.billingPortal.configurations.create({
    business_profile: {
      headline: 'Manage your Huddl subscription',
    },
    features: {
      subscription_cancel: {
        enabled: true,
        mode: 'at_period_end',
        cancellation_reason: {
          enabled: true,
          options: [
            'too_expensive',
            'missing_features',
            'switched_service',
            'unused',
            'other',
          ],
        },
      },
      subscription_update: {
        enabled: true,
        default_allowed_updates: ['price', 'promotion_code'],
        proration_behavior: 'create_prorations',
        products: [
          {
            product: neighbourhood.id,
            prices: [nhMonthly.id, nhAnnual.id, nhFounding.id],
          },
          {
            product: innerCircle.id,
            prices: [icMonthly.id, icAnnual.id],
          },
        ],
      },
      payment_method_update: { enabled: true },
      invoice_history: { enabled: true },
    },
  });
  console.log('Customer Portal configured.\n');

  console.log('All done! Your Stripe products are ready.');
  console.log('Next steps:');
  console.log('  1. Copy price IDs to .env');
  console.log('  2. Set up webhook endpoint in Stripe Dashboard');
  console.log('  3. Start the backend: npm start');
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
