/**
 * Huddl — F-01 Notifications Security Rules Tests
 *
 * Tests the F-01 fix to the notifications/{notificationId} rule:
 *
 *   BEFORE (broken — three compounding bugs):
 *     1. read:   checked resource.data.recipientId  — field is 'userId' → always DENIED
 *     2. create: checked request.resource.data.senderId — field never written by _write() → always DENIED
 *     3. update: checked resource.data.recipientId  — field is 'userId' → always DENIED
 *                affectedKeys(['isRead','readAt'])   — field is 'read'  → always DENIED
 *
 *   AFTER (F-01):
 *     read:   resource.data.userId == auth.uid
 *     create: senderId == auth.uid
 *             + keys().hasOnly([known schema fields])
 *     update: resource.data.userId == auth.uid
 *             + affectedKeys().hasOnly(['read'])
 *     delete: if false (unchanged)
 *
 * Scenarios (10 tests):
 *
 *   READ
 *   T-F01-read-own        — alice reads her own notif (userId==alice)    → SUCCEEDS
 *   T-F01-read-other      — alice reads bob's notif (userId==bob)        → DENIED
 *   T-F01-read-unauthed   — unauthenticated read of alice's notif        → DENIED
 *
 *   CREATE
 *   T-F01-create-legit    — alice writes notif to bob (senderId==alice)  → SUCCEEDS
 *                           (cross-user: userId=bob, senderId=alice)
 *   T-F01-create-spoofed  — alice writes with senderId==bob (spoofed)   → DENIED
 *   T-F01-create-no-sender — alice writes with no senderId field         → DENIED
 *   T-F01-create-extra-field — alice writes with extra unknown field     → DENIED
 *   T-F01-create-unauthed — unauthenticated create                       → DENIED
 *
 *   UPDATE (mark as read)
 *   T-F01-markread-own    — alice marks her own notif read               → SUCCEEDS
 *   T-F01-markread-other  — alice marks bob's notif read                 → DENIED
 *   T-F01-markread-body   — alice tries to edit title of own notif       → DENIED
 *
 * Seed personas:
 *   alice  — notif recipient (userId == ALICE_UID)
 *   bob    — different user
 *
 * Seed docs:
 *   notifications/notif_alice — userId: ALICE_UID, senderId: BOB_UID, read: false
 *   notifications/notif_bob   — userId: BOB_UID,   senderId: ALICE_UID, read: false
 *
 * Run (from test_backend/):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 npx jest \
 *     --testPathPattern='f01_notifications' \
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
  addDoc,
  updateDoc,
  collection,
  serverTimestamp,
} from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

// ─── Constants ────────────────────────────────────────────────────────────────

const PROJECT_ID = "huddl-test-project";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const ALICE_UID = "alice_f01_uid";
const BOB_UID   = "bob_f01_uid";

const NOTIF_ALICE_ID = "notif_alice_f01";
const NOTIF_BOB_ID   = "notif_bob_f01";

// ─── Test environment ─────────────────────────────────────────────────────────

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "localhost",
      port: 8080,
    },
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

afterAll(async () => {
  await testEnv.cleanup();
});

// ─── Seed helpers ─────────────────────────────────────────────────────────────

/** Seed two notification docs via admin bypass. */
async function seedNotifications() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // alice's notification (bob sent it)
    await setDoc(doc(db, "notifications", NOTIF_ALICE_ID), {
      userId:         ALICE_UID,
      senderId:       BOB_UID,
      type:           "new_dm",
      title:          "Bob",
      body:           "Hey Alice",
      read:           false,
      data:           { route: "/dm_chat", conversationId: "conv_001" },
      senderName:     "Bob",
      senderPhotoUrl: null,
      imageUrl:       null,
      createdAt:      new Date(),
    });

    // bob's notification (alice sent it)
    await setDoc(doc(db, "notifications", NOTIF_BOB_ID), {
      userId:         BOB_UID,
      senderId:       ALICE_UID,
      type:           "new_dm",
      title:          "Alice",
      body:           "Hey Bob",
      read:           false,
      data:           { route: "/dm_chat", conversationId: "conv_001" },
      senderName:     "Alice",
      senderPhotoUrl: null,
      imageUrl:       null,
      createdAt:      new Date(),
    });
  });
}

/** Valid notification payload from alice to bob (cross-user write). */
const validNotifAliceToBob = () => ({
  userId:         BOB_UID,
  senderId:       ALICE_UID,   // F-01: must match the writing user
  type:           "new_dm",
  title:          "Alice",
  body:           "Hey Bob",
  read:           false,
  data:           { route: "/dm_chat", conversationId: "conv_123" },
  senderName:     "Alice",
  senderPhotoUrl: null,
  imageUrl:       null,
  createdAt:      new Date(),
});

// ─── READ tests ───────────────────────────────────────────────────────────────

describe("F-01 Notifications — READ", () => {
  beforeEach(seedNotifications);

  it("T-F01-read-own: recipient reads own notification → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      getDoc(doc(alice.firestore(), "notifications", NOTIF_ALICE_ID))
    );
  });

  it("T-F01-read-other: alice reads bob's notification → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      getDoc(doc(alice.firestore(), "notifications", NOTIF_BOB_ID))
    );
  });

  it("T-F01-read-unauthed: unauthenticated read → DENIED", async () => {
    const unauthed = testEnv.unauthenticatedContext();
    await assertFails(
      getDoc(doc(unauthed.firestore(), "notifications", NOTIF_ALICE_ID))
    );
  });
});

// ─── CREATE tests ─────────────────────────────────────────────────────────────

describe("F-01 Notifications — CREATE", () => {
  it("T-F01-create-legit: alice writes notif to bob (cross-user) → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      addDoc(collection(alice.firestore(), "notifications"), validNotifAliceToBob())
    );
  });

  it("T-F01-create-spoofed: alice writes senderId == bob (identity spoof) → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    const spoofed = { ...validNotifAliceToBob(), senderId: BOB_UID };
    await assertFails(
      addDoc(collection(alice.firestore(), "notifications"), spoofed)
    );
  });

  it("T-F01-create-no-sender: alice writes with no senderId field → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    // Omit senderId — simulates old _write() schema before F-01 Dart fix
    const { senderId: _omitted, ...noSender } = validNotifAliceToBob();
    await assertFails(
      addDoc(collection(alice.firestore(), "notifications"), noSender)
    );
  });

  it("T-F01-create-extra-field: alice writes with extra unknown field → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    const extraField = { ...validNotifAliceToBob(), arbitraryField: "injected" };
    await assertFails(
      addDoc(collection(alice.firestore(), "notifications"), extraField)
    );
  });

  it("T-F01-create-unauthed: unauthenticated create → DENIED", async () => {
    const unauthed = testEnv.unauthenticatedContext();
    await assertFails(
      addDoc(collection(unauthed.firestore(), "notifications"), validNotifAliceToBob())
    );
  });
});

// ─── UPDATE tests ─────────────────────────────────────────────────────────────

describe("F-01 Notifications — UPDATE (mark read)", () => {
  beforeEach(seedNotifications);

  it("T-F01-markread-own: alice marks own notification read → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), "notifications", NOTIF_ALICE_ID), {
        read: true,
      })
    );
  });

  it("T-F01-markread-other: alice marks bob's notification read → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      updateDoc(doc(alice.firestore(), "notifications", NOTIF_BOB_ID), {
        read: true,
      })
    );
  });

  it("T-F01-markread-body: alice edits title of own notification → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      updateDoc(doc(alice.firestore(), "notifications", NOTIF_ALICE_ID), {
        title: "Injected title",
      })
    );
  });
});
