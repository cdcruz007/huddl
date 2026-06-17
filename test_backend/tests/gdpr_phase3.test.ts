/**
 * Huddl — GDPR Deletion CF Phase 3 Tests
 *
 * Tests the Phase 3 anonymise operations added to deleteUserData:
 *
 *   CONVERSATIONS + MESSAGES (spec B.3):
 *     T-GDPR3-conv-two-participant   — alice's messages scrubbed; bob's messages
 *                                      COMPLETELY UNCHANGED (field-by-field);
 *                                      participants no longer contains alice;
 *                                      conversation doc still EXISTS.
 *     T-GDPR3-conv-sole-participant  — alice is only participant; conversation
 *                                      doc DELETED after empty-participants check.
 *     T-GDPR3-conv-delete-branch-not-over-eager — sole-participant conv deleted AND
 *                                      two-participant conv kept in the SAME run;
 *                                      proves delete branch fires only when empty.
 *     T-GDPR3-conv-scoping-carol     — carol's conversation (alice not a
 *                                      participant) entirely untouched.
 *
 *   GROUP_MESSAGES (spec B.4 — behind authored_content switch):
 *     T-GDPR3-gm-default-anonymise   — NO _config doc; default (anonymise) applies;
 *                                      docs RETAINED, identity scrubbed. Regression
 *                                      guard for the default-is-anonymise invariant.
 *     T-GDPR3-gm-anonymise           — explicit anonymise override (_config doc set):
 *                                      docs RETAINED, identity scrubbed;
 *                                      bob's group messages UNTOUCHED (field-by-field).
 *     T-GDPR3-gm-delete              — EXPLICIT delete override (_config doc set):
 *                                      alice's group messages DELETED; bob's untouched.
 *     T-GDPR3-gm-retain              — policy.authored_content=retain: alice's
 *                                      group messages skipped entirely.
 *
 *   SENTINEL / NULL CHECKS:
 *     T-GDPR3-null-senderid          — explicitly asserts senderId IS null (not
 *                                      just absent) on anonymised messages — G.1.
 *
 *   IDEMPOTENCY:
 *     T-GDPR3-idempotency            — second run on already-anonymised data
 *                                      produces no error steps, success=true.
 *
 * Total: 10 tests
 *
 * Schema confirmed from source:
 *   conversations/{id}
 *     participants: string[]           (realtime_dm_service.dart:120)
 *     participantNames: {uid: name}    (realtime_dm_service.dart:121)
 *     participantAvatars: {uid: url}   (realtime_dm_service.dart:122)
 *
 *   conversations/{id}/messages/{msgId}
 *     senderId: String                 (realtime_dm_service.dart:213)
 *     senderName: String               (realtime_dm_service.dart:214)
 *     senderAvatar: String             (realtime_dm_service.dart:215)
 *     message: String                  (realtime_dm_service.dart:216)
 *
 *   group_messages/{id}
 *     senderId: String                 (firestore_service.dart:362)
 *     senderName: String               (firestore_service.dart:363)
 *     senderAvatar: String             (firestore_service.dart:364)  ← NOT senderPhotoUrl
 *     message: String                  (firestore_service.dart:365)
 */

import * as admin from "firebase-admin";

// ── Emulator + project ID ──────────────────────────────────────────────────

const PROJECT_ID = "huddl-gdpr-phase3-test";
process.env.FIRESTORE_EMULATOR_HOST        = "127.0.0.1:8180";
process.env.GCLOUD_PROJECT                 = PROJECT_ID;
// Storage emulator: route Phase 4 storage steps to the emulator, not production.
process.env.FIREBASE_STORAGE_EMULATOR_HOST = "localhost:9299";
process.env.GDPR_STORAGE_BUCKET            = `${PROJECT_ID}.appspot.com`;

// ── Sentinel — must match the constant in index.ts ─────────────────────────
const DELETED_CONTENT_SENTINEL = "[deleted]";

// ── Personas ───────────────────────────────────────────────────────────────
const ALICE_UID  = "alice_gdpr3_uid";
const BOB_UID    = "bob_gdpr3_uid";
const CAROL_UID  = "carol_gdpr3_uid";  // third user; never deleted

// ── State ──────────────────────────────────────────────────────────────────
let adminApp: admin.app.App;
let db: admin.firestore.Firestore;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let deleteUserDataHandler: (data: any, context: any) => Promise<any>;

// ── Auth context helper ────────────────────────────────────────────────────
function authCtx(uid: string) { return { auth: { uid, token: {} } }; }

// ── Seed helpers ───────────────────────────────────────────────────────────

/** Seed a conversation doc between alice and bob (or a sole participant). */
async function seedConversation(
  convId: string,
  participantUids: string[]
): Promise<void> {
  const participantNames: Record<string, string> = {};
  const participantAvatars: Record<string, string> = {};
  for (const uid of participantUids) {
    participantNames[uid]   = `Name_${uid}`;
    participantAvatars[uid] = `https://example.com/avatar_${uid}.jpg`;
  }
  await db.collection("conversations").doc(convId).set({
    participants:       participantUids,
    participantNames,
    participantAvatars,
    lastMessage:        "hey",
    lastSenderId:       participantUids[0],
    lastSenderName:     `Name_${participantUids[0]}`,
    lastMessageAt:      new Date(),
    createdAt:          new Date(),
    borough:            "Cambridge",
    unreadCount:        Object.fromEntries(participantUids.map(u => [u, 0])),
    seeded:             true,
  });
}

/**
 * Seed a message in a conversation.
 * Returns the document reference so tests can verify fields later.
 */
async function seedMessage(
  convId: string,
  msgId: string,
  senderUid: string,
  messageText: string
): Promise<admin.firestore.DocumentReference> {
  const ref = db
    .collection("conversations")
    .doc(convId)
    .collection("messages")
    .doc(msgId);
  await ref.set({
    id:          msgId,
    senderId:    senderUid,
    senderName:  `Name_${senderUid}`,
    senderAvatar: `https://example.com/avatar_${senderUid}.jpg`,
    message:     messageText,
    timestamp:   new Date(),
    type:        "text",
    status:      "sent",
    reactions:   {},
    seeded:      true,
  });
  return ref;
}

/** Seed a group_messages doc. */
async function seedGroupMessage(
  msgId: string,
  senderUid: string,
  messageText: string,
  groupId = "group_001"
): Promise<admin.firestore.DocumentReference> {
  const ref = db.collection("group_messages").doc(msgId);
  await ref.set({
    groupId,
    senderId:     senderUid,
    senderName:   `Name_${senderUid}`,
    senderAvatar: `https://example.com/avatar_${senderUid}.jpg`,
    message:      messageText,
    timestamp:    new Date(),
    reactions:    {},
    seeded:       true,
  });
  return ref;
}

/** Read a document's data or null if it doesn't exist. */
async function readDoc(
  path: string[]
): Promise<Record<string, unknown> | null> {
  let ref: admin.firestore.DocumentReference = db
    .collection(path[0])
    .doc(path[1]);
  for (let i = 2; i < path.length - 1; i += 2) {
    ref = ref.collection(path[i]).doc(path[i + 1]);
  }
  const snap = await ref.get();
  return snap.exists ? (snap.data() as Record<string, unknown>) : null;
}

/** Check whether a document at an exact path exists. */
async function docExists(path: string[]): Promise<boolean> {
  return (await readDoc(path)) !== null;
}

// ── Cleanup ────────────────────────────────────────────────────────────────

async function clearAll(): Promise<void> {
  // Top-level collections used by Phase 3 tests
  for (const col of ["conversations", "group_messages", "_config"]) {
    const snap = await db.collection(col).limit(500).get();
    if (!snap.empty) {
      const batch = db.batch();
      snap.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
    }
  }
  // conversations/{id}/messages subcollections (emulator doesn't cascade)
  // Re-fetch any surviving conversation docs and clear their messages.
  const convSnap = await db.collection("conversations").limit(500).get();
  for (const convDoc of convSnap.docs) {
    const msgSnap = await convDoc.ref.collection("messages").limit(500).get();
    if (!msgSnap.empty) {
      const batch = db.batch();
      msgSnap.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
    }
  }
  // Brute-force: clear known conv IDs used in tests even if parent was deleted
  for (const convId of [
    "conv_alice_bob", "conv_alice_sole", "conv_carol_other",
  ]) {
    const msgSnap = await db
      .collection("conversations").doc(convId)
      .collection("messages").limit(500).get();
    if (!msgSnap.empty) {
      const batch = db.batch();
      msgSnap.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
    }
  }
}

// ── Setup / Teardown ───────────────────────────────────────────────────────

beforeAll(async () => {
  adminApp = admin.initializeApp({ projectId: PROJECT_ID }, "gdpr-phase3-test");
  db = adminApp.firestore();

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
// CONVERSATIONS + MESSAGES
// ══════════════════════════════════════════════════════════════════════════

describe("Conversations and messages", () => {

  test("T-GDPR3-conv-two-participant: alice's messages scrubbed; bob's UNCHANGED; conv doc survives", async () => {
    const CONV_ID = "conv_alice_bob";
    await seedConversation(CONV_ID, [ALICE_UID, BOB_UID]);

    // Alice's messages
    await seedMessage(CONV_ID, "msg_alice_1", ALICE_UID, "alice message 1");
    await seedMessage(CONV_ID, "msg_alice_2", ALICE_UID, "alice message 2");

    // Bob's messages — will assert field-by-field unchanged
    await seedMessage(CONV_ID, "msg_bob_1", BOB_UID, "bob message 1");
    await seedMessage(CONV_ID, "msg_bob_2", BOB_UID, "bob message 2");

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    // ── Step result checks ──
    expect(result.steps.conversations_messages.status).toBe("ok");
    expect(result.steps.conversations_messages.count).toBe(2); // 2 alice msgs
    expect(result.steps.conversations_docs.status).toBe("ok");
    expect(result.steps.conversations_docs.count).toBe(1); // 1 conversation updated

    // ── Conversation doc still EXISTS (bob is still a participant) ──
    expect(await docExists(["conversations", CONV_ID])).toBe(true);

    // ── alice removed from participants ──
    const convData = await readDoc(["conversations", CONV_ID]);
    const participants = convData?.["participants"] as string[];
    expect(participants).not.toContain(ALICE_UID);
    expect(participants).toContain(BOB_UID);

    // ── Alice's messages: senderId=null, senderName=null, senderAvatar=null, message=sentinel ──
    for (const msgId of ["msg_alice_1", "msg_alice_2"]) {
      const msgData = await readDoc(["conversations", CONV_ID, "messages", msgId]);
      expect(msgData).not.toBeNull();
      // G.1: senderId must be null (not just absent)
      expect(msgData!["senderId"]).toBeNull();
      expect(msgData!["senderName"]).toBeNull();
      expect(msgData!["senderAvatar"]).toBeNull();
      expect(msgData!["message"]).toBe(DELETED_CONTENT_SENTINEL);
    }

    // ── Bob's messages: COMPLETELY UNCHANGED — every identity field asserted ──
    for (const [msgId, origText] of [["msg_bob_1", "bob message 1"], ["msg_bob_2", "bob message 2"]]) {
      const msgData = await readDoc(["conversations", CONV_ID, "messages", msgId]);
      expect(msgData).not.toBeNull();
      expect(msgData!["senderId"]).toBe(BOB_UID);                             // not null
      expect(msgData!["senderName"]).toBe(`Name_${BOB_UID}`);                 // exact name
      expect(msgData!["senderAvatar"]).toBe(`https://example.com/avatar_${BOB_UID}.jpg`); // exact avatar
      expect(msgData!["message"]).toBe(origText);                             // exact text
      expect(msgData!["type"]).toBe("text");                                  // other fields intact
      expect(msgData!["status"]).toBe("sent");
    }
  });

  test("T-GDPR3-conv-sole-participant: alice is only participant → conversation doc DELETED", async () => {
    const CONV_ID = "conv_alice_sole";
    await seedConversation(CONV_ID, [ALICE_UID]);
    await seedMessage(CONV_ID, "msg_alice_sole_1", ALICE_UID, "a note to self");
    await seedMessage(CONV_ID, "msg_alice_sole_2", ALICE_UID, "another note");

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.conversations_messages.status).toBe("ok");
    expect(result.steps.conversations_messages.count).toBe(2);
    expect(result.steps.conversations_docs.status).toBe("ok");
    // Counted as 1 (the deletion)
    expect(result.steps.conversations_docs.count).toBe(1);

    // ── Conversation doc DELETED ──
    expect(await docExists(["conversations", CONV_ID])).toBe(false);
  });

  test("T-GDPR3-conv-delete-branch-not-over-eager: sole-participant conv deleted; two-participant conv kept — same run", async () => {
    // This is the combined-run proof that the delete branch fires ONLY when
    // participants is actually empty, not over-eagerly on every conversation.
    //
    // alice has TWO conversations in the same run:
    //   conv_sole_run  → participants = [ALICE_UID]         should be DELETED
    //   conv_mixed_run → participants = [ALICE_UID, BOB_UID] should be KEPT
    //
    // Both enter the same pagination loop. Only conv_sole_run should be deleted.

    const SOLE_CONV  = "conv_sole_run";
    const MIXED_CONV = "conv_mixed_run";

    // Sole-participant conversation
    await seedConversation(SOLE_CONV, [ALICE_UID]);
    await seedMessage(SOLE_CONV, "msg_sole_alice", ALICE_UID, "sole conv message");

    // Two-participant conversation
    await seedConversation(MIXED_CONV, [ALICE_UID, BOB_UID]);
    await seedMessage(MIXED_CONV, "msg_mixed_alice", ALICE_UID, "mixed conv alice msg");
    await seedMessage(MIXED_CONV, "msg_mixed_bob",   BOB_UID,   "mixed conv bob msg");

    // Single CF run — both conversations processed in the same pagination loop
    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.conversations_messages.status).toBe("ok");
    expect(result.steps.conversations_messages.count).toBe(2); // 1 sole + 1 mixed (alice's only)
    expect(result.steps.conversations_docs.status).toBe("ok");
    expect(result.steps.conversations_docs.count).toBe(2); // 1 deleted + 1 updated

    // ── sole-participant conv: DELETED ──
    expect(await docExists(["conversations", SOLE_CONV])).toBe(false);

    // ── two-participant conv: NOT deleted — kept because bob is still present ──
    expect(await docExists(["conversations", MIXED_CONV])).toBe(true);
    const mixedData = await readDoc(["conversations", MIXED_CONV]);
    const remaining = mixedData?.["participants"] as string[];
    expect(remaining).not.toContain(ALICE_UID);  // alice removed
    expect(remaining).toContain(BOB_UID);         // bob still present

    // ── alice's message in the kept conv: scrubbed ──
    const aliceMsg = await readDoc(["conversations", MIXED_CONV, "messages", "msg_mixed_alice"]);
    expect(aliceMsg!["senderId"]).toBeNull();
    expect(aliceMsg!["message"]).toBe(DELETED_CONTENT_SENTINEL);

    // ── bob's message in the kept conv: UNCHANGED ──
    const bobMsg = await readDoc(["conversations", MIXED_CONV, "messages", "msg_mixed_bob"]);
    expect(bobMsg!["senderId"]).toBe(BOB_UID);
    expect(bobMsg!["message"]).toBe("mixed conv bob msg");
  });

  test("T-GDPR3-conv-scoping-carol: carol's conversation (alice not a participant) entirely untouched", async () => {
    const CAROL_CONV = "conv_carol_other";
    await seedConversation(CAROL_CONV, [CAROL_UID, BOB_UID]);
    await seedMessage(CAROL_CONV, "msg_carol_1", CAROL_UID, "carol says hi");
    await seedMessage(CAROL_CONV, "msg_bob_in_carol", BOB_UID, "bob replies to carol");

    // Delete ALICE — carol's conversation must be completely untouched
    await deleteUserDataHandler({}, authCtx(ALICE_UID));

    // Carol's conversation doc still exists, participants unchanged
    expect(await docExists(["conversations", CAROL_CONV])).toBe(true);
    const convData = await readDoc(["conversations", CAROL_CONV]);
    const participants = convData?.["participants"] as string[];
    expect(participants).toContain(CAROL_UID);
    expect(participants).toContain(BOB_UID);

    // Carol's and Bob's messages completely untouched
    const carolMsg = await readDoc(["conversations", CAROL_CONV, "messages", "msg_carol_1"]);
    expect(carolMsg!["senderId"]).toBe(CAROL_UID);
    expect(carolMsg!["message"]).toBe("carol says hi");

    const bobMsg = await readDoc(["conversations", CAROL_CONV, "messages", "msg_bob_in_carol"]);
    expect(bobMsg!["senderId"]).toBe(BOB_UID);
    expect(bobMsg!["message"]).toBe("bob replies to carol");
  });
});

// ══════════════════════════════════════════════════════════════════════════
// GROUP_MESSAGES
// ══════════════════════════════════════════════════════════════════════════

describe("group_messages", () => {

  test("T-GDPR3-gm-anonymise: explicit anonymise override → alice's messages scrubbed+retained; bob's UNCHANGED", async () => {
    // Explicit override via _config doc. Default is also "anonymise", but this
    // test validates the path end-to-end with the override mechanism in place.
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "anonymise",
      reports: "retain",
      feedback: "delete",
      invitations_sent: "retain",
      dry_run_default: false,
    });

    // Alice's group messages
    await seedGroupMessage("gm_alice_1", ALICE_UID, "alice group msg 1");
    await seedGroupMessage("gm_alice_2", ALICE_UID, "alice group msg 2");
    await seedGroupMessage("gm_alice_3", ALICE_UID, "alice group msg 3");

    // Bob's group messages — assert field-by-field unchanged
    await seedGroupMessage("gm_bob_1", BOB_UID, "bob group msg 1");
    await seedGroupMessage("gm_bob_2", BOB_UID, "bob group msg 2");

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.group_messages.status).toBe("ok");
    expect(result.steps.group_messages.count).toBe(3);

    // ── Alice's docs: RETAINED as documents, identity scrubbed ──
    for (const [msgId, origText] of [
      ["gm_alice_1", "alice group msg 1"],
      ["gm_alice_2", "alice group msg 2"],
      ["gm_alice_3", "alice group msg 3"],
    ]) {
      const data = await readDoc(["group_messages", msgId]);
      expect(data).not.toBeNull(); // doc still exists
      // G.1: senderId must be null
      expect(data!["senderId"]).toBeNull();
      expect(data!["senderName"]).toBeNull();
      expect(data!["senderAvatar"]).toBeNull();
      expect(data!["message"]).toBe(DELETED_CONTENT_SENTINEL);
      // Original text is gone
      expect(data!["message"]).not.toBe(origText);
    }

    // ── Bob's docs: COMPLETELY UNCHANGED — field-by-field ──
    for (const [msgId, origText] of [["gm_bob_1", "bob group msg 1"], ["gm_bob_2", "bob group msg 2"]]) {
      const data = await readDoc(["group_messages", msgId]);
      expect(data).not.toBeNull();
      expect(data!["senderId"]).toBe(BOB_UID);
      expect(data!["senderName"]).toBe(`Name_${BOB_UID}`);
      expect(data!["senderAvatar"]).toBe(`https://example.com/avatar_${BOB_UID}.jpg`);
      expect(data!["message"]).toBe(origText);
    }
  });

  test("T-GDPR3-gm-delete: EXPLICIT delete override → alice's docs DELETED; bob's untouched", async () => {
    // Default is now "anonymise". Must explicitly set delete via _config override.
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "delete",
      reports:          "retain",
      feedback:         "delete",
      invitations_sent: "retain",
      dry_run_default:  false,
    });

    await seedGroupMessage("gm_del_alice_1", ALICE_UID, "alice delete msg 1");
    await seedGroupMessage("gm_del_alice_2", ALICE_UID, "alice delete msg 2");
    await seedGroupMessage("gm_del_bob_1",   BOB_UID,   "bob delete msg 1");

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.group_messages.status).toBe("ok");
    expect(result.steps.group_messages.count).toBe(2);

    // Alice's docs gone
    expect(await docExists(["group_messages", "gm_del_alice_1"])).toBe(false);
    expect(await docExists(["group_messages", "gm_del_alice_2"])).toBe(false);

    // Bob's doc untouched
    const bobData = await readDoc(["group_messages", "gm_del_bob_1"]);
    expect(bobData).not.toBeNull();
    expect(bobData!["senderId"]).toBe(BOB_UID);
    expect(bobData!["message"]).toBe("bob delete msg 1");
  });

  test("T-GDPR3-gm-default-anonymise: NO _config doc → default anonymise applies; docs retained, identity scrubbed", async () => {
    // No _config doc written — clearAll() guarantees the collection is empty,
    // so resolveGdprPolicy() falls back to DEFAULT_GDPR_POLICY.
    // This is the regression guard: if authored_content default ever reverts to
    // "delete", this test fails (docs would be missing instead of retained).

    await seedGroupMessage("gm_def_alice_1", ALICE_UID, "default alice msg 1");
    await seedGroupMessage("gm_def_alice_2", ALICE_UID, "default alice msg 2");
    await seedGroupMessage("gm_def_bob_1",   BOB_UID,   "default bob msg 1");

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.group_messages.status).toBe("ok");
    expect(result.steps.group_messages.count).toBe(2); // 2 alice docs touched

    // ── Alice's docs: RETAINED as documents, identity scrubbed ──
    for (const [msgId, origText] of [
      ["gm_def_alice_1", "default alice msg 1"],
      ["gm_def_alice_2", "default alice msg 2"],
    ]) {
      const data = await readDoc(["group_messages", msgId]);
      expect(data).not.toBeNull(); // doc still EXISTS — not deleted
      expect(data!["senderId"]).toBeNull();
      expect(data!["senderName"]).toBeNull();
      expect(data!["senderAvatar"]).toBeNull();
      expect(data!["message"]).toBe(DELETED_CONTENT_SENTINEL);
      expect(data!["message"]).not.toBe(origText);
    }

    // ── Bob's doc: completely untouched ──
    const bobData = await readDoc(["group_messages", "gm_def_bob_1"]);
    expect(bobData).not.toBeNull();
    expect(bobData!["senderId"]).toBe(BOB_UID);
    expect(bobData!["senderName"]).toBe(`Name_${BOB_UID}`);
    expect(bobData!["message"]).toBe("default bob msg 1");
  });

  test("T-GDPR3-gm-retain: policy.authored_content=retain → group_messages step skipped entirely", async () => {
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "retain",
      reports: "retain",
      feedback: "retain",
      invitations_sent: "retain",
      dry_run_default: false,
    });

    await seedGroupMessage("gm_retain_alice", ALICE_UID, "alice retained msg");

    const result = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    expect(result.steps.group_messages.status).toBe("skipped");
    expect(result.steps.group_messages.count).toBe(0);

    // Doc untouched
    const data = await readDoc(["group_messages", "gm_retain_alice"]);
    expect(data).not.toBeNull();
    expect(data!["senderId"]).toBe(ALICE_UID);
    expect(data!["message"]).toBe("alice retained msg");
  });
});

// ══════════════════════════════════════════════════════════════════════════
// SENTINEL / NULL CHECKS (G.1)
// ══════════════════════════════════════════════════════════════════════════

describe("Sentinel and null senderId (G.1)", () => {

  test("T-GDPR3-null-senderid: senderId is explicitly null (not just absent) on anonymised messages", async () => {
    // Use anonymise mode for group_messages
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "anonymise",
      reports: "retain",
      feedback: "delete",
      invitations_sent: "retain",
      dry_run_default: false,
    });

    // Seed a group message and a conversation message
    await seedGroupMessage("gm_null_check", ALICE_UID, "original group msg");

    const CONV_ID = "conv_alice_bob";
    await seedConversation(CONV_ID, [ALICE_UID, BOB_UID]);
    await seedMessage(CONV_ID, "msg_null_check", ALICE_UID, "original conv msg");

    await deleteUserDataHandler({}, authCtx(ALICE_UID));

    // group_messages doc: senderId must be null (not undefined, not '')
    const gmData = await readDoc(["group_messages", "gm_null_check"]);
    expect(gmData).not.toBeNull();
    // Explicit null check — this is the G.1 requirement
    expect(Object.prototype.hasOwnProperty.call(gmData, "senderId")).toBe(true);
    expect(gmData!["senderId"]).toBeNull();
    expect(gmData!["senderName"]).toBeNull();
    expect(gmData!["senderAvatar"]).toBeNull();
    expect(gmData!["message"]).toBe(DELETED_CONTENT_SENTINEL);

    // conversation message: senderId must also be null
    const msgData = await readDoc(["conversations", CONV_ID, "messages", "msg_null_check"]);
    expect(msgData).not.toBeNull();
    expect(Object.prototype.hasOwnProperty.call(msgData, "senderId")).toBe(true);
    expect(msgData!["senderId"]).toBeNull();
    expect(msgData!["senderName"]).toBeNull();
    expect(msgData!["senderAvatar"]).toBeNull();
    expect(msgData!["message"]).toBe(DELETED_CONTENT_SENTINEL);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// IDEMPOTENCY
// ══════════════════════════════════════════════════════════════════════════

describe("Idempotency", () => {

  test("T-GDPR3-idempotency: second run on already-anonymised data → no error steps, success=true", async () => {
    // Use anonymise for group_messages
    await db.collection("_config").doc("gdpr_deletion_policy").set({
      authored_content: "anonymise",
      reports: "retain",
      feedback: "delete",
      invitations_sent: "retain",
      dry_run_default: false,
    });

    const CONV_ID = "conv_alice_bob";
    await seedConversation(CONV_ID, [ALICE_UID, BOB_UID]);
    await seedMessage(CONV_ID, "msg_idem_alice", ALICE_UID, "idempotency test");
    await seedGroupMessage("gm_idem_alice", ALICE_UID, "gm idempotency test");

    // First run
    const first = await deleteUserDataHandler({}, authCtx(ALICE_UID));
    expect(first.success).toBe(true);

    // Second run — all alice messages already anonymised; conv already has alice removed;
    // group_messages already has null senderId. All steps should complete with ok/skipped.
    const second = await deleteUserDataHandler({}, authCtx(ALICE_UID));

    const errorSteps = Object.entries(second.steps)
      .filter(([, s]) => (s as { status: string }).status === "error");
    expect(errorSteps).toHaveLength(0);
    expect(second.success).toBe(true);
  });
});
