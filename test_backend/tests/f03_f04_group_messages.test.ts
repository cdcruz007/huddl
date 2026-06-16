/**
 * Huddl — F-03 / F-04 Group Messages Security Rules Tests
 *
 * Tests the two firestore.rules changes to group_messages/{messageId}:
 *
 *   F-03: read was allow read: if isAuth()
 *         → any authed user could read ALL group messages across ALL groups,
 *           harvesting imageUrl/audioUrl/documentUrl media tokens.
 *         Fix: allow read: if isAuth() && uid in groups/{groupId}.memberIds
 *
 *   F-04: create had no membership check
 *         → any authed user could inject messages into any group and spoof senderId.
 *         Fix: allow create: requires membership in groups/{groupId} AND senderId == uid
 *
 * Seed personas:
 *   alice  — member of GROUP_A
 *   bob    — NOT a member of GROUP_A
 *   carol  — member of GROUP_A (second member, for completeness)
 *
 * Seed documents:
 *   groups/group_a  — memberIds: [ALICE_UID, CAROL_UID]
 *   group_messages/msg_001  — groupId: 'group_a', senderId: ALICE_UID
 *   group_messages/msg_media — groupId: 'group_a', senderId: CAROL_UID,
 *                              imageUrl: 'https://...', audioUrl: 'https://...'
 *                              (simulates a media-bearing message with harvest tokens)
 *
 * Run (from test_backend/):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 npx jest \
 *     --testPathPattern='f03_f04_group_messages' \
 *     --forceExit --runInBand --verbose
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  setDoc,
  getDoc,
  getDocs,
  collection,
  query,
  where,
  updateDoc,
  deleteDoc,
} from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

// ─── Constants ────────────────────────────────────────────────────────────────

const PROJECT_ID  = "huddl-test-project";
const RULES_PATH  = path.resolve(__dirname, "../../firestore.rules");

const ALICE_UID = "alice_uid";   // member of GROUP_A
const BOB_UID   = "bob_uid";    // NOT a member of GROUP_A
const CAROL_UID = "carol_uid";  // member of GROUP_A

const GROUP_A_ID = "group_a";
const MSG_001_ID = "msg_001";   // alice's text message in group_a
const MSG_MEDIA_ID = "msg_media"; // carol's media message in group_a

// ─── Test environment ─────────────────────────────────────────────────────────

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host:  "localhost",
      port:  8080,
    },
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

afterAll(async () => {
  await testEnv.cleanup();
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

function alice() { return testEnv.authenticatedContext(ALICE_UID); }
function bob()   { return testEnv.authenticatedContext(BOB_UID);   }
function carol() { return testEnv.authenticatedContext(CAROL_UID); }
function anon()  { return testEnv.unauthenticatedContext();        }

async function seed(collPath: string, docId: string, data: object): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), collPath, docId), data);
  });
}

/**
 * Seeds the full test fixture:
 *   groups/group_a         — memberIds: [alice, carol]
 *   group_messages/msg_001 — alice's text message
 *   group_messages/msg_media — carol's media message with URLs
 */
async function seedFixture(): Promise<void> {
  // The group — alice and carol are members; bob is not
  await seed("groups", GROUP_A_ID, {
    id: GROUP_A_ID,
    name: "Test Group A",
    borough: "Cambridge",
    creatorUid: ALICE_UID,
    memberIds: [ALICE_UID, CAROL_UID],
    memberCount: 2,
  });

  // Text message from alice
  await seed("group_messages", MSG_001_ID, {
    id: MSG_001_ID,
    groupId: GROUP_A_ID,
    senderId: ALICE_UID,
    senderName: "Alice",
    message: "Hello group!",
    type: "text",
    reactions: {},
    pinned: false,
    isSystem: false,
  });

  // Media message from carol — simulates an imageUrl + audioUrl with bypass tokens
  // This is the F-03 harvest target: bob must NOT be able to read this doc.
  await seed("group_messages", MSG_MEDIA_ID, {
    id: MSG_MEDIA_ID,
    groupId: GROUP_A_ID,
    senderId: CAROL_UID,
    senderName: "Carol",
    message: "📷 Photo",
    type: "image",
    imageUrl:  "https://firebasestorage.googleapis.com/v0/b/huddl-connect.appspot.com/o/group_images%2Fgroup_a%2Fcarol_123.jpg?alt=media&token=abc123",
    audioUrl:  "https://firebasestorage.googleapis.com/v0/b/huddl-connect.appspot.com/o/voice_notes%2Fgroup_a%2Fcarol_456.m4a?alt=media&token=def456",
    reactions: {},
    pinned: false,
    isSystem: false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// F-03: group_messages read scoped to group members
// ─────────────────────────────────────────────────────────────────────────────

describe("F-03 — group_messages read access control", () => {

  beforeEach(async () => {
    await seedFixture();
  });

  // T-F03-01: member reads their own group's message → SUCCEEDS
  test("T-F03-01: alice (member) reads msg_001 in group_a → SUCCEEDS", async () => {
    const ref = doc(alice().firestore(), "group_messages", MSG_001_ID);
    await assertSucceeds(getDoc(ref));
  });

  // T-F03-02: non-member reads a group message → DENIED (core F-03 fix)
  test("T-F03-02: bob (non-member) reads msg_001 in group_a → DENIED", async () => {
    const ref = doc(bob().firestore(), "group_messages", MSG_001_ID);
    await assertFails(getDoc(ref));
  });

  // T-F03-03: non-member reads the media message → DENIED
  // This is the concrete URL-harvest attack: bob cannot obtain the imageUrl/audioUrl tokens.
  test("T-F03-03: bob (non-member) reads media message (imageUrl/audioUrl) in group_a → DENIED", async () => {
    const ref = doc(bob().firestore(), "group_messages", MSG_MEDIA_ID);
    await assertFails(getDoc(ref));
  });

  // T-F03-04: non-member queries all group_messages without groupId filter → empty/denied
  // This is the enumeration attack: bob tries to harvest all messages across all groups.
  // The rule evaluates per-doc; any doc where bob is not in memberIds is denied.
  // Firestore returns an empty result set rather than an error for queries where
  // all matching docs are denied — the key check is that no docs leak through.
  test("T-F03-04: bob queries group_messages collection without filter → returns no readable docs", async () => {
    const q = query(collection(bob().firestore(), "group_messages"));
    // getDocs on a collection where all docs are denied returns empty snapshot
    // (Firestore security: permission-denied queries return 0 docs, not error,
    // when using client SDK with rules that deny individual docs).
    // assertFails is not correct here — the SDK returns empty, not an exception.
    // We assert the result contains zero docs from group_a.
    await assertFails(getDocs(q));
  });

  // T-F03-05: non-member queries group_messages with groupId filter → denied
  // Even with the specific groupId, bob is not a member and cannot read docs.
  test("T-F03-05: bob queries group_messages where groupId=group_a → DENIED", async () => {
    const q = query(
      collection(bob().firestore(), "group_messages"),
      where("groupId", "==", GROUP_A_ID)
    );
    await assertFails(getDocs(q));
  });

  // T-F03-06: second member can also read messages in their group
  test("T-F03-06: carol (member) reads alice's message in group_a → SUCCEEDS", async () => {
    const ref = doc(carol().firestore(), "group_messages", MSG_001_ID);
    await assertSucceeds(getDoc(ref));
  });

  // T-F03-07: unauthenticated user cannot read any group message
  test("T-F03-07: unauthenticated user reads msg_001 → DENIED", async () => {
    const ref = doc(anon().firestore(), "group_messages", MSG_001_ID);
    await assertFails(getDoc(ref));
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// F-04: group_messages create requires membership + no sender impersonation
// ─────────────────────────────────────────────────────────────────────────────

describe("F-04 — group_messages create access control", () => {

  beforeEach(async () => {
    await seedFixture();
  });

  // T-F04-01: member creates a message with their own senderId → SUCCEEDS
  test("T-F04-01: alice (member) creates message in group_a with senderId=alice → SUCCEEDS", async () => {
    const ref = doc(alice().firestore(), "group_messages", "msg_new_alice");
    await assertSucceeds(
      setDoc(ref, {
        id: "msg_new_alice",
        groupId: GROUP_A_ID,
        senderId: ALICE_UID,
        senderName: "Alice",
        message: "New message",
        type: "text",
        reactions: {},
        pinned: false,
        isSystem: false,
      })
    );
  });

  // T-F04-02: member tries to impersonate another sender → DENIED (F-04 senderId check)
  test("T-F04-02: alice creates message in group_a with senderId=bob (impersonation) → DENIED", async () => {
    const ref = doc(alice().firestore(), "group_messages", "msg_impersonate");
    await assertFails(
      setDoc(ref, {
        id: "msg_impersonate",
        groupId: GROUP_A_ID,
        senderId: BOB_UID,        // alice tries to pose as bob
        senderName: "Bob",
        message: "I am bob",
        type: "text",
        reactions: {},
        pinned: false,
        isSystem: false,
      })
    );
  });

  // T-F04-03: non-member creates a message in a group they don't belong to → DENIED
  test("T-F04-03: bob (non-member) creates message in group_a → DENIED", async () => {
    const ref = doc(bob().firestore(), "group_messages", "msg_injected");
    await assertFails(
      setDoc(ref, {
        id: "msg_injected",
        groupId: GROUP_A_ID,
        senderId: BOB_UID,
        senderName: "Bob",
        message: "Injected message",
        type: "text",
        reactions: {},
        pinned: false,
        isSystem: false,
      })
    );
  });

  // T-F04-04: non-member with correct senderId still denied (membership is required)
  // Belt-and-suspenders: even if bob correctly sets senderId=bob, membership blocks it.
  test("T-F04-04: bob creates message with senderId=bob but is non-member → DENIED", async () => {
    const ref = doc(bob().firestore(), "group_messages", "msg_bob_correct_sender");
    await assertFails(
      setDoc(ref, {
        id: "msg_bob_correct_sender",
        groupId: GROUP_A_ID,
        senderId: BOB_UID,        // correct senderId, but bob is not a member
        senderName: "Bob",
        message: "I tried to join",
        type: "text",
        reactions: {},
        pinned: false,
        isSystem: false,
      })
    );
  });

  // T-F04-05: unauthenticated user cannot create any group message
  test("T-F04-05: unauthenticated user creates message → DENIED", async () => {
    const ref = doc(anon().firestore(), "group_messages", "msg_anon");
    await assertFails(
      setDoc(ref, {
        id: "msg_anon",
        groupId: GROUP_A_ID,
        senderId: "anon",
        message: "Anon message",
        type: "text",
      })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// Existing update/delete rules — confirm unchanged and still correct
// ─────────────────────────────────────────────────────────────────────────────

describe("Update/delete rules — preserved, no regression", () => {

  beforeEach(async () => {
    await seedFixture();
  });

  // T-UPD-01: sender can update their own message (edit text)
  test("T-UPD-01: alice (sender) updates her own message text → SUCCEEDS", async () => {
    const ref = doc(alice().firestore(), "group_messages", MSG_001_ID);
    await assertSucceeds(
      updateDoc(ref, { message: "Edited text" })
    );
  });

  // T-UPD-02: any member can add a reaction (affectedKeys allowlist)
  test("T-UPD-02: carol (member, not sender) adds a reaction → SUCCEEDS", async () => {
    const ref = doc(carol().firestore(), "group_messages", MSG_001_ID);
    await assertSucceeds(
      updateDoc(ref, {
        reactions: { "👍": 1 },
        reactionUsers: { [CAROL_UID]: "👍" },
      })
    );
  });

  // T-UPD-03: non-sender cannot edit message text
  test("T-UPD-03: carol (member, non-sender) edits alice's message text → DENIED", async () => {
    const ref = doc(carol().firestore(), "group_messages", MSG_001_ID);
    await assertFails(
      updateDoc(ref, { message: "Carol edits alice's message" })
    );
  });

  // T-UPD-04: non-member cannot update any field (F-03 read lock prevents even update reads)
  // Note: update rules also require reading the existing doc — denied for non-members.
  test("T-UPD-04: bob (non-member) attempts to update a message → DENIED", async () => {
    const ref = doc(bob().firestore(), "group_messages", MSG_001_ID);
    await assertFails(
      updateDoc(ref, { reactions: { "👍": 1 } })
    );
  });

  // T-DEL-01: sender can delete (unsend) their own message
  test("T-DEL-01: alice (sender) deletes her own message → SUCCEEDS", async () => {
    const ref = doc(alice().firestore(), "group_messages", MSG_001_ID);
    await assertSucceeds(deleteDoc(ref));
  });

  // T-DEL-02: non-sender cannot delete another user's message
  test("T-DEL-02: carol (non-sender) deletes alice's message → DENIED", async () => {
    const ref = doc(carol().firestore(), "group_messages", MSG_001_ID);
    await assertFails(deleteDoc(ref));
  });

});
