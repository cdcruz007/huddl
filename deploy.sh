#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Huddl — Firebase deploy script
# Project: huddl-connect
#
# Deploys Firestore rules, Firestore indexes, and Storage rules.
# Functions are intentionally excluded (separate CI pipeline).
#
# Usage (from repo root — requires firebase CLI and login):
#   chmod +x deploy.sh
#   firebase login          # one-time; skip if already logged in
#   ./deploy.sh
#
# Or with an existing CI token:
#   FIREBASE_TOKEN=<token> ./deploy.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT="huddl-connect"

echo "▶  Deploying Firestore rules + indexes + Storage rules to $PROJECT …"

firebase deploy \
  --only firestore:rules,firestore:indexes,storage \
  --project "$PROJECT"

echo ""
echo "✅  Deploy complete."
echo ""
echo "   Firestore rules  → https://console.firebase.google.com/project/$PROJECT/firestore/rules"
echo "   Firestore indexes → https://console.firebase.google.com/project/$PROJECT/firestore/indexes"
echo "   Storage rules    → https://console.firebase.google.com/project/$PROJECT/storage/rules"
echo ""
echo "   NOTE: Composite index builds take 2–5 minutes after deploy."
echo "         Monitor progress at the Firestore indexes link above."
