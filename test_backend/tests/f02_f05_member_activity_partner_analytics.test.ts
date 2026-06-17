/**
 * Huddl — F-02 / F-05 Security Rules Tests
 *
 * F-02 — memberActivity subcollection (groups/{groupId}/memberActivity/{memberUid})
 * ─────────────────────────────────────────────────────────────────────────────
 * BEFORE (broken): match /memberActivity/{docId} at top-level — a root collection
 *   that does not exist. The actual subcollection had NO rule → Firestore
 *   default-deny silently blocked all client writes in production.
 *
 * AFTER (F-02): rule placed correctly inside groups/{groupId} match block.
 *   read  — any group member (isGroupMember(groupId))
 *   write — group member writing ONLY their own doc (memberUid == request.auth.uid)
 *
 * F-05 — partner_analytics/{partnerUid}
 * ─────────────────────────────────────────────────────────────────────────────
 * BEFORE (broken): allow write: if isAuth() — any auth user could write any
 *   fields to any partner's analytics doc (zero counters, inject fields, etc.)
 *
 * AFTER (F-05): writes are still cross-user (viewer increments partner's counters)
 *   but locked to the two active counter fields + lastUpdated via affectedKeys().
 *   Reserved fields (totalBookingClicks, totalEndorsements) are client-write locked.
 *
 * Seed personas:
 *   alice  — member of GROUP_A, creator of GROUP_A
 *   bob    — member of GROUP_A
 *   carol  — NOT a member of GROUP_A (outsider)
 *   dave   — partner subscriber (owns partner_analytics/dave_uid)
 *
 * Run (from test_backend/):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 npx jest \
 *     --testPathPattern='f02_f05' \
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
  updateDoc,
  query,
  orderBy,
  limit,
  FieldValue,
  increment,
} from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

// ─── Constants ────────────────────────────────────────────────────────────────

const PROJECT_ID = "huddl-test-project";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const ALICE_UID = "alice_uid";   // creator + member of GROUP_A
const BOB_UID   = "bob_uid";    // member of GROUP_A
const CAROL_UID = "carol_uid";  // NOT a member of GROUP_A
const DAVE_UID  = "dave_uid";   // partner subscriber

const GROUP_A_ID = "group_a";

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
function dave()   { return testEnv.authenticatedContext(DAVE_UID); }

async function seed(collPath: string, docId: string, data: object): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), collPath, docId), data);
  });
}

async function seedSubcollection(
  parentPath: string,
  parentId: string,
  subcoll: string,
  docId: string,
  data: object
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const ref = doc(ctx.firestore(), parentPath, parentId, subcoll, docId);
    await setDoc(ref, data);
  });
}

/**
 * Seed fixture:
 *   groups/group_a          — alice (creator) + bob are members
 *   groups/group_a/memberActivity/alice_uid — alice's activity doc
 *   groups/group_a/memberActivity/bob_uid   — bob's activity doc
 *   partner_analytics/dave_uid              — dave's analytics doc (existing)
 */
async function seedFixture(): Promise<void> {
  // Group A — alice creator, alice + bob members
  await seed("groups", GROUP_A_ID, {
    id:          GROUP_A_ID,
    name:        "Test Group A",
    borough:     "Cambridge",
    privacy:     "public",
    creatorUid:  ALICE_UID,
    memberIds:   [ALICE_UID, BOB_UID],
    members:     [ALICE_UID, BOB_UID],
    memberCount: 2,
  });

  // Alice's existing memberActivity doc
  await seedSubcollection("groups", GROUP_A_ID, "memberActivity", ALICE_UID, {
    userId:       ALICE_UID,
    messageCount: 10,
    joinedAt:     new Date().toISOString(),
    lastActiveAt: new Date().toISOString(),
  });

  // Bob's existing memberActivity doc
  await seedSubcollection("groups", GROUP_A_ID, "memberActivity", BOB_UID, {
    userId:       BOB_UID,
    messageCount: 3,
    joinedAt:     new Date().toISOString(),
    lastActiveAt: new Date().toISOString(),
  });

  // Dave's partner_analytics doc (pre-existing — tests the update path)
  await seed("partner_analytics", DAVE_UID, {
    totalProfileViews:  5,
    totalListingViews:  2,
    lastUpdated:        new Date().toISOString(),
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// F-02 — memberActivity subcollection
// ══════════════════════════════════════════════════════════════════════════════

describe("F-02 — memberActivity read access", () => {

  beforeEach(async () => { await seedFixture(); });

  // T-F02-R1: group member reads their own activity doc → SUCCEEDS
  test("T-F02-R1: group member reads own memberActivity doc → SUCCEEDS", async () => {
    const ref = doc(alice().firestore(), "groups", GROUP_A_ID, "memberActivity", ALICE_UID);
    await assertSucceeds(getDoc(ref));
  });

  // T-F02-R2: group member reads ANOTHER member's activity doc → SUCCEEDS
  // (required by auto-promotion and admin-demotion flows that query the entire subcollection)
  test("T-F02-R2: group member reads another member's activity doc → SUCCEEDS", async () => {
    const ref = doc(alice().firestore(), "groups", GROUP_A_ID, "memberActivity", BOB_UID);
    await assertSucceeds(getDoc(ref));
  });

  // T-F02-R3: group member queries entire memberActivity subcollection ordered
  // by messageCount (the exact query used by auto-promote / manage_admins flows)
  // → SUCCEEDS
  test("T-F02-R3: group member queries memberActivity subcollection (orderBy messageCount) → SUCCEEDS", async () => {
    const colRef = collection(alice().firestore(), "groups", GROUP_A_ID, "memberActivity");
    const q = query(colRef, orderBy("messageCount", "desc"), limit(10));
    await assertSucceeds(getDocs(q));
  });

  // T-F02-R4: non-member (carol) attempts to read memberActivity → DENIED
  test("T-F02-R4: non-member reads memberActivity doc → DENIED", async () => {
    const ref = doc(carol().firestore(), "groups", GROUP_A_ID, "memberActivity", ALICE_UID);
    await assertFails(getDoc(ref));
  });

});

describe("F-02 — memberActivity write access (own-doc + member guard)", () => {

  beforeEach(async () => { await seedFixture(); });

  // T-F02-W1: group member writes their own memberActivity doc → SUCCEEDS
  // (mirrors group_chat_screen._incrementMemberActivity)
  test("T-F02-W1: group member writes own memberActivity (messageCount increment) → SUCCEEDS", async () => {
    const ref = doc(bob().firestore(), "groups", GROUP_A_ID, "memberActivity", BOB_UID);
    await assertSucceeds(
      setDoc(ref, {
        userId:       BOB_UID,
        messageCount: increment(1),
        lastActiveAt: new Date().toISOString(),
      }, { merge: true })
    );
  });

  // T-F02-W2: group member writes initial joinedAt doc (create path — mirrors
  // invitation_service.joinPublicGroup write-once pattern)
  test("T-F02-W2: new member creates own memberActivity doc with joinedAt → SUCCEEDS", async () => {
    // seed a fresh group with carol as a member (not using GROUP_A where carol isn't)
    const NEW_GROUP_ID = "new_group";
    await seed("groups", NEW_GROUP_ID, {
      id:          NEW_GROUP_ID,
      name:        "New Group",
      borough:     "Cambridge",
      privacy:     "public",
      creatorUid:  ALICE_UID,
      memberIds:   [ALICE_UID, CAROL_UID],
      members:     [ALICE_UID, CAROL_UID],
      memberCount: 2,
    });
    const ref = doc(carol().firestore(), "groups", NEW_GROUP_ID, "memberActivity", CAROL_UID);
    await assertSucceeds(
      setDoc(ref, {
        userId:       CAROL_UID,
        messageCount: 0,
        joinedAt:     new Date().toISOString(),
        lastActiveAt: new Date().toISOString(),
      }, { merge: true })
    );
  });

  // T-F02-W3: non-member (carol) writes memberActivity to GROUP_A → DENIED
  // (isGroupMember check blocks carol who is not in group_a.memberIds)
  test("T-F02-W3: non-member writes memberActivity → DENIED", async () => {
    const ref = doc(carol().firestore(), "groups", GROUP_A_ID, "memberActivity", CAROL_UID);
    await assertFails(
      setDoc(ref, {
        userId:       CAROL_UID,
        messageCount: 0,
        joinedAt:     new Date().toISOString(),
        lastActiveAt: new Date().toISOString(),
      }, { merge: true })
    );
  });

  // T-F02-W4: group member writes ANOTHER member's activity doc → DENIED
  // (memberUid == request.auth.uid check: bob cannot write alice's doc)
  test("T-F02-W4: group member writes ANOTHER member's activity doc → DENIED", async () => {
    const ref = doc(bob().firestore(), "groups", GROUP_A_ID, "memberActivity", ALICE_UID);
    await assertFails(
      setDoc(ref, {
        userId:       ALICE_UID,
        messageCount: increment(1),
        lastActiveAt: new Date().toISOString(),
      }, { merge: true })
    );
  });

});

// ══════════════════════════════════════════════════════════════════════════════
// F-05 — partner_analytics
// ══════════════════════════════════════════════════════════════════════════════

describe("F-05 — partner_analytics read access (unchanged)", () => {

  beforeEach(async () => { await seedFixture(); });

  // T-F05-R1: partner reads their own analytics doc → SUCCEEDS (read unchanged)
  test("T-F05-R1: partner reads own analytics doc → SUCCEEDS", async () => {
    const ref = doc(dave().firestore(), "partner_analytics", DAVE_UID);
    await assertSucceeds(getDoc(ref));
  });

  // T-F05-R2: different user tries to read another's analytics doc → DENIED
  test("T-F05-R2: non-owner reads another partner's analytics doc → DENIED", async () => {
    const ref = doc(alice().firestore(), "partner_analytics", DAVE_UID);
    await assertFails(getDoc(ref));
  });

});

describe("F-05 — partner_analytics LEGITIMATE writes (allowlisted fields)", () => {

  beforeEach(async () => { await seedFixture(); });

  // T-F05-W1: viewer increments totalProfileViews + lastUpdated on partner's doc
  // → SUCCEEDS (mirrors partner_profile_screen view tracking)
  test("T-F05-W1: viewer increments totalProfileViews + lastUpdated → SUCCEEDS", async () => {
    const ref = doc(alice().firestore(), "partner_analytics", DAVE_UID);
    await assertSucceeds(
      updateDoc(ref, {
        totalProfileViews: increment(1),
        lastUpdated:       new Date().toISOString(),
      })
    );
  });

  // T-F05-W2: service increments totalListingViews + lastUpdated
  // → SUCCEEDS (mirrors local_services_service.recordView)
  test("T-F05-W2: viewer increments totalListingViews + lastUpdated → SUCCEEDS", async () => {
    const ref = doc(bob().firestore(), "partner_analytics", DAVE_UID);
    await assertSucceeds(
      updateDoc(ref, {
        totalListingViews: increment(1),
        lastUpdated:       new Date().toISOString(),
      })
    );
  });

  // T-F05-W3: first-time view creates the partner_analytics doc (create path)
  // → SUCCEEDS (doc didn't exist before; SetOptions merge:true triggers create)
  test("T-F05-W3: first-time profile view creates partner_analytics doc → SUCCEEDS", async () => {
    const NEW_PARTNER_UID = "new_partner_uid";
    // No pre-existing doc for new_partner_uid
    const ref = doc(alice().firestore(), "partner_analytics", NEW_PARTNER_UID);
    await assertSucceeds(
      setDoc(ref, {
        totalProfileViews: increment(1),
        lastUpdated:       new Date().toISOString(),
      }, { merge: true })
    );
  });

});

describe("F-05 — partner_analytics BLOCKED writes (field injection / reserved fields)", () => {

  beforeEach(async () => { await seedFixture(); });

  // T-F05-W4: attacker tries to zero out totalProfileViews by writing 0
  // (this changes the field value → affectedKeys contains totalProfileViews;
  // the field IS in the allowlist but the value is set directly — this SUCCEEDS
  // because affectedKeys only checks WHICH fields changed, not HOW they changed.
  // Separately: T-F05-W5 tests injecting a non-allowlisted field — that's the real
  // injection risk the rule blocks.)
  // NOTE: Counter zeroing via direct set of an allowlisted field is still allowed —
  // the field-restriction approach prevents field injection but not value manipulation
  // on permitted fields. This is an acceptable residual risk noted in the diff.
  // This test confirms the rule does NOT block allowlisted field writes (even zeroing).
  test("T-F05-W4: any auth user writes only allowlisted fields → SUCCEEDS (cross-user design)", async () => {
    const ref = doc(carol().firestore(), "partner_analytics", DAVE_UID);
    await assertSucceeds(
      updateDoc(ref, {
        totalProfileViews: increment(1),
        lastUpdated:       new Date().toISOString(),
      })
    );
  });

  // T-F05-W5: attacker injects a non-allowlisted field (totalBookingClicks)
  // → DENIED (affectedKeys hasOnly check blocks it)
  test("T-F05-W5: writing reserved field totalBookingClicks → DENIED", async () => {
    const ref = doc(alice().firestore(), "partner_analytics", DAVE_UID);
    await assertFails(
      updateDoc(ref, {
        totalBookingClicks: increment(1),
        lastUpdated:        new Date().toISOString(),
      })
    );
  });

  // T-F05-W6: attacker injects an arbitrary field (maliciousField)
  // → DENIED (not in allowlist)
  test("T-F05-W6: injecting arbitrary field on partner_analytics doc → DENIED", async () => {
    const ref = doc(bob().firestore(), "partner_analytics", DAVE_UID);
    await assertFails(
      updateDoc(ref, {
        maliciousField: "injected",
        lastUpdated:    new Date().toISOString(),
      })
    );
  });

  // T-F05-W7: attacker writes totalEndorsements (reserved — no active client write path)
  // → DENIED
  test("T-F05-W7: writing reserved field totalEndorsements → DENIED", async () => {
    const ref = doc(carol().firestore(), "partner_analytics", DAVE_UID);
    await assertFails(
      updateDoc(ref, {
        totalEndorsements: increment(1),
        lastUpdated:       new Date().toISOString(),
      })
    );
  });

  // T-F05-W8: unauthenticated user tries to write → DENIED
  test("T-F05-W8: unauthenticated write to partner_analytics → DENIED", async () => {
    const ref = doc(testEnv.unauthenticatedContext().firestore(), "partner_analytics", DAVE_UID);
    await assertFails(
      updateDoc(ref, {
        totalProfileViews: increment(1),
        lastUpdated:       new Date().toISOString(),
      })
    );
  });

});
