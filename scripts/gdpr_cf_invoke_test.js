#!/usr/bin/env node
/**
 * gdpr_cf_invoke_test.js
 *
 * Invokes the DEPLOYED deleteUserData callable Cloud Function authenticated
 * AS the given test user.  The CF reads uid from context.auth.uid — NOT from
 * a parameter — so we must authenticate as that user, not just pass a uid.
 *
 * Token flow
 * ──────────
 *  1. admin.initializeApp() with the service-account key
 *  2. Optionally create the Auth user if they don't exist yet
 *     (createCustomToken does NOT require the user to exist in Auth; the Identity
 *      Toolkit signInWithCustomToken ALSO works without a pre-existing user record.
 *      BUT if either step rejects for "user not found", we create the user first
 *      and note it for cleanup.)
 *  3. admin.auth().createCustomToken(TEST_UID) → customToken
 *  4. POST identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken
 *        body: { token: customToken, returnSecureToken: true }
 *     → idToken
 *  5. POST https://europe-west2-huddl-connect.cloudfunctions.net/deleteUserData
 *        Authorization: Bearer {idToken}
 *        Content-Type: application/json
 *        body: {"data":{}}   ← callable protocol wrapper
 *     → print HTTP status + full structured result JSON
 *
 * Usage
 * ─────
 *   node scripts/gdpr_cf_invoke_test.js \
 *       /path/to/service-account-key.json \
 *       CFTEST_1781772973290 \
 *       AIzaSy_YOUR_WEB_API_KEY
 *
 * Args
 * ────
 *   arg2  Path to Firebase service-account JSON (Admin SDK key)
 *   arg3  TEST_UID — e.g. CFTEST_1781772973290
 *   arg4  Firebase Web API key (project-level browser key; find it in
 *         Firebase Console → Project Settings → General → "Web API key",
 *         or as "current_key" inside google-services.json)
 *         Cannot be derived from the service-account JSON — different key type.
 *
 * WARNING
 * ───────
 *   This script invokes the REAL deployed CF which deletes user data server-side
 *   for the given UID.  Run only against throwaway CFTEST_ UIDs.
 *   The script itself deletes NOTHING — all deletion is performed by the CF.
 *
 *   If the script had to create an Auth user in step 2, it will print a cleanup
 *   reminder at the end.  Delete that user with:
 *     node -e "
 *       const admin = require('./functions/node_modules/firebase-admin');
 *       admin.initializeApp({ credential: admin.credential.cert('<key.json>') });
 *       admin.auth().deleteUser('<uid>').then(() => console.log('deleted'));
 *     "
 */

"use strict";

const path = require("path");
const fs   = require("fs");

// ── Resolve deps from functions/node_modules regardless of cwd ──────────────
// scripts/ is a sibling of functions/; resolve absolutely from __dirname.
const FUNCTIONS_DIR = path.resolve(__dirname, "..", "functions");

const fetch = require(
  path.join(FUNCTIONS_DIR, "node_modules", "node-fetch", "lib", "index.js")
);
const admin = require(
  path.join(FUNCTIONS_DIR, "node_modules", "firebase-admin", "lib", "index.js")
);

// ── Constants ────────────────────────────────────────────────────────────────
const CF_ENDPOINT =
  "https://europe-west2-huddl-connect.cloudfunctions.net/deleteUserData";
const IDENTITY_TOOLKIT_URL =
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken";

// ── Arg parsing (argv[0]=node, argv[1]=script, then our args) ────────────────
const [,, keyPath, testUid, webApiKey] = process.argv;

if (!keyPath || !testUid || !webApiKey) {
  console.error([
    "",
    "Usage:",
    "  node scripts/gdpr_cf_invoke_test.js \\",
    "      /path/to/service-account-key.json \\",
    "      <TEST_UID> \\",
    "      <WEB_API_KEY>",
    "",
    "Args:",
    "  arg2  Service-account key JSON path",
    "  arg3  TEST_UID (e.g. CFTEST_1781772973290)",
    "  arg4  Firebase Web API key",
    "        (Firebase Console → Project Settings → General → Web API key)",
    "",
    "ERROR: Missing required argument(s).",
    "",
  ].join("\n"));
  process.exit(1);
}

const absKeyPath = path.resolve(keyPath);
if (!fs.existsSync(absKeyPath)) {
  console.error(`\nERROR: Service-account key not found: ${absKeyPath}\n`);
  process.exit(1);
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/** banner(msg) — diagnostic output on stderr so stdout stays clean JSON */
function banner(msg) {
  console.error(msg);
}

/**
 * die(label, detail) — print a structured error block and exit 1.
 * detail may be a string, Error, or plain object.
 */
function die(label, detail) {
  console.error(`\n── ERROR: ${label} ${"─".repeat(Math.max(0, 50 - label.length))}`);
  if (detail instanceof Error) {
    console.error(`  ${detail.message}`);
    if (detail.code) console.error(`  code: ${detail.code}`);
  } else if (typeof detail === "object") {
    console.error(JSON.stringify(detail, null, 2));
  } else {
    console.error(`  ${detail}`);
  }
  console.error("──────────────────────────────────────────────────────\n");
  process.exit(1);
}

// ── Main ─────────────────────────────────────────────────────────────────────
(async () => {

  banner("═══════════════════════════════════════════════════════");
  banner(" gdpr_cf_invoke_test.js");
  banner("═══════════════════════════════════════════════════════");
  banner(`  CF endpoint : ${CF_ENDPOINT}`);
  banner(`  Test UID    : ${testUid}`);
  banner(`  Key file    : ${absKeyPath}`);
  banner("═══════════════════════════════════════════════════════\n");

  // ── Step 1: Initialise Admin SDK ──────────────────────────────────────────
  banner("[1/5] Initialising Firebase Admin SDK...");
  try {
    admin.initializeApp({
      credential: admin.credential.cert(absKeyPath),
    });
  } catch (err) {
    die("Admin SDK init failed", err);
  }
  banner("      Admin SDK initialised OK.\n");

  // ── Step 2: Verify / create Auth user ────────────────────────────────────
  // createCustomToken does NOT require the UID to exist in Firebase Auth.
  // signInWithCustomToken at the Identity Toolkit also works without a
  // pre-existing record — it will CREATE a sparse user record automatically.
  // So we don't need to pre-create the user.  We attempt the token path
  // directly; if the CF callable rejects with UNAUTHENTICATED we note it here.
  //
  // However: if the caller explicitly wants a real Auth record (e.g. to verify
  // the token in emulator logs), we do a getUser() probe and createUser() if
  // absent, noting the cleanup requirement.
  banner("[2/5] Checking Auth user existence...");
  let authUserCreated = false;
  try {
    await admin.auth().getUser(testUid);
    banner(`      Auth user ${testUid} already exists in Firebase Auth.`);
  } catch (err) {
    if (err.code === "auth/user-not-found") {
      banner(`      Auth user ${testUid} not found — creating sparse Auth record...`);
      try {
        await admin.auth().createUser({ uid: testUid });
        authUserCreated = true;
        banner(`      Auth user created OK.`);
        banner(`  ⚠  CLEANUP NOTE: Auth user ${testUid} was created by this script.`);
        banner(`  ⚠  Delete it afterwards with:`);
        banner(`  ⚠    admin.auth().deleteUser("${testUid}")`);
      } catch (createErr) {
        die("auth/createUser failed", createErr);
      }
    } else {
      // Unexpected error (network, permissions) — abort
      die("auth/getUser failed with unexpected error", err);
    }
  }
  banner("");

  // ── Step 3: Mint custom token ─────────────────────────────────────────────
  banner("[3/5] Minting custom token for UID: " + testUid);
  let customToken;
  try {
    customToken = await admin.auth().createCustomToken(testUid);
  } catch (err) {
    die("createCustomToken failed", err);
  }
  banner("      Custom token minted OK.\n");

  // ── Step 4: Exchange custom token → ID token ─────────────────────────────
  banner("[4/5] Exchanging custom token for ID token (Identity Toolkit)...");
  let idToken;
  {
    const url = `${IDENTITY_TOOLKIT_URL}?key=${webApiKey}`;
    let resp, body;
    try {
      resp = await fetch(url, {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify({ token: customToken, returnSecureToken: true }),
      });
      body = await resp.json();
    } catch (err) {
      die("Identity Toolkit request failed (network)", err);
    }

    if (!resp.ok || !body.idToken) {
      console.error(`      HTTP status: ${resp.status}`);
      die("Identity Toolkit exchange failed", body);
    }

    idToken = body.idToken;
  }
  banner("      ID token obtained OK.\n");

  // ── Step 5: Call the deployed callable CF ────────────────────────────────
  banner("[5/5] Calling deployed CF...");
  banner(`      POST ${CF_ENDPOINT}`);
  banner(`      Authorization: Bearer <idToken>`);
  banner(`      Body: {"data":{}}\n`);

  let httpStatus;
  let cfRaw;
  let cfParsed;

  try {
    const resp = await fetch(CF_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type":  "application/json",
        "Authorization": `Bearer ${idToken}`,
      },
      body: JSON.stringify({ data: {} }),
    });

    httpStatus = resp.status;
    cfRaw      = await resp.text();

    try {
      cfParsed = JSON.parse(cfRaw);
    } catch {
      die(
        `CF returned non-JSON body (HTTP ${httpStatus})`,
        `Raw body:\n${cfRaw}`
      );
    }
  } catch (err) {
    if (err.code) {
      // Already called die() above for non-JSON; this catches network errors
      die("CF request failed (network)", err);
    }
    throw err;
  }

  banner(`      HTTP status: ${httpStatus}`);
  if (httpStatus >= 200 && httpStatus < 300) {
    banner("      CF call completed OK.\n");
  } else {
    banner(`      CF returned non-2xx status — error details below.\n`);
  }

  // ── Output ────────────────────────────────────────────────────────────────
  // Callable success:  { "result": <DeleteUserDataResult> }
  // Callable error:    { "error": { "status": "...", "message": "...", "details": ... } }
  //
  // Unwrap "result" so stdout is the raw DeleteUserDataResult (success, steps,
  // uid, timestamps).  Errors are passed through as-is with an "error" key.
  const output = (cfParsed && cfParsed.result !== undefined)
    ? cfParsed.result
    : cfParsed;

  // ── Structured stderr summary ─────────────────────────────────────────────
  banner("═══════════════════════════════════════════════════════");
  banner(` RESULT  (HTTP ${httpStatus})`);
  banner("═══════════════════════════════════════════════════════\n");

  // ── Machine-readable result to STDOUT ────────────────────────────────────
  console.log(JSON.stringify(output, null, 2));

  // ── Cleanup reminder (stderr, after stdout) ───────────────────────────────
  if (authUserCreated) {
    banner("\n═══════════════════════════════════════════════════════");
    banner(" ⚠  CLEANUP REQUIRED");
    banner("═══════════════════════════════════════════════════════");
    banner(` Auth user created: ${testUid}`);
    banner(" This user now exists in Firebase Auth and must be deleted manually.");
    banner(" Run:");
    banner(`   node -e "const a=require('./functions/node_modules/firebase-admin');` +
           `a.initializeApp({credential:a.credential.cert('${absKeyPath}')});` +
           `a.auth().deleteUser('${testUid}').then(()=>console.log('deleted')).catch(console.error)"`);
    banner("═══════════════════════════════════════════════════════\n");
  }

  process.exit(httpStatus >= 200 && httpStatus < 300 ? 0 : 1);

})();
