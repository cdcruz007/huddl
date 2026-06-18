/**
 * gdpr_cf_seed_prod.js
 *
 * One-off seeding script — creates two throwaway test users and seeds one
 * document / file in EVERY location the deleteUserData CF touches, mirroring
 * the Phase 5 integration test against PRODUCTION huddl-connect.
 *
 * Usage:
 *   node gdpr_cf_seed_prod.js <path-to-service-account-key.json>
 *
 * Requires: firebase-admin (use the functions package — no separate install needed)
 *   cd functions && node ../scripts/gdpr_cf_seed_prod.js /path/to/service-account.json
 *   OR: npm install firebase-admin in scripts/ directory if running standalone.
 *
 * What it does:
 *   1. Generates two deterministic, clearly-disposable UIDs:
 *        TEST_UID      = "CFTEST_<timestamp>"      — the user whose data gets deleted
 *        BYSTANDER_UID = "CFTEST_BYST_<timestamp>" — shares every shared structure
 *   2. Seeds Firestore + Storage in every CF-touched location.
 *   3. Prints a complete manifest of every doc path + storage path written.
 *
 * What it does NOT do:
 *   - Does NOT call the CF.
 *   - Does NOT delete anything.
 *   - Does NOT create real Firebase Auth accounts (UIDs are synthetic).
 *
 * Cleanup after testing:
 *   The printed manifest contains every path. Run the CF against TEST_UID,
 *   then verify each manifest entry is gone / anonymised. Bystander data
 *   should be completely untouched.
 *
 * Project:  huddl-connect
 * Bucket:   huddl-connect.firebasestorage.app
 * Region:   europe-west2 (CF), europe-west4 (Firestore)
 */

"use strict";

const admin  = require("firebase-admin");
const path   = require("path");
const fs     = require("fs");

// ── CLI arg check ─────────────────────────────────────────────────────────────

const keyPath = process.argv[2];
if (!keyPath) {
  console.error("\nUsage: node gdpr_cf_seed_prod.js <path-to-service-account-key.json>\n");
  process.exit(1);
}
const resolvedKey = path.resolve(keyPath);
if (!fs.existsSync(resolvedKey)) {
  console.error(`\nService account key not found: ${resolvedKey}\n`);
  process.exit(1);
}

// ── Firebase init ─────────────────────────────────────────────────────────────

const PROJECT_ID    = "huddl-connect";
const STORAGE_BUCKET = "huddl-connect.firebasestorage.app";

admin.initializeApp({
  credential:    admin.credential.cert(resolvedKey),
  projectId:     PROJECT_ID,
  storageBucket: STORAGE_BUCKET,
});

const db     = admin.firestore();
const bucket = admin.storage().bucket(STORAGE_BUCKET);

// ── UIDs — deterministic, clearly disposable ──────────────────────────────────

const TS           = Date.now().toString();
const TEST_UID     = `CFTEST_${TS}`;
const BYSTANDER_UID = `CFTEST_BYST_${TS}`;

// ── Shared fixture IDs — keyed on TS so they don't collide with real data ─────

const CONV_ID       = `cftest_conv_${TS}`;       // shared DM conversation
const GROUP_ID      = `cftest_group_${TS}`;      // shared group
const ANN_ID_TEST   = `cftest_ann_${TS}`;        // announcement authored by TEST_UID
const ANN_ID_BYST   = `cftest_ann_byst_${TS}`;   // announcement authored by BYSTANDER_UID
const LS_OTHER_ID   = `cftest_ls_${TS}`;         // local_service for endorsement parent
const INV_OUT_TEST  = `cftest_invout_${TS}`;     // outbound invitation parent (test)
const INV_OUT_BYST  = `cftest_invout_byst_${TS}`; // outbound invitation parent (bystander)

// Timestamp used as filename infix for storage paths
const FILE_TS       = TS;

// ── Manifest accumulator ──────────────────────────────────────────────────────

const manifest = {
  testUid:      TEST_UID,
  bystanderUid: BYSTANDER_UID,
  convId:       CONV_ID,
  groupId:      GROUP_ID,
  firestore:    [],   // { path, owner, note }
  storage:      [],   // { path, owner, note }
  errors:       [],
};

function mfs(path, owner, note = "") {
  manifest.firestore.push({ path, owner, note });
}
function mst(path, owner, note = "") {
  manifest.storage.push({ path, owner, note });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

async function set(collectionPath, docId, data, owner, note = "") {
  const ref = db.doc(`${collectionPath}/${docId}`);
  await ref.set(data);
  mfs(`${collectionPath}/${docId}`, owner, note);
}

async function setSubcollection(parentPath, subcollection, docId, data, owner, note = "") {
  const ref = db.doc(`${parentPath}/${subcollection}/${docId}`);
  await ref.set(data);
  mfs(`${parentPath}/${subcollection}/${docId}`, owner, note);
}

async function uploadFile(storagePath, owner, note = "") {
  const content = Buffer.from(`cftest-placeholder-${owner}-${storagePath}`);
  await bucket.file(storagePath).save(content, {
    metadata: { contentType: "application/octet-stream" },
  });
  mst(storagePath, owner, note);
}

// ── Main seed ─────────────────────────────────────────────────────────────────

async function seedAll() {

  const now = admin.firestore.Timestamp.now();

  console.log(`\n${"═".repeat(72)}`);
  console.log(`  GDPR CF SEED — huddl-connect PRODUCTION`);
  console.log(`${"═".repeat(72)}`);
  console.log(`  TEST_UID      = ${TEST_UID}`);
  console.log(`  BYSTANDER_UID = ${BYSTANDER_UID}`);
  console.log(`  CONV_ID       = ${CONV_ID}`);
  console.log(`  GROUP_ID      = ${GROUP_ID}`);
  console.log(`  TIMESTAMP     = ${TS}`);
  console.log(`${"═".repeat(72)}\n`);
  console.log("Seeding Firestore + Storage...\n");

  // ════════════════════════════════════════════════════════════════════════════
  // PHASE 1 — Simple top-level collections (field = uid query target)
  // ════════════════════════════════════════════════════════════════════════════

  // ── users + users_public (profile) ────────────────────────────────────────
  // Not directly queried by CF but seeded for realism / verification
  await set("users", TEST_UID, {
    uid:         TEST_UID,
    displayName: "CFTEST User",
    email:       `cftest_${TS}@throwaway.huddl`,
    createdAt:   now,
    _cftest:     true,
  }, "TEST", "user profile doc");

  await set("users", BYSTANDER_UID, {
    uid:         BYSTANDER_UID,
    displayName: "CFTEST Bystander",
    email:       `cftest_byst_${TS}@throwaway.huddl`,
    createdAt:   now,
    _cftest:     true,
  }, "BYSTANDER", "user profile doc");

  await set("users_public", TEST_UID, {
    uid:         TEST_UID,
    displayName: "CFTEST User",
    avatarUrl:   "https://placeholder.invalid/cftest.jpg",
    _cftest:     true,
  }, "TEST", "public profile doc");

  await set("users_public", BYSTANDER_UID, {
    uid:         BYSTANDER_UID,
    displayName: "CFTEST Bystander",
    avatarUrl:   "https://placeholder.invalid/cftest_byst.jpg",
    _cftest:     true,
  }, "BYSTANDER", "public profile doc");

  // ── subscriptions — field: userId ─────────────────────────────────────────
  await set("subscriptions", `cftest_sub_${TS}`, {
    userId: TEST_UID, plan: "basic", _cftest: true,
  }, "TEST", "CF queries: userId==uid");

  await set("subscriptions", `cftest_sub_byst_${TS}`, {
    userId: BYSTANDER_UID, plan: "basic", _cftest: true,
  }, "BYSTANDER", "must survive TEST deletion");

  // ── notifications — field: userId ────────────────────────────────────────
  await set("notifications", `cftest_notif_${TS}`, {
    userId: TEST_UID, text: "cftest notification", _cftest: true,
  }, "TEST", "CF queries: userId==uid");

  await set("notifications", `cftest_notif_byst_${TS}`, {
    userId: BYSTANDER_UID, text: "cftest bystander notification", _cftest: true,
  }, "BYSTANDER", "must survive TEST deletion");

  // ── local_services — field: createdByUid ──────────────────────────────────
  await set("local_services", `cftest_ls_test_${TS}`, {
    createdByUid: TEST_UID, name: "CFTEST Service", _cftest: true,
  }, "TEST", "CF queries: createdByUid==uid");

  await set("local_services", `cftest_ls_byst_${TS}`, {
    createdByUid: BYSTANDER_UID, name: "CFTEST Bystander Service", _cftest: true,
  }, "BYSTANDER", "must survive TEST deletion");

  // ── borough_feed — field: partnerUid ──────────────────────────────────────
  await set("borough_feed", `cftest_bf_${TS}`, {
    partnerUid: TEST_UID, text: "cftest feed post", _cftest: true,
  }, "TEST", "CF queries: partnerUid==uid");

  await set("borough_feed", `cftest_bf_byst_${TS}`, {
    partnerUid: BYSTANDER_UID, text: "cftest bystander feed post", _cftest: true,
  }, "BYSTANDER", "must survive TEST deletion");

  // ── feedback — field: user_uid ────────────────────────────────────────────
  await set("feedback", `cftest_fb_${TS}`, {
    user_uid: TEST_UID, text: "cftest feedback", _cftest: true,
  }, "TEST", "CF queries: user_uid==uid (deleted by default policy)");

  await set("feedback", `cftest_fb_byst_${TS}`, {
    user_uid: BYSTANDER_UID, text: "cftest bystander feedback", _cftest: true,
  }, "BYSTANDER", "must survive TEST deletion");

  // ── community_wisdom — fields: author_uid, author_name, author_avatar, content_text
  await set("community_wisdom", `cftest_cw_${TS}`, {
    author_uid:    TEST_UID,
    author_name:   "CFTEST User",
    author_avatar: "https://placeholder.invalid/cftest.jpg",
    content_text:  "cftest wisdom entry",
    _cftest:       true,
  }, "TEST", "CF: anonymises author_uid/name/avatar + content_text (default policy)");

  await set("community_wisdom", `cftest_cw_byst_${TS}`, {
    author_uid:    BYSTANDER_UID,
    author_name:   "CFTEST Bystander",
    author_avatar: "https://placeholder.invalid/cftest_byst.jpg",
    content_text:  "cftest bystander wisdom entry",
    _cftest:       true,
  }, "BYSTANDER", "must survive untouched");

  // ── borough_announcements — authored post + comment on bystander's post ───
  // (a) TEST_UID authors an announcement
  await set("borough_announcements", ANN_ID_TEST, {
    authorId:     TEST_UID,
    text:         "cftest announcement",
    commentCount: 1,
    _cftest:      true,
  }, "TEST", "CF: anonymises authorId (default policy)");

  // (b) BYSTANDER_UID authors an announcement with commentCount=2
  await set("borough_announcements", ANN_ID_BYST, {
    authorId:     BYSTANDER_UID,
    text:         "cftest bystander announcement",
    commentCount: 2,
    _cftest:      true,
  }, "BYSTANDER", "must survive untouched; commentCount will decrement by 1");

  // (c) TEST_UID leaves a comment on BYSTANDER's announcement
  await setSubcollection(
    `borough_announcements/${ANN_ID_BYST}`, "comments",
    `cftest_comment_test_${TS}`,
    { authorId: TEST_UID, text: "cftest test comment", createdAt: now, _cftest: true },
    "TEST",
    "CF: always deleted; decrements commentCount on ANN_ID_BYST"
  );

  // (d) BYSTANDER_UID's own comment on their own announcement
  await setSubcollection(
    `borough_announcements/${ANN_ID_BYST}`, "comments",
    `cftest_comment_byst_${TS}`,
    { authorId: BYSTANDER_UID, text: "cftest bystander comment", createdAt: now, _cftest: true },
    "BYSTANDER",
    "must survive untouched"
  );

  // ── reports — field: reportedByUid ────────────────────────────────────────
  await set("reports", `cftest_rep_${TS}`, {
    reportedByUid: TEST_UID, reason: "cftest", _cftest: true,
  }, "TEST", "CF: RETAINED by default (hard-lock); only deleted on explicit policy");

  await set("reports", `cftest_rep_byst_${TS}`, {
    reportedByUid: BYSTANDER_UID, reason: "cftest", _cftest: true,
  }, "BYSTANDER", "must survive untouched");

  // ── group_messages — fields: senderId, senderName, senderAvatar, message ──
  await set("group_messages", `cftest_gm_${TS}`, {
    senderId:    TEST_UID,
    senderName:  "CFTEST User",
    senderAvatar: "https://placeholder.invalid/cftest.jpg",
    message:     "cftest group message",
    _cftest:     true,
  }, "TEST", "CF: anonymises senderId/senderName/senderAvatar/message (default policy)");

  await set("group_messages", `cftest_gm_byst_${TS}`, {
    senderId:    BYSTANDER_UID,
    senderName:  "CFTEST Bystander",
    senderAvatar: "https://placeholder.invalid/cftest_byst.jpg",
    message:     "cftest bystander group message",
    _cftest:     true,
  }, "BYSTANDER", "must survive untouched");

  // ── meetups — fields: createdBy + organiserId (two separate queries) ───────
  await set("meetups", `cftest_meet_createdby_${TS}`, {
    createdBy: TEST_UID, title: "cftest meetup A", _cftest: true,
  }, "TEST", "CF queries: createdBy==uid");

  await set("meetups", `cftest_meet_organiser_${TS}`, {
    organiserId: TEST_UID, title: "cftest meetup B", _cftest: true,
  }, "TEST", "CF queries: organiserId==uid");

  await set("meetups", `cftest_meet_byst_${TS}`, {
    createdBy: BYSTANDER_UID, title: "cftest bystander meetup", _cftest: true,
  }, "BYSTANDER", "must survive untouched");

  // ── marketplace — field: sellerId ────────────────────────────────────────
  await set("marketplace", `cftest_mkt_${TS}`, {
    sellerId: TEST_UID, item: "cftest item", _cftest: true,
  }, "TEST", "CF queries: sellerId==uid");

  await set("marketplace", `cftest_mkt_byst_${TS}`, {
    sellerId: BYSTANDER_UID, item: "cftest bystander item", _cftest: true,
  }, "BYSTANDER", "must survive untouched");

  // ── polls — field: createdByUid ───────────────────────────────────────────
  await set("polls", `cftest_poll_${TS}`, {
    createdByUid: TEST_UID, question: "cftest poll?", _cftest: true,
  }, "TEST", "CF queries: createdByUid==uid");

  await set("polls", `cftest_poll_byst_${TS}`, {
    createdByUid: BYSTANDER_UID, question: "cftest bystander poll?", _cftest: true,
  }, "BYSTANDER", "must survive untouched");

  // ── partner_analytics — doc ID == uid (point-delete) ────────────────────
  await set("partner_analytics", TEST_UID, {
    views: 7, _cftest: true,
  }, "TEST", "CF: point-delete by doc ID (doc ID == uid)");

  await set("partner_analytics", BYSTANDER_UID, {
    views: 3, _cftest: true,
  }, "BYSTANDER", "must survive untouched");

  // ════════════════════════════════════════════════════════════════════════════
  // PHASE 2 — Subcollections under users/{uid}/
  // ════════════════════════════════════════════════════════════════════════════

  // saved_messages
  await setSubcollection(`users/${TEST_UID}`, "saved_messages", `cftest_sm_${TS}`,
    { text: "cftest saved message", _cftest: true },
    "TEST", "CF: deletes all docs in users/{uid}/saved_messages");

  await setSubcollection(`users/${BYSTANDER_UID}`, "saved_messages", `cftest_sm_byst_${TS}`,
    { text: "cftest bystander saved message", _cftest: true },
    "BYSTANDER", "must survive untouched");

  // notifPrefs/settings (single doc, point-delete)
  await setSubcollection(`users/${TEST_UID}`, "notifPrefs", "settings",
    { enabled: true, _cftest: true },
    "TEST", "CF: point-delete users/{uid}/notifPrefs/settings");

  await setSubcollection(`users/${BYSTANDER_UID}`, "notifPrefs", "settings",
    { enabled: true, _cftest: true },
    "BYSTANDER", "must survive untouched");

  // deadlines
  await setSubcollection(`users/${TEST_UID}`, "deadlines", `cftest_dl_${TS}`,
    { title: "cftest deadline", _cftest: true },
    "TEST", "CF: deletes all docs in users/{uid}/deadlines");

  await setSubcollection(`users/${BYSTANDER_UID}`, "deadlines", `cftest_dl_byst_${TS}`,
    { title: "cftest bystander deadline", _cftest: true },
    "BYSTANDER", "must survive untouched");

  // saved_items
  await setSubcollection(`users/${TEST_UID}`, "saved_items", `cftest_si_${TS}`,
    { item: "cftest saved item", _cftest: true },
    "TEST", "CF: deletes all docs in users/{uid}/saved_items");

  await setSubcollection(`users/${BYSTANDER_UID}`, "saved_items", `cftest_si_byst_${TS}`,
    { item: "cftest bystander saved item", _cftest: true },
    "BYSTANDER", "must survive untouched");

  // blocks forward (users/{uid}/blocks/{targetUid})
  await setSubcollection(`users/${TEST_UID}`, "blocks", `cftest_blocked_${TS}`,
    { targetUid: `cftest_blocked_${TS}`, _cftest: true },
    "TEST", "CF: deletes all docs in users/{uid}/blocks (forward blocks)");

  // blocks reverse: another user blocks TEST_UID — field: targetUid
  // (collectionGroup query: collectionGroup('blocks').where('targetUid','==',uid))
  await setSubcollection(`users/${BYSTANDER_UID}`, "blocks", `cftest_rev_${TS}`,
    { targetUid: TEST_UID, _cftest: true },
    "TEST",
    "CF: blocks_reverse — collectionGroup('blocks').where('targetUid','==',uid) — this doc gets deleted"
  );

  // invitations received (users/{uid}/invitations/{invId})
  await setSubcollection(`users/${TEST_UID}`, "invitations", `cftest_inv_${TS}`,
    { fromUid: BYSTANDER_UID, _cftest: true },
    "TEST", "CF: deletes all docs in users/{uid}/invitations");

  // user_rsvps
  await setSubcollection(`user_rsvps/${TEST_UID}`, "meetups", `cftest_rsvp_${TS}`,
    { meetupId: `cftest_meet_createdby_${TS}`, _cftest: true },
    "TEST", "CF: deletes all docs in user_rsvps/{uid}/meetups");

  await setSubcollection(`user_rsvps/${BYSTANDER_UID}`, "meetups", `cftest_rsvp_byst_${TS}`,
    { meetupId: `cftest_meet_byst_${TS}`, _cftest: true },
    "BYSTANDER", "must survive untouched");

  // endorsements (collectionGroup: local_services/{lsId}/endorsements/{uid})
  // field: uid == endorser uid
  await setSubcollection(`local_services/${LS_OTHER_ID}`, "endorsements", TEST_UID,
    { uid: TEST_UID, _cftest: true },
    "TEST",
    "CF: collectionGroup('endorsements').where('uid','==',uid) — doc ID = uid"
  );

  await setSubcollection(`local_services/${LS_OTHER_ID}`, "endorsements", BYSTANDER_UID,
    { uid: BYSTANDER_UID, _cftest: true },
    "BYSTANDER", "must survive untouched");

  // invitations sent (collectionGroup: any/{parentId}/invitations/{id})
  // field: invitedById == uid
  await setSubcollection(`outbound_invitations/${INV_OUT_TEST}`, "invitations", `cftest_sent_${TS}`,
    { invitedById: TEST_UID, _cftest: true },
    "TEST",
    "CF: collectionGroup('invitations').where('invitedById','==',uid) — RETAINED by default policy"
  );

  await setSubcollection(`outbound_invitations/${INV_OUT_BYST}`, "invitations", `cftest_sent_byst_${TS}`,
    { invitedById: BYSTANDER_UID, _cftest: true },
    "BYSTANDER", "must survive untouched");

  // ── groups — memberIds array-contains, memberCount, memberActivity ──────────
  await set("groups", GROUP_ID, {
    memberIds:   [TEST_UID, BYSTANDER_UID],
    memberCount: 2,
    name:        "CFTEST Group",
    createdAt:   now,
    _cftest:     true,
  }, "SHARED",
    "CF: arrayRemove(TEST_UID) from memberIds + memberCount--; group doc survives"
  );

  await setSubcollection(`groups/${GROUP_ID}`, "memberActivity", TEST_UID,
    { lastSeen: now, _cftest: true },
    "TEST",
    "CF: point-delete groups/{gid}/memberActivity/{uid}"
  );

  await setSubcollection(`groups/${GROUP_ID}`, "memberActivity", BYSTANDER_UID,
    { lastSeen: now, _cftest: true },
    "BYSTANDER", "must survive untouched");

  // ════════════════════════════════════════════════════════════════════════════
  // PHASE 3 — Conversations (DM messages)
  // ════════════════════════════════════════════════════════════════════════════

  // Conversation doc — both users in participants array
  await set("conversations", CONV_ID, {
    participants: [TEST_UID, BYSTANDER_UID],
    lastMessage:  "cftest message",
    createdAt:    now,
    _cftest:      true,
  }, "SHARED",
    "CF: arrayRemove(TEST_UID) from participants; doc deleted only if participants empty"
  );

  // TEST_UID's message — INVARIANT: always anonymised, NEVER hard-deleted
  // fields: senderId, senderName, senderAvatar, message (from realtime_dm_service.dart:214)
  await setSubcollection(`conversations/${CONV_ID}`, "messages", `cftest_msg_test_${TS}`,
    {
      senderId:    TEST_UID,
      senderName:  "CFTEST User",
      senderAvatar: "https://placeholder.invalid/cftest.jpg",
      message:     "cftest test message hello",
      sentAt:      now,
      _cftest:     true,
    },
    "TEST",
    "CF: ALWAYS anonymised (senderId/senderName/senderAvatar→null, message→[deleted]) regardless of authored_content switch"
  );

  // BYSTANDER's message in same conversation — must be completely untouched
  await setSubcollection(`conversations/${CONV_ID}`, "messages", `cftest_msg_byst_${TS}`,
    {
      senderId:    BYSTANDER_UID,
      senderName:  "CFTEST Bystander",
      senderAvatar: "https://placeholder.invalid/cftest_byst.jpg",
      message:     "cftest bystander message hey there",
      sentAt:      now,
      _cftest:     true,
    },
    "BYSTANDER",
    "INVARIANT proof: bystander's message in SAME conversation must remain fully intact after TEST deletion"
  );

  // ════════════════════════════════════════════════════════════════════════════
  // PHASE 4 — Storage
  // All files contain a placeholder byte payload and are real GCS objects.
  //
  // storage_prefix_delete: profile_photos/{uid}/ + marketplace_images/{uid}/
  //   (uid IS the directory prefix — entire directory is wiped)
  //
  // storage_dm_media: dm_images/{convId}/, dm_documents/{convId}/,
  //   voice_notes/dm/{convId}/
  //   Filter: filename.startsWith(uid + "_")
  //
  // storage_group_media: group_images/{groupId}/, group_documents/{groupId}/,
  //   voice_notes/group/{groupId}/
  //   Filter: filename.startsWith(uid + "_") OR filename.startsWith("thread_" + uid + "_")
  // ════════════════════════════════════════════════════════════════════════════

  // ── storage_prefix_delete ─────────────────────────────────────────────────

  // profile_photos/{uid}/ — TEST
  await uploadFile(`profile_photos/${TEST_UID}/avatar.jpg`, "TEST",
    "CF: entire prefix profile_photos/{uid}/ deleted");
  await uploadFile(`profile_photos/${TEST_UID}/avatar_thumb.jpg`, "TEST",
    "CF: entire prefix deleted (second file in same prefix)");

  // profile_photos — BYSTANDER (different prefix — must survive)
  await uploadFile(`profile_photos/${BYSTANDER_UID}/avatar.jpg`, "BYSTANDER",
    "must survive — bystander has different uid prefix");

  // marketplace_images/{uid}/ — TEST
  await uploadFile(`marketplace_images/${TEST_UID}/item1.jpg`, "TEST",
    "CF: entire prefix marketplace_images/{uid}/ deleted");

  // marketplace_images — BYSTANDER
  await uploadFile(`marketplace_images/${BYSTANDER_UID}/item1.jpg`, "BYSTANDER",
    "must survive — bystander has different uid prefix");

  // ── storage_dm_media — filter: filename.startsWith(uid + "_") ───────────

  // dm_images/{convId}/{uid}_{ts}.jpg — TEST
  await uploadFile(`dm_images/${CONV_ID}/${TEST_UID}_${FILE_TS}.jpg`, "TEST",
    `CF: dm_images/{convId}/ filtered by filename.startsWith('${TEST_UID}_')`);

  // dm_images — BYSTANDER (same convId prefix, different uid in filename)
  await uploadFile(`dm_images/${CONV_ID}/${BYSTANDER_UID}_${FILE_TS}.jpg`, "BYSTANDER",
    "uid-prefix-collision proof: same convId prefix, bystander uid in filename — must survive");

  // dm_documents/{convId}/{uid}_{ts}.pdf — TEST
  await uploadFile(`dm_documents/${CONV_ID}/${TEST_UID}_${FILE_TS}.pdf`, "TEST",
    "CF: dm_documents/{convId}/ filtered by filename.startsWith(uid + '_')");

  // dm_documents — BYSTANDER
  await uploadFile(`dm_documents/${CONV_ID}/${BYSTANDER_UID}_${FILE_TS}.pdf`, "BYSTANDER",
    "must survive — bystander uid in filename");

  // voice_notes/dm/{convId}/{uid}_{ts}.m4a — TEST
  await uploadFile(`voice_notes/dm/${CONV_ID}/${TEST_UID}_${FILE_TS}.m4a`, "TEST",
    "CF: voice_notes/dm/{convId}/ filtered by filename.startsWith(uid + '_')");

  // voice_notes/dm — BYSTANDER
  await uploadFile(`voice_notes/dm/${CONV_ID}/${BYSTANDER_UID}_${FILE_TS}.m4a`, "BYSTANDER",
    "must survive — bystander uid in filename");

  // ── storage_group_media — filter: uid + "_" OR "thread_" + uid + "_" ─────

  // group_images/{groupId}/{uid}_{ts}.jpg — TEST (direct post)
  await uploadFile(`group_images/${GROUP_ID}/${TEST_UID}_${FILE_TS}.jpg`, "TEST",
    "CF: group_images/{groupId}/ filtered by filename.startsWith(uid + '_')");

  // group_images — TEST thread reply
  await uploadFile(`group_images/${GROUP_ID}/thread_${TEST_UID}_${FILE_TS}.jpg`, "TEST",
    "CF: group_images/{groupId}/ filtered by filename.startsWith('thread_' + uid + '_')");

  // group_images — BYSTANDER direct post (same groupId prefix, different uid)
  await uploadFile(`group_images/${GROUP_ID}/${BYSTANDER_UID}_${FILE_TS}.jpg`, "BYSTANDER",
    "uid-prefix-collision proof: same groupId prefix, bystander uid — must survive");

  // group_images — BYSTANDER thread reply
  await uploadFile(`group_images/${GROUP_ID}/thread_${BYSTANDER_UID}_${FILE_TS}.jpg`, "BYSTANDER",
    "uid-prefix-collision proof: thread_ variant, bystander uid — must survive");

  // group_documents/{groupId}/{uid}_{ts}.pdf — TEST
  await uploadFile(`group_documents/${GROUP_ID}/${TEST_UID}_${FILE_TS}.pdf`, "TEST",
    "CF: group_documents/{groupId}/ filtered by filename.startsWith(uid + '_')");

  // group_documents — BYSTANDER
  await uploadFile(`group_documents/${GROUP_ID}/${BYSTANDER_UID}_${FILE_TS}.pdf`, "BYSTANDER",
    "must survive — bystander uid in filename");

  // voice_notes/group/{groupId}/{uid}_{ts}.m4a — TEST
  await uploadFile(`voice_notes/group/${GROUP_ID}/${TEST_UID}_${FILE_TS}.m4a`, "TEST",
    "CF: voice_notes/group/{groupId}/ filtered by filename.startsWith(uid + '_')");

  // voice_notes/group — BYSTANDER
  await uploadFile(`voice_notes/group/${GROUP_ID}/${BYSTANDER_UID}_${FILE_TS}.m4a`, "BYSTANDER",
    "must survive — bystander uid in filename");
}

// ── Manifest printer ──────────────────────────────────────────────────────────

function printManifest() {
  const SEP   = "─".repeat(72);
  const WIDE  = "═".repeat(72);

  console.log(`\n${WIDE}`);
  console.log(`  SEED MANIFEST — huddl-connect PRODUCTION`);
  console.log(WIDE);
  console.log(`  TEST_UID      = ${manifest.testUid}`);
  console.log(`  BYSTANDER_UID = ${manifest.bystanderUid}`);
  console.log(`  CONV_ID       = ${manifest.convId}`);
  console.log(`  GROUP_ID      = ${manifest.groupId}`);
  console.log(WIDE);

  // ── Firestore ──────────────────────────────────────────────────────────────
  const testFS  = manifest.firestore.filter(e => e.owner === "TEST");
  const bystFS  = manifest.firestore.filter(e => e.owner === "BYSTANDER");
  const shrdFS  = manifest.firestore.filter(e => e.owner === "SHARED");

  console.log(`\n  FIRESTORE — TEST_UID data (${testFS.length} docs)`);
  console.log(`  (these should be deleted / anonymised after CF run)\n`);
  testFS.forEach(e => {
    console.log(`    [TEST]  ${e.path}`);
    if (e.note) console.log(`            → ${e.note}`);
  });

  console.log(`\n${SEP}`);
  console.log(`\n  FIRESTORE — BYSTANDER_UID data (${bystFS.length} docs)`);
  console.log(`  (these must ALL survive COMPLETELY UNTOUCHED)\n`);
  bystFS.forEach(e => {
    console.log(`    [BYST]  ${e.path}`);
    if (e.note) console.log(`            → ${e.note}`);
  });

  console.log(`\n${SEP}`);
  console.log(`\n  FIRESTORE — SHARED structures (${shrdFS.length} docs)`);
  console.log(`  (TEST_UID removed; doc survives for bystander)\n`);
  shrdFS.forEach(e => {
    console.log(`    [SHRD]  ${e.path}`);
    if (e.note) console.log(`            → ${e.note}`);
  });

  // ── Storage ────────────────────────────────────────────────────────────────
  const testST  = manifest.storage.filter(e => e.owner === "TEST");
  const bystST  = manifest.storage.filter(e => e.owner === "BYSTANDER");

  console.log(`\n${SEP}`);
  console.log(`\n  STORAGE — TEST_UID files (${testST.length} files)`);
  console.log(`  Bucket: ${STORAGE_BUCKET}`);
  console.log(`  (these should be deleted after CF run)\n`);
  testST.forEach(e => {
    console.log(`    [TEST]  gs://${STORAGE_BUCKET}/${e.path}`);
    if (e.note) console.log(`            → ${e.note}`);
  });

  console.log(`\n${SEP}`);
  console.log(`\n  STORAGE — BYSTANDER files (${bystST.length} files)`);
  console.log(`  (these must ALL survive COMPLETELY UNTOUCHED)\n`);
  bystST.forEach(e => {
    console.log(`    [BYST]  gs://${STORAGE_BUCKET}/${e.path}`);
    if (e.note) console.log(`            → ${e.note}`);
  });

  // ── Summary ────────────────────────────────────────────────────────────────
  const totalTest = testFS.length + testST.length;
  const totalByst = bystFS.length + bystST.length;
  const totalShrd = shrdFS.length;

  console.log(`\n${WIDE}`);
  console.log(`  SUMMARY`);
  console.log(WIDE);
  console.log(`  Firestore docs written : ${manifest.firestore.length}`);
  console.log(`    TEST       : ${testFS.length}`);
  console.log(`    BYSTANDER  : ${bystFS.length}`);
  console.log(`    SHARED     : ${shrdFS.length}`);
  console.log(`  Storage files written  : ${manifest.storage.length}`);
  console.log(`    TEST       : ${testST.length}`);
  console.log(`    BYSTANDER  : ${bystST.length}`);
  console.log(`  ─────────────────────────────────────────`);
  console.log(`  Total TEST locations   : ${totalTest} (should be gone/anonymised post-CF)`);
  console.log(`  Total BYSTANDER items  : ${totalByst + totalShrd} (must ALL survive)`);
  console.log(WIDE);

  // ── Machine-readable JSON dump ────────────────────────────────────────────
  console.log("\n  MACHINE-READABLE JSON (save this for post-run diff):\n");
  console.log(JSON.stringify({
    testUid:      manifest.testUid,
    bystanderUid: manifest.bystanderUid,
    convId:       manifest.convId,
    groupId:      manifest.groupId,
    timestamp:    TS,
    bucket:       STORAGE_BUCKET,
    firestore: manifest.firestore,
    storage:   manifest.storage,
  }, null, 2));

  if (manifest.errors.length > 0) {
    console.error(`\n  ERRORS (${manifest.errors.length}):`);
    manifest.errors.forEach(e => console.error(`    ${e}`));
  }

  console.log(`\n${WIDE}`);
  console.log(`  NEXT STEP: invoke the CF as TEST_UID, then verify this manifest.`);
  console.log(`  DO NOT delete anything manually — let the CF handle it.`);
  console.log(WIDE + "\n");
}

// ── Entry point ───────────────────────────────────────────────────────────────

(async () => {
  try {
    await seedAll();
    console.log("\nSeed complete.\n");
    printManifest();
    process.exit(0);
  } catch (err) {
    console.error("\nFATAL ERROR during seed:");
    console.error(err);
    console.error("\nPartial manifest at time of failure:");
    printManifest();
    process.exit(1);
  }
})();
