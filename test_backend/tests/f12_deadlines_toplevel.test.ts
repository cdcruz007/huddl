/**
 * Huddl — F-12 Top-level deadlines Collection Lock Tests
 *
 * Tests the F-12 fix to the top-level match /deadlines/{docId} rule.
 *
 *   BEFORE (broken): allow read, write permitted any authenticated user who
 *     included a 'uid' field matching their own UID. Speculatively written
 *     rule for a collection that was never used — SendDeadline.toJson() does
 *     not even write a 'uid' field, so the old rule would have denied live
 *     writes anyway. But any raw Firestore call with uid: auth.uid would pass.
 *
 *   AFTER (F-12): allow read, write: if false — fully locked.
 *     Real SEND deadline data lives at users/{uid}/deadlines/{docId} (unchanged).
 *
 * Confirms:
 *   1. Top-level deadlines collection is fully locked (all ops DENIED)
 *   2. users/{uid}/deadlines subcollection is NOT affected — legitimate path
 *      still accessible by the owner (critical regression check)
 *
 * Seed personas:
 *   alice  — authenticated user
 *
 * Tests (7):
 *
 *   TOP-LEVEL deadlines/{docId} — all DENIED
 *   T-F12-toplevel-read-denied       — alice reads top-level deadlines doc → DENIED
 *   T-F12-toplevel-create-denied     — alice creates top-level deadlines doc → DENIED
 *   T-F12-toplevel-create-uid-denied — alice creates with uid==self (old pattern) → DENIED
 *   T-F12-toplevel-update-denied     — alice updates top-level deadlines doc → DENIED
 *   T-F12-toplevel-delete-denied     — alice deletes top-level deadlines doc → DENIED
 *   T-F12-toplevel-unauthed-denied   — unauthenticated create → DENIED
 *
 *   SUBCOLLECTION users/{uid}/deadlines (regression check)
 *   T-F12-subcollection-owner-read   — alice reads her own subcollection doc → SUCCEEDS
 *   T-F12-subcollection-owner-write  — alice writes her own subcollection doc → SUCCEEDS
 *   T-F12-subcollection-other-denied — alice reads bob's subcollection doc → DENIED
 *
 * Run (from test_backend/):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 npx jest \
 *     --testPathPattern='f12_deadlines_toplevel' \
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

const PROJECT_ID  = "huddl-test-project";
const RULES_PATH  = path.resolve(__dirname, "../../firestore.rules");

const ALICE_UID   = "alice_f12_uid";
const BOB_UID     = "bob_f12_uid";

const TOPLEVEL_DOC_ID   = "deadline_toplevel_f12";
const SUBCOL_DOC_ID     = "deadline_subcol_f12";

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

    // Top-level deadlines doc (seeded via admin bypass — simulating legacy data)
    await setDoc(doc(db, "deadlines", TOPLEVEL_DOC_ID), {
      uid:         ALICE_UID,
      title:       "LA decision deadline",
      description: "LA must respond within 6 weeks",
      date:        Date.now() + 86400000 * 14,
      category:    "statutory",
      isCompleted: false,
    });

    // Legitimate subcollection doc for alice
    await setDoc(doc(db, "users", ALICE_UID, "deadlines", SUBCOL_DOC_ID), {
      id:          SUBCOL_DOC_ID,
      title:       "Appeal window closes",
      description: "2-month appeal window from final EHCP",
      date:        Date.now() + 86400000 * 30,
      category:    "tribunal",
      isCompleted: false,
    });

    // users doc needed for the subcollection rule to resolve userId
    await setDoc(doc(db, "users", ALICE_UID), { name: "Alice" });
    await setDoc(doc(db, "users", BOB_UID),   { name: "Bob" });

    // Bob's subcollection doc (for cross-user denial test)
    await setDoc(doc(db, "users", BOB_UID, "deadlines", "bob_deadline_f12"), {
      id:    "bob_deadline_f12",
      title: "Bob's deadline",
      date:  Date.now(),
    });
  });
}

// ─── TOP-LEVEL deadlines — all DENIED ─────────────────────────────────────────

describe("F-12 deadlines top-level — ALL OPS DENIED (if false)", () => {
  beforeEach(seedDocs);

  it("T-F12-toplevel-read-denied: alice reads top-level deadlines doc → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      getDoc(doc(alice.firestore(), "deadlines", TOPLEVEL_DOC_ID))
    );
  });

  it("T-F12-toplevel-create-denied: alice creates top-level deadlines doc → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      setDoc(doc(alice.firestore(), "deadlines", "new_doc_f12"), {
        title:       "New deadline",
        date:        Date.now(),
        isCompleted: false,
      })
    );
  });

  it("T-F12-toplevel-create-uid-denied: alice creates with uid==self (old allowed pattern) → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      setDoc(doc(alice.firestore(), "deadlines", "uid_pattern_f12"), {
        uid:         ALICE_UID,   // old rule required this field — now irrelevant
        title:       "EHCP decision",
        date:        Date.now(),
        isCompleted: false,
      })
    );
  });

  it("T-F12-toplevel-update-denied: alice updates top-level deadlines doc → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      updateDoc(doc(alice.firestore(), "deadlines", TOPLEVEL_DOC_ID), {
        isCompleted: true,
      })
    );
  });

  it("T-F12-toplevel-delete-denied: alice deletes top-level deadlines doc → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      deleteDoc(doc(alice.firestore(), "deadlines", TOPLEVEL_DOC_ID))
    );
  });

  it("T-F12-toplevel-unauthed-denied: unauthenticated create → DENIED", async () => {
    const unauthed = testEnv.unauthenticatedContext();
    await assertFails(
      setDoc(doc(unauthed.firestore(), "deadlines", "unauthed_f12"), {
        title: "should not be written",
      })
    );
  });
});

// ─── SUBCOLLECTION users/{uid}/deadlines — regression check ───────────────────

describe("F-12 users/{uid}/deadlines subcollection — REGRESSION CHECK (must still work)", () => {
  beforeEach(seedDocs);

  it("T-F12-subcollection-owner-read: alice reads her own subcollection deadline → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      getDoc(doc(alice.firestore(), "users", ALICE_UID, "deadlines", SUBCOL_DOC_ID))
    );
  });

  it("T-F12-subcollection-owner-write: alice writes her own subcollection deadline → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      setDoc(doc(alice.firestore(), "users", ALICE_UID, "deadlines", "new_f12"), {
        id:          "new_f12",
        title:       "Final EHCP issued",
        description: "Annual review due in 12 months",
        date:        Date.now() + 86400000 * 365,
        category:    "review",
        isCompleted: false,
      })
    );
  });

  it("T-F12-subcollection-other-denied: alice reads bob's subcollection deadline → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      getDoc(doc(alice.firestore(), "users", BOB_UID, "deadlines", "bob_deadline_f12"))
    );
  });
});
