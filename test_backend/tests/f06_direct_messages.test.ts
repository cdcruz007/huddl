/**
 * Huddl — F-06 direct_messages Dead Collection Lock Tests
 *
 * Tests the F-06 fix to match /direct_messages/{messageId}:
 *
 *   BEFORE (broken): allow create/update permitted any authenticated user
 *     to write to a collection that has no live write path — orphaned
 *     sendDirectMessage() method with zero call sites.
 *
 *   AFTER (F-06): create/update locked to if false.
 *     read:   retained, scoped to conversation participants (legacy access)
 *     delete: retained, scoped to senderId == auth.uid (legacy unsend)
 *
 * Seed personas:
 *   alice  — participant in CONV_ID, sender of LEGACY_MSG_ID
 *   bob    — participant in CONV_ID, recipient
 *   carol  — NOT a participant in CONV_ID
 *
 * Seed docs:
 *   conversations/conv_f06  — participants: [alice, bob]
 *   direct_messages/msg_f06 — conversationId: 'conv_f06', senderId: alice
 *
 * Tests (8):
 *
 *   READ
 *   T-F06-read-participant    — alice reads msg_f06 (alice in participants) → SUCCEEDS
 *   T-F06-read-non-participant — carol reads msg_f06 (carol not in participants) → DENIED
 *   T-F06-read-unauthed       — unauthenticated read → DENIED
 *
 *   CREATE (locked)
 *   T-F06-create-denied       — alice attempts to create a new direct_message → DENIED
 *
 *   UPDATE (locked)
 *   T-F06-update-denied       — alice attempts to update msg_f06 → DENIED
 *
 *   DELETE (legacy, scoped)
 *   T-F06-delete-sender       — alice deletes her own msg_f06 → SUCCEEDS
 *   T-F06-delete-non-sender   — bob attempts to delete alice's msg_f06 → DENIED
 *   T-F06-delete-unauthed     — unauthenticated delete → DENIED
 *
 * Run (from test_backend/):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 npx jest \
 *     --testPathPattern='f06_direct_messages' \
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
  deleteDoc,
  collection,
} from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

// ─── Constants ────────────────────────────────────────────────────────────────

const PROJECT_ID   = "huddl-test-project";
const RULES_PATH   = path.resolve(__dirname, "../../firestore.rules");

const ALICE_UID    = "alice_f06_uid";
const BOB_UID      = "bob_f06_uid";
const CAROL_UID    = "carol_f06_uid";

const CONV_ID      = "conv_f06";
const MSG_ID       = "msg_f06";

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

// ─── Seed ─────────────────────────────────────────────────────────────────────

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // Conversation doc — alice and bob are participants
    await setDoc(doc(db, "conversations", CONV_ID), {
      participants: [ALICE_UID, BOB_UID],
      lastMessage: "hey",
      lastMessageAt: new Date(),
    });

    // Legacy direct_message doc — alice sent it
    await setDoc(doc(db, "direct_messages", MSG_ID), {
      conversationId: CONV_ID,
      senderId:       ALICE_UID,
      senderName:     "Alice",
      message:        "legacy message",
      timestamp:      new Date(),
      status:         "sent",
      type:           "text",
    });
  });
}

// ─── READ tests ───────────────────────────────────────────────────────────────

describe("F-06 direct_messages — READ (legacy, participant-scoped)", () => {
  beforeEach(seed);

  it("T-F06-read-participant: alice reads own legacy message → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      getDoc(doc(alice.firestore(), "direct_messages", MSG_ID))
    );
  });

  it("T-F06-read-participant-bob: bob reads message in his conversation → SUCCEEDS", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertSucceeds(
      getDoc(doc(bob.firestore(), "direct_messages", MSG_ID))
    );
  });

  it("T-F06-read-non-participant: carol reads message she's not party to → DENIED", async () => {
    const carol = testEnv.authenticatedContext(CAROL_UID);
    await assertFails(
      getDoc(doc(carol.firestore(), "direct_messages", MSG_ID))
    );
  });

  it("T-F06-read-unauthed: unauthenticated read → DENIED", async () => {
    const unauthed = testEnv.unauthenticatedContext();
    await assertFails(
      getDoc(doc(unauthed.firestore(), "direct_messages", MSG_ID))
    );
  });
});

// ─── CREATE tests (locked) ────────────────────────────────────────────────────

describe("F-06 direct_messages — CREATE (locked: if false)", () => {
  it("T-F06-create-denied: alice creates a new direct_message → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      addDoc(collection(alice.firestore(), "direct_messages"), {
        conversationId: CONV_ID,
        senderId:       ALICE_UID,
        senderName:     "Alice",
        message:        "should not be allowed",
        timestamp:      new Date(),
        status:         "sent",
        type:           "text",
      })
    );
  });

  it("T-F06-create-denied-unauthed: unauthenticated create → DENIED", async () => {
    const unauthed = testEnv.unauthenticatedContext();
    await assertFails(
      addDoc(collection(unauthed.firestore(), "direct_messages"), {
        conversationId: CONV_ID,
        senderId:       ALICE_UID,
        message:        "unauthenticated write attempt",
      })
    );
  });
});

// ─── UPDATE tests (locked) ────────────────────────────────────────────────────

describe("F-06 direct_messages — UPDATE (locked: if false)", () => {
  beforeEach(seed);

  it("T-F06-update-denied-sender: alice updates her own legacy message → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      updateDoc(doc(alice.firestore(), "direct_messages", MSG_ID), {
        message: "edited message",
      })
    );
  });

  it("T-F06-update-denied-reaction: bob adds a reaction → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      updateDoc(doc(bob.firestore(), "direct_messages", MSG_ID), {
        reactions: { [BOB_UID]: "👍" },
      })
    );
  });
});

// ─── DELETE tests (legacy, sender-scoped) ─────────────────────────────────────

describe("F-06 direct_messages — DELETE (legacy, sender-scoped)", () => {
  beforeEach(seed);

  it("T-F06-delete-sender: alice deletes her own legacy message → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      deleteDoc(doc(alice.firestore(), "direct_messages", MSG_ID))
    );
  });

  it("T-F06-delete-non-sender: bob deletes alice's message → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      deleteDoc(doc(bob.firestore(), "direct_messages", MSG_ID))
    );
  });

  it("T-F06-delete-unauthed: unauthenticated delete → DENIED", async () => {
    const unauthed = testEnv.unauthenticatedContext();
    await assertFails(
      deleteDoc(doc(unauthed.firestore(), "direct_messages", MSG_ID))
    );
  });
});
