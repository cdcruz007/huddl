/**
 * Huddl — GDPR Deletion CF Phase 1 Tests
 *
 * Tests the deleteUserData Cloud Function spine:
 *
 *   SECURITY (most critical):
 *     T-GDPR1-unauth          — context.auth null → throws unauthenticated
 *     T-GDPR1-payload-uid-ignored — context.auth.uid != payload uid → uses auth uid only
 *
 *   SIMPLE QUERY-DELETES (9 collections, correct field names):
 *     T-GDPR1-subscriptions   — deletes subscriptions by userId
 *     T-GDPR1-notifications   — deletes notifications by userId
 *     T-GDPR1-local-services  — deletes local_services by createdByUid
 *     T-GDPR1-borough-feed    — deletes borough_feed by partnerUid
 *     T-GDPR1-feedback        — deletes feedback by user_uid (policy=delete)
 *     T-GDPR1-community-wisdom — deletes community_wisdom by author_uid (policy=delete)
 *     T-GDPR1-group-messages  — deletes group_messages by senderId
 *     T-GDPR1-meetups         — deletes meetups by createdBy AND organiserId
 *     T-GDPR1-marketplace     — deletes marketplace by sellerId
 *
 *   SCOPING (second user untouched):
 *     T-GDPR1-scoping         — bob's docs in all 9 collections survive alice's deletion
 *
 *   PAGINATION:
 *     T-GDPR1-pagination      — >400 docs in subscriptions → all deleted across multiple batches
 *
 *   CONFIG:
 *     T-GDPR1-config-absent   — no _config doc → defaults applied (feedback:delete, authored_content:anonymise)
 *     T-GDPR1-config-present  — _config doc present → overrides applied
 *     T-GDPR1-config-authored-content-retain — policy.authored_content=retain → community_wisdom skipped
 *     T-GDPR1-config-feedback-retain         — policy.feedback=retain → feedback skipped
 *
 *   DRY RUN:
 *     T-GDPR1-dryrun          — dryRun=true reports counts but deletes nothing
 *
 *   RETURN SHAPE:
 *     T-GDPR1-return-shape    — result has success, uid, dryRun, startedAt, completedAt, policy, steps
 *
 * Approach:
 *   The CF handler is called directly (not via HTTP) by extracting the inner
 *   async handler from the exported onCall wrapper. We pass controlled context
 *   objects to test the security invariant without a running Functions emulator.
 *
 *   Firestore state is seeded/verified via Admin SDK pointed at the
 *   Firestore emulator (port 8180, matching prior session convention).
 *
 * Total: 18 tests
 */

import * as admin from "firebase-admin";

// ── Emulator connection ────────────────────────────────────────────────────

const PROJECT_ID = "huddl-gdpr-phase1-test";

// Point Admin SDK at the Firestore emulator.
// Must be set BEFORE importing the CF module so that the CF's module-level
// admin.initializeApp() and its `db` reference both connect to the emulator.
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8180";

// Supply a project ID so the CF's default Admin SDK app can form collection
// paths without needing ADC / GCLOUD credentials.
// GCLOUD_PROJECT is honoured by both firebase-admin and @google-cloud/firestore.
process.env.GCLOUD_PROJECT = PROJECT_ID;

let adminApp: admin.app.App;
let db: admin.firestore.Firestore;

// ── Personas ───────────────────────────────────────────────────────────────

const ALICE_UID = "alice_gdpr1_uid";
const BOB_UID   = "bob_gdpr1_uid";

// ── CF handler extraction ──────────────────────────────────────────────────
//
// firebase-functions v5 onCall returns an object with a `.run()` method that
// accepts (data, context). We call this directly to avoid HTTP overhead and
// to control context.auth precisely for security tests.

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let deleteUserDataHandler: (data: any, context: any) => Promise<any>;

// ── Helpers ────────────────────────────────────────────────────────────────

/** Build a mock context with a valid auth uid. */
function authCtx(uid: string) {
  return { auth: { uid, token: {} } };
}

/** Build a mock context with no auth (unauthenticated). */
function unauthCtx() {
  return { auth: null };
}

/** Seed `count` docs into `collectionName` with `uidField` set to `uid`.
 *  Each doc gets a unique ID and a `seeded: true` marker for easy verification. */
async function seed(
  collectionName: string,
  uidField: string,
  uid: string,
  count: number,
  extraFields: Record<string, unknown> = {}
): Promise<void> {
  const col = db.collection(collectionName);
  // Include uidField in the doc ID to prevent collisions when seeding
  // the same collection with different field names (e.g. meetups createdBy vs organiserId).
  const fieldSlug = uidField.replace(/[^a-zA-Z0-9]/g, "_");
  const chunks: Array<Array<{ id: string; data: Record<string, unknown> }>> = [[]];
  for (let i = 0; i < count; i++) {
    const last = chunks[chunks.length - 1];
    if (last.length >= 499) chunks.push([]);
    chunks[chunks.length - 1].push({
      id: `${collectionName}_${fieldSlug}_${uid}_${String(i).padStart(4, "0")}`,
      data: { [uidField]: uid, seeded: true, idx: i, ...extraFields },
    });
  }
  for (const chunk of chunks) {
    const batch = db.batch();
    for (const { id, data } of chunk) {
      batch.set(col.doc(id), data);
    }
    await batch.commit();
  }
}

/** Count docs in a collection where `uidField == uid`. */
async function countDocs(collectionName: string, uidField: string, uid: string): Promise<number> {
  const snap = await db.collection(collectionName).where(uidField, "==", uid).get();
  return snap.size;
}

/** Delete all docs in a collection (cleanup between tests). */
async function clearCollection(collectionName: string): Promise<void> {
  const snap = await db.collection(collectionName).limit(500).get();
  if (snap.empty) return;
  const batch = db.batch();
  snap.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
  // Recurse if there were more docs
  if (snap.docs.length === 500) await clearCollection(collectionName);
}

/** All collections touched by Phase 1 (for cleanup). */
const ALL_COLLECTIONS = [
  "subscriptions", "notifications", "local_services", "borough_feed",
  "feedback", "community_wisdom", "group_messages", "meetups", "marketplace",
  "_config",
];

async function clearAll(): Promise<void> {
  await Promise.all(ALL_COLLECTIONS.map(clearCollection));
}

// ── Setup / Teardown ───────────────────────────────────────────────────────

beforeAll(async () => {
  // Init Admin SDK against emulator.
  adminApp = admin.initializeApp({ projectId: PROJECT_ID }, "gdpr-phase1-test");
  db = adminApp.firestore();

  // Extract the CF handler.
  // We re-use the compiled functions module. Since the CF module calls
  // admin.initializeApp() at module level, we need to ensure our test app
  // is the one being used. We do this by pointing FIRESTORE_EMULATOR_HOST
  // before requiring the module.
  //
  // The CF exports `deleteUserData` as a firebase-functions CallableFunction.
  // In firebase-functions v5, the underlying handler is available via `.run()`.
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const cfModule = require("../../functions/lib/index.js");
  const cf = cfModule.deleteUserData;

  if (typeof cf.run === "function") {
    deleteUserDataHandler = cf.run.bind(cf);
  } else if (typeof cf === "function") {
    // Fallback: some versions expose the handler directly
    deleteUserDataHandler = cf;
  } else {
    throw new Error("Cannot extract deleteUserData handler from CF module.");
  }
});

beforeEach(async () => {
  await clearAll();
});

afterAll(async () => {
  await clearAll();
  await adminApp.delete();
});

// ══════════════════════════════════════════════════════════════════════════
// SECURITY TESTS
// ══════════════════════════════════════════════════════════════════════════

describe("Security invariant", () => {

  test("T-GDPR1-unauth: null context.auth → throws unauthenticated", async () => {
    await expect(deleteUserDataHandler({}, unauthCtx()))
      .rejects
      .toMatchObject({ code: "unauthenticated" });
  });

  test("T-GDPR1-payload-uid-ignored: context.auth.uid used; payload uid ignored", async () => {
    // Seed 2 docs for alice, 2 docs for bob in subscriptions.
    await seed("subscriptions", "userId", ALICE_UID, 2);
    await seed("subscriptions", "userId", BOB_UID, 2);

    // Call with alice's auth context but put BOB's uid in the payload.
    // The CF must use alice's uid (from context) and leave bob's docs untouched.
    // If the CF incorrectly used the payload uid, it would delete bob's 2 docs instead.
    const result = await deleteUserDataHandler(
      { uid: BOB_UID }, // attacker-supplied uid in payload — must be ignored
      authCtx(ALICE_UID)
    );

    // Alice's docs deleted, bob's docs untouched.
    const aliceRemaining = await countDocs("subscriptions", "userId", ALICE_UID);
    const bobRemaining   = await countDocs("subscriptions", "userId", BOB_UID);

    expect(result.uid).toBe(ALICE_UID);      // CF used auth uid, not payload uid
    expect(aliceRemaining).toBe(0);           // alice's docs gone
    expect(bobRemaining).toBe(2);             // bob's docs untouched
  });
});

// ══════════════════════════════════════════════════════════════════════════
// SIMPLE QUERY-DELETE TESTS (one per collection)
// ══════════════════════════════════════════════════════════════════════════

describe("Simple query-deletes", () => {

  test("T-GDPR1-subscriptions: deletes subscriptions by userId", async () => {
    await seed("subscriptions", "userId", ALICE_UID, 3);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.subscriptions.status).toBe("ok");
    expect(result.steps.subscriptions.count).toBe(3);
    expect(await countDocs("subscriptions", "userId", ALICE_UID)).toBe(0);
  });

  test("T-GDPR1-notifications: deletes notifications by userId", async () => {
    await seed("notifications", "userId", ALICE_UID, 3);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.notifications.status).toBe("ok");
    expect(result.steps.notifications.count).toBe(3);
    expect(await countDocs("notifications", "userId", ALICE_UID)).toBe(0);
  });

  test("T-GDPR1-local-services: deletes local_services by createdByUid", async () => {
    await seed("local_services", "createdByUid", ALICE_UID, 2);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.local_services.status).toBe("ok");
    expect(result.steps.local_services.count).toBe(2);
    expect(await countDocs("local_services", "createdByUid", ALICE_UID)).toBe(0);
  });

  test("T-GDPR1-borough-feed: deletes borough_feed by partnerUid", async () => {
    await seed("borough_feed", "partnerUid", ALICE_UID, 4);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.borough_feed.status).toBe("ok");
    expect(result.steps.borough_feed.count).toBe(4);
    expect(await countDocs("borough_feed", "partnerUid", ALICE_UID)).toBe(0);
  });

  test("T-GDPR1-feedback: deletes feedback by user_uid (default policy)", async () => {
    await seed("feedback", "user_uid", ALICE_UID, 2);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.feedback.status).toBe("ok");
    expect(result.steps.feedback.count).toBe(2);
    expect(await countDocs("feedback", "user_uid", ALICE_UID)).toBe(0);
  });

  test("T-GDPR1-community-wisdom: deletes community_wisdom by author_uid (explicit delete policy)", async () => {
    // authored_content default is now "anonymise". Use explicit override to test the delete path.
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "delete",
      reports:          "retain",
      feedback:         "delete",
      dry_run_default:  false,
    });
    await seed("community_wisdom", "author_uid", ALICE_UID, 3);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.community_wisdom.status).toBe("ok");
    expect(result.steps.community_wisdom.count).toBe(3);
    expect(await countDocs("community_wisdom", "author_uid", ALICE_UID)).toBe(0);
  });

  test("T-GDPR1-group-messages: deletes group_messages by senderId", async () => {
    await seed("group_messages", "senderId", ALICE_UID, 5);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.group_messages.status).toBe("ok");
    expect(result.steps.group_messages.count).toBe(5);
    expect(await countDocs("group_messages", "senderId", ALICE_UID)).toBe(0);
  });

  test("T-GDPR1-meetups: deletes meetups by createdBy AND organiserId (both passes)", async () => {
    // Seed 2 docs with createdBy (new field) + 3 docs with organiserId (legacy alias).
    await seed("meetups", "createdBy",    ALICE_UID, 2);
    await seed("meetups", "organiserId",  ALICE_UID, 3);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    // Both passes should report ok
    expect(result.steps.meetups_createdBy.status).toBe("ok");
    expect(result.steps.meetups_createdBy.count).toBe(2);
    expect(result.steps.meetups_organiserId.status).toBe("ok");
    expect(result.steps.meetups_organiserId.count).toBe(3);
    // All docs gone
    expect(await countDocs("meetups", "createdBy",   ALICE_UID)).toBe(0);
    expect(await countDocs("meetups", "organiserId", ALICE_UID)).toBe(0);
  });

  test("T-GDPR1-marketplace: deletes marketplace by sellerId", async () => {
    await seed("marketplace", "sellerId", ALICE_UID, 4);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.marketplace.status).toBe("ok");
    expect(result.steps.marketplace.count).toBe(4);
    expect(await countDocs("marketplace", "sellerId", ALICE_UID)).toBe(0);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// SCOPING TEST — second user's data must be untouched
// ══════════════════════════════════════════════════════════════════════════

describe("Scoping", () => {

  test("T-GDPR1-scoping: bob's docs untouched after alice's deletion", async () => {
    // Seed docs for both alice and bob in all 9 Phase 1 collections.
    const collections: Array<[string, string]> = [
      ["subscriptions",   "userId"],
      ["notifications",   "userId"],
      ["local_services",  "createdByUid"],
      ["borough_feed",    "partnerUid"],
      ["feedback",        "user_uid"],
      ["community_wisdom","author_uid"],
      ["group_messages",  "senderId"],
      ["marketplace",     "sellerId"],
    ];
    for (const [col, field] of collections) {
      await seed(col, field, ALICE_UID, 2);
      await seed(col, field, BOB_UID,   2);
    }
    // meetups: seed both field variants for both users
    await seed("meetups", "createdBy",   ALICE_UID, 1);
    await seed("meetups", "organiserId", ALICE_UID, 1);
    await seed("meetups", "createdBy",   BOB_UID,   1);
    await seed("meetups", "organiserId", BOB_UID,   1);

    // Run deletion for alice only.
    // Use explicit authored_content=delete so community_wisdom is deleted in this scoping test.
    // (Default is now "anonymise"; the scoping test is about scoping, not policy defaults.)
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "delete",
      reports:          "retain",
      feedback:         "delete",
      dry_run_default:  false,
    });
    await deleteUserDataHandler({}, authCtx(ALICE_UID));

    // Assert: alice's docs gone, bob's docs intact.
    for (const [col, field] of collections) {
      const aliceCount = await countDocs(col, field, ALICE_UID);
      const bobCount   = await countDocs(col, field, BOB_UID);
      expect(aliceCount).toBe(0);  // alice gone
      expect(bobCount).toBe(2);    // bob untouched
    }
    expect(await countDocs("meetups", "createdBy",   ALICE_UID)).toBe(0);
    expect(await countDocs("meetups", "organiserId", ALICE_UID)).toBe(0);
    expect(await countDocs("meetups", "createdBy",   BOB_UID)).toBe(1);
    expect(await countDocs("meetups", "organiserId", BOB_UID)).toBe(1);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// PAGINATION TEST — >400 docs must be deleted across multiple batches
// ══════════════════════════════════════════════════════════════════════════

describe("Pagination", () => {

  test("T-GDPR1-pagination: 450 subscriptions → all deleted in 2 batches", async () => {
    // Seed 450 docs (> PAGE_SIZE of 400) — requires 2 paginated delete passes.
    await seed("subscriptions", "userId", ALICE_UID, 450);

    const before = await countDocs("subscriptions", "userId", ALICE_UID);
    expect(before).toBe(450); // verify seed

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.subscriptions.status).toBe("ok");
    expect(result.steps.subscriptions.count).toBe(450);
    expect(await countDocs("subscriptions", "userId", ALICE_UID)).toBe(0);
  }, 60000); // allow 60s for 450-doc seed + paginated delete

});

// ══════════════════════════════════════════════════════════════════════════
// CONFIG SWITCH TESTS
// ══════════════════════════════════════════════════════════════════════════

describe("Config switch", () => {

  test("T-GDPR1-config-absent: no _config doc → hardcoded defaults applied", async () => {
    await seed("feedback",          "user_uid",   ALICE_UID, 2);
    await seed("community_wisdom",  "author_uid", ALICE_UID, 2);

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    // Default: feedback=delete, authored_content=anonymise
    expect(result.policy.feedback).toBe("delete");
    expect(result.policy.authored_content).toBe("anonymise");
    // feedback deleted; community_wisdom skipped (authored_content=anonymise, not delete)
    expect(result.steps.feedback.status).toBe("ok");
    expect(result.steps.community_wisdom.status).toBe("skipped");
  });

  test("T-GDPR1-config-present: _config doc present → overrides applied", async () => {
    // Write a config doc with non-default values.
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "anonymise", // override
      reports:          "retain",
      feedback:         "delete",    // same as default
      dry_run_default:  false,
    });

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.policy.authored_content).toBe("anonymise");
    expect(result.policy.feedback).toBe("delete");
    expect(result.policy.reports).toBe("retain");
  });

  test("T-GDPR1-config-authored-content-retain: policy.authored_content=retain → community_wisdom skipped", async () => {
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "retain",
      reports:          "retain",
      feedback:         "delete",
      dry_run_default:  false,
    });
    await seed("community_wisdom", "author_uid", ALICE_UID, 3);

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.community_wisdom.status).toBe("skipped");
    expect(result.steps.community_wisdom.count).toBe(0);
    // Docs must NOT have been deleted.
    expect(await countDocs("community_wisdom", "author_uid", ALICE_UID)).toBe(3);
  });

  test("T-GDPR1-config-feedback-retain: policy.feedback=retain → feedback skipped", async () => {
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "delete",
      reports:          "retain",
      feedback:         "retain",
      dry_run_default:  false,
    });
    await seed("feedback", "user_uid", ALICE_UID, 2);

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.feedback.status).toBe("skipped");
    expect(result.steps.feedback.count).toBe(0);
    expect(await countDocs("feedback", "user_uid", ALICE_UID)).toBe(2);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// DRY RUN TEST
// ══════════════════════════════════════════════════════════════════════════

describe("Dry run", () => {

  test("T-GDPR1-dryrun: dryRun=true reports counts but deletes nothing", async () => {
    await seed("subscriptions", "userId",    ALICE_UID, 5);
    await seed("notifications", "userId",    ALICE_UID, 3);
    await seed("marketplace",   "sellerId",  ALICE_UID, 2);

    const result = await deleteUserDataHandler({ dryRun: true }, authCtx(ALICE_UID));

    expect(result.dryRun).toBe(true);
    expect(result.steps.subscriptions.count).toBe(5);   // counted
    expect(result.steps.notifications.count).toBe(3);   // counted
    expect(result.steps.marketplace.count).toBe(2);     // counted

    // Docs must still be present — nothing deleted.
    expect(await countDocs("subscriptions", "userId",   ALICE_UID)).toBe(5);
    expect(await countDocs("notifications", "userId",   ALICE_UID)).toBe(3);
    expect(await countDocs("marketplace",   "sellerId", ALICE_UID)).toBe(2);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// RETURN SHAPE TEST
// ══════════════════════════════════════════════════════════════════════════

describe("Return shape", () => {

  test("T-GDPR1-return-shape: result has all required top-level fields and steps keys", async () => {
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    // Top-level shape
    expect(typeof result.success).toBe("boolean");
    expect(result.uid).toBe(ALICE_UID);
    expect(typeof result.dryRun).toBe("boolean");
    expect(typeof result.startedAt).toBe("string");
    expect(typeof result.completedAt).toBe("string");
    expect(typeof result.policy).toBe("object");
    expect(typeof result.steps).toBe("object");

    // Policy shape
    expect(["delete", "anonymise", "retain"]).toContain(result.policy.authored_content);
    expect(["delete", "anonymise", "retain"]).toContain(result.policy.feedback);
    expect(["delete", "anonymise", "retain"]).toContain(result.policy.reports);
    expect(typeof result.policy.dry_run_default).toBe("boolean");

    // All Phase 1 step keys present
    const expectedStepKeys = [
      "subscriptions", "notifications", "local_services", "borough_feed",
      "feedback", "community_wisdom", "group_messages",
      "meetups_createdBy", "meetups_organiserId", "marketplace",
    ];
    for (const key of expectedStepKeys) {
      expect(result.steps[key]).toBeDefined();
      expect(["ok", "skipped", "error"]).toContain(result.steps[key].status);
      expect(typeof result.steps[key].count).toBe("number");
    }

    // ISO-8601 timestamps
    expect(() => new Date(result.startedAt)).not.toThrow();
    expect(() => new Date(result.completedAt)).not.toThrow();
    expect(new Date(result.completedAt) >= new Date(result.startedAt)).toBe(true);
  });
});
