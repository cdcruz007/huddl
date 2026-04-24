# Huddl Connect Backend — Deployment Guide

## Quick Start (Railway — Recommended)

Railway is the easiest deployment option and costs ~$5/month for a starter server.

### Step 1 — Create Railway Project
1. Go to **https://railway.app** → New Project → Deploy from GitHub repo
2. Select the `huddl` repository
3. Set the **Root Directory** to `backend`
4. Railway will auto-detect Node.js and use `node src/server.js`

### Step 2 — Set Environment Variables in Railway Dashboard

In Railway → your service → **Variables**, add ALL of the following:

```
NODE_ENV=production
PORT=3000

# Firebase (base64-encoded service account JSON — see Step 3 below)
FIREBASE_SERVICE_ACCOUNT_JSON=<base64_encoded_service_account_json>
FIREBASE_PROJECT_ID=huddl-connect

# Stripe Live Keys
STRIPE_SECRET_KEY=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
STRIPE_PUBLISHABLE_KEY=pk_live_51J29CxGb8Lg9FVI5PQEEj71cpf0Atd5VIOJmLfUsXCurf5ogOJ2dgff2iKwrhQUuCi0kaBCMxoV98hp9vC2IPgqQ00wF0RKjiR
STRIPE_WEBHOOK_SECRET=whsec_NrvFWpNMGtedrfVkrUOMUqZfnophXtYQ

# Stripe Price IDs (names must match stripe-service.js PRICE_MAP exactly)
STRIPE_PRICE_NEIGHBOUR_MONTHLY=price_1TPMiQGb8Lg9FVI5hzdkzA23
STRIPE_PRICE_NEIGHBOUR_ANNUAL=price_1TPMjBGb8Lg9FVI5zZwvMgVe
STRIPE_PRICE_CIRCLE_MONTHLY=price_1TPUqjGb8Lg9FVI5uk3rAKlJ
STRIPE_PRICE_CIRCLE_ANNUAL=price_1TPMl5Gb8Lg9FVI5YKuJNSRL

# Apple App Store
APPLE_SHARED_SECRET=4bf37233a58e4688bd061ee0ea50da68
APPLE_BUNDLE_ID=com.huddlconnect.huddlConnect
APPLE_ISSUER_ID=865a0b1f-f8c6-401f-9d00-c3330b81a36c
APPLE_KEY_ID=G47KFBNUBQ
# Paste the FULL contents of your .p8 file as a single value.
# In the Railway UI enter the value exactly as below (Railway preserves newlines):
#   -----BEGIN PRIVATE KEY-----
#   MIGHAgEAMBMG...
#   -----END PRIVATE KEY-----
# The code automatically converts \n escape sequences to real newlines.
APPLE_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n<your_key_body_here>\n-----END PRIVATE KEY-----

# Google Play
GOOGLE_PLAY_PACKAGE_NAME=com.huddlconnect.huddl_connect

# Email — Hostinger SMTP
SMTP_HOST=smtp.hostinger.com
SMTP_PORT=465
SMTP_USER=welcome@huddlapp.co.uk
SMTP_PASS=<your_hostinger_email_password>

# JWT
JWT_SECRET=8a47036b067d831a626eaaf11b633d22fcc109d0dc8f04118f036e0009261f10
JWT_EXPIRY=7d

# Cron job authentication (sent as X-Cron-Secret header)
CRON_SECRET=58eb005d394c350dbb75dfc04d5e1fe5e23aaf9c9b8161e6d9af931dcf95ef1d

# Frontend URLs
FRONTEND_URL=https://www.huddlapp.co.uk
STRIPE_SUCCESS_URL=https://www.huddlapp.co.uk/subscription/success
STRIPE_CANCEL_URL=https://www.huddlapp.co.uk/subscription/cancel
```

### Step 3 — Generate Firebase Base64 Value

On your local machine, run:
```bash
base64 -i config/firebase-admin-sdk.json | tr -d '\n'
```
Paste the output as the value of `FIREBASE_SERVICE_ACCOUNT_JSON`.

### Step 4 — Apple Private Key in Railway

In Railway, set `APPLE_PRIVATE_KEY` to the **full contents** of your `.p8` file.
Railway's multi-line variable editor preserves newlines — paste it exactly as the
file reads (including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`).

The code in `receipt-verification-service.js` calls `.replace(/\\n/g, '\n')` so
Railway-style `\n` escape sequences are also handled correctly.

### Step 5 — Add Custom Domain
1. Railway → Settings → Domains → Add Custom Domain → `api.huddlapp.co.uk`
2. Add the CNAME record shown to your DNS provider (Hostinger DNS panel)

### Step 6 — Update Stripe Webhook
1. Go to **https://dashboard.stripe.com/webhooks**
2. Edit your webhook endpoint to point to: `https://api.huddlapp.co.uk/api/webhooks/stripe`
3. Ensure these events are enabled:
   - `checkout.session.completed`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`

### Step 7 — Configure Stripe Customer Portal
Go to **https://dashboard.stripe.com/settings/billing/portal** and enable it.
Configure allowed actions: upgrade, downgrade, cancel, update payment method.

---

## Alternative: Render.com

1. Go to **https://render.com** → New → Web Service → Connect GitHub
2. Select `huddl` repo, set root directory to `backend`
3. Build command: `npm install --production`
4. Start command: `node src/server.js`
5. Add all environment variables from Step 2 above
6. Add custom domain `api.huddlapp.co.uk`

---

## Health Check

Once deployed, verify the backend is running:
```
GET https://api.huddlapp.co.uk/health
```
Expected response:
```json
{ "status": "ok", "environment": "production" }
```

---

## Local Development

```bash
cd backend
cp .env.example .env   # Fill in your test keys
npm install
npm run dev            # Uses nodemon for hot reload
```

Stripe CLI for local webhook testing:
```bash
npm run stripe:listen  # Forwards Stripe webhooks to localhost:3000
```
