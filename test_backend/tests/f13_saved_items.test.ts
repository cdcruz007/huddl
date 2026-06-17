/**
 * Huddl — F-13 saved_items Rule Fix Tests
 *
 * Tests the F-13 fix: subcollection rule added + top-level lock.
 *
 *   BEFORE (broken):
 *     - users/{uid}/saved_items/{listingId} had NO rule → default-deny.
 *       Every user-facing op (save, unsave, list) was PERMISSION_DENIED.
 *     - Top-level saved_items/{docId} had a phantom rule checking
 *       resource.data.userId — a field that doesn't exist in the doc schema
 *       (schema is { listingId, savedAt } only), so it was effectively open
 *       to any authed caller who crafted a doc with uid: auth.uid.
 *
 *   AFTER (F-13):
 *     - users/{uid}/saved_items/{listingId}: allow read, write if isOwner(userId)
 *       → owner can list, get, set, delete their own saved items.
 *     - Top-level saved_items/{docId}: allow read, write: if false → fully locked.
 *
 * Test personas:
 *   alice — the item owner / saver
 *   bob   — an unrelated authenticated user
 *
 * Tests (9):
 *   T-F13-list-own                  — alice lists her own saved items (.get() on collection)    → SUCCEEDS
 *   T-F13-save-item                 — alice saves an item (set on her subcollection)             → SUCCEEDS
 *   T-F13-unsave-item               — alice unsaves an item (delete from her subcollection)      → SUCCEEDS
 *   T-F13-get-own-doc               — alice reads a single saved_item doc she owns               → SUCCEEDS
 *   T-F13-list-other                — bob lists alice's saved items (cross-user list)            → DENIED
 *   T-F13-write-other               — bob writes to alice's saved_items subcollection            → DENIED
 *   T-F13-toplevel-read-denied      — alice reads top-level saved_items doc                      → DENIED
 *   T-F13-toplevel-write-denied     — alice writes top-level saved_items (no userId)             → DENIED
 *   T-F13-toplevel-uid-pattern-denied — alice writes top-level with userId==self (old pattern)   → DENIED
 *
 * Run (from test_backend/):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 npx jest \
 *     --testPathPattern='f13_saved_items' \
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
  deleteDoc,
  collection,
} from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

// ─── Constants ────────────────────────────────────────────────────────────────

const PROJECT_ID = "huddl-test-project";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const ALICE_UID = "alice_f13_uid";
const BOB_UID   = "bob_f13_uid";

const LISTING_A = "listing_f13_001";
const LISTING_B = "listing_f13_002";
const TOPLEVEL_DOC = "toplevel_f13_doc";

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

async function seedDocs() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // User docs required for isOwner() resolution
    await setDoc(doc(db, "users", ALICE_UID), { name: "Alice" });
    await setDoc(doc(db, "users", BOB_UID),   { name: "Bob" });

    // Alice's saved items subcollection — two pre-existing saves
    await setDoc(
      doc(db, "users", ALICE_UID, "saved_items", LISTING_A),
      { listingId: LISTING_A, savedAt: new Date() }
    );
    await setDoc(
      doc(db, "users", ALICE_UID, "saved_items", LISTING_B),
      { listingId: LISTING_B, savedAt: new Date() }
    );

    // Top-level saved_items doc (legacy/phantom — seeded via admin bypass)
    await setDoc(doc(db, "saved_items", TOPLEVEL_DOC), {
      listingId: LISTING_A,
      savedAt:   new Date(),
      // Deliberately omit userId to reflect actual schema
    });
  });
}

// ─── Subcollection — OWNER ops (all SUCCEED) ─────────────────────────────────

describe("F-13 users/{uid}/saved_items — OWNER ops (must SUCCEED)", () => {
  beforeEach(seedDocs);

  it("T-F13-list-own: alice lists her own saved items (.get() on collection) → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      getDocs(collection(alice.firestore(), "users", ALICE_UID, "saved_items"))
    );
  });

  it("T-F13-save-item: alice saves a new item (set on her subcollection) → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      setDoc(
        doc(alice.firestore(), "users", ALICE_UID, "saved_items", "listing_new_f13"),
        { listingId: "listing_new_f13", savedAt: new Date() }
      )
    );
  });

  it("T-F13-unsave-item: alice unsaves an item (delete from her subcollection) → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      deleteDoc(doc(alice.firestore(), "users", ALICE_UID, "saved_items", LISTING_A))
    );
  });

  it("T-F13-get-own-doc: alice reads a single saved_item doc she owns → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      getDoc(doc(alice.firestore(), "users", ALICE_UID, "saved_items", LISTING_A))
    );
  });
});

// ─── Subcollection — CROSS-USER ops (all DENIED) ─────────────────────────────

describe("F-13 users/{uid}/saved_items — CROSS-USER ops (must DENY)", () => {
  beforeEach(seedDocs);

  it("T-F13-list-other: bob lists alice's saved items (cross-user list) → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      getDocs(collection(bob.firestore(), "users", ALICE_UID, "saved_items"))
    );
  });

  it("T-F13-write-other: bob writes to alice's saved_items subcollection → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      setDoc(
        doc(bob.firestore(), "users", ALICE_UID, "saved_items", "listing_injected_f13"),
        { listingId: "listing_injected_f13", savedAt: new Date() }
      )
    );
  });
});

// ─── Top-level saved_items — fully locked (DENIED) ───────────────────────────

describe("F-13 top-level saved_items — ALL OPS DENIED (if false)", () => {
  beforeEach(seedDocs);

  it("T-F13-toplevel-read-denied: alice reads top-level saved_items doc → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      getDoc(doc(alice.firestore(), "saved_items", TOPLEVEL_DOC))
    );
  });

  it("T-F13-toplevel-write-denied: alice writes to top-level saved_items (no userId) → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      setDoc(doc(alice.firestore(), "saved_items", "new_toplevel_f13"), {
        listingId: LISTING_A,
        savedAt:   new Date(),
      })
    );
  });

  it("T-F13-toplevel-uid-pattern-denied: alice writes top-level with userId==self (old phantom pattern) → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      setDoc(doc(alice.firestore(), "saved_items", "uid_pattern_f13"), {
        userId:    ALICE_UID,   // old phantom-open pattern — must now be DENIED
        listingId: LISTING_A,
        savedAt:   new Date(),
      })
    );
  });
});
