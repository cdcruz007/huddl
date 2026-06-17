/**
 * Huddl — F-11 Borough Announcements Comments Subcollection Tests
 *
 * Tests the F-11 migration: comments moved from embedded commentsList array
 * to borough_announcements/{announcementId}/comments/{commentId} subcollection.
 *
 * Security fixes verified:
 *   1. IMPERSONATION: authorId must equal request.auth.uid on create (rule enforced).
 *   2. OWNERSHIP: only comment author can delete their own comment.
 *   3. EDIT SCOPE: only comment author can edit; others can only update likes/likedBy.
 *   4. BLOAT PROOF: parent doc body is NOT touched by comment writes (no arrayUnion to parent).
 *   5. COUNTER: commentCount increment on parent is permitted (affectedKeys allowlist).
 *   6. CLOSURE: writing commentsList to parent doc is now DENIED (removed from allowlist).
 *
 * Personas:
 *   alice  — comment author
 *   bob    — different authenticated user (non-author)
 *   carol  — another authenticated user
 *   unauth — unauthenticated caller
 *
 * Announcement doc: ann_f11 (borough: Hackney)
 * Comment docs:     cmt_alice_001 (authored by alice), cmt_bob_001 (authored by bob)
 *
 * Tests (15):
 *
 *   --- CREATE (impersonation gate) ---
 *   T-F11-create-own          alice creates comment with authorId==self → SUCCEEDS
 *   T-F11-create-impersonate  alice creates comment with authorId==bob  → DENIED
 *   T-F11-create-unauth       unauthenticated create                    → DENIED
 *   T-F11-reply-own           alice creates reply with replyToId set, authorId==self → SUCCEEDS
 *
 *   --- READ ---
 *   T-F11-read-authed         bob reads alice's comment → SUCCEEDS
 *   T-F11-read-unauth         unauthenticated read      → DENIED
 *
 *   --- UPDATE (ownership + likes-only gate) ---
 *   T-F11-update-author       alice edits own comment content → SUCCEEDS
 *   T-F11-update-nonauthor    bob edits alice's comment → DENIED
 *   T-F11-update-likes-any    carol updates only likes/likedBy on alice's comment → SUCCEEDS
 *   T-F11-update-likes-extra  carol tries to update likes AND content together → DENIED
 *
 *   --- DELETE ---
 *   T-F11-delete-author       alice deletes own comment → SUCCEEDS
 *   T-F11-delete-nonauthor    bob deletes alice's comment → DENIED
 *
 *   --- PARENT DOC: counter allowed, commentsList closed ---
 *   T-F11-parent-commentcount    any auth user increments commentCount on parent → SUCCEEDS
 *   T-F11-parent-commentslist    any auth user writes commentsList to parent → DENIED
 *   T-F11-parent-bloat-check     comment write goes to subcollection only; parent body unchanged → CONFIRMED
 */

import {
  initializeTestEnvironment,
  RulesTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import { doc, setDoc, getDoc, addDoc, updateDoc, deleteDoc, collection } from "firebase/firestore";
import * as fs from "fs";

// ── Project / Persona constants ─────────────────────────────────────────────
const PROJECT_ID    = "huddl-f11-project";
const ALICE_UID     = "alice_f11_uid";
const BOB_UID       = "bob_f11_uid";
const CAROL_UID     = "carol_f11_uid";
const ANN_ID        = "ann_f11";
const CMT_ALICE_ID  = "cmt_alice_001";
const CMT_BOB_ID    = "cmt_bob_001";

let testEnv: RulesTestEnvironment;

// ── Helpers ──────────────────────────────────────────────────────────────────
function aliceCtx()  { return testEnv.authenticatedContext(ALICE_UID); }
function bobCtx()    { return testEnv.authenticatedContext(BOB_UID); }
function carolCtx()  { return testEnv.authenticatedContext(CAROL_UID); }
function unauthCtx() { return testEnv.unauthenticatedContext(); }

function annRef(ctx: ReturnType<typeof aliceCtx>) {
  return doc(ctx.firestore(), "borough_announcements", ANN_ID);
}
function commentCol(ctx: ReturnType<typeof aliceCtx>) {
  return collection(ctx.firestore(), "borough_announcements", ANN_ID, "comments");
}
function commentDoc(ctx: ReturnType<typeof aliceCtx>, cid: string) {
  return doc(ctx.firestore(), "borough_announcements", ANN_ID, "comments", cid);
}

// ── Seed data ────────────────────────────────────────────────────────────────
async function seedData() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // Parent announcement doc
    await setDoc(doc(db, "borough_announcements", ANN_ID), {
      authorId:      ALICE_UID,
      authorName:    "Alice",
      boroughId:     "Hackney",
      content:       "Test announcement for F-11 rule tests",
      commentCount:  2,
      likes:         0,
      likedBy:       [],
      isPinned:      false,
      isBookmarked:  false,
      shares:        0,
      isPartnerPost: false,
    });

    // Alice's comment (alice is the author)
    await setDoc(doc(db, "borough_announcements", ANN_ID, "comments", CMT_ALICE_ID), {
      authorId:      ALICE_UID,
      authorName:    "Alice",
      authorPhotoUrl: null,
      content:       "Alice's top-level comment",
      createdAt:     new Date(),
      isReply:       false,
      boroughId:     "Hackney",
      announcementId: ANN_ID,
      likes:         0,
      likedBy:       [],
    });

    // Bob's comment
    await setDoc(doc(db, "borough_announcements", ANN_ID, "comments", CMT_BOB_ID), {
      authorId:      BOB_UID,
      authorName:    "Bob",
      authorPhotoUrl: null,
      content:       "Bob's comment",
      createdAt:     new Date(),
      isReply:       false,
      boroughId:     "Hackney",
      announcementId: ANN_ID,
      likes:         0,
      likedBy:       [],
    });
  });
}

// ── Suite setup / teardown ───────────────────────────────────────────────────
beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync("/home/user/flutter_app/firestore.rules", "utf8"),
      host:  "127.0.0.1",
      port:  8180,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seedData();
});

afterAll(async () => {
  await testEnv.cleanup();
});

// ─────────────────────────────────────────────────────────────────────────────
// CREATE — impersonation gate
// ─────────────────────────────────────────────────────────────────────────────
describe("F-11 comments subcollection — CREATE", () => {

  it("T-F11-create-own: alice creates comment with authorId==self → SUCCEEDS", async () => {
    await assertSucceeds(
      addDoc(commentCol(aliceCtx()), {
        authorId:       ALICE_UID,
        authorName:     "Alice",
        authorPhotoUrl: null,
        content:        "A legitimate comment",
        createdAt:      new Date(),
        isReply:        false,
        boroughId:      "Hackney",
        announcementId: ANN_ID,
      })
    );
  });

  it("T-F11-create-impersonate: alice creates comment with authorId==bob (impersonation) → DENIED", async () => {
    await assertFails(
      addDoc(commentCol(aliceCtx()), {
        authorId:       BOB_UID,       // ← attacker sets someone else's uid
        authorName:     "Definitely Not Alice",
        content:        "Impersonated comment",
        createdAt:      new Date(),
        isReply:        false,
        boroughId:      "Hackney",
        announcementId: ANN_ID,
      })
    );
  });

  it("T-F11-create-unauth: unauthenticated create → DENIED", async () => {
    await assertFails(
      addDoc(commentCol(unauthCtx()), {
        authorId:       "anyone",
        authorName:     "Nobody",
        content:        "Unauth comment",
        createdAt:      new Date(),
        isReply:        false,
        boroughId:      "Hackney",
        announcementId: ANN_ID,
      })
    );
  });

  it("T-F11-reply-own: alice creates reply with replyToId set and authorId==self → SUCCEEDS", async () => {
    await assertSucceeds(
      addDoc(commentCol(aliceCtx()), {
        authorId:       ALICE_UID,
        authorName:     "Alice",
        authorPhotoUrl: null,
        content:        "This is a reply",
        createdAt:      new Date(),
        isReply:        true,
        replyToId:      CMT_BOB_ID,
        replyToName:    "Bob",
        boroughId:      "Hackney",
        announcementId: ANN_ID,
      })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// READ
// ─────────────────────────────────────────────────────────────────────────────
describe("F-11 comments subcollection — READ", () => {

  it("T-F11-read-authed: bob reads alice's comment → SUCCEEDS", async () => {
    await assertSucceeds(
      getDoc(commentDoc(bobCtx(), CMT_ALICE_ID))
    );
  });

  it("T-F11-read-unauth: unauthenticated reads a comment → DENIED", async () => {
    await assertFails(
      getDoc(commentDoc(unauthCtx(), CMT_ALICE_ID))
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// UPDATE — ownership + likes-only gate
// ─────────────────────────────────────────────────────────────────────────────
describe("F-11 comments subcollection — UPDATE", () => {

  it("T-F11-update-author: alice edits content of her own comment → SUCCEEDS", async () => {
    await assertSucceeds(
      updateDoc(commentDoc(aliceCtx(), CMT_ALICE_ID), {
        content: "Alice edited her comment",
      })
    );
  });

  it("T-F11-update-nonauthor: bob tries to edit alice's comment → DENIED", async () => {
    await assertFails(
      updateDoc(commentDoc(bobCtx(), CMT_ALICE_ID), {
        content: "Bob hijacking alice's comment",
      })
    );
  });

  it("T-F11-update-likes-any: carol updates only likes/likedBy on alice's comment → SUCCEEDS", async () => {
    await assertSucceeds(
      updateDoc(commentDoc(carolCtx(), CMT_ALICE_ID), {
        likes:   1,
        likedBy: [CAROL_UID],
      })
    );
  });

  it("T-F11-update-likes-extra: carol updates likes AND content together → DENIED", async () => {
    await assertFails(
      updateDoc(commentDoc(carolCtx(), CMT_ALICE_ID), {
        likes:   1,
        likedBy: [CAROL_UID],
        content: "Carol sneaking in a content change",  // ← outside hasOnly allowlist
      })
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE
// ─────────────────────────────────────────────────────────────────────────────
describe("F-11 comments subcollection — DELETE", () => {

  it("T-F11-delete-author: alice deletes her own comment → SUCCEEDS", async () => {
    await assertSucceeds(
      deleteDoc(commentDoc(aliceCtx(), CMT_ALICE_ID))
    );
  });

  it("T-F11-delete-nonauthor: bob tries to delete alice's comment → DENIED", async () => {
    await assertFails(
      deleteDoc(commentDoc(bobCtx(), CMT_ALICE_ID))
    );
  });

});

// ─────────────────────────────────────────────────────────────────────────────
// PARENT DOC: commentCount allowed; commentsList closed; bloat confirmation
// ─────────────────────────────────────────────────────────────────────────────
describe("F-11 parent doc — counter + closure", () => {

  it("T-F11-parent-commentcount: any auth user increments commentCount on parent → SUCCEEDS", async () => {
    // Simulates the FieldValue.increment(1) fired after addComment()
    // bob is not the announcement author but commentCount is in the affectedKeys allowlist
    await assertSucceeds(
      updateDoc(annRef(bobCtx()), {
        commentCount: 3,   // emulator doesn't support FieldValue — pass raw increment value
      })
    );
  });

  it("T-F11-parent-commentslist: any auth user writes commentsList to parent → DENIED", async () => {
    // commentsList was removed from affectedKeys().hasOnly() in F-11.
    // A non-author writing commentsList to the parent doc must now be denied.
    await assertFails(
      updateDoc(annRef(bobCtx()), {
        commentsList: [{ authorName: "Bob", content: "old-style embedded comment" }],
      })
    );
  });

  it("T-F11-parent-bloat-check: comment write goes to subcollection only; parent doc body is unchanged", async () => {
    // Read parent doc BEFORE the comment write
    // withSecurityRulesDisabled returns void; capture via mutable ref.
    let beforeData: Record<string, unknown> = {};
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDoc(doc(ctx.firestore(), "borough_announcements", ANN_ID));
      beforeData = (snap.data() ?? {}) as Record<string, unknown>;
    });

    // Alice posts a new comment via the subcollection (not arrayUnion on parent)
    await assertSucceeds(
      addDoc(commentCol(aliceCtx()), {
        authorId:       ALICE_UID,
        authorName:     "Alice",
        content:        "Bloat check comment",
        createdAt:      new Date(),
        isReply:        false,
        boroughId:      "Hackney",
        announcementId: ANN_ID,
      })
    );

    // Read parent doc AFTER the comment write
    let afterData: Record<string, unknown> = {};
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDoc(doc(ctx.firestore(), "borough_announcements", ANN_ID));
      afterData = (snap.data() ?? {}) as Record<string, unknown>;
    });

    // Parent doc body must NOT have grown with a commentsList field
    expect(afterData["commentsList"]).toBeUndefined();
    // commentCount on the parent is untouched by the subcollection write itself
    // (the client fires a separate increment; the subcollection write is isolated)
    expect(afterData["commentCount"]).toEqual(beforeData["commentCount"]);
  });

});
