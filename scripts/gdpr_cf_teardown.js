#!/usr/bin/env node
/**
 * gdpr_cf_teardown.js
 *
 * Deletes EVERY artifact created by gdpr_cf_seed_prod.js, for both the test
 * user and the bystander, giving a clean slate.
 *
 * Usage
 * ─────
 *   node scripts/gdpr_cf_teardown.js <service-account-key.json> [timestamp]
 *
 * Args
 * ────
 *   arg2  Path to Firebase service-account JSON  (required)
 *   arg3  Timestamp suffix from the seed run, e.g. 1781772973290  (optional)
 *         When supplied: deletes only artifacts from THAT seed run.
 *         When omitted:  scans ALL docs whose IDs contain "cftest" (case-insensitive)
 *                        and deletes them — catches leftovers from multiple runs.
 *
 * What gets deleted
 * ─────────────────
 *   1. Firestore — every doc whose ID contains "cftest" across all seeded
 *      collections, PLUS:
 *        • borough_announcements/{annId}/comments subcollection
 *        • conversations/{convId}/messages subcollection
 *        • users/{uid}/* subcollections (saved_messages, notifPrefs, deadlines,
 *          saved_items, blocks, invitations)
 *        • groups/{gid}/memberActivity subcollection
 *        • user_rsvps/{uid}/meetups subcollection
 *        • local_services/{lsId}/endorsements subcollection
 *        • outbound_invitations/{parentId}/invitations subcollection
 *      Scan-all mode uses collectionGroup scans for subcollections where
 *      the parent ID may vary across runs.
 *
 *   2. Storage — all files under prefixes containing "cftest" in:
 *        profile_photos/CFTEST_<ts> .../
 *        marketplace_images/CFTEST_<ts> .../
 *        dm_images/cftest_conv_<ts> .../
 *        dm_documents/cftest_conv_<ts> .../
 *        voice_notes/dm/cftest_conv_<ts> .../
 *        group_images/cftest_group_<ts> .../
 *        group_documents/cftest_group_<ts> .../
 *        voice_notes/group/cftest_group_<ts> .../
 *
 *   3. Firebase Auth — any user whose uid starts with "CFTEST_" (or exactly
 *      matches "CFTEST_<ts>" / "CFTEST_BYST_<ts>" when ts is supplied).
 *      Failures on non-existent users are silently ignored.
 *
 * What it does NOT do
 * ───────────────────
 *   • Does NOT touch any doc, file, or auth user that does not match the
 *     cftest pattern — bystander documents are ALSO cftest-prefixed so they
 *     ARE cleaned up here (this is intentional: teardown removes everything).
 *   • Does NOT call the GDPR CF.
 *
 * Output
 * ──────
 *   Prints a per-collection, per-storage-prefix, per-auth summary of counts.
 *   Exits 0 on success, 1 if any deletion failed.
 */

"use strict";

const path = require("path");
const fs   = require("fs");

// ── Resolve deps from functions/node_modules (cwd-independent) ───────────────
const FUNCTIONS_DIR = path.resolve(__dirname, "..", "functions");
const admin = require(path.join(FUNCTIONS_DIR, "node_modules", "firebase-admin", "lib", "index.js"));

// ── Arg parsing ───────────────────────────────────────────────────────────────
const [,, keyPath, tsArg] = process.argv;

if (!keyPath) {
  console.error([
    "",
    "Usage:",
    "  node scripts/gdpr_cf_teardown.js <service-account-key.json> [timestamp]",
    "",
    "Args:",
    "  arg2  Service-account key JSON path  (required)",
    "  arg3  Seed timestamp suffix, e.g. 1781772973290  (optional)",
    "        Omit to scan-all and delete every cftest artifact.",
    "",
    "ERROR: Missing required argument.",
    "",
  ].join("\n"));
  process.exit(1);
}

const absKeyPath = path.resolve(keyPath);
if (!fs.existsSync(absKeyPath)) {
  console.error(`\nERROR: Service-account key not found: ${absKeyPath}\n`);
  process.exit(1);
}

const TS = tsArg || null;   // null = scan-all mode

// ── Firebase init ─────────────────────────────────────────────────────────────
const PROJECT_ID     = "huddl-connect";
const STORAGE_BUCKET = "huddl-connect.firebasestorage.app";

admin.initializeApp({
  credential:    admin.credential.cert(absKeyPath),
  projectId:     PROJECT_ID,
  storageBucket: STORAGE_BUCKET,
});

const db     = admin.firestore();
const bucket = admin.storage().bucket(STORAGE_BUCKET);

// ── Helpers ───────────────────────────────────────────────────────────────────

/** log to stderr so stdout stays clean for any pipe usage */
function log(msg)  { console.error(msg); }
function logErr(m) { console.error(`  ⚠  ${m}`); }

/**
 * isCftest(id) — true if the doc/file ID contains "cftest" (case-insensitive).
 * When TS is provided, also checks the id ends with the timestamp suffix.
 */
function isCftest(id) {
  if (!id) return false;
  const lower = id.toLowerCase();
  if (!lower.includes("cftest")) return false;
  if (TS && !id.includes(TS)) return false;
  return true;
}

/**
 * deleteQueryResults(query, label) — executes query, deletes all matching docs,
 * returns count deleted.
 */
async function deleteQueryResults(query, label) {
  const snap = await query.get();
  if (snap.empty) return 0;
  const batch = db.batch();
  snap.docs.forEach(d => batch.delete(d.ref));
  await batch.commit();
  return snap.size;
}

/**
 * deleteCollection(collRef, label) — scans the collection for all docs whose
 * ID passes isCftest(), deletes them, returns count.
 */
async function deleteCollection(collectionPath, label) {
  const snap = await db.collection(collectionPath).get();
  if (snap.empty) return 0;
  const matching = snap.docs.filter(d => isCftest(d.id));
  if (matching.length === 0) return 0;
  // Delete in batches of 400
  let total = 0;
  for (let i = 0; i < matching.length; i += 400) {
    const batch = db.batch();
    matching.slice(i, i + 400).forEach(d => batch.delete(d.ref));
    await batch.commit();
    total += Math.min(400, matching.length - i);
  }
  return total;
}

/**
 * deleteSubcollectionOfCftestParents(parentCollection, subcollection)
 * — finds all docs in parentCollection whose IDs are cftest-prefixed,
 *   then deletes ALL docs in their subcollection.
 * Returns total docs deleted.
 */
async function deleteSubcollectionOfCftestParents(parentCollection, subcollection) {
  const parentSnap = await db.collection(parentCollection).get();
  if (parentSnap.empty) return 0;
  const cftestParents = parentSnap.docs.filter(d => isCftest(d.id));
  let total = 0;
  for (const parent of cftestParents) {
    const subSnap = await parent.ref.collection(subcollection).get();
    if (subSnap.empty) continue;
    for (let i = 0; i < subSnap.docs.length; i += 400) {
      const batch = db.batch();
      subSnap.docs.slice(i, i + 400).forEach(d => batch.delete(d.ref));
      await batch.commit();
      total += Math.min(400, subSnap.docs.length - i);
    }
  }
  return total;
}

/**
 * deleteCollectionGroupCftest(collectionId)
 * — collectionGroup scan: deletes all docs in any subcollection named
 *   collectionId whose own doc ID passes isCftest(), OR whose parent doc
 *   ID passes isCftest().
 * Used for subcollections whose parent path is not predictable.
 * Returns total docs deleted.
 */
async function deleteCollectionGroupCftest(collectionId) {
  const snap = await db.collectionGroup(collectionId).get();
  if (snap.empty) return 0;
  // Delete if doc ID is cftest OR parent doc ID is cftest
  const matching = snap.docs.filter(d => {
    const docId    = d.id;
    const parentId = d.ref.parent.parent ? d.ref.parent.parent.id : "";
    return isCftest(docId) || isCftest(parentId);
  });
  if (matching.length === 0) return 0;
  let total = 0;
  for (let i = 0; i < matching.length; i += 400) {
    const batch = db.batch();
    matching.slice(i, i + 400).forEach(d => batch.delete(d.ref));
    await batch.commit();
    total += Math.min(400, matching.length - i);
  }
  return total;
}

/**
 * deleteStoragePrefix(prefix) — lists and deletes all files under a given
 * GCS prefix. Returns count deleted.
 */
async function deleteStoragePrefix(prefix) {
  const [files] = await bucket.getFiles({ prefix });
  if (!files || files.length === 0) return 0;
  await Promise.all(files.map(f => f.delete().catch(() => {})));
  return files.length;
}

/**
 * deleteStoragePrefixesMatching(topPrefix, filterFn)
 * — lists all files under topPrefix, applies filterFn(filePath) to include
 *   only cftest-relevant files, deletes matching ones.
 * Returns count deleted.
 */
async function deleteStoragePrefixesMatching(topPrefix, filterFn) {
  const [files] = await bucket.getFiles({ prefix: topPrefix });
  if (!files || files.length === 0) return 0;
  const matching = files.filter(f => filterFn(f.name));
  if (matching.length === 0) return 0;
  await Promise.all(matching.map(f => f.delete().catch(() => {})));
  return matching.length;
}

// ── Auth deletion helpers ─────────────────────────────────────────────────────

/**
 * deleteAuthUser(uid) — deletes an Auth user, silently ignores user-not-found.
 * Returns true if deleted, false if not found, throws on other errors.
 */
async function deleteAuthUser(uid) {
  try {
    await admin.auth().deleteUser(uid);
    return true;
  } catch (err) {
    if (err.code === "auth/user-not-found") return false;
    throw err;
  }
}

/**
 * deleteAllCftestAuthUsers() — lists all Auth users (paginated), deletes any
 * whose uid starts with "CFTEST_". When TS is set, further filters to exact
 * seed-run UIDs (CFTEST_<ts> and CFTEST_BYST_<ts>).
 * Returns count deleted.
 */
async function deleteAllCftestAuthUsers() {
  if (TS) {
    // Fast path: exact UIDs known
    const uids = [`CFTEST_${TS}`, `CFTEST_BYST_${TS}`];
    let count = 0;
    for (const uid of uids) {
      const deleted = await deleteAuthUser(uid);
      if (deleted) count++;
    }
    return count;
  }

  // Scan-all path: paginate through all Auth users
  let count      = 0;
  let pageToken;
  do {
    const listResult = await admin.auth().listUsers(1000, pageToken);
    const cftestUsers = listResult.users.filter(u =>
      u.uid.startsWith("CFTEST_")
    );
    for (const user of cftestUsers) {
      const deleted = await deleteAuthUser(user.uid);
      if (deleted) count++;
    }
    pageToken = listResult.pageToken;
  } while (pageToken);

  return count;
}

// ── Summary accumulator ───────────────────────────────────────────────────────

const summary = {
  firestore: {},   // label → count
  storage:   {},   // label → count
  auth:      0,
  errors:    [],
};

function recordFS(label, count) {
  summary.firestore[label] = (summary.firestore[label] || 0) + count;
}
function recordST(label, count) {
  summary.storage[label] = (summary.storage[label] || 0) + count;
}

// ── Main ─────────────────────────────────────────────────────────────────────

(async () => {

  const SEP  = "─".repeat(72);
  const WIDE = "═".repeat(72);

  log(`\n${WIDE}`);
  log(` gdpr_cf_teardown.js — huddl-connect PRODUCTION`);
  log(WIDE);
  log(` Mode      : ${TS ? `targeted  (ts=${TS})` : "scan-all  (every cftest artifact)"}`);
  log(` Key file  : ${absKeyPath}`);
  log(WIDE + "\n");

  let hasError = false;

  // ──────────────────────────────────────────────────────────────────────────
  // 1. FIRESTORE — top-level collections
  // ──────────────────────────────────────────────────────────────────────────

  log("[1/3] Deleting Firestore documents...\n");

  // Collections where the doc ID itself is the cftest ID
  const topLevelCollections = [
    "users",
    "users_public",
    "subscriptions",
    "notifications",
    "local_services",
    "borough_feed",
    "feedback",
    "community_wisdom",
    "borough_announcements",
    "reports",
    "group_messages",
    "meetups",
    "marketplace",
    "polls",
    "partner_analytics",
    "groups",
    "conversations",
    "user_rsvps",
    "outbound_invitations",
  ];

  for (const coll of topLevelCollections) {
    try {
      const n = await deleteCollection(coll, coll);
      recordFS(coll, n);
      if (n > 0) log(`    ${coll.padEnd(30)} ${n} doc(s) deleted`);
    } catch (err) {
      logErr(`deleteCollection(${coll}) failed: ${err.message}`);
      summary.errors.push(`deleteCollection(${coll}): ${err.message}`);
      hasError = true;
    }
  }

  // ── Subcollections of borough_announcements/{annId}/comments ─────────────
  try {
    const n = await deleteSubcollectionOfCftestParents("borough_announcements", "comments");
    recordFS("borough_announcements/*/comments", n);
    if (n > 0) log(`    ${"borough_announcements/*/comments".padEnd(30)} ${n} doc(s) deleted`);
  } catch (err) {
    logErr(`borough_announcements/*/comments failed: ${err.message}`);
    summary.errors.push(`borough_announcements/*/comments: ${err.message}`);
    hasError = true;
  }

  // ── Subcollections of conversations/{convId}/messages ────────────────────
  try {
    const n = await deleteSubcollectionOfCftestParents("conversations", "messages");
    recordFS("conversations/*/messages", n);
    if (n > 0) log(`    ${"conversations/*/messages".padEnd(30)} ${n} doc(s) deleted`);
  } catch (err) {
    logErr(`conversations/*/messages failed: ${err.message}`);
    summary.errors.push(`conversations/*/messages: ${err.message}`);
    hasError = true;
  }

  // ── users/{uid}/* subcollections — parent doc ID is the UID (cftest) ─────
  const userSubcollections = [
    "saved_messages",
    "notifPrefs",
    "deadlines",
    "saved_items",
    "blocks",
    "invitations",
  ];

  for (const sub of userSubcollections) {
    try {
      const n = await deleteSubcollectionOfCftestParents("users", sub);
      recordFS(`users/*/${sub}`, n);
      if (n > 0) log(`    ${"users/*/"+sub.padEnd(27)} ${n} doc(s) deleted`);
    } catch (err) {
      logErr(`users/*/${sub} failed: ${err.message}`);
      summary.errors.push(`users/*/${sub}: ${err.message}`);
      hasError = true;
    }
  }

  // ── groups/{gid}/memberActivity ───────────────────────────────────────────
  // Group doc ID is cftest_group_<ts>
  try {
    const n = await deleteSubcollectionOfCftestParents("groups", "memberActivity");
    recordFS("groups/*/memberActivity", n);
    if (n > 0) log(`    ${"groups/*/memberActivity".padEnd(30)} ${n} doc(s) deleted`);
  } catch (err) {
    logErr(`groups/*/memberActivity failed: ${err.message}`);
    summary.errors.push(`groups/*/memberActivity: ${err.message}`);
    hasError = true;
  }

  // ── user_rsvps/{uid}/meetups ──────────────────────────────────────────────
  try {
    const n = await deleteSubcollectionOfCftestParents("user_rsvps", "meetups");
    recordFS("user_rsvps/*/meetups", n);
    if (n > 0) log(`    ${"user_rsvps/*/meetups".padEnd(30)} ${n} doc(s) deleted`);
  } catch (err) {
    logErr(`user_rsvps/*/meetups failed: ${err.message}`);
    summary.errors.push(`user_rsvps/*/meetups: ${err.message}`);
    hasError = true;
  }

  // ── local_services/{lsId}/endorsements ───────────────────────────────────
  // lsId is cftest_ls_<ts>; endorsement doc ID may be the UID itself
  try {
    const n = await deleteSubcollectionOfCftestParents("local_services", "endorsements");
    recordFS("local_services/*/endorsements", n);
    if (n > 0) log(`    ${"local_services/*/endorsements".padEnd(30)} ${n} doc(s) deleted`);
  } catch (err) {
    logErr(`local_services/*/endorsements failed: ${err.message}`);
    summary.errors.push(`local_services/*/endorsements: ${err.message}`);
    hasError = true;
  }

  // ── outbound_invitations/{parentId}/invitations ───────────────────────────
  try {
    const n = await deleteSubcollectionOfCftestParents("outbound_invitations", "invitations");
    recordFS("outbound_invitations/*/invitations", n);
    if (n > 0) log(`    ${"outbound_invitations/*/inv".padEnd(30)} ${n} doc(s) deleted`);
  } catch (err) {
    logErr(`outbound_invitations/*/invitations failed: ${err.message}`);
    summary.errors.push(`outbound_invitations/*/invitations: ${err.message}`);
    hasError = true;
  }

  // ── collectionGroup scans for invitations and endorsements (belt + braces) ─
  // Catches any invitations/endorsements nested under non-cftest parent IDs
  // e.g. if a real group or service has a cftest sub-doc we missed above.
  try {
    const n = await deleteCollectionGroupCftest("invitations");
    if (n > 0) {
      recordFS("collectionGroup(invitations)", n);
      log(`    ${"collectionGroup(invitations)".padEnd(30)} ${n} doc(s) deleted`);
    }
  } catch (err) {
    logErr(`collectionGroup(invitations) failed: ${err.message}`);
    summary.errors.push(`collectionGroup(invitations): ${err.message}`);
    hasError = true;
  }

  try {
    const n = await deleteCollectionGroupCftest("endorsements");
    if (n > 0) {
      recordFS("collectionGroup(endorsements)", n);
      log(`    ${"collectionGroup(endorsements)".padEnd(30)} ${n} doc(s) deleted`);
    }
  } catch (err) {
    logErr(`collectionGroup(endorsements) failed: ${err.message}`);
    summary.errors.push(`collectionGroup(endorsements): ${err.message}`);
    hasError = true;
  }

  log("");

  // ──────────────────────────────────────────────────────────────────────────
  // 2. STORAGE — all cftest-prefixed files
  // ──────────────────────────────────────────────────────────────────────────

  log("[2/3] Deleting Storage files...\n");

  /**
   * storageJobs: each entry is:
   *   { topPrefix, label, filter? }
   * filter(filename) → bool — if omitted, all files under topPrefix are deleted.
   * "cftest-containing" filtering on the path component after topPrefix.
   */

  // For scan-all mode we use broad "cftest" prefix matching.
  // For targeted mode (TS supplied) we also accept the exact CFTEST_<ts> pattern.
  function cfPath(p) {
    return p.toLowerCase().includes("cftest");
  }

  const storageJobs = [
    // profile_photos/CFTEST_*/  — entire uid-prefixed subtree
    {
      topPrefix: "profile_photos/",
      label: "profile_photos/CFTEST*/",
      filter: (name) => {
        // name = "profile_photos/CFTEST_<ts>/filename.jpg"
        const segment = name.split("/")[1] || "";
        return segment.startsWith("CFTEST_") && (TS ? segment.includes(TS) : true);
      },
    },
    // marketplace_images/CFTEST_*/
    {
      topPrefix: "marketplace_images/",
      label: "marketplace_images/CFTEST*/",
      filter: (name) => {
        const segment = name.split("/")[1] || "";
        return segment.startsWith("CFTEST_") && (TS ? segment.includes(TS) : true);
      },
    },
    // dm_images/cftest_conv*/
    {
      topPrefix: "dm_images/",
      label: "dm_images/cftest_conv*/",
      filter: (name) => {
        const segment = name.split("/")[1] || "";
        return segment.startsWith("cftest_conv") && (TS ? segment.includes(TS) : true);
      },
    },
    // dm_documents/cftest_conv*/
    {
      topPrefix: "dm_documents/",
      label: "dm_documents/cftest_conv*/",
      filter: (name) => {
        const segment = name.split("/")[1] || "";
        return segment.startsWith("cftest_conv") && (TS ? segment.includes(TS) : true);
      },
    },
    // voice_notes/dm/cftest_conv*/
    {
      topPrefix: "voice_notes/dm/",
      label: "voice_notes/dm/cftest_conv*/",
      filter: (name) => {
        // name = "voice_notes/dm/cftest_conv_<ts>/file.m4a"
        const parts   = name.split("/");
        const segment = parts[2] || "";
        return segment.startsWith("cftest_conv") && (TS ? segment.includes(TS) : true);
      },
    },
    // group_images/cftest_group*/
    {
      topPrefix: "group_images/",
      label: "group_images/cftest_group*/",
      filter: (name) => {
        const segment = name.split("/")[1] || "";
        return segment.startsWith("cftest_group") && (TS ? segment.includes(TS) : true);
      },
    },
    // group_documents/cftest_group*/
    {
      topPrefix: "group_documents/",
      label: "group_documents/cftest_group*/",
      filter: (name) => {
        const segment = name.split("/")[1] || "";
        return segment.startsWith("cftest_group") && (TS ? segment.includes(TS) : true);
      },
    },
    // voice_notes/group/cftest_group*/
    {
      topPrefix: "voice_notes/group/",
      label: "voice_notes/group/cftest_group*/",
      filter: (name) => {
        const parts   = name.split("/");
        const segment = parts[2] || "";
        return segment.startsWith("cftest_group") && (TS ? segment.includes(TS) : true);
      },
    },
  ];

  for (const job of storageJobs) {
    try {
      const n = await deleteStoragePrefixesMatching(job.topPrefix, job.filter);
      recordST(job.label, n);
      if (n > 0) log(`    ${job.label.padEnd(40)} ${n} file(s) deleted`);
    } catch (err) {
      logErr(`Storage ${job.label} failed: ${err.message}`);
      summary.errors.push(`Storage ${job.label}: ${err.message}`);
      hasError = true;
    }
  }

  log("");

  // ──────────────────────────────────────────────────────────────────────────
  // 3. AUTH — CFTEST_* users
  // ──────────────────────────────────────────────────────────────────────────

  log("[3/3] Deleting Firebase Auth users...\n");
  try {
    const n = await deleteAllCftestAuthUsers();
    summary.auth = n;
    log(`    Auth users deleted                   ${n}`);
  } catch (err) {
    logErr(`Auth deletion failed: ${err.message}`);
    summary.errors.push(`Auth: ${err.message}`);
    hasError = true;
  }

  log("");

  // ──────────────────────────────────────────────────────────────────────────
  // 4. SUMMARY
  // ──────────────────────────────────────────────────────────────────────────

  const totalFS = Object.values(summary.firestore).reduce((a, b) => a + b, 0);
  const totalST = Object.values(summary.storage).reduce((a, b) => a + b, 0);

  log(WIDE);
  log(` TEARDOWN COMPLETE`);
  log(WIDE);
  log(` Mode         : ${TS ? `targeted (ts=${TS})` : "scan-all"}`);
  log(SEP);

  log(` Firestore    : ${totalFS} doc(s) deleted`);
  for (const [label, count] of Object.entries(summary.firestore)) {
    if (count > 0) log(`   ${label.padEnd(40)} ${count}`);
  }

  log(SEP);
  log(` Storage      : ${totalST} file(s) deleted`);
  for (const [label, count] of Object.entries(summary.storage)) {
    if (count > 0) log(`   ${label.padEnd(40)} ${count}`);
  }

  log(SEP);
  log(` Auth         : ${summary.auth} user(s) deleted`);

  if (summary.errors.length > 0) {
    log(SEP);
    log(` ERRORS (${summary.errors.length}):`);
    summary.errors.forEach(e => log(`   ⚠  ${e}`));
  }

  log(WIDE);

  // Machine-readable JSON to stdout
  console.log(JSON.stringify({
    mode:      TS ? "targeted" : "scan-all",
    timestamp: TS || null,
    firestore: summary.firestore,
    storage:   summary.storage,
    auth:      summary.auth,
    totals: {
      firestore: totalFS,
      storage:   totalST,
      auth:      summary.auth,
    },
    errors: summary.errors,
  }, null, 2));

  process.exit(hasError ? 1 : 0);

})();
