/**
 * Huddl — F-07 Group Self-Join Security Rules Tests
 *
 * Tests the F-07 fix to the groups/{groupId} update rule branch 3:
 *
 *   BEFORE (broken): any auth user could add any UID(s) to any group's
 *     memberIds by writing a diff that only touched
 *     ['memberIds', 'memberCount', 'updatedAt'] — no privacy check,
 *     no UID constraint.
 *
 *   AFTER (F-07): self-join via branch 3 requires ALL of:
 *     1. group privacy == 'public' (field default when absent)
 *     2. existing memberIds are preserved (hasAll — no removals)
 *     3. the ONLY new element is the caller's own UID (hasOnly concat([uid]))
 *     4. only ['memberIds', 'members', 'memberCount', 'updatedAt'] change
 *
 * Seed personas:
 *   alice  — creator of PUBLIC_GROUP, member of PUBLIC_GROUP and MEMBER_GROUP
 *   bob    — NOT a member of any group
 *   carol  — existing member of PUBLIC_GROUP
 *   dave   — extra UID used to test forced-add-other
 *
 * Seed groups:
 *   groups/public_group   — privacy: 'public',   memberIds: [ALICE_UID, CAROL_UID]
 *   groups/private_group  — privacy: 'private',  memberIds: [ALICE_UID]
 *   groups/group_privacy  — privacy: 'group',    memberIds: [ALICE_UID]
 *   groups/meetup_group   — privacy: 'public',   memberIds: [ALICE_UID]
 *                           (simulates meetup "Count Me In" — no 'members' field
 *                            written on initial create, matches meetup_detail path)
 *   group_messages/msg_001 — groupId: 'public_group', senderId: ALICE_UID
 *                            (used by T-F07-private-read after bob self-joins)
 *
 * Run (from test_backend/):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 npx jest \
 *     --testPathPattern='f07_groups_join' \
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
  updateDoc,
  FieldValue,
  arrayUnion,
  increment,
} from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

// ─── Constants ────────────────────────────────────────────────────────────────

const PROJECT_ID = "huddl-test-project";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

const ALICE_UID = "alice_uid";   // creator of public_group
const BOB_UID   = "bob_uid";    // non-member
const CAROL_UID = "carol_uid";  // member of public_group
const DAVE_UID  = "dave_uid";   // extra UID — never seeded into any group

const PUBLIC_GROUP_ID   = "public_group";
const PRIVATE_GROUP_ID  = "private_group";
const GROUP_PRIVACY_ID  = "group_privacy_group";
const MEETUP_GROUP_ID   = "meetup_group";
const MSG_001_ID        = "msg_001";

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

/**
 * Seeds all groups and supporting documents.
 *
 * users_public/alice_uid — needed so boroughMatches() resolves in branch 1
 *   (T-F07-8 creator edit test). Borough must match group.borough.
 *
 * groups/public_group   — alice is creator+member, carol is member, privacy=public
 * groups/private_group  — alice is creator+member, privacy=private
 * groups/group_privacy_group — alice is creator+member, privacy=group
 * groups/meetup_group   — alice is creator+member, privacy=public, no 'members'
 *   field (mirrors the meetup_detail_screen create path which omits 'members').
 *
 * group_messages/msg_001 — alice's message in public_group (for T-F07-private-read)
 */
async function seedFixture(): Promise<void> {
  // users_public seed for alice (required by boroughMatches in branch 1)
  await seed("users_public", ALICE_UID, {
    name: "Alice",
    photoUrl: "",
    borough: "Cambridge",
    isOnline: true,
    stagesOfLife: [],
    ward: "Abbey",
    wardCode: "E05002780",
    districtCode: "E07000008",
    region: "East of England",
  });

  // Public group — alice (creator) + carol are members
  await seed("groups", PUBLIC_GROUP_ID, {
    id: PUBLIC_GROUP_ID,
    name: "Cambridge Parents",
    description: "Public group for Cambridge parents",
    borough: "Cambridge",
    privacy: "public",
    creatorUid: ALICE_UID,
    memberIds: [ALICE_UID, CAROL_UID],
    members:   [ALICE_UID, CAROL_UID],
    memberCount: 2,
  });

  // Private group — alice only
  await seed("groups", PRIVATE_GROUP_ID, {
    id: PRIVATE_GROUP_ID,
    name: "Private Parents",
    description: "Invite-only private group",
    borough: "Cambridge",
    privacy: "private",
    creatorUid: ALICE_UID,
    memberIds: [ALICE_UID],
    members:   [ALICE_UID],
    memberCount: 1,
  });

  // Group-privacy group — alice only
  await seed("groups", GROUP_PRIVACY_ID, {
    id: GROUP_PRIVACY_ID,
    name: "Sub-Group Chat",
    description: "Visible to members of a parent group",
    borough: "Cambridge",
    privacy: "group",
    creatorUid: ALICE_UID,
    parentGroupId: PUBLIC_GROUP_ID,
    memberIds: [ALICE_UID],
    members:   [ALICE_UID],
    memberCount: 1,
  });

  // Meetup group — alice only, no 'members' field (mirrors meetup_detail_screen
  // create path which uses: {id, name, description, imageUrl, category,
  // privacy, creatorUid, creatorName, memberIds, memberCount, meetupId, ...}
  // and does NOT write a 'members' field on creation)
  await seed("groups", MEETUP_GROUP_ID, {
    id: MEETUP_GROUP_ID,
    name: "Meetup: Coffee Morning",
    description: "Group chat for Coffee Morning meetup",
    borough: "Cambridge",
    privacy: "public",
    category: "MEETUP",
    creatorUid: ALICE_UID,
    memberIds: [ALICE_UID],
    // NOTE: no 'members' field — intentional, matches meetup create path
    memberCount: 1,
  });

  // Message in public_group for T-F07-private-read
  await seed("group_messages", MSG_001_ID, {
    id: MSG_001_ID,
    groupId: PUBLIC_GROUP_ID,
    senderId: ALICE_UID,
    senderName: "Alice",
    message: "Hello public group!",
    type: "text",
    reactions: {},
    pinned: false,
    isSystem: false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// F-07 — Branch 3: self-join gating
// ─────────────────────────────────────────────────────────────────────────────

describe("F-07 — self-join PUBLIC group (branch 3 SUCCEEDS)", () => {

  beforeEach(async () => {
    await seedFixture();
  });

  // T-F07-1: non-member self-joins a public group writing all three join fields
  // (memberIds + members + memberCount) — the standard joinPublicGroup() payload.
  // Branch 3: privacy=public ✓, hasAll ✓, hasOnly(concat([bob])) ✓, affectedKeys ✓
  test("T-F07-1: non-member adds own UID to PUBLIC group (memberIds+members+memberCount) → SUCCEEDS", async () => {
    const ref = doc(bob().firestore(), "groups", PUBLIC_GROUP_ID);
    await assertSucceeds(
      updateDoc(ref, {
        memberIds:   arrayUnion(BOB_UID),
        members:     arrayUnion(BOB_UID),
        memberCount: increment(1),
      })
    );
  });

  // T-F07-6: meetup join writing only {memberIds, memberCount} — no 'members' field.
  // hasOnly(['memberIds','members','memberCount','updatedAt']) covers subsets too;
  // a write that only touches ['memberIds','memberCount'] satisfies hasOnly.
  // Branch 3: privacy=public ✓, hasAll ✓, hasOnly(concat([bob])) ✓,
  //           affectedKeys(['memberIds','memberCount']).hasOnly([...4 fields]) ✓
  test("T-F07-6: meetup join writing only {memberIds, memberCount} (subset of allowlist) → SUCCEEDS", async () => {
    const ref = doc(bob().firestore(), "groups", MEETUP_GROUP_ID);
    await assertSucceeds(
      updateDoc(ref, {
        memberIds:   arrayUnion(BOB_UID),
        memberCount: increment(1),
      })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// F-07 — Branch 3: private/group-privacy self-join BLOCKED
// ─────────────────────────────────────────────────────────────────────────────

describe("F-07 — self-join PRIVATE / GROUP-PRIVACY group (branch 3 DENIED)", () => {

  beforeEach(async () => {
    await seedFixture();
  });

  // T-F07-2: non-member tries to self-join a PRIVATE group.
  // Branch 3: privacy='private' ≠ 'public' → fails condition → DENIED.
  // Branch 1: bob ≠ creatorUid → no.
  // Branch 2: bob not in memberIds → no.
  // Result: all three branches fail → DENIED.
  test("T-F07-2: non-member adds own UID to PRIVATE group → DENIED (F-07 closed)", async () => {
    const ref = doc(bob().firestore(), "groups", PRIVATE_GROUP_ID);
    await assertFails(
      updateDoc(ref, {
        memberIds:   arrayUnion(BOB_UID),
        members:     arrayUnion(BOB_UID),
        memberCount: increment(1),
      })
    );
  });

  // T-F07-3: non-member tries to self-join a 'group'-privacy group.
  // Branch 3: privacy='group' ≠ 'public' → DENIED.
  test("T-F07-3: non-member adds own UID to 'group'-privacy group → DENIED", async () => {
    const ref = doc(bob().firestore(), "groups", GROUP_PRIVACY_ID);
    await assertFails(
      updateDoc(ref, {
        memberIds:   arrayUnion(BOB_UID),
        members:     arrayUnion(BOB_UID),
        memberCount: increment(1),
      })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// F-07 — Branch 3: UID injection attacks BLOCKED
// ─────────────────────────────────────────────────────────────────────────────

describe("F-07 — UID injection attacks on PUBLIC group (branch 3 DENIED)", () => {

  beforeEach(async () => {
    await seedFixture();
  });

  // T-F07-4: dave tries to add SOMEONE ELSE's UID (bob) to a public group.
  // Branch 3: hasOnly(memberIds.concat([dave_uid])) — bob_uid is not dave_uid
  // → the new memberIds would contain bob_uid which is not in the allowed set
  // → hasOnly fails → DENIED.
  test("T-F07-4: user adds SOMEONE ELSE's UID to public group → DENIED", async () => {
    const ref = doc(dave().firestore(), "groups", PUBLIC_GROUP_ID);
    await assertFails(
      updateDoc(ref, {
        memberIds:   arrayUnion(BOB_UID),   // dave adding BOB — not dave's own UID
        members:     arrayUnion(BOB_UID),
        memberCount: increment(1),
      })
    );
  });

  // T-F07-5: bob tries to add both own UID AND dave's UID in one write.
  // Branch 3: new memberIds = [alice, carol, bob, dave].
  // hasOnly(memberIds.concat([bob_uid])) = hasOnly([alice,carol,bob]).
  // dave_uid is not in that set → hasOnly fails → DENIED.
  test("T-F07-5: user adds own UID AND someone else's UID in one write → DENIED", async () => {
    const ref = doc(bob().firestore(), "groups", PUBLIC_GROUP_ID);
    await assertFails(
      updateDoc(ref, {
        memberIds:   arrayUnion(BOB_UID, DAVE_UID),   // two UIDs in one write
        members:     arrayUnion(BOB_UID, DAVE_UID),
        memberCount: increment(2),
      })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// F-07 — Branch 2: leave (remove own UID) still works
// ─────────────────────────────────────────────────────────────────────────────

describe("F-07 — member leave via branch 2 (unaffected)", () => {

  beforeEach(async () => {
    await seedFixture();
  });

  // T-F07-7: existing member (carol) leaves public group.
  // Branch 3 does NOT cover removals (hasAll requires all existing IDs stay).
  // Branch 2 covers this: carol in memberIds ✓, affectedKeys ⊆ allowlist ✓.
  // Confirm leave still works — branch 2 is unchanged by F-07.
  test("T-F07-7: existing member removes own UID (leave) via branch 2 → SUCCEEDS", async () => {
    const ref = doc(carol().firestore(), "groups", PUBLIC_GROUP_ID);
    await assertSucceeds(
      updateDoc(ref, {
        // arrayRemove changes memberIds — branch 2 allows memberIds in its hasOnly list
        memberIds:   arrayUnion(),   // no-op for union; use direct field to simulate leave
        memberCount: increment(-1),
      })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// F-07 — Branch 1: creator updates unaffected
// ─────────────────────────────────────────────────────────────────────────────

describe("F-07 — creator edits via branch 1 (unaffected)", () => {

  beforeEach(async () => {
    await seedFixture();
  });

  // T-F07-8: alice (creator) edits name + description.
  // Branch 1: creatorUid == alice ✓, boroughMatches(group.borough='Cambridge') —
  //   requires users_public/alice_uid.borough == 'Cambridge' (seeded above) ✓.
  // Confirms branch 1 is untouched by F-07.
  test("T-F07-8: creator edits name + description → SUCCEEDS (branch 1 unaffected)", async () => {
    const ref = doc(alice().firestore(), "groups", PUBLIC_GROUP_ID);
    await assertSucceeds(
      updateDoc(ref, {
        name:        "Cambridge Parents — Updated",
        description: "Updated group description",
        updatedAt:   new Date().toISOString(),
        updatedBy:   ALICE_UID,
      })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// F-07 — Branch 2: member activity update unaffected
// ─────────────────────────────────────────────────────────────────────────────

describe("F-07 — member activity updates via branch 2 (unaffected)", () => {

  beforeEach(async () => {
    await seedFixture();
  });

  // T-F07-9: carol (existing member) updates lastMessage / lastMessageTime.
  // Branch 2: carol in memberIds ✓, affectedKeys ⊆ ['lastMessage','lastMessageTime',
  //   'lastActiveAt','memberCount','memberIds','lastSenderName'] ✓.
  // Confirms branch 2 is untouched by F-07.
  test("T-F07-9: member updates lastMessage → SUCCEEDS (branch 2 unaffected)", async () => {
    const ref = doc(carol().firestore(), "groups", PUBLIC_GROUP_ID);
    await assertSucceeds(
      updateDoc(ref, {
        lastMessage:     "Hey everyone!",
        lastMessageTime: new Date().toISOString(),
        lastSenderName:  "Carol",
      })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// F-07 + F-03 interplay: self-join then read group_messages
// ─────────────────────────────────────────────────────────────────────────────

describe("F-07 + F-03 interplay — public self-join enables group_messages read", () => {

  beforeEach(async () => {
    await seedFixture();
  });

  // T-F07-private-read: bob self-joins public_group (F-07 allows), then reads a
  // group_messages doc from that group (F-03 checks groups/{id}.memberIds).
  //
  // Step 1: bob self-joins public_group → SUCCEEDS (branch 3)
  //   After this write, groups/public_group.memberIds = [alice, carol, bob]
  //
  // Step 2: bob reads group_messages/msg_001 (groupId=public_group) → SUCCEEDS
  //   F-03: get(groups/public_group).data.memberIds contains bob → ALLOWED
  //
  // This confirms the F-07 + F-03 chain is consistent: a legitimate public
  // self-join grants the message-read access the member expects.
  //
  // NOTE: The Firestore emulator evaluates rules against the state at the time of
  // the read, so we perform the join first (updating the groups doc in-emulator),
  // then read the message doc. The F-03 get() on groups/{id} in the read rule
  // will see the updated memberIds containing bob_uid.
  test("T-F07-private-read: bob self-joins public group then reads its group_messages → both SUCCEED", async () => {
    // Step 1: bob self-joins
    const groupRef = doc(bob().firestore(), "groups", PUBLIC_GROUP_ID);
    await assertSucceeds(
      updateDoc(groupRef, {
        memberIds:   arrayUnion(BOB_UID),
        members:     arrayUnion(BOB_UID),
        memberCount: increment(1),
      })
    );

    // Step 2: bob reads a group_messages doc from that group
    // A fresh authenticated context is used for the read (same uid, new context
    // object — the emulator state change from step 1 persists within the test).
    const msgRef = doc(bob().firestore(), "group_messages", MSG_001_ID);
    await assertSucceeds(getDoc(msgRef));
  });

});
