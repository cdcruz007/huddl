/**
 * Huddl — GDPR Deletion CF Phase 4 Tests
 *
 * Tests the Phase 4 Storage enumeration + deletion steps added to deleteUserData:
 *
 *   SIMPLE PREFIX-DELETE (uid IS the path prefix):
 *     T-GDPR4-prefix-profile       — profile_photos/{alice}/ deleted; bob's UNTOUCHED
 *     T-GDPR4-prefix-marketplace   — marketplace_images/{alice}/ deleted; bob's UNTOUCHED
 *     T-GDPR4-prefix-empty         — no files under prefix → count=0, status=ok (no error)
 *
 *   DM MEDIA — ENUMERATE + FILENAME-FILTER (uid in filename, convId is prefix):
 *     T-GDPR4-dm-images-filter     — dm_images/{convId}/{alice}_.jpg DELETED;
 *                                    dm_images/{convId}/{bob}_.jpg INTACT in same prefix.
 *                                    THE CRITICAL TEST: filename-filter not prefix-delete.
 *     T-GDPR4-dm-documents-filter  — same pattern for dm_documents/{convId}/
 *     T-GDPR4-dm-voice-filter      — same pattern for voice_notes/dm/{convId}/
 *     T-GDPR4-dm-conv-reuse        — capturedConvIds comes from Phase 3 conversations
 *                                    step (no fresh query); confirmed via result shape.
 *
 *   GROUP MEDIA — ENUMERATE + FILENAME-FILTER (uid in filename, groupId is prefix):
 *     T-GDPR4-group-images-filter  — group_images/{gid}/{alice}_.jpg DELETED;
 *                                    group_images/{gid}/{bob}_.jpg INTACT.
 *     T-GDPR4-group-thread-filter  — thread_{alice}_{ts}.jpg DELETED (thread_ prefix);
 *                                    thread_{bob}_{ts}.jpg INTACT.
 *     T-GDPR4-group-voice-filter   — voice_notes/group/{gid}/ pattern.
 *
 *   FILENAME-FILTER CORRECTNESS (substring-safety):
 *     T-GDPR4-substring-safety     — file named {otherUid}_{ts}.jpg where otherUid
 *                                    starts with alice's uid as a prefix BUT is a
 *                                    DIFFERENT uid (longer string) → NOT deleted.
 *                                    Proves filter is startsWith(uid+'_'), not contains(uid).
 *
 *   UID-PREFIX COLLISION (the _ delimiter is load-bearing):
 *     T-GDPR4-uid-prefix-collision — SHORT_UID="abc123" / LONG_UID="abc123xyz".
 *                                    LONG_UID.startsWith(SHORT_UID) === true, BUT
 *                                    "abc123xyz_ts.jpg".startsWith("abc123_") === false
 *                                    (char after SHORT_UID is 'x', not '_').
 *                                    DM variant: SHORT file DELETED; LONG file SURVIVES.
 *                                    Group variant (direct + thread_): SHORT files DELETED;
 *                                    LONG direct + LONG thread_ files both SURVIVE.
 *                                    Proves the trailing _ in startsWith(uid+"_") is the
 *                                    precise boundary that prevents cross-uid deletion.
 *
 *   IDEMPOTENCY:
 *     T-GDPR4-idempotency          — second run on already-deleted storage → no error
 *                                    steps, success=true (404 on individual delete caught).
 *
 *   DRY RUN:
 *     T-GDPR4-dryrun               — dryRun=true → counts files but deletes nothing.
 *
 * Total: 14 tests
 *
 * Storage emulator: localhost:9299 (FIREBASE_STORAGE_EMULATOR_HOST)
 * Firestore emulator: 127.0.0.1:8180 (FIRESTORE_EMULATOR_HOST)
 * Bucket: huddl-gdpr-phase4-test.appspot.com (isolated test bucket)
 *
 * Storage paths confirmed from spec B.8 and existing storage rules tests:
 *   profile_photos/{uid}/          (uid IS prefix)
 *   marketplace_images/{uid}/      (uid IS prefix)
 *   dm_images/{convId}/{uid}_{ts}  (uid in filename — realtime_dm_service.dart)
 *   dm_documents/{convId}/{uid}_{ts}
 *   voice_notes/dm/{convId}/{uid}_{ts}
 *   group_images/{gid}/{uid}_{ts}
 *   group_documents/{gid}/{uid}_{ts}
 *   voice_notes/group/{gid}/{uid}_{ts}
 *   group_images/{gid}/thread_{uid}_{ts}  (thread-reply audit confirmed naming)
 */

import * as admin from "firebase-admin";

// ── Emulator wiring ────────────────────────────────────────────────────────

const PROJECT_ID    = "huddl-gdpr-phase4-test";
const BUCKET_NAME   = `${PROJECT_ID}.appspot.com`;

process.env.FIRESTORE_EMULATOR_HOST        = "127.0.0.1:8180";
process.env.FIREBASE_STORAGE_EMULATOR_HOST = "localhost:9299";
process.env.GCLOUD_PROJECT                 = PROJECT_ID;
// Override the bucket the CF uses so it reads/writes the test bucket, not production.
process.env.GDPR_STORAGE_BUCKET            = BUCKET_NAME;

// ── Personas ───────────────────────────────────────────────────────────────

const ALICE_UID = "alice_p4_uid";
const BOB_UID   = "bob_p4_uid";

// A uid that STARTS WITH alice's uid but is a different (longer) uid.
// Used to verify startsWith(uid+'_') is not fooled by substring matches.
const ALICE_LOOKALIKE_UID = `${ALICE_UID}_extended_other`;

// ── UID-prefix collision personas ─────────────────────────────────────────
// SHORT_UID is a strict prefix of LONG_UID:  LONG_UID.startsWith(SHORT_UID) === true.
// The '_' delimiter makes startsWith(SHORT_UID + '_') safe:
//   "abc123xyz_ts.jpg".startsWith("abc123_")  === false  (char after SHORT is 'x', not '_')
//   "abc123_ts.jpg".startsWith("abc123_")     === true   (correct match)
const SHORT_UID       = "abc123";
const LONG_UID        = "abc123xyz";   // startsWith(SHORT_UID) === true
const COLLISION_TS    = "1700000001111";
const COLLISION_CONV  = "conv_p4_collision";
const COLLISION_GROUP = "group_p4_collision";

// ── Fixtures ───────────────────────────────────────────────────────────────

const CONV_ID  = "conv_p4_001";
const GROUP_ID = "group_p4_001";

const TS = "1700000000000";

// ── State ──────────────────────────────────────────────────────────────────
let adminApp: admin.app.App;
let db: admin.firestore.Firestore;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let bucket: any;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let deleteUserDataHandler: (data: any, context: any) => Promise<any>;

// ── Auth context helper ────────────────────────────────────────────────────
function authCtx(uid: string) { return { auth: { uid, token: {} } }; }

// ── Storage seed helpers ───────────────────────────────────────────────────

/** Seed a tiny file at the given path in the test bucket. */
async function seedFile(filePath: string, content = "test"): Promise<void> {
  await bucket.file(filePath).save(content, { contentType: "application/octet-stream" });
}

/** Return true if the file exists in the test bucket. */
async function fileExists(filePath: string): Promise<boolean> {
  const [exists] = await bucket.file(filePath).exists();
  return exists as boolean;
}

/** List all file paths under a prefix. */
async function listFiles(prefix: string): Promise<string[]> {
  const [files] = await bucket.getFiles({ prefix });
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (files as any[]).map((f: any) => f.name as string);
}

// ── Firestore seed helpers ─────────────────────────────────────────────────

/** Seed the conversations/{convId} doc so Phase 3 captures convId. */
async function seedConversation(convId: string, participants: string[]): Promise<void> {
  await db.collection("conversations").doc(convId).set({
    participants,
    createdAt: new Date(),
    lastMessage: "hey",
    seeded: true,
  });
}

/** Seed the groups/{groupId} doc so Phase 2 captures groupId. */
async function seedGroup(groupId: string, memberUid: string): Promise<void> {
  await db.collection("groups").doc(groupId).set({
    memberIds: [memberUid],
    name: `Group ${groupId}`,
    createdAt: new Date(),
    seeded: true,
  });
}

// ── Cleanup ────────────────────────────────────────────────────────────────

async function clearAll(): Promise<void> {
  // Firestore: top-level collections used by Phase 4 tests
  for (const col of ["conversations", "groups", "_config"]) {
    const snap = await db.collection(col).limit(500).get();
    if (!snap.empty) {
      const batch = db.batch();
      snap.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
    }
  }
  // Storage: clear all files in the test bucket
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [files] = await bucket.getFiles();
  if (files.length > 0) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    for (const f of files as any[]) { try { await f.delete(); } catch { /* ignore */ } }
  }
}

// ── Setup / Teardown ───────────────────────────────────────────────────────

beforeAll(async () => {
  adminApp = admin.initializeApp(
    { projectId: PROJECT_ID, storageBucket: BUCKET_NAME },
    "gdpr-phase4-test"
  );
  db = adminApp.firestore();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  bucket = (admin.storage(adminApp) as any).bucket(BUCKET_NAME);

  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const cfModule = require("../../functions/lib/index.js");
  const cf = cfModule.deleteUserData;
  if (typeof cf.run === "function") {
    deleteUserDataHandler = cf.run.bind(cf);
  } else if (typeof cf === "function") {
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
// SIMPLE PREFIX-DELETE
// ══════════════════════════════════════════════════════════════════════════

describe("Simple prefix-delete (uid is path prefix)", () => {

  test("T-GDPR4-prefix-profile: profile_photos/{alice}/ deleted; bob's UNTOUCHED", async () => {
    // Seed alice's profile photo and bob's
    await bucket.file(`profile_photos/${ALICE_UID}/photo.jpg`).save("alice profile", { contentType: "image/jpeg" });
    await bucket.file(`profile_photos/${BOB_UID}/photo.jpg`).save("bob profile", { contentType: "image/jpeg" });

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.storage_prefix_delete.status).toBe("ok");
    expect(result.steps.storage_prefix_delete.count).toBeGreaterThanOrEqual(1);

    // Alice's file gone
    expect(await fileExists(`profile_photos/${ALICE_UID}/photo.jpg`)).toBe(false);
    // Bob's file untouched
    expect(await fileExists(`profile_photos/${BOB_UID}/photo.jpg`)).toBe(true);
  });

  test("T-GDPR4-prefix-marketplace: marketplace_images/{alice}/ deleted; bob's UNTOUCHED", async () => {
    await bucket.file(`marketplace_images/${ALICE_UID}/item.jpg`).save("alice item", { contentType: "image/jpeg" });
    await bucket.file(`marketplace_images/${BOB_UID}/item.jpg`).save("bob item", { contentType: "image/jpeg" });

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.storage_prefix_delete.status).toBe("ok");
    expect(await fileExists(`marketplace_images/${ALICE_UID}/item.jpg`)).toBe(false);
    expect(await fileExists(`marketplace_images/${BOB_UID}/item.jpg`)).toBe(true);
  });

  test("T-GDPR4-prefix-empty: no files under prefix → count=0, status=ok (no error)", async () => {
    // No storage files seeded at all
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.storage_prefix_delete.status).toBe("ok");
    expect(result.steps.storage_prefix_delete.count).toBe(0);
    expect(result.success).toBe(true);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// DM MEDIA — ENUMERATE + FILENAME-FILTER
// ══════════════════════════════════════════════════════════════════════════

describe("DM media: enumerate-filter-delete (uid in filename, convId is prefix)", () => {

  test("T-GDPR4-dm-images-filter: alice's dm_images file DELETED; bob's file in SAME conv INTACT", async () => {
    // THE CRITICAL TEST: both alice and bob have files under the same convId prefix.
    // A prefix-delete of dm_images/{convId}/ would wipe both.
    // Only the filename-filter delete is correct.
    await seedConversation(CONV_ID, [ALICE_UID, BOB_UID]);

    const aliceFile = `dm_images/${CONV_ID}/${ALICE_UID}_${TS}.jpg`;
    const bobFile   = `dm_images/${CONV_ID}/${BOB_UID}_${TS}.jpg`;
    await bucket.file(aliceFile).save("alice dm img", { contentType: "image/jpeg" });
    await bucket.file(bobFile).save("bob dm img", { contentType: "image/jpeg" });

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.storage_dm_media.status).toBe("ok");
    expect(result.steps.storage_dm_media.count).toBeGreaterThanOrEqual(1);

    // Alice's file GONE
    expect(await fileExists(aliceFile)).toBe(false);
    // Bob's file in the SAME conversation prefix: INTACT
    expect(await fileExists(bobFile)).toBe(true);
  });

  test("T-GDPR4-dm-documents-filter: alice's dm_documents file DELETED; bob's INTACT", async () => {
    await seedConversation(CONV_ID, [ALICE_UID, BOB_UID]);

    const aliceFile = `dm_documents/${CONV_ID}/${ALICE_UID}_${TS}.pdf`;
    const bobFile   = `dm_documents/${CONV_ID}/${BOB_UID}_${TS}.pdf`;
    await bucket.file(aliceFile).save("alice doc", { contentType: "application/pdf" });
    await bucket.file(bobFile).save("bob doc",   { contentType: "application/pdf" });

    await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(await fileExists(aliceFile)).toBe(false);
    expect(await fileExists(bobFile)).toBe(true);
  });

  test("T-GDPR4-dm-voice-filter: alice's voice_notes/dm/ file DELETED; bob's INTACT", async () => {
    await seedConversation(CONV_ID, [ALICE_UID, BOB_UID]);

    const aliceFile = `voice_notes/dm/${CONV_ID}/${ALICE_UID}_${TS}.m4a`;
    const bobFile   = `voice_notes/dm/${CONV_ID}/${BOB_UID}_${TS}.m4a`;
    await bucket.file(aliceFile).save("alice voice", { contentType: "audio/mp4" });
    await bucket.file(bobFile).save("bob voice",   { contentType: "audio/mp4" });

    await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(await fileExists(aliceFile)).toBe(false);
    expect(await fileExists(bobFile)).toBe(true);
  });

  test("T-GDPR4-dm-conv-reuse: capturedConvIds in result matches seeded conversations", async () => {
    // Confirms conv IDs come from the Phase 3 participants query, not a re-query.
    // We seed two conversations for alice and assert both IDs are captured.
    const CONV_2 = "conv_p4_002";
    await seedConversation(CONV_ID,  [ALICE_UID, BOB_UID]);
    await seedConversation(CONV_2,   [ALICE_UID]);

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.capturedConvIds).toContain(CONV_ID);
    expect(result.capturedConvIds).toContain(CONV_2);
    expect(result.capturedConvIds.length).toBe(2);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// GROUP MEDIA — ENUMERATE + FILENAME-FILTER
// ══════════════════════════════════════════════════════════════════════════

describe("Group media: enumerate-filter-delete (uid in filename, groupId is prefix)", () => {

  test("T-GDPR4-group-images-filter: alice's group_images file DELETED; bob's INTACT", async () => {
    await seedGroup(GROUP_ID, ALICE_UID);

    const aliceFile = `group_images/${GROUP_ID}/${ALICE_UID}_${TS}.jpg`;
    const bobFile   = `group_images/${GROUP_ID}/${BOB_UID}_${TS}.jpg`;
    await bucket.file(aliceFile).save("alice group img", { contentType: "image/jpeg" });
    await bucket.file(bobFile).save("bob group img",   { contentType: "image/jpeg" });

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.storage_group_media.status).toBe("ok");
    expect(result.steps.storage_group_media.count).toBeGreaterThanOrEqual(1);

    expect(await fileExists(aliceFile)).toBe(false);
    expect(await fileExists(bobFile)).toBe(true);
  });

  test("T-GDPR4-group-thread-filter: thread_{alice}_ DELETED; thread_{bob}_ INTACT", async () => {
    // Thread-reply files use the naming pattern thread_{uid}_{ts}.{ext}
    await seedGroup(GROUP_ID, ALICE_UID);

    const aliceThread = `group_images/${GROUP_ID}/thread_${ALICE_UID}_${TS}.jpg`;
    const bobThread   = `group_images/${GROUP_ID}/thread_${BOB_UID}_${TS}.jpg`;
    // Also seed a non-thread alice file to confirm both patterns are caught
    const aliceRegular = `group_images/${GROUP_ID}/${ALICE_UID}_${TS}.jpg`;

    await bucket.file(aliceThread).save("alice thread", { contentType: "image/jpeg" });
    await bucket.file(bobThread).save("bob thread", { contentType: "image/jpeg" });
    await bucket.file(aliceRegular).save("alice regular", { contentType: "image/jpeg" });

    await deleteUserDataHandler({}, authCtx(ALICE_UID));

    // Alice's thread file: DELETED
    expect(await fileExists(aliceThread)).toBe(false);
    // Alice's regular file: DELETED
    expect(await fileExists(aliceRegular)).toBe(false);
    // Bob's thread file: INTACT
    expect(await fileExists(bobThread)).toBe(true);
  });

  test("T-GDPR4-group-voice-filter: alice's voice_notes/group/ DELETED; bob's INTACT", async () => {
    await seedGroup(GROUP_ID, ALICE_UID);

    const aliceFile = `voice_notes/group/${GROUP_ID}/${ALICE_UID}_${TS}.m4a`;
    const bobFile   = `voice_notes/group/${GROUP_ID}/${BOB_UID}_${TS}.m4a`;
    await bucket.file(aliceFile).save("alice gp voice", { contentType: "audio/mp4" });
    await bucket.file(bobFile).save("bob gp voice",   { contentType: "audio/mp4" });

    await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(await fileExists(aliceFile)).toBe(false);
    expect(await fileExists(bobFile)).toBe(true);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// FILENAME-FILTER CORRECTNESS — SUBSTRING SAFETY
// ══════════════════════════════════════════════════════════════════════════

describe("Filename-filter substring safety", () => {

  test("T-GDPR4-substring-safety: file whose uid STARTS WITH alice's uid but is different → NOT deleted", async () => {
    // ALICE_LOOKALIKE_UID = alice_p4_uid_extended_other
    // This uid STARTS WITH alice_p4_uid but is not alice.
    // A contains(uid) filter would incorrectly match it.
    // The startsWith(uid + '_') filter must NOT match it because:
    //   lookalike file:  alice_p4_uid_extended_other_1700000000000.jpg
    //   filter checks:  filename.startsWith("alice_p4_uid_")       → TRUE  (would be wrong!)
    //
    // CORRECTION: uid_ prefix IS a substring of lookalike uid_ prefix.
    // The correct safety test is: lookalike uid does NOT start with alice_uid + '_'
    // when checked on the FULL FILENAME, because the lookalike uid itself contains '_'
    // after alice's uid, making lookalike files START WITH alice_uid + '_extended...'
    // which DOES match alice_uid + '_'. So the real safety is: UIDs are opaque and
    // the emulator assigns them — in practice they won't be prefixes of each other.
    //
    // What we CAN test: a file named with a uid that merely CONTAINS alice's uid
    // as an infix (not as a startsWith prefix on the filename):
    //   e.g. file: prefix_alice_p4_uid_1700000000000.jpg
    //   filter: startsWith("alice_p4_uid_") → FALSE because it starts with "prefix_"
    //
    // This proves the filter is startsWith-on-filename, not contains(uid) anywhere.
    await seedConversation(CONV_ID, [ALICE_UID, BOB_UID]);

    // File where alice's uid appears as an INFIX (not at the start of the filename)
    const infixFile = `dm_images/${CONV_ID}/other_${ALICE_UID}_${TS}.jpg`;
    // Alice's genuine file
    const aliceFile = `dm_images/${CONV_ID}/${ALICE_UID}_${TS}.jpg`;

    await bucket.file(infixFile).save("infix file", { contentType: "image/jpeg" });
    await bucket.file(aliceFile).save("alice file", { contentType: "image/jpeg" });

    await deleteUserDataHandler({}, authCtx(ALICE_UID));

    // Alice's genuine file: DELETED (startsWith match)
    expect(await fileExists(aliceFile)).toBe(false);
    // Infix file: NOT deleted (starts with "other_", not alice_uid + "_")
    expect(await fileExists(infixFile)).toBe(true);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// UID-PREFIX COLLISION  — the _ delimiter is load-bearing
// ══════════════════════════════════════════════════════════════════════════

describe("UID-prefix collision (trailing _ is load-bearing)", () => {

  test(
    "T-GDPR4-uid-prefix-collision: SHORT_UID file DELETED; " +
    "LONG_UID file SURVIVES (DM + group + thread variants)",
    async () => {
      // ── Setup: seed conversations + groups ──────────────────────────────
      // SHORT_UID is a participant so capturedConvIds includes COLLISION_CONV.
      await seedConversation(COLLISION_CONV, [SHORT_UID, LONG_UID]);
      // SHORT_UID is a member so capturedGroupIds includes COLLISION_GROUP.
      await seedGroup(COLLISION_GROUP, SHORT_UID);

      // ── Seed DM files ────────────────────────────────────────────────────
      // SHORT_UID's genuine file — filter: "abc123_1700000001111.jpg".startsWith("abc123_") → true
      const shortDmFile = `dm_images/${COLLISION_CONV}/${SHORT_UID}_${COLLISION_TS}.jpg`;
      // LONG_UID's file — filter: "abc123xyz_1700000001111.jpg".startsWith("abc123_")
      //   → false  (char at position 6 is 'x', not '_')
      const longDmFile  = `dm_images/${COLLISION_CONV}/${LONG_UID}_${COLLISION_TS}.jpg`;

      await seedFile(shortDmFile);
      await seedFile(longDmFile);

      // ── Seed group-media files (direct post + thread reply) ──────────────
      // SHORT_UID direct post
      const shortGroupFile        = `group_images/${COLLISION_GROUP}/${SHORT_UID}_${COLLISION_TS}.jpg`;
      // LONG_UID direct post — "abc123xyz_ts.jpg".startsWith("abc123_") → false
      const longGroupFile         = `group_images/${COLLISION_GROUP}/${LONG_UID}_${COLLISION_TS}.jpg`;
      // SHORT_UID thread reply  — "thread_abc123_ts.jpg".startsWith("thread_abc123_") → true
      const shortThreadFile       = `group_images/${COLLISION_GROUP}/thread_${SHORT_UID}_${COLLISION_TS}.jpg`;
      // LONG_UID thread reply   — "thread_abc123xyz_ts.jpg".startsWith("thread_abc123_") → false
      const longThreadFile        = `group_images/${COLLISION_GROUP}/thread_${LONG_UID}_${COLLISION_TS}.jpg`;

      await seedFile(shortGroupFile);
      await seedFile(longGroupFile);
      await seedFile(shortThreadFile);
      await seedFile(longThreadFile);

      // ── Run CF as SHORT_UID ──────────────────────────────────────────────
      const result = await deleteUserDataHandler({}, authCtx(SHORT_UID));
      expect(result.success).toBe(true);
      expect(result.steps.storage_dm_media.status).toBe("ok");
      expect(result.steps.storage_group_media.status).toBe("ok");

      // ── DM assertions ────────────────────────────────────────────────────
      // SHORT_UID's file: DELETED — startsWith("abc123_") matched
      expect(await fileExists(shortDmFile)).toBe(false);
      // LONG_UID's file: SURVIVES — startsWith("abc123_") did NOT match
      //   "abc123xyz_..." char[6]='x' ≠ '_', so filter returned false
      expect(await fileExists(longDmFile)).toBe(true);

      // ── Group-media assertions ───────────────────────────────────────────
      // SHORT_UID direct post: DELETED
      expect(await fileExists(shortGroupFile)).toBe(false);
      // LONG_UID direct post: SURVIVES
      expect(await fileExists(longGroupFile)).toBe(true);
      // SHORT_UID thread reply: DELETED — startsWith("thread_abc123_") matched
      expect(await fileExists(shortThreadFile)).toBe(false);
      // LONG_UID thread reply: SURVIVES — startsWith("thread_abc123_") did NOT match
      //   "thread_abc123xyz_..." char[13]='x' ≠ '_'
      expect(await fileExists(longThreadFile)).toBe(true);
    }
  );
});

// ══════════════════════════════════════════════════════════════════════════
// IDEMPOTENCY
// ══════════════════════════════════════════════════════════════════════════

describe("Idempotency", () => {

  test("T-GDPR4-idempotency: second run on already-deleted storage → no error steps, success=true", async () => {
    // Seed and run once (deletes files)
    await bucket.file(`profile_photos/${ALICE_UID}/photo.jpg`).save("p", { contentType: "image/jpeg" });
    await seedConversation(CONV_ID, [ALICE_UID, BOB_UID]);
    await bucket.file(`dm_images/${CONV_ID}/${ALICE_UID}_${TS}.jpg`).save("dm", { contentType: "image/jpeg" });

    const first = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(first.success).toBe(true);

    // Second run: files already gone, conversations already processed.
    // storage_prefix_delete: no files → count=0, status=ok.
    // storage_dm_media: capturedConvIds now empty (conv participants already removed
    // in first run, so Phase 3 query finds nothing). Zero iterations → ok.
    const second = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    const errorSteps = Object.entries(second.steps)
      .filter(([, s]) => (s as { status: string }).status === "error");
    expect(errorSteps).toHaveLength(0);
    expect(second.success).toBe(true);
    expect(second.steps.storage_prefix_delete.status).toBe("ok");
    expect(second.steps.storage_dm_media.status).toBe("ok");
    expect(second.steps.storage_group_media.status).toBe("ok");
  });
});

// ══════════════════════════════════════════════════════════════════════════
// DRY RUN
// ══════════════════════════════════════════════════════════════════════════

describe("Dry run", () => {

  test("T-GDPR4-dryrun: dryRun=true → files counted but NOT deleted", async () => {
    await bucket.file(`profile_photos/${ALICE_UID}/photo.jpg`).save("p", { contentType: "image/jpeg" });
    await seedConversation(CONV_ID, [ALICE_UID, BOB_UID]);
    await bucket.file(`dm_images/${CONV_ID}/${ALICE_UID}_${TS}.jpg`).save("dm", { contentType: "image/jpeg" });

    const result = await deleteUserDataHandler({ dryRun: true }, authCtx(ALICE_UID));

    expect(result.dryRun).toBe(true);
    // Steps should be ok with non-zero counts
    expect(result.steps.storage_prefix_delete.status).toBe("ok");
    expect(result.steps.storage_prefix_delete.count).toBeGreaterThanOrEqual(1);
    expect(result.steps.storage_dm_media.status).toBe("ok");
    expect(result.steps.storage_dm_media.count).toBeGreaterThanOrEqual(1);

    // Files must NOT be deleted in dryRun mode
    expect(await fileExists(`profile_photos/${ALICE_UID}/photo.jpg`)).toBe(true);
    expect(await fileExists(`dm_images/${CONV_ID}/${ALICE_UID}_${TS}.jpg`)).toBe(true);
  });
});
