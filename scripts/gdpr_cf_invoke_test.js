#!/usr/bin/env node
/**
 * gdpr_cf_invoke_test.js
 *
 * Invokes the DEPLOYED deleteUserData callable Cloud Function authenticated
 * AS the given test user (the CF reads uid from context.auth.uid, not a param).
 *
 * Token flow:
 *   admin.auth().createCustomToken(TEST_UID)
 *     → POST identitytoolkit signInWithCustomToken  →  idToken
 *       → POST CF callable endpoint with Bearer auth + {"data":{}}
 *         → pretty-print full structured result
 *
 * Usage:
 *   cd functions
 *   node ../scripts/gdpr_cf_invoke_test.js \
 *       /path/to/service-account-key.json \
 *       CFTEST_1781772973290 \
 *       <WEB_API_KEY>
 *
 * Args:
 *   arg1  Path to Firebase service-account JSON (Admin SDK key)
 *   arg2  TEST_UID — e.g. CFTEST_1781772973290
 *   arg3  Firebase Web API key (project-level browser key, NOT derivable from
 *         service account; find it in Firebase Console → Project Settings → General
 *         under "Web API key" or in the google-services.json as "current_key")
 *
 * WARNING: This script INVOKES the real deployed CF which DELETES user data
 *          server-side for the given UID. Run only against throwaway test UIDs.
 *          It does NO deletion itself — all deletion is performed by the CF.
 */

"use strict";

// ── Resolve node-fetch v2 CJS from functions/node_modules (CJS-compatible) ──
// The script must be run with `cd functions && node ../scripts/...` so that
// require() resolves from functions/, OR we resolve explicitly via __dirname.
// We use path.resolve relative to this file's location: scripts/ is one level
// above functions/, so functions/node_modules is at ../functions/node_modules
// from scripts/.
const path  = require("path");
const fs    = require("fs");

const FUNCTIONS_DIR = path.resolve(__dirname, "..", "functions");
const fetch = require(path.join(FUNCTIONS_DIR, "node_modules", "node-fetch", "lib", "index.js"));
const admin = require(path.join(FUNCTIONS_DIR, "node_modules", "firebase-admin", "lib", "index.js"));

// ── Constants ──────────────────────────────────────────────────────────────
const CF_ENDPOINT =
  "https://europe-west2-huddl-connect.cloudfunctions.net/deleteUserData";
const IDENTITY_TOOLKIT_URL =
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken";

// ── Arg validation ─────────────────────────────────────────────────────────
const [,, keyPath, testUid, webApiKey] = process.argv;

if (!keyPath || !testUid || !webApiKey) {
  console.error([
    "",
    "Usage:",
    "  cd functions",
    "  node ../scripts/gdpr_cf_invoke_test.js \\",
    "      /path/to/service-account-key.json \\",
    "      <TEST_UID> \\",
    "      <WEB_API_KEY>",
    "",
    "Args:",
    "  arg1  Service-account key JSON path",
    "  arg2  TEST_UID (e.g. CFTEST_1781772973290)",
    "  arg3  Firebase Web API key (Firebase Console → Project Settings → General)",
    "",
    "ERROR: Missing required argument(s).",
  ].join("\n"));
  process.exit(1);
}

const absKeyPath = path.resolve(keyPath);
if (!fs.existsSync(absKeyPath)) {
  console.error(`ERROR: Service-account key not found at: ${absKeyPath}`);
  process.exit(1);
}

// ── Main ───────────────────────────────────────────────────────────────────
(async () => {
  // ── Step 1: Initialise Admin SDK ─────────────────────────────────────────
  console.error(`[1/4] Initialising Admin SDK with key: ${absKeyPath}`);
  admin.initializeApp({
    credential: admin.credential.cert(absKeyPath),
  });

  // ── Step 2: Mint custom token for test user ───────────────────────────────
  console.error(`[2/4] Minting custom token for UID: ${testUid}`);
  let customToken;
  try {
    customToken = await admin.auth().createCustomToken(testUid);
  } catch (err) {
    console.error(`ERROR minting custom token: ${err.message}`);
    process.exit(1);
  }
  console.error("      Custom token minted OK.");

  // ── Step 3: Exchange custom token → ID token via Identity Toolkit REST ────
  console.error("[3/4] Exchanging custom token for ID token via Identity Toolkit...");
  let idToken;
  try {
    const resp = await fetch(
      `${IDENTITY_TOOLKIT_URL}?key=${webApiKey}`,
      {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify({ token: customToken, returnSecureToken: true }),
      }
    );
    const body = await resp.json();
    if (!resp.ok || !body.idToken) {
      console.error(
        `ERROR: Identity Toolkit returned HTTP ${resp.status}:\n` +
        JSON.stringify(body, null, 2)
      );
      process.exit(1);
    }
    idToken = body.idToken;
  } catch (err) {
    console.error(`ERROR calling Identity Toolkit: ${err.message}`);
    process.exit(1);
  }
  console.error("      ID token obtained OK.");

  // ── Step 4: POST to callable CF endpoint with Bearer auth ─────────────────
  console.error(`[4/4] Calling CF endpoint: ${CF_ENDPOINT}`);
  console.error(`      Authenticated as UID: ${testUid}`);
  let cfResponse;
  try {
    const resp = await fetch(CF_ENDPOINT, {
      method:  "POST",
      headers: {
        "Content-Type":  "application/json",
        "Authorization": `Bearer ${idToken}`,
      },
      // Callable protocol wraps payload in {"data": ...}
      body: JSON.stringify({ data: {} }),
    });

    const raw = await resp.text();
    try {
      cfResponse = JSON.parse(raw);
    } catch {
      console.error(`ERROR: CF returned non-JSON body (HTTP ${resp.status}):\n${raw}`);
      process.exit(1);
    }

    if (!resp.ok) {
      // Callable errors arrive as {"error": {"status": "...", "message": "..."}}
      console.error(`CF returned HTTP ${resp.status} — see output below.`);
    } else {
      console.error("      CF call completed OK.");
    }
  } catch (err) {
    console.error(`ERROR calling CF endpoint: ${err.message}`);
    process.exit(1);
  }

  // ── Output: pretty-print the full CF result to STDOUT ─────────────────────
  // The callable protocol wraps success in {"result": <DeleteUserDataResult>}
  // and errors in {"error": {"status": "...", "message": "...", "details": ...}}
  // Unwrap "result" if present so the consumer sees the raw DeleteUserDataResult.
  const output = cfResponse.result !== undefined ? cfResponse.result : cfResponse;
  console.log(JSON.stringify(output, null, 2));

  process.exit(0);
})();
