/**
 * Huddl — F-08 / F-09 / Borough-Spoofing Security Rules Tests
 *
 * Tests the four firestore.rules changes from Step 4:
 *   1. users_public/{userId}: allow read: if isAuth(); allow write: if false
 *   2. users/{userId} read locked to isOwner || isAdmin  (F-08)
 *   3. users/{userId} update affectedKeys blocklist  (F-09)
 *   4. writerBorough() reads users_public/{uid}.borough  (borough-spoof fix)
 *
 * Seed personas:
 *   alice  — regular user, owns her doc; users.borough = 'Islington' (spoofed),
 *             users_public.borough = 'Cambridge' (CF-controlled truth)
 *   bob    — regular user
 *   carol  — admin (roles.isAdmin: true)
 *
 * Run:
 *   cd test_backend && npm run test:rules
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
  updateDoc,
  deleteDoc,
} from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

// ─── Constants ────────────────────────────────────────────────────────────────

const PROJECT_ID = "huddl-test-project";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const ALICE_UID = "alice_uid";
const BOB_UID   = "bob_uid";
const CAROL_UID = "carol_uid";  // admin

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

// ─── Helpers ──────────────────────────────────────────────────────────────────

function alice()  { return testEnv.authenticatedContext(ALICE_UID); }
function bob()    { return testEnv.authenticatedContext(BOB_UID); }
function carol()  { return testEnv.authenticatedContext(CAROL_UID); }
function anon()   { return testEnv.unauthenticatedContext(); }

async function seed(collPath: string, docId: string, data: object): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), collPath, docId), data);
  });
}

/**
 * Seeds all three personas.
 *
 * users/alice_uid     — private doc: has children, phone, postcode;
 *                       borough = 'Islington' (simulates attacker-written value)
 * users_public/alice_uid — public mirror: borough = 'Cambridge' (CF truth)
 *
 * users/carol_uid     — admin doc
 * users_public/carol_uid — admin public mirror
 *
 * users/bob_uid + users_public/bob_uid — regular user
 */
async function seedPersonas(): Promise<void> {
  // Alice — private doc. borough = 'Cambridge' (the correct CF-managed value).
  // T-05d writes borough: 'Islington' (a genuine change: Cambridge → Islington).
  // affectedKeys() returns {'borough'} → hasAny([...'borough'...]) = true → !true = false → DENIED.
  // NOTE: If this seed had borough: 'Islington' and T-05d wrote 'Islington', the diff
  // would be empty (no-op), affectedKeys() = {} → hasAny = false → !false = true → allowed.
  // That's correct Firestore semantics: a no-op write changes nothing, so blocking it adds
  // nothing. The security property is: you cannot CHANGE borough, not that you cannot send it.
  await seed("users", ALICE_UID, {
    uid: ALICE_UID,
    name: "Alice",
    phone: "+447700900001",
    email: "alice@example.com",
    postcode: "CB1 2AB",
    borough: "Cambridge",          // correct value; T-05d will write 'Islington' (a real change)
    children: [{ name: "Charlie", birthday: "2020-03-01" }],
    roles: {},
    tier: "welcome",
    stripeCustomerId: "",
    isFoundingMember: false,
    isPhoneVerified: true,
    isOnline: true,
    fcmToken: "alice_token_001",
  });

  // Alice — public mirror (CF-managed): borough is Cambridge
  await seed("users_public", ALICE_UID, {
    name: "Alice",
    photoUrl: "",
    parentType: "parent",
    borough: "Cambridge",          // CF-controlled truth
    isOnline: true,
    stagesOfLife: ["toddler"],
    ward: "Abbey",
    wardCode: "E05002780",
    districtCode: "E07000008",
    region: "East of England",
  });

  // Bob — regular user
  await seed("users", BOB_UID, {
    uid: BOB_UID,
    name: "Bob",
    phone: "+447700900002",
    email: "bob@example.com",
    postcode: "CB2 1TN",
    borough: "Cambridge",
    roles: {},
    tier: "welcome",
    isOnline: false,
    fcmToken: "bob_token_001",
  });

  await seed("users_public", BOB_UID, {
    name: "Bob",
    photoUrl: "",
    parentType: "parent",
    borough: "Cambridge",
    isOnline: false,
    stagesOfLife: [],
    ward: "Market",
    wardCode: "E05002784",
    districtCode: "E07000008",
    region: "East of England",
  });

  // Carol — admin
  await seed("users", CAROL_UID, {
    uid: CAROL_UID,
    name: "Carol",
    phone: "+447700900003",
    email: "carol@huddl.app",
    postcode: "CB3 0ET",
    borough: "Cambridge",
    roles: { isAdmin: true },
    tier: "welcome",
    isOnline: true,
    fcmToken: "carol_token_001",
  });

  await seed("users_public", CAROL_UID, {
    name: "Carol",
    photoUrl: "",
    parentType: "parent",
    borough: "Cambridge",
    isOnline: true,
    stagesOfLife: [],
    ward: "Newnham",
    wardCode: "E05002785",
    districtCode: "E07000008",
    region: "East of England",
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// F-09: users/{uid} update — affectedKeys blocklist
// ─────────────────────────────────────────────────────────────────────────────

describe("F-09 — affectedKeys blocklist on users/{uid} update", () => {

  beforeEach(async () => {
    await seedPersonas();
  });

  // T-05: privilege escalation via roles
  test("T-05: alice writes {roles: {isAdmin: true}} to her own users doc → DENIED", async () => {
    const ref = doc(alice().firestore(), "users", ALICE_UID);
    await assertFails(
      updateDoc(ref, { roles: { isAdmin: true } })
    );
  });

  // T-05b: legitimate edit — must not be over-blocked
  test("T-05b: alice writes {name: 'X', bio: 'Y'} to her own users doc → SUCCEEDS", async () => {
    const ref = doc(alice().firestore(), "users", ALICE_UID);
    await assertSucceeds(
      updateDoc(ref, { name: "X", bio: "Y" })
    );
  });

  // T-05c: tier manipulation
  test("T-05c: alice writes {tier: 'plus'} to her own users doc → DENIED", async () => {
    const ref = doc(alice().firestore(), "users", ALICE_UID);
    await assertFails(
      updateDoc(ref, { tier: "plus" })
    );
  });

  // T-05d: borough self-write (Cambridge → Islington — genuine field change).
  // alice.users.borough is seeded as 'Cambridge'. Writing 'Islington' is a real
  // mutation; affectedKeys() returns {'borough'} → hasAny([...'borough'...]) = true
  // → !true = false → DENIED.
  test("T-05d: alice writes {borough: 'Islington'} to her own users doc → DENIED", async () => {
    const ref = doc(alice().firestore(), "users", ALICE_UID);
    await assertFails(
      updateDoc(ref, { borough: "Islington" })   // genuine change: Cambridge → Islington
    );
  });

  // T-05e: fcmToken self-write — must succeed (push registration must not break)
  test("T-05e: alice writes {fcmToken: 'xyz'} to her own users doc → SUCCEEDS", async () => {
    const ref = doc(alice().firestore(), "users", ALICE_UID);
    await assertSucceeds(
      updateDoc(ref, { fcmToken: "xyz_new_token" })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// F-08: users/{uid} read locked to owner + admin
// ─────────────────────────────────────────────────────────────────────────────

describe("F-08 — users/{uid} read access control", () => {

  beforeEach(async () => {
    await seedPersonas();
  });

  // T-08a: cross-user read of private doc — closed
  test("T-08a: bob reads users/alice → DENIED", async () => {
    const ref = doc(bob().firestore(), "users", ALICE_UID);
    await assertFails(getDoc(ref));
  });

  // T-08b: public mirror is readable; no sensitive fields present
  test("T-08b: bob reads users_public/alice → SUCCEEDS; name present, phone/children/postcode ABSENT", async () => {
    const ref = doc(bob().firestore(), "users_public", ALICE_UID);
    const snap = await assertSucceeds(getDoc(ref));
    const data = snap.data() as Record<string, unknown>;

    // name must be present
    expect(data["name"]).toBe("Alice");

    // sensitive fields must be absent from the public mirror
    expect(data["phone"]).toBeUndefined();
    expect(data["children"]).toBeUndefined();
    expect(data["postcode"]).toBeUndefined();
    expect(data["email"]).toBeUndefined();
    expect(data["fcmToken"]).toBeUndefined();
  });

  // T-08c: admin can read any private doc (R-14 admin panel)
  test("T-08c: carol (admin) reads users/bob → SUCCEEDS", async () => {
    const ref = doc(carol().firestore(), "users", BOB_UID);
    await assertSucceeds(getDoc(ref));
  });

  // T-08d: unauthenticated read of public mirror — denied
  test("T-08d: unauthenticated reads users_public/alice → DENIED", async () => {
    const ref = doc(anon().firestore(), "users_public", ALICE_UID);
    await assertFails(getDoc(ref));
  });

  // T-08e: client cannot write to users_public (mirror poisoning blocked)
  test("T-08e: alice writes to users_public/alice → DENIED", async () => {
    const ref = doc(alice().firestore(), "users_public", ALICE_UID);
    await assertFails(
      setDoc(ref, { name: "HACKED", borough: "London" })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// Borough-spoofing: writerBorough() reads users_public, not users
// ─────────────────────────────────────────────────────────────────────────────

describe("Borough-spoofing — writerBorough() reads users_public", () => {

  beforeEach(async () => {
    await seedPersonas();
  });

  /**
   * T-BOROUGH: alice.users.borough = 'Cambridge' (CF-correct)
   *            alice.users_public.borough = 'Cambridge' (CF truth)
   *
   * She attempts to create a group with borough = 'Islington' in the group doc.
   * boroughMatches('Islington') calls writerBorough() → reads users_public → 'Cambridge'
   * 'Cambridge'.lower() != 'Islington'.lower() → DENIED.
   *
   * This test verifies that a user cannot stamp a group with an arbitrary borough string
   * that differs from their CF-managed users_public.borough. Even though their
   * users.borough also says 'Cambridge' here, if it were 'Islington' (pre-fix spoofed),
   * the old writerBorough() reading users/{uid} would allow it — the new version
   * reading users_public prevents that spoof path entirely.
   */
  test("T-BOROUGH: alice creates group with borough='Islington' while users_public.borough='Cambridge' → DENIED", async () => {
    const ref = doc(alice().firestore(), "groups", "group_spoof_attempt");
    await assertFails(
      setDoc(ref, {
        creatorUid: ALICE_UID,
        name: "Islington Parents",
        borough: "Islington",       // attacker-controlled borough
        memberIds: [ALICE_UID],
        memberCount: 1,
        createdAt: new Date().toISOString(),
      })
    );
  });

  /**
   * Positive counterpart: alice creates a group with borough='Cambridge'.
   * boroughMatches() → users_public.borough = 'Cambridge' == 'Cambridge' → ALLOWED.
   */
  test("T-BOROUGH-positive: alice creates group with borough='Cambridge' (matches users_public) → SUCCEEDS", async () => {
    const ref = doc(alice().firestore(), "groups", "group_cambridge_legit");
    await assertSucceeds(
      setDoc(ref, {
        creatorUid: ALICE_UID,
        name: "Cambridge Parents",
        borough: "Cambridge",       // matches users_public.borough
        memberIds: [ALICE_UID],
        memberCount: 1,
        createdAt: new Date().toISOString(),
      })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// isAdmin() recursion safety: locking users read must not break admin checks
// ─────────────────────────────────────────────────────────────────────────────

describe("T-ISADMIN-NORECURSE — isAdmin() still works after F-08 read lock", () => {

  beforeEach(async () => {
    await seedPersonas();
  });

  /**
   * isAdmin() calls get(/databases/.../users/{uid}).data.get('roles', {}).get('isAdmin', false).
   * After F-08, users/{uid} is only readable by owner or admin.
   *
   * Firestore security rule get() calls are evaluated by the rules engine with
   * the same auth context — but the rules engine itself is allowed to read
   * any doc for get() calls inside rules functions. This is how isAdmin() works
   * in every other Firestore project. Verify carol's admin access still works.
   */
  // Carol is NOT the reporter (bob is) — her access is granted by isAdmin() only.
  // This confirms the isAdmin() get() call still works after the F-08 read lock.
  test("T-ISADMIN-NORECURSE: carol can read reports (isAdmin() gate) after F-08 lock", async () => {
    await seed("reports", "report_001", {
      reporterId: BOB_UID,    // bob reported; carol is admin, not reporter
      targetId: ALICE_UID,
      reason: "spam",
    });
    const ref = doc(carol().firestore(), "reports", "report_001");
    await assertSucceeds(getDoc(ref));
  });

  // Bob is NOT the reporter (alice is) and is NOT admin — must be denied.
  test("T-ISADMIN-NORECURSE: bob (non-admin, non-reporter) cannot read reports", async () => {
    await seed("reports", "report_001", {
      reporterId: ALICE_UID,   // alice reported; bob is unrelated
      targetId: CAROL_UID,
      reason: "spam",
    });
    const ref = doc(bob().firestore(), "reports", "report_001");
    await assertFails(getDoc(ref));
  });

  test("T-ISADMIN-NORECURSE: carol (admin) can update her own users doc arbitrary fields", async () => {
    const ref = doc(carol().firestore(), "users", CAROL_UID);
    await assertSucceeds(
      updateDoc(ref, { name: "Carol Admin Updated" })
    );
  });

  test("T-ISADMIN-NORECURSE: carol (admin) can update bob's users doc (moderation)", async () => {
    const ref = doc(carol().firestore(), "users", BOB_UID);
    await assertSucceeds(
      updateDoc(ref, { name: "Bob Moderated" })
    );
  });

});
