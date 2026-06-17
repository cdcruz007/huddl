/**
 * Huddl — GDPR Deletion CF Phase 5: Full Integration Test
 *
 * This is the master composition proof for the entire deleteUserData CF.
 * One user (INTEGRATION_UID) is seeded with data in EVERY location across
 * all phases. A BYSTANDER_UID shares collections/prefixes but has their
 * own independent data. The suite asserts:
 *
 *   T-GDPR5-default-config:
 *     Run with DEFAULT policy (authored_content=anonymise, reports=retain,
 *     feedback=delete, invitations_sent=retain, created_content=delete).
 *     Every step reports status=ok or status=skipped (per policy).
 *     Integration user's deletable data is gone; authored content is anonymised.
 *     BYSTANDER data is COMPLETELY UNTOUCHED (master scoping proof).
 *
 *   T-GDPR5-all-switches-flipped:
 *     Run with ALL switches flipped:
 *       authored_content=delete, reports=delete, feedback=retain,
 *       invitations_sent=delete, created_content_meetups=retain,
 *       created_content_marketplace=retain.
 *     Assert each location responds to its switch.
 *
 *   T-GDPR5-reports-hard-lock:
 *     Default run: reports step status=skipped (hard-lock retain).
 *     Explicit delete run: reports step status=ok, docs gone.
 *
 *   T-GDPR5-idempotency:
 *     Two consecutive full runs → second run success=true, no error steps.
 *
 *   T-GDPR5-return-shape:
 *     Structured result has every expected step key with a status field
 *     and success=true; counts are > 0 for seeded locations.
 *
 * Total: 5 tests
 *
 * Emulators:
 *   Firestore:  127.0.0.1:8180
 *   Storage:    localhost:9299
 * Bucket: huddl-gdpr-phase5-test.appspot.com (isolated)
 */

import * as admin from "firebase-admin";

// ── Emulator wiring ────────────────────────────────────────────────────────

const PROJECT_ID  = "huddl-gdpr-phase5-test";
const BUCKET_NAME = `${PROJECT_ID}.appspot.com`;

process.env.FIRESTORE_EMULATOR_HOST        = "127.0.0.1:8180";
process.env.FIREBASE_STORAGE_EMULATOR_HOST = "localhost:9299";
process.env.GCLOUD_PROJECT                 = PROJECT_ID;
process.env.GDPR_STORAGE_BUCKET            = BUCKET_NAME;

// ── Personas ───────────────────────────────────────────────────────────────

const INTEGRATION_UID = "intg_uid_001";
const BYSTANDER_UID   = "bystander_uid_002";

// ── Shared fixture IDs ────────────────────────────────────────────────────

const CONV_ID   = "conv_intg_001";  // shared DM conversation
const GROUP_ID  = "group_intg_001"; // shared group
const ANN_ID    = "ann_intg_001";   // announcement authored by INTEGRATION_UID
const ANN_ID2   = "ann_bystander_001"; // announcement authored by BYSTANDER_UID
const TS        = "1700000000000";

// ── State ──────────────────────────────────────────────────────────────────

let adminApp: admin.app.App;
let db: admin.firestore.Firestore;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let bucket: any;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let deleteUserDataHandler: (data: any, context: any) => Promise<any>;

function authCtx(uid: string) { return { auth: { uid, token: {} } }; }

// ── Storage helpers ────────────────────────────────────────────────────────

async function seedFile(path: string, content = "x"): Promise<void> {
  await bucket.file(path).save(content, { contentType: "application/octet-stream" });
}

async function fileExists(path: string): Promise<boolean> {
  const [exists] = await bucket.file(path).exists();
  return exists as boolean;
}

// ── Firestore seed helpers ─────────────────────────────────────────────────

async function seedDoc(
  collection: string, docId: string,
  data: Record<string, unknown>
): Promise<void> {
  await db.collection(collection).doc(docId).set(data);
}

async function docExists(collection: string, docId: string): Promise<boolean> {
  const snap = await db.collection(collection).doc(docId).get();
  return snap.exists;
}

async function getDocData(
  collection: string, docId: string
): Promise<Record<string, unknown> | null> {
  const snap = await db.collection(collection).doc(docId).get();
  return snap.exists ? (snap.data() as Record<string, unknown>) : null;
}

async function countDocs(
  query: admin.firestore.Query | admin.firestore.CollectionReference
): Promise<number> {
  const snap = await query.get();
  return snap.size;
}

// ── Full seed: seeds ONE integration user + ONE bystander across ALL locations ──

async function seedAll(): Promise<void> {
  const now = admin.firestore.Timestamp.now();

  // ── Phase 1 simple collections ──────────────────────────────────────────

  // subscriptions
  await seedDoc("subscriptions", `sub_intg`, { userId: INTEGRATION_UID, plan: "basic" });
  await seedDoc("subscriptions", `sub_byst`, { userId: BYSTANDER_UID,   plan: "basic" });

  // notifications
  await seedDoc("notifications", `notif_intg`, { userId: INTEGRATION_UID, text: "hello" });
  await seedDoc("notifications", `notif_byst`, { userId: BYSTANDER_UID,   text: "hello" });

  // local_services
  await seedDoc("local_services", `ls_intg`, { createdByUid: INTEGRATION_UID, name: "svc" });
  await seedDoc("local_services", `ls_byst`, { createdByUid: BYSTANDER_UID,   name: "svc" });

  // borough_feed
  await seedDoc("borough_feed", `bf_intg`, { partnerUid: INTEGRATION_UID, text: "post" });
  await seedDoc("borough_feed", `bf_byst`, { partnerUid: BYSTANDER_UID,   text: "post" });

  // feedback
  await seedDoc("feedback", `fb_intg`, { user_uid: INTEGRATION_UID, text: "good" });
  await seedDoc("feedback", `fb_byst`, { user_uid: BYSTANDER_UID,   text: "good" });

  // community_wisdom
  await seedDoc("community_wisdom", `cw_intg`, {
    author_uid: INTEGRATION_UID, author_name: "Alice",
    author_avatar: "http://a", content_text: "wisdom",
  });
  await seedDoc("community_wisdom", `cw_byst`, {
    author_uid: BYSTANDER_UID, author_name: "Bob",
    author_avatar: "http://b", content_text: "wisdom",
  });

  // borough_announcements (authored) + comment in bystander's announcement
  await seedDoc("borough_announcements", ANN_ID, {
    authorId: INTEGRATION_UID, text: "my ann", commentCount: 1,
  });
  await seedDoc("borough_announcements", ANN_ID2, {
    authorId: BYSTANDER_UID, text: "bystander ann", commentCount: 2,
  });
  // Integration user's comment on bystander's announcement
  await db.collection("borough_announcements").doc(ANN_ID2)
    .collection("comments").doc("comment_intg").set({
      authorId: INTEGRATION_UID, text: "my comment", createdAt: now,
    });
  // Bystander's own comment on their own announcement
  await db.collection("borough_announcements").doc(ANN_ID2)
    .collection("comments").doc("comment_byst").set({
      authorId: BYSTANDER_UID, text: "their comment", createdAt: now,
    });

  // reports  (filed BY integration user — hard-lock retain by default)
  await seedDoc("reports", `rep_intg`, { reportedByUid: INTEGRATION_UID, reason: "spam" });
  await seedDoc("reports", `rep_byst`, { reportedByUid: BYSTANDER_UID,   reason: "spam" });

  // meetups
  await seedDoc("meetups", `meet_intg_a`, { createdBy: INTEGRATION_UID,  title: "meetup A" });
  await seedDoc("meetups", `meet_intg_b`, { organiserId: INTEGRATION_UID, title: "meetup B" });
  await seedDoc("meetups", `meet_byst`,   { createdBy: BYSTANDER_UID,    title: "meetup C" });

  // marketplace
  await seedDoc("marketplace", `mkt_intg`, { sellerId: INTEGRATION_UID, item: "thing" });
  await seedDoc("marketplace", `mkt_byst`, { sellerId: BYSTANDER_UID,   item: "thing" });

  // polls
  await seedDoc("polls", `poll_intg`, { createdByUid: INTEGRATION_UID, question: "?" });
  await seedDoc("polls", `poll_byst`, { createdByUid: BYSTANDER_UID,   question: "?" });

  // ── Phase 2 subcollections ───────────────────────────────────────────────

  await db.collection("users").doc(INTEGRATION_UID)
    .collection("saved_messages").doc("sm1").set({ text: "saved" });
  await db.collection("users").doc(BYSTANDER_UID)
    .collection("saved_messages").doc("sm_b").set({ text: "saved" });

  await db.collection("users").doc(INTEGRATION_UID)
    .collection("notifPrefs").doc("settings").set({ enabled: true });
  await db.collection("users").doc(BYSTANDER_UID)
    .collection("notifPrefs").doc("settings").set({ enabled: true });

  await db.collection("users").doc(INTEGRATION_UID)
    .collection("deadlines").doc("dl1").set({ title: "deadline" });
  await db.collection("users").doc(BYSTANDER_UID)
    .collection("deadlines").doc("dl_b").set({ title: "deadline" });

  await db.collection("users").doc(INTEGRATION_UID)
    .collection("saved_items").doc("si1").set({ item: "item" });
  await db.collection("users").doc(BYSTANDER_UID)
    .collection("saved_items").doc("si_b").set({ item: "item" });

  await db.collection("users").doc(INTEGRATION_UID)
    .collection("blocks").doc("blocked_one").set({ targetUid: "blocked_one" });

  await db.collection("users").doc(BYSTANDER_UID)
    .collection("blocks").doc(INTEGRATION_UID).set({ targetUid: INTEGRATION_UID });

  await db.collection("users").doc(INTEGRATION_UID)
    .collection("invitations").doc("inv1").set({ fromUid: "other" });

  await db.collection("user_rsvps").doc(INTEGRATION_UID)
    .collection("meetups").doc("rsvp1").set({ meetupId: "m1" });
  await db.collection("user_rsvps").doc(BYSTANDER_UID)
    .collection("meetups").doc("rsvp_b").set({ meetupId: "m2" });

  // collectionGroup: endorsements (uid field = endorser)
  await db.collection("local_services").doc("ls_other")
    .collection("endorsements").doc(INTEGRATION_UID).set({ uid: INTEGRATION_UID });
  await db.collection("local_services").doc("ls_other")
    .collection("endorsements").doc(BYSTANDER_UID).set({ uid: BYSTANDER_UID });

  // invitations_sent: collectionGroup invitations with invitedById == uid
  // Different parent path to distinguish from invitations-received above
  await db.collection("outbound_invitations").doc("inv_out_intg")
    .collection("invitations").doc("sent_1").set({ invitedById: INTEGRATION_UID });
  await db.collection("outbound_invitations").doc("inv_out_byst")
    .collection("invitations").doc("sent_b").set({ invitedById: BYSTANDER_UID });

  // blocks_reverse: blocks where targetUid == INTEGRATION_UID
  await db.collection("users").doc("other_blocker")
    .collection("blocks").doc("b_rev").set({ targetUid: INTEGRATION_UID });

  // partner_analytics (doc ID == uid)
  await db.collection("partner_analytics").doc(INTEGRATION_UID).set({ views: 5 });
  await db.collection("partner_analytics").doc(BYSTANDER_UID).set({ views: 3 });

  // ── Phase 2 groups ───────────────────────────────────────────────────────

  await db.collection("groups").doc(GROUP_ID).set({
    memberIds: [INTEGRATION_UID, BYSTANDER_UID],
    name: "Test Group",
    createdAt: now,
  });
  await db.collection("groups").doc(GROUP_ID)
    .collection("memberActivity").doc(INTEGRATION_UID).set({ lastSeen: now });
  await db.collection("groups").doc(GROUP_ID)
    .collection("memberActivity").doc(BYSTANDER_UID).set({ lastSeen: now });

  // ── Phase 3 conversations ────────────────────────────────────────────────

  await db.collection("conversations").doc(CONV_ID).set({
    participants: [INTEGRATION_UID, BYSTANDER_UID],
    lastMessage: "hi",
    createdAt: now,
  });
  // Integration user's message — field is 'message' (realtime_dm_service.dart:214)
  await db.collection("conversations").doc(CONV_ID)
    .collection("messages").doc("msg_intg").set({
      senderId: INTEGRATION_UID, senderName: "Alice", senderAvatar: "http://a",
      message: "hello", sentAt: now,
    });
  // Bystander's message in same conversation
  await db.collection("conversations").doc(CONV_ID)
    .collection("messages").doc("msg_byst").set({
      senderId: BYSTANDER_UID, senderName: "Bob", senderAvatar: "http://b",
      message: "hey there", sentAt: now,
    });

  // group_messages
  await db.collection("group_messages").doc("gm_intg").set({
    senderId: INTEGRATION_UID, senderName: "Alice",
    senderAvatar: "http://a", message: "group msg",
  });
  await db.collection("group_messages").doc("gm_byst").set({
    senderId: BYSTANDER_UID, senderName: "Bob",
    senderAvatar: "http://b", message: "group msg bystander",
  });

  // ── Phase 4 storage ──────────────────────────────────────────────────────

  // profile photos (uid is prefix)
  await seedFile(`profile_photos/${INTEGRATION_UID}/photo.jpg`);
  await seedFile(`profile_photos/${BYSTANDER_UID}/photo.jpg`);

  // marketplace images (uid is prefix)
  await seedFile(`marketplace_images/${INTEGRATION_UID}/img.jpg`);
  await seedFile(`marketplace_images/${BYSTANDER_UID}/img.jpg`);

  // DM media — both users in same conversation prefix
  await seedFile(`dm_images/${CONV_ID}/${INTEGRATION_UID}_${TS}.jpg`);
  await seedFile(`dm_images/${CONV_ID}/${BYSTANDER_UID}_${TS}.jpg`);
  await seedFile(`voice_notes/dm/${CONV_ID}/${INTEGRATION_UID}_${TS}.m4a`);
  await seedFile(`voice_notes/dm/${CONV_ID}/${BYSTANDER_UID}_${TS}.m4a`);

  // Group media — both users in same group prefix (direct + thread)
  await seedFile(`group_images/${GROUP_ID}/${INTEGRATION_UID}_${TS}.jpg`);
  await seedFile(`group_images/${GROUP_ID}/${BYSTANDER_UID}_${TS}.jpg`);
  await seedFile(`group_images/${GROUP_ID}/thread_${INTEGRATION_UID}_${TS}.jpg`);
  await seedFile(`group_images/${GROUP_ID}/thread_${BYSTANDER_UID}_${TS}.jpg`);
}

// ── Policy helpers ─────────────────────────────────────────────────────────

function configDoc(overrides: Record<string, unknown>) {
  return db.collection("_config").doc("gdpr_deletion_policy").set(overrides);
}

async function clearConfig() {
  try {
    await db.collection("_config").doc("gdpr_deletion_policy").delete();
  } catch { /* ignore */ }
}

// ── Cleanup ────────────────────────────────────────────────────────────────

async function clearAll(): Promise<void> {
  const collections = [
    "subscriptions", "notifications", "local_services", "borough_feed",
    "feedback", "community_wisdom", "borough_announcements", "reports",
    "meetups", "marketplace", "polls", "conversations", "group_messages",
    "groups", "users", "user_rsvps", "partner_analytics",
    "outbound_invitations", "_config",
  ];
  for (const col of collections) {
    const snap = await db.collection(col).limit(500).get();
    if (!snap.empty) {
      const batch = db.batch();
      snap.docs.forEach(d => batch.delete(d.ref));
      await batch.commit();
    }
  }
  // Storage
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [files] = await bucket.getFiles();
  for (const f of files as any[]) { try { await f.delete(); } catch { /* ignore */ } }
}

// ── Setup / Teardown ───────────────────────────────────────────────────────

beforeAll(async () => {
  adminApp = admin.initializeApp(
    { projectId: PROJECT_ID, storageBucket: BUCKET_NAME },
    "gdpr-phase5-test"
  );
  db = adminApp.firestore();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  bucket = (admin.storage(adminApp) as any).bucket(BUCKET_NAME);

  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const cfModule = require("../../functions/lib/index.js");
  const cf = cfModule.deleteUserData;
  deleteUserDataHandler = typeof cf.run === "function" ? cf.run.bind(cf) : cf;
});

beforeEach(async () => {
  await clearAll();
  await clearConfig();
});

afterAll(async () => {
  await clearAll();
  await adminApp.delete();
});

// ══════════════════════════════════════════════════════════════════════════
// T-GDPR5-default-config
// Master integration test: default policy + bystander-untouched proof
// ══════════════════════════════════════════════════════════════════════════

test(
  "T-GDPR5-default-config: default policy deletes/anonymises all integration data; " +
  "bystander data COMPLETELY UNTOUCHED",
  async () => {
    await seedAll();

    // No _config doc → uses DEFAULT_GDPR_POLICY
    const result = await deleteUserDataHandler({}, authCtx(INTEGRATION_UID));

    // ── Structured result ──────────────────────────────────────────────────
    expect(result.success).toBe(true);
    expect(result.dryRun).toBe(false);
    expect(result.uid).toBe(INTEGRATION_UID);
    expect(result.policy.authored_content).toBe("anonymise");
    expect(result.policy.reports).toBe("retain");
    expect(result.policy.feedback).toBe("delete");
    expect(result.policy.invitations_sent).toBe("retain");
    expect(result.policy.created_content_meetups).toBe("delete");
    expect(result.policy.created_content_marketplace).toBe("delete");

    // No step should be in error
    const errorSteps = Object.entries(result.steps)
      .filter(([, s]) => (s as { status: string }).status === "error");
    expect(errorSteps).toHaveLength(0);

    // ── Phase 1: simple deletes (integration user gone) ────────────────────
    expect(await docExists("subscriptions",  "sub_intg")).toBe(false);
    expect(await docExists("notifications",  "notif_intg")).toBe(false);
    expect(await docExists("local_services", "ls_intg")).toBe(false);
    expect(await docExists("borough_feed",   "bf_intg")).toBe(false);
    expect(await docExists("feedback",       "fb_intg")).toBe(false);
    expect(await docExists("meetups",        "meet_intg_a")).toBe(false);
    expect(await docExists("meetups",        "meet_intg_b")).toBe(false);
    expect(await docExists("marketplace",    "mkt_intg")).toBe(false);
    expect(await docExists("polls",          "poll_intg")).toBe(false);

    // ── community_wisdom: ANONYMISED (default = anonymise) ─────────────────
    const cw = await getDocData("community_wisdom", "cw_intg");
    expect(cw).not.toBeNull();                    // doc retained
    expect(cw!["author_uid"]).toBeNull();         // identity scrubbed
    expect(cw!["author_name"]).toBeNull();
    expect(cw!["author_avatar"]).toBeNull();
    expect(cw!["content_text"]).toBe("[deleted]");

    // ── borough_announcements: authored post ANONYMISED; comment DELETED ───
    const ann = await getDocData("borough_announcements", ANN_ID);
    expect(ann).not.toBeNull();                   // authored announcement retained
    expect(ann!["authorId"]).toBeNull();          // authorId scrubbed
    // Integration user's comment on bystander's announcement: DELETED
    const commentSnap = await db
      .collection("borough_announcements").doc(ANN_ID2)
      .collection("comments").doc("comment_intg").get();
    expect(commentSnap.exists).toBe(false);
    // commentCount on bystander's announcement: decremented by 1 (was 2, now 1)
    const ann2data = await getDocData("borough_announcements", ANN_ID2);
    expect(ann2data!["commentCount"]).toBe(1);

    // ── reports: RETAINED (hard-lock default) ─────────────────────────────
    expect(result.steps["reports"].status).toBe("skipped");
    expect(await docExists("reports", "rep_intg")).toBe(true);

    // ── Phase 2 subcollections (integration user gone) ─────────────────────
    const savedMsgCount = await countDocs(
      db.collection("users").doc(INTEGRATION_UID).collection("saved_messages")
    );
    expect(savedMsgCount).toBe(0);
    const settingsSnap = await db.collection("users").doc(INTEGRATION_UID)
      .collection("notifPrefs").doc("settings").get();
    expect(settingsSnap.exists).toBe(false);
    const deadlineCount = await countDocs(
      db.collection("users").doc(INTEGRATION_UID).collection("deadlines")
    );
    expect(deadlineCount).toBe(0);
    const savedItemCount = await countDocs(
      db.collection("users").doc(INTEGRATION_UID).collection("saved_items")
    );
    expect(savedItemCount).toBe(0);
    expect(await docExists("partner_analytics", INTEGRATION_UID)).toBe(false);

    // blocks_reverse: the block targeting INTEGRATION_UID was deleted
    const blockRevSnap = await db.collection("users").doc("other_blocker")
      .collection("blocks").doc("b_rev").get();
    expect(blockRevSnap.exists).toBe(false);

    // ── Group membership: removed from memberIds; group doc survives ───────
    const groupData = await getDocData("groups", GROUP_ID);
    expect((groupData!["memberIds"] as string[]).includes(INTEGRATION_UID)).toBe(false);
    expect(groupData).not.toBeNull(); // group itself survives

    // memberActivity for integration user deleted
    const maSnap = await db.collection("groups").doc(GROUP_ID)
      .collection("memberActivity").doc(INTEGRATION_UID).get();
    expect(maSnap.exists).toBe(false);

    // ── invitations_sent: RETAINED (default) ──────────────────────────────
    expect(result.steps["invitations_sent"].status).toBe("skipped");

    // ── Phase 3 conversations ──────────────────────────────────────────────
    // Integration user's message scrubbed (default = anonymise)
    const msgIntgData = await db.collection("conversations").doc(CONV_ID)
      .collection("messages").doc("msg_intg").get();
    expect(msgIntgData.exists).toBe(true);         // doc retained
    expect(msgIntgData.data()!["senderId"]).toBeNull();
    expect(msgIntgData.data()!["senderName"]).toBeNull();
    expect(msgIntgData.data()!["senderAvatar"]).toBeNull();
    expect(msgIntgData.data()!["message"]).toBe("[deleted]");

    // group_messages: ANONYMISED (default = anonymise)
    const gm = await getDocData("group_messages", "gm_intg");
    expect(gm).not.toBeNull();
    expect(gm!["senderId"]).toBeNull();
    expect(gm!["message"]).toBe("[deleted]");

    // ── Phase 4 storage ────────────────────────────────────────────────────
    // Profile + marketplace prefix (uid IS prefix): DELETED
    expect(await fileExists(`profile_photos/${INTEGRATION_UID}/photo.jpg`)).toBe(false);
    expect(await fileExists(`marketplace_images/${INTEGRATION_UID}/img.jpg`)).toBe(false);

    // DM media: integration user's files DELETED
    expect(await fileExists(`dm_images/${CONV_ID}/${INTEGRATION_UID}_${TS}.jpg`)).toBe(false);
    expect(await fileExists(`voice_notes/dm/${CONV_ID}/${INTEGRATION_UID}_${TS}.m4a`)).toBe(false);

    // Group media: integration user's files DELETED (direct + thread)
    expect(await fileExists(`group_images/${GROUP_ID}/${INTEGRATION_UID}_${TS}.jpg`)).toBe(false);
    expect(await fileExists(`group_images/${GROUP_ID}/thread_${INTEGRATION_UID}_${TS}.jpg`)).toBe(false);

    // ══════════════════════════════════════════════════════════════════
    // BYSTANDER MASTER SCOPING PROOF — every single bystander asset
    // must be COMPLETELY UNTOUCHED after the integration user's deletion
    // ══════════════════════════════════════════════════════════════════

    // Phase 1 collections
    expect(await docExists("subscriptions",  "sub_byst")).toBe(true);
    expect(await docExists("notifications",  "notif_byst")).toBe(true);
    expect(await docExists("local_services", "ls_byst")).toBe(true);
    expect(await docExists("borough_feed",   "bf_byst")).toBe(true);
    expect(await docExists("feedback",       "fb_byst")).toBe(true);
    expect(await docExists("meetups",        "meet_byst")).toBe(true);
    expect(await docExists("marketplace",    "mkt_byst")).toBe(true);
    expect(await docExists("polls",          "poll_byst")).toBe(true);

    // Bystander's community_wisdom: untouched
    const cwByst = await getDocData("community_wisdom", "cw_byst");
    expect(cwByst!["author_uid"]).toBe(BYSTANDER_UID);
    expect(cwByst!["content_text"]).toBe("wisdom");

    // Bystander's announcement: authorId NOT nulled
    const ann2 = await getDocData("borough_announcements", ANN_ID2);
    expect(ann2!["authorId"]).toBe(BYSTANDER_UID);
    // Bystander's own comment: INTACT
    const bystCommentSnap = await db.collection("borough_announcements").doc(ANN_ID2)
      .collection("comments").doc("comment_byst").get();
    expect(bystCommentSnap.exists).toBe(true);
    expect(bystCommentSnap.data()!["authorId"]).toBe(BYSTANDER_UID);

    // Bystander's report: untouched
    expect(await docExists("reports", "rep_byst")).toBe(true);

    // Phase 2 subcollections
    const bystSavedMsg = await db.collection("users").doc(BYSTANDER_UID)
      .collection("saved_messages").doc("sm_b").get();
    expect(bystSavedMsg.exists).toBe(true);
    const bystSettings = await db.collection("users").doc(BYSTANDER_UID)
      .collection("notifPrefs").doc("settings").get();
    expect(bystSettings.exists).toBe(true);
    expect(await docExists("partner_analytics", BYSTANDER_UID)).toBe(true);

    // Bystander still in group
    const groupDataAfter = await getDocData("groups", GROUP_ID);
    expect((groupDataAfter!["memberIds"] as string[]).includes(BYSTANDER_UID)).toBe(true);

    // Bystander's memberActivity intact
    const bystMaSnap = await db.collection("groups").doc(GROUP_ID)
      .collection("memberActivity").doc(BYSTANDER_UID).get();
    expect(bystMaSnap.exists).toBe(true);

    // Bystander's message in shared conversation: INTACT and unmodified
    const bystMsg = await db.collection("conversations").doc(CONV_ID)
      .collection("messages").doc("msg_byst").get();
    expect(bystMsg.exists).toBe(true);
    expect(bystMsg.data()!["senderId"]).toBe(BYSTANDER_UID);
    expect(bystMsg.data()!["message"]).toBe("hey there");

    // Bystander's group_messages: untouched
    const gmByst = await getDocData("group_messages", "gm_byst");
    expect(gmByst!["senderId"]).toBe(BYSTANDER_UID);
    expect(gmByst!["message"]).toBe("group msg bystander");

    // Storage: bystander's files in SAME prefixes as integration user: INTACT
    expect(await fileExists(`profile_photos/${BYSTANDER_UID}/photo.jpg`)).toBe(true);
    expect(await fileExists(`marketplace_images/${BYSTANDER_UID}/img.jpg`)).toBe(true);
    expect(await fileExists(`dm_images/${CONV_ID}/${BYSTANDER_UID}_${TS}.jpg`)).toBe(true);
    expect(await fileExists(`voice_notes/dm/${CONV_ID}/${BYSTANDER_UID}_${TS}.m4a`)).toBe(true);
    expect(await fileExists(`group_images/${GROUP_ID}/${BYSTANDER_UID}_${TS}.jpg`)).toBe(true);
    expect(await fileExists(`group_images/${GROUP_ID}/thread_${BYSTANDER_UID}_${TS}.jpg`)).toBe(true);
  },
  60000
);

// ══════════════════════════════════════════════════════════════════════════
// T-GDPR5-all-switches-flipped
// Every switch flipped from default — assert each location responds
// ══════════════════════════════════════════════════════════════════════════

test(
  "T-GDPR5-all-switches-flipped: authored_content=delete, reports=delete, " +
  "feedback=retain, invitations_sent=delete, created_content=retain",
  async () => {
    await seedAll();

    await configDoc({
      authored_content:            "delete",
      reports:                     "delete",
      feedback:                    "retain",
      invitations_sent:            "delete",
      created_content_meetups:     "retain",
      created_content_marketplace: "retain",
    });

    const result = await deleteUserDataHandler({}, authCtx(INTEGRATION_UID));
    expect(result.success).toBe(true);

    // authored_content=delete → community_wisdom DELETED (not just anonymised)
    expect(await docExists("community_wisdom", "cw_intg")).toBe(false);

    // authored_content=delete → borough_announcements authored post DELETED
    expect(await docExists("borough_announcements", ANN_ID)).toBe(false);

    // authored_content=delete → group_messages DELETED
    expect(await docExists("group_messages", "gm_intg")).toBe(false);

    // authored_content=delete → conversation messages: ALWAYS anonymised, NEVER individually
    // deleted. The conversations step is independent of authored_content — it always
    // anonymises (senderId/senderName/senderAvatar → null, message → "[deleted]") to
    // preserve the other participant's conversation history.
    const msgIntg = await db.collection("conversations").doc(CONV_ID)
      .collection("messages").doc("msg_intg").get();
    expect(msgIntg.exists).toBe(true);           // doc retained (other participant's history)
    expect(msgIntg.data()!["senderId"]).toBeNull();
    expect(msgIntg.data()!["message"]).toBe("[deleted]");

    // reports=delete → reports DELETED
    expect(result.steps["reports"].status).toBe("ok");
    expect(await docExists("reports", "rep_intg")).toBe(false);

    // feedback=retain → feedback doc still exists
    expect(result.steps["feedback"].status).toBe("skipped");
    expect(await docExists("feedback", "fb_intg")).toBe(true);

    // invitations_sent=delete → sent invitation deleted
    expect(result.steps["invitations_sent"].status).toBe("ok");
    const sentInv = await db.collection("outbound_invitations").doc("inv_out_intg")
      .collection("invitations").doc("sent_1").get();
    expect(sentInv.exists).toBe(false);

    // created_content_meetups=retain → meetups NOT deleted
    expect(result.steps["meetups_createdBy"].status).toBe("skipped");
    expect(result.steps["meetups_organiserId"].status).toBe("skipped");
    expect(await docExists("meetups", "meet_intg_a")).toBe(true);
    expect(await docExists("meetups", "meet_intg_b")).toBe(true);

    // created_content_marketplace=retain → marketplace NOT deleted
    expect(result.steps["marketplace"].status).toBe("skipped");
    expect(await docExists("marketplace", "mkt_intg")).toBe(true);

    // Bystander's reports still intact (scoping: only deleted reportedByUid==INTEGRATION_UID)
    expect(await docExists("reports", "rep_byst")).toBe(true);
    // Bystander's feedback intact
    expect(await docExists("feedback", "fb_byst")).toBe(true);
  },
  60000
);

// ══════════════════════════════════════════════════════════════════════════
// T-GDPR5-reports-hard-lock
// ══════════════════════════════════════════════════════════════════════════

test(
  "T-GDPR5-reports-hard-lock: default policy retains reports (hard-lock); " +
  "explicit delete policy removes them",
  async () => {
    await seedAll();

    // ── Default run: reports RETAINED ──────────────────────────────────────
    const r1 = await deleteUserDataHandler({}, authCtx(INTEGRATION_UID));
    expect(r1.steps["reports"].status).toBe("skipped");
    expect(r1.steps["reports"].count).toBe(0);
    expect(await docExists("reports", "rep_intg")).toBe(true);

    // ── Re-seed just the report ─────────────────────────────────────────────
    await seedDoc("reports", "rep_intg", { reportedByUid: INTEGRATION_UID, reason: "spam" });

    // ── Explicit delete run ─────────────────────────────────────────────────
    await configDoc({ reports: "delete" });
    const r2 = await deleteUserDataHandler({}, authCtx(INTEGRATION_UID));
    expect(r2.steps["reports"].status).toBe("ok");
    expect(r2.steps["reports"].count).toBeGreaterThanOrEqual(1);
    expect(await docExists("reports", "rep_intg")).toBe(false);

    // Bystander report never touched
    expect(await docExists("reports", "rep_byst")).toBe(true);
  },
  60000
);

// ══════════════════════════════════════════════════════════════════════════
// T-GDPR5-idempotency
// ══════════════════════════════════════════════════════════════════════════

test(
  "T-GDPR5-idempotency: two consecutive full runs → second run success=true, no error steps",
  async () => {
    await seedAll();

    const first = await deleteUserDataHandler({}, authCtx(INTEGRATION_UID));
    expect(first.success).toBe(true);

    // Second run: all data already processed/deleted/anonymised.
    // Storage 404s are swallowed. Firestore queries return 0 results.
    const second = await deleteUserDataHandler({}, authCtx(INTEGRATION_UID));

    const errorSteps = Object.entries(second.steps)
      .filter(([, s]) => (s as { status: string }).status === "error");
    expect(errorSteps).toHaveLength(0);
    expect(second.success).toBe(true);
  },
  120000
);

// ══════════════════════════════════════════════════════════════════════════
// T-GDPR5-return-shape
// ══════════════════════════════════════════════════════════════════════════

test(
  "T-GDPR5-return-shape: result has all expected step keys, success=true, " +
  "non-zero counts for seeded locations",
  async () => {
    await seedAll();
    const result = await deleteUserDataHandler({}, authCtx(INTEGRATION_UID));

    expect(result.success).toBe(true);
    expect(typeof result.uid).toBe("string");
    expect(typeof result.startedAt).toBe("string");
    expect(typeof result.completedAt).toBe("string");
    expect(result.policy).toBeDefined();

    // Every expected step key must be present with a status field
    const expectedSteps = [
      "subscriptions", "notifications", "local_services", "borough_feed",
      "feedback", "community_wisdom", "borough_announcements", "reports",
      "meetups_createdBy", "meetups_organiserId", "marketplace",
      "polls", "partner_analytics",
      "users_saved_messages", "users_notifPrefs_settings",
      "users_deadlines", "users_saved_items", "users_blocks_forward",
      "users_invitations_received", "user_rsvps_meetups",
      "blocks_reverse", "endorsements_by_uid", "invitations_sent",
      "groups_membership_remove", "member_activity",
      "conversations_messages", "conversations_docs",
      "group_messages",
      "storage_prefix_delete", "storage_dm_media", "storage_group_media",
    ];

    for (const key of expectedSteps) {
      expect(result.steps[key]).toBeDefined();
      expect(["ok", "skipped", "error"]).toContain(result.steps[key].status);
    }

    // Spot-check counts are > 0 for locations we definitely seeded
    expect(result.steps["subscriptions"].count).toBeGreaterThanOrEqual(1);
    expect(result.steps["notifications"].count).toBeGreaterThanOrEqual(1);
    expect(result.steps["feedback"].count).toBeGreaterThanOrEqual(1);
    expect(result.steps["meetups_createdBy"].count +
           result.steps["meetups_organiserId"].count).toBeGreaterThanOrEqual(2);
    expect(result.steps["marketplace"].count).toBeGreaterThanOrEqual(1);
    expect(result.steps["borough_announcements"].count).toBeGreaterThanOrEqual(1);
    expect(result.steps["storage_prefix_delete"].count).toBeGreaterThanOrEqual(2); // profile + marketplace
    expect(result.steps["storage_dm_media"].count).toBeGreaterThanOrEqual(2);
    expect(result.steps["storage_group_media"].count).toBeGreaterThanOrEqual(2);

    // capturedGroupIds and capturedConvIds in result
    expect(Array.isArray(result.capturedGroupIds)).toBe(true);
    expect(result.capturedGroupIds).toContain(GROUP_ID);
    expect(Array.isArray(result.capturedConvIds)).toBe(true);
    expect(result.capturedConvIds).toContain(CONV_ID);
  },
  60000
);
