/**
 * Huddl — GDPR Deletion CF Phase 2 Tests
 *
 * Tests the Phase 2 additions to deleteUserData:
 *
 *   PHASE 1 CORRECTIONS:
 *     T-GDPR2-polls              — deletes polls by createdByUid (missed in Phase 1)
 *     T-GDPR2-partner-analytics  — deletes partner_analytics/{uid} point-delete (missed in Phase 1)
 *
 *   SUBCOLLECTION SWEEPS:
 *     T-GDPR2-saved-messages     — users/{uid}/saved_messages swept
 *     T-GDPR2-notifprefs         — users/{uid}/notifPrefs/settings point-delete
 *     T-GDPR2-deadlines          — users/{uid}/deadlines swept
 *     T-GDPR2-saved-items        — users/{uid}/saved_items swept
 *     T-GDPR2-blocks-forward     — users/{uid}/blocks swept
 *     T-GDPR2-invitations-recv   — users/{uid}/invitations swept
 *     T-GDPR2-rsvps              — user_rsvps/{uid}/meetups swept
 *
 *   COLLECTION GROUP SWEEPS:
 *     T-GDPR2-blocks-reverse     — collectionGroup(blocks).targetUid == uid deleted
 *     T-GDPR2-endorsements       — collectionGroup(endorsements).documentId == uid deleted
 *     T-GDPR2-invitations-sent-retain  — default policy → sent invitations NOT deleted
 *     T-GDPR2-invitations-sent-delete  — policy.invitations_sent=delete → sent invitations deleted
 *
 *   GROUPS MEMBERSHIP + MEMBER ACTIVITY:
 *     T-GDPR2-groups-membership  — uid removed from memberIds in all 3 groups; group docs survive
 *     T-GDPR2-member-activity    — memberActivity/{uid} deleted in each group
 *     T-GDPR2-capturedGroupIds   — capturedGroupIds in result contains all 3 group IDs
 *
 *   SCOPING:
 *     T-GDPR2-scoping            — bob's subcollection data untouched after alice's deletion
 *
 *   IDEMPOTENCY:
 *     T-GDPR2-idempotency        — running twice produces zero errors on second run
 *
 * Total: 18 tests
 */

import * as admin from "firebase-admin";

// ── Emulator + project ID ──────────────────────────────────────────────────

const PROJECT_ID = "huddl-gdpr-phase2-test";
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8180";
process.env.GCLOUD_PROJECT = PROJECT_ID;

// ── Personas ───────────────────────────────────────────────────────────────

const ALICE_UID = "alice_gdpr2_uid";
const BOB_UID   = "bob_gdpr2_uid";

// Group IDs for membership tests
const GROUP_A = "group_alpha";
const GROUP_B = "group_beta";
const GROUP_C = "group_gamma";
const GROUPS = [GROUP_A, GROUP_B, GROUP_C];

// ── State ──────────────────────────────────────────────────────────────────

let adminApp: admin.app.App;
let db: admin.firestore.Firestore;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let deleteUserDataHandler: (data: any, context: any) => Promise<any>;

// ── Helpers ────────────────────────────────────────────────────────────────

function authCtx(uid: string) { return { auth: { uid, token: {} } }; }

/** Write a document at an exact path. */
async function writeDoc(
  path: string[],
  data: Record<string, unknown>
): Promise<void> {
  let ref: admin.firestore.DocumentReference = db
    .collection(path[0])
    .doc(path[1]);
  for (let i = 2; i < path.length - 1; i += 2) {
    ref = ref.collection(path[i]).doc(path[i + 1]);
  }
  await ref.set(data);
}

/** Check whether a document at an exact path exists. */
async function docExists(path: string[]): Promise<boolean> {
  let ref: admin.firestore.DocumentReference = db
    .collection(path[0])
    .doc(path[1]);
  for (let i = 2; i < path.length - 1; i += 2) {
    ref = ref.collection(path[i]).doc(path[i + 1]);
  }
  const snap = await ref.get();
  return snap.exists;
}

/** Seed `count` docs into a subcollection under a root doc. */
async function seedSubcol(
  rootCol: string,
  rootDocId: string,
  subCol: string,
  count: number,
  extraFields: Record<string, unknown> = {}
): Promise<void> {
  const batch = db.batch();
  for (let i = 0; i < count; i++) {
    const ref = db.collection(rootCol).doc(rootDocId).collection(subCol).doc(`doc_${i}`);
    batch.set(ref, { idx: i, seeded: true, ...extraFields });
  }
  await batch.commit();
}

/** Count docs in a subcollection under a root doc. */
async function countSubcol(
  rootCol: string,
  rootDocId: string,
  subCol: string
): Promise<number> {
  const snap = await db.collection(rootCol).doc(rootDocId).collection(subCol).get();
  return snap.size;
}

/** Seed a group doc with alice as a member. */
async function seedGroup(
  groupId: string,
  memberIds: string[],
  extraMemberIds: string[] = []
): Promise<void> {
  await db.collection("groups").doc(groupId).set({
    name: `Group ${groupId}`,
    memberIds: [...memberIds, ...extraMemberIds],
    memberCount: memberIds.length + extraMemberIds.length,
    seeded: true,
  });
}

/** Get the memberIds array from a group doc. */
async function getMemberIds(groupId: string): Promise<string[]> {
  const snap = await db.collection("groups").doc(groupId).get();
  if (!snap.exists) return [];
  return (snap.data()?.memberIds as string[]) ?? [];
}

const ALL_CLEANUP_COLLECTIONS = [
  "polls", "partner_analytics",
  "users", "user_rsvps", "groups",
  "_config",
];

// Subcollections under users docs are deleted when the user doc is deleted in clearAll.
// We also need to clear collectionGroup sources explicitly.
async function clearAll(): Promise<void> {
  for (const col of ALL_CLEANUP_COLLECTIONS) {
    const snap = await db.collection(col).limit(500).get();
    if (!snap.empty) {
      const batch = db.batch();
      snap.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
    }
  }
  // Subcollections under users/{uid}: Firestore emulator doesn't auto-delete
  // subcollections when parent is deleted. Clear them explicitly.
  for (const uid of [ALICE_UID, BOB_UID]) {
    for (const sub of ["saved_messages", "notifPrefs", "deadlines", "saved_items", "blocks", "invitations"]) {
      const snap = await db.collection("users").doc(uid).collection(sub).limit(500).get();
      if (!snap.empty) {
        const batch = db.batch();
        snap.docs.forEach(d => batch.delete(d.ref));
        await batch.commit();
      }
    }
    // user_rsvps subcollection
    const rsvpSnap = await db.collection("user_rsvps").doc(uid).collection("meetups").limit(500).get();
    if (!rsvpSnap.empty) {
      const batch = db.batch();
      rsvpSnap.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
    }
  }
  // memberActivity subcollections under groups
  for (const gid of GROUPS) {
    const snap = await db.collection("groups").doc(gid).collection("memberActivity").limit(500).get();
    if (!snap.empty) {
      const batch = db.batch();
      snap.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
    }
  }
  // collectionGroup sweeps for data seeded under arbitrary user doc IDs
  // (e.g. invitations under user_recv_1/user_recv_2, blocks under user_x/y/z,
  //  endorsements under listing_001/listing_002 — these survive parent doc deletion
  //  in the emulator and must be explicitly cleared between tests)
  for (const cgName of ["invitations", "blocks", "endorsements"]) {
    const snap = await db.collectionGroup(cgName).limit(500).get();
    if (!snap.empty) {
      const batch = db.batch();
      snap.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
    }
  }
  // local_services docs seeded for endorsements tests
  const lsSnap = await db.collection("local_services").limit(500).get();
  if (!lsSnap.empty) {
    const batch = db.batch();
    lsSnap.docs.forEach(d => batch.delete(d.ref));
    await batch.commit();
  }
}

// ── Setup / Teardown ───────────────────────────────────────────────────────

beforeAll(async () => {
  adminApp = admin.initializeApp({ projectId: PROJECT_ID }, "gdpr-phase2-test");
  db = adminApp.firestore();

  // Extract handler — same approach as Phase 1 tests.
  // The CF module is already cached from Phase 1 require() if tests run together,
  // but since this is a separate test file it will re-require. The GCLOUD_PROJECT
  // env var ensures the CF's default admin app picks up the correct project.
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
// PHASE 1 CORRECTIONS
// ══════════════════════════════════════════════════════════════════════════

describe("Phase 1 corrections", () => {

  test("T-GDPR2-polls: deletes polls by createdByUid (firestore_service.dart:1402)", async () => {
    // Seed 3 polls by alice
    const batch = db.batch();
    for (let i = 0; i < 3; i++) {
      batch.set(db.collection("polls").doc(`poll_alice_${i}`), {
        createdByUid: ALICE_UID, question: `Q${i}`, seeded: true,
      });
    }
    await batch.commit();

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.polls.status).toBe("ok");
    expect(result.steps.polls.count).toBe(3);

    const remaining = await db.collection("polls").where("createdByUid", "==", ALICE_UID).get();
    expect(remaining.size).toBe(0);
  });

  test("T-GDPR2-partner-analytics: deletes partner_analytics/{uid} point-delete (local_services_service.dart:721)", async () => {
    // Seed the analytics doc (doc ID == uid)
    await db.collection("partner_analytics").doc(ALICE_UID).set({
      totalListingViews: 42, lastUpdated: new Date(), seeded: true,
    });

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.partner_analytics.status).toBe("ok");
    expect(result.steps.partner_analytics.count).toBe(1);

    const still = await db.collection("partner_analytics").doc(ALICE_UID).get();
    expect(still.exists).toBe(false);
  });

  test("T-GDPR2-partner-analytics-absent: no analytics doc → count 0, status ok", async () => {
    // No doc seeded — should report 0, no error
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.partner_analytics.status).toBe("ok");
    expect(result.steps.partner_analytics.count).toBe(0);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// SUBCOLLECTION SWEEPS
// ══════════════════════════════════════════════════════════════════════════

describe("Subcollection sweeps", () => {

  test("T-GDPR2-saved-messages: users/{uid}/saved_messages swept (saved_message_service.dart:119)", async () => {
    await seedSubcol("users", ALICE_UID, "saved_messages", 5);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.users_saved_messages.status).toBe("ok");
    expect(result.steps.users_saved_messages.count).toBe(5);
    expect(await countSubcol("users", ALICE_UID, "saved_messages")).toBe(0);
  });

  test("T-GDPR2-notifprefs: users/{uid}/notifPrefs/settings point-delete (user_privacy_prefs_service.dart:82)", async () => {
    // Seed the single settings doc
    await writeDoc(["users", ALICE_UID, "notifPrefs", "settings"], {
      pref_push_enabled: true, _enc: "some_blob", seeded: true,
    });

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.users_notifPrefs_settings.status).toBe("ok");
    expect(result.steps.users_notifPrefs_settings.count).toBe(1);
    expect(await docExists(["users", ALICE_UID, "notifPrefs", "settings"])).toBe(false);
  });

  test("T-GDPR2-notifprefs-absent: no settings doc → count 0, status ok", async () => {
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.users_notifPrefs_settings.status).toBe("ok");
    expect(result.steps.users_notifPrefs_settings.count).toBe(0);
  });

  test("T-GDPR2-deadlines: users/{uid}/deadlines swept (firebase_auth_service.dart:845)", async () => {
    await seedSubcol("users", ALICE_UID, "deadlines", 4);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.users_deadlines.status).toBe("ok");
    expect(result.steps.users_deadlines.count).toBe(4);
    expect(await countSubcol("users", ALICE_UID, "deadlines")).toBe(0);
  });

  test("T-GDPR2-saved-items: users/{uid}/saved_items swept (firebase_auth_service.dart:821)", async () => {
    await seedSubcol("users", ALICE_UID, "saved_items", 3);
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.users_saved_items.status).toBe("ok");
    expect(result.steps.users_saved_items.count).toBe(3);
    expect(await countSubcol("users", ALICE_UID, "saved_items")).toBe(0);
  });

  test("T-GDPR2-blocks-forward: users/{uid}/blocks swept (block_service.dart:91)", async () => {
    await seedSubcol("users", ALICE_UID, "blocks", 2, { targetUid: "some_other_user" });
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.users_blocks_forward.status).toBe("ok");
    expect(result.steps.users_blocks_forward.count).toBe(2);
    expect(await countSubcol("users", ALICE_UID, "blocks")).toBe(0);
  });

  test("T-GDPR2-invitations-recv: users/{uid}/invitations swept (invitation_service.dart:232)", async () => {
    await seedSubcol("users", ALICE_UID, "invitations", 3, { status: "pending" });
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.users_invitations_received.status).toBe("ok");
    expect(result.steps.users_invitations_received.count).toBe(3);
    expect(await countSubcol("users", ALICE_UID, "invitations")).toBe(0);
  });

  test("T-GDPR2-rsvps: user_rsvps/{uid}/meetups swept (firestore_service.dart:1346)", async () => {
    await seedSubcol("user_rsvps", ALICE_UID, "meetups", 4, { going: true });
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.user_rsvps_meetups.status).toBe("ok");
    expect(result.steps.user_rsvps_meetups.count).toBe(4);
    expect(await countSubcol("user_rsvps", ALICE_UID, "meetups")).toBe(0);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// COLLECTION GROUP SWEEPS
// ══════════════════════════════════════════════════════════════════════════

describe("collectionGroup sweeps", () => {

  test("T-GDPR2-blocks-reverse: collectionGroup(blocks).targetUid==uid deleted (block_service.dart:97)", async () => {
    // Seed blocks OTHER users placed on alice (alice is the target, not the owner)
    for (const blockerId of ["user_x", "user_y", "user_z"]) {
      await db.collection("users").doc(blockerId).collection("blocks").doc(ALICE_UID).set({
        targetUid: ALICE_UID,
        blockedAt: new Date(),
        seeded: true,
      });
    }

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.blocks_reverse.status).toBe("ok");
    expect(result.steps.blocks_reverse.count).toBe(3);

    // Verify they're gone
    const remaining = await db.collectionGroup("blocks").where("targetUid", "==", ALICE_UID).get();
    expect(remaining.size).toBe(0);
  });

  test("T-GDPR2-endorsements: collectionGroup(endorsements).uid==uid deleted (local_services_service.dart:180)", async () => {
    // Seed endorsement docs where the doc ID == alice's uid AND field uid == alice's uid
    // (local_services_service.dart:180 writes 'uid': uid on every endorsement doc)
    // NOTE: FieldPath.documentId() equality on collectionGroup requires a full document path
    // (bare uid is an odd-segment path — SDK rejects it). The 'uid' field is the correct query.
    for (const listingId of ["listing_001", "listing_002"]) {
      await db.collection("local_services").doc(listingId).collection("endorsements").doc(ALICE_UID).set({
        uid: ALICE_UID, firstName: "Alice", borough: "Cambridge",
        quote: "Great service!", createdAt: new Date(), seeded: true,
      });
    }

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(result.steps.endorsements_by_uid.status).toBe("ok");
    expect(result.steps.endorsements_by_uid.count).toBe(2);

    // Verify gone — use the 'uid' field (same field the CF query uses)
    const remaining = await db.collectionGroup("endorsements")
      .where("uid", "==", ALICE_UID).get();
    expect(remaining.size).toBe(0);
  });

  test("T-GDPR2-invitations-sent-retain: default policy → sent invitations NOT deleted", async () => {
    // Seed sent invitations: alice is invitedById in other users' invitations subcollections
    await db.collection("users").doc("user_recv_1").collection("invitations").doc("inv_001").set({
      invitedById: ALICE_UID, targetMemberId: "user_recv_1", status: "pending", seeded: true,
    });
    await db.collection("users").doc("user_recv_2").collection("invitations").doc("inv_002").set({
      invitedById: ALICE_UID, targetMemberId: "user_recv_2", status: "pending", seeded: true,
    });

    // Default policy: invitations_sent = retain
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.invitations_sent.status).toBe("skipped");
    expect(result.steps.invitations_sent.count).toBe(0);
    expect(result.policy.invitations_sent).toBe("retain");

    // Docs must still exist
    const remaining = await db.collectionGroup("invitations").where("invitedById", "==", ALICE_UID).get();
    expect(remaining.size).toBe(2);
  });

  test("T-GDPR2-invitations-sent-delete: policy.invitations_sent=delete → sent invitations deleted", async () => {
    // Set policy switch
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "delete",
      reports: "retain",
      feedback: "delete",
      invitations_sent: "delete",
      dry_run_default: false,
    });

    await db.collection("users").doc("user_recv_1").collection("invitations").doc("inv_003").set({
      invitedById: ALICE_UID, targetMemberId: "user_recv_1", status: "pending", seeded: true,
    });

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.invitations_sent.status).toBe("ok");
    expect(result.steps.invitations_sent.count).toBe(1);

    const remaining = await db.collectionGroup("invitations").where("invitedById", "==", ALICE_UID).get();
    expect(remaining.size).toBe(0);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// GROUPS MEMBERSHIP + MEMBER ACTIVITY
// ══════════════════════════════════════════════════════════════════════════

describe("Groups membership and memberActivity", () => {

  test("T-GDPR2-groups-membership: uid removed from memberIds; group docs survive", async () => {
    // Seed 3 groups with alice as member
    for (const gid of GROUPS) {
      await seedGroup(gid, [ALICE_UID, BOB_UID]);
    }

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.groups_membership_remove.status).toBe("ok");
    expect(result.steps.groups_membership_remove.count).toBe(3);

    // Group docs still exist
    for (const gid of GROUPS) {
      expect(await docExists(["groups", gid])).toBe(true);
    }

    // Alice removed from memberIds in all groups; bob still present
    for (const gid of GROUPS) {
      const members = await getMemberIds(gid);
      expect(members).not.toContain(ALICE_UID);
      expect(members).toContain(BOB_UID);
    }
  });

  test("T-GDPR2-member-activity: memberActivity/{uid} deleted per group", async () => {
    // Seed groups + memberActivity docs for alice
    for (const gid of GROUPS) {
      await seedGroup(gid, [ALICE_UID, BOB_UID]);
      // memberActivity for alice
      await db.collection("groups").doc(gid).collection("memberActivity").doc(ALICE_UID).set({
        userId: ALICE_UID, messageCount: 5, joinedAt: new Date(), seeded: true,
      });
      // memberActivity for bob (must survive)
      await db.collection("groups").doc(gid).collection("memberActivity").doc(BOB_UID).set({
        userId: BOB_UID, messageCount: 3, joinedAt: new Date(), seeded: true,
      });
    }

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.member_activity.status).toBe("ok");
    // Count should be 3 (one per group in dryRun=false mode)
    expect(result.steps.member_activity.count).toBe(3);

    // Alice's memberActivity docs gone in all groups
    for (const gid of GROUPS) {
      expect(await docExists(["groups", gid, "memberActivity", ALICE_UID])).toBe(false);
    }

    // Bob's memberActivity docs untouched
    for (const gid of GROUPS) {
      expect(await docExists(["groups", gid, "memberActivity", BOB_UID])).toBe(true);
    }
  });

  test("T-GDPR2-capturedGroupIds: capturedGroupIds in result contains all 3 group IDs", async () => {
    for (const gid of GROUPS) {
      await seedGroup(gid, [ALICE_UID]);
    }

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(Array.isArray(result.capturedGroupIds)).toBe(true);
    expect(result.capturedGroupIds.length).toBe(3);
    for (const gid of GROUPS) {
      expect(result.capturedGroupIds).toContain(gid);
    }
  });

  test("T-GDPR2-member-activity-no-groups: no group membership → member_activity count=0, no error", async () => {
    // Alice is not in any group — capturedGroupIds should be empty
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.groups_membership_remove.status).toBe("ok");
    expect(result.steps.groups_membership_remove.count).toBe(0);
    expect(result.steps.member_activity.status).toBe("ok");
    expect(result.steps.member_activity.count).toBe(0);
    expect(result.capturedGroupIds).toEqual([]);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// SCOPING
// ══════════════════════════════════════════════════════════════════════════

describe("Scoping", () => {

  test("T-GDPR2-scoping: bob's subcollection data untouched after alice's deletion", async () => {
    // Seed data for both alice and bob across Phase 2 subcollections
    for (const uid of [ALICE_UID, BOB_UID]) {
      await seedSubcol("users", uid, "saved_messages", 2);
      await writeDoc(["users", uid, "notifPrefs", "settings"], { seeded: true });
      await seedSubcol("users", uid, "deadlines", 2);
      await seedSubcol("users", uid, "saved_items", 2);
      await seedSubcol("users", uid, "blocks", 1, { targetUid: "some_target" });
      await seedSubcol("users", uid, "invitations", 1, { status: "pending" });
      await seedSubcol("user_rsvps", uid, "meetups", 2);
      await db.collection("partner_analytics").doc(uid).set({ totalListingViews: 10 });
      // polls
      await db.collection("polls").doc(`poll_${uid}`).set({ createdByUid: uid, seeded: true });
    }

    // Groups: both alice and bob are members
    for (const gid of GROUPS) {
      await seedGroup(gid, [ALICE_UID, BOB_UID]);
      await db.collection("groups").doc(gid).collection("memberActivity").doc(ALICE_UID).set({ userId: ALICE_UID });
      await db.collection("groups").doc(gid).collection("memberActivity").doc(BOB_UID).set({ userId: BOB_UID });
    }

    // Run deletion for alice only
    await deleteUserDataHandler({}, authCtx(ALICE_UID));

    // Bob's data must be intact
    expect(await countSubcol("users", BOB_UID, "saved_messages")).toBe(2);
    expect(await docExists(["users", BOB_UID, "notifPrefs", "settings"])).toBe(true);
    expect(await countSubcol("users", BOB_UID, "deadlines")).toBe(2);
    expect(await countSubcol("users", BOB_UID, "saved_items")).toBe(2);
    expect(await countSubcol("users", BOB_UID, "blocks")).toBe(1);
    expect(await countSubcol("users", BOB_UID, "invitations")).toBe(1);
    expect(await countSubcol("user_rsvps", BOB_UID, "meetups")).toBe(2);
    expect((await db.collection("partner_analytics").doc(BOB_UID).get()).exists).toBe(true);
    expect((await db.collection("polls").doc(`poll_${BOB_UID}`).get()).exists).toBe(true);

    // Bob still in groups
    for (const gid of GROUPS) {
      const members = await getMemberIds(gid);
      expect(members).toContain(BOB_UID);
      expect(await docExists(["groups", gid, "memberActivity", BOB_UID])).toBe(true);
    }

    // Alice's data gone
    expect(await countSubcol("users", ALICE_UID, "saved_messages")).toBe(0);
    expect(await docExists(["users", ALICE_UID, "notifPrefs", "settings"])).toBe(false);
    expect((await db.collection("partner_analytics").doc(ALICE_UID).get()).exists).toBe(false);
    expect((await db.collection("polls").doc(`poll_${ALICE_UID}`).get()).exists).toBe(false);
    for (const gid of GROUPS) {
      const members = await getMemberIds(gid);
      expect(members).not.toContain(ALICE_UID);
      expect(await docExists(["groups", gid, "memberActivity", ALICE_UID])).toBe(false);
    }
  });
});

// ══════════════════════════════════════════════════════════════════════════
// IDEMPOTENCY
// ══════════════════════════════════════════════════════════════════════════

describe("Idempotency", () => {

  test("T-GDPR2-idempotency: second run produces zero errors (all steps ok or skipped)", async () => {
    // Seed some data for alice
    await seedSubcol("users", ALICE_UID, "saved_messages", 3);
    for (const gid of GROUPS) {
      await seedGroup(gid, [ALICE_UID]);
      await db.collection("groups").doc(gid).collection("memberActivity").doc(ALICE_UID).set({
        userId: ALICE_UID, messageCount: 1, seeded: true,
      });
    }

    // First run — deletes everything
    const first = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(first.success).toBe(true);

    // Second run — everything already gone; all steps should be ok (count=0) or skipped
    const second = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    const errorSteps = Object.entries(second.steps)
      .filter(([, s]) => (s as { status: string }).status === "error");
    expect(errorSteps).toHaveLength(0);
    expect(second.success).toBe(true);
  });
});
