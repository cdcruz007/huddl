/**
 * Huddl — Firestore Security Rules Tests
 * Workflows: B (chat), C (save/bookmark), E (marketplace), G (groups/polls), H (SEND/privacy)
 *
 * Run: FIRESTORE_EMULATOR_HOST=localhost:8080 npx jest firestore_rules.test.ts
 * Or via npm test (which sets env vars via the emulator harness).
 *
 * Rules under test: firestore.rules
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
  RulesTestContext,
} from "@firebase/rules-unit-testing";
import { doc, setDoc, getDoc, updateDoc, deleteDoc, collection, addDoc } from "firebase/firestore";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "huddl-test-project";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

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

// ── Helpers ──────────────────────────────────────────────────────────────────

function authedContext(uid: string): RulesTestContext {
  return testEnv.authenticatedContext(uid);
}

function unauthedContext(): RulesTestContext {
  return testEnv.unauthenticatedContext();
}

// Seed a document directly without rules using the admin context.
async function seedDoc(collPath: string, docId: string, data: object): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), collPath, docId), data);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW C: Data Persistence & Save/Bookmark
// Asserts: write scoped to owner, different user CANNOT read it.
// ─────────────────────────────────────────────────────────────────────────────

describe("Workflow C — saved items security", () => {
  const ownerUid = "user_alice";
  const otherUid = "user_bob";

  test("owner can write their own saved_items doc", async () => {
    const ctx = authedContext(ownerUid);
    const ref = doc(ctx.firestore(), "users", ownerUid, "savedListings", "listing_001");
    await assertSucceeds(
      setDoc(ref, { userId: ownerUid, listingId: "listing_001", savedAt: new Date().toISOString() })
    );
  });

  test("owner can read their own saved_items doc back", async () => {
    await seedDoc(`users/${ownerUid}/savedListings`, "listing_001", {
      userId: ownerUid,
      listingId: "listing_001",
      savedAt: "2024-01-01",
    });
    const ctx = authedContext(ownerUid);
    const ref = doc(ctx.firestore(), "users", ownerUid, "savedListings", "listing_001");
    await assertSucceeds(getDoc(ref));
  });

  test("DIFFERENT USER cannot read another user's saved_items — rule enforced", async () => {
    await seedDoc(`users/${ownerUid}/savedListings`, "listing_001", {
      userId: ownerUid,
      listingId: "listing_001",
    });
    const otherCtx = authedContext(otherUid);
    const ref = doc(otherCtx.firestore(), "users", ownerUid, "savedListings", "listing_001");
    await assertFails(getDoc(ref));
  });

  test("unauthenticated user cannot read saved_items", async () => {
    await seedDoc(`users/${ownerUid}/savedListings`, "listing_001", { userId: ownerUid });
    const ctx = unauthedContext();
    const ref = doc(ctx.firestore(), "users", ownerUid, "savedListings", "listing_001");
    await assertFails(getDoc(ref));
  });

  test("owner can delete their own saved item (unsave)", async () => {
    await seedDoc(`users/${ownerUid}/savedListings`, "listing_001", { userId: ownerUid });
    const ctx = authedContext(ownerUid);
    const ref = doc(ctx.firestore(), "users", ownerUid, "savedListings", "listing_001");
    await assertSucceeds(deleteDoc(ref));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW E: Marketplace — Listings
// ─────────────────────────────────────────────────────────────────────────────

describe("Workflow E — marketplace listings security", () => {
  const sellerUid = "user_seller";
  const buyerUid = "user_buyer";
  const listingId = "listing_stroller_001";

  test("authenticated user can create a listing if createdBy == their uid", async () => {
    const ctx = authedContext(sellerUid);
    const ref = doc(ctx.firestore(), "listings", listingId);
    await assertSucceeds(
      setDoc(ref, {
        createdBy: sellerUid,
        title: "Baby stroller",
        price: 40,
        borough: "Cambridge",
        status: "active",
        createdAt: new Date().toISOString(),
      })
    );
  });

  test("user CANNOT create listing with a different createdBy uid", async () => {
    const ctx = authedContext(buyerUid);
    const ref = doc(ctx.firestore(), "listings", listingId);
    await assertFails(
      setDoc(ref, {
        createdBy: sellerUid, // attacker spoofing seller's uid
        title: "Fake listing",
        price: 0,
      })
    );
  });

  test("any authenticated user can read listings", async () => {
    await seedDoc("listings", listingId, { createdBy: sellerUid, title: "Stroller", price: 40 });
    const ctx = authedContext(buyerUid);
    const ref = doc(ctx.firestore(), "listings", listingId);
    await assertSucceeds(getDoc(ref));
  });

  test("seller can update their own listing (title change)", async () => {
    await seedDoc("listings", listingId, { createdBy: sellerUid, title: "Stroller", price: 40 });
    const ctx = authedContext(sellerUid);
    const ref = doc(ctx.firestore(), "listings", listingId);
    await assertSucceeds(updateDoc(ref, { title: "Baby stroller v2", price: 35 }));
  });

  test("buyer CANNOT update seller's listing arbitrary fields", async () => {
    await seedDoc("listings", listingId, { createdBy: sellerUid, title: "Stroller", price: 40 });
    const ctx = authedContext(buyerUid);
    const ref = doc(ctx.firestore(), "listings", listingId);
    await assertFails(updateDoc(ref, { title: "Hacked title", price: 1 }));
  });

  test("buyer CAN update viewCount/saveCount (aggregate field)", async () => {
    await seedDoc("listings", listingId, {
      createdBy: sellerUid,
      title: "Stroller",
      price: 40,
      viewCount: 0,
      saveCount: 0,
      updatedAt: "2024-01-01",
    });
    const ctx = authedContext(buyerUid);
    const ref = doc(ctx.firestore(), "listings", listingId);
    await assertSucceeds(updateDoc(ref, { viewCount: 1, updatedAt: new Date().toISOString() }));
  });

  test("seller can delete their own listing", async () => {
    await seedDoc("listings", listingId, { createdBy: sellerUid, title: "Stroller" });
    const ctx = authedContext(sellerUid);
    const ref = doc(ctx.firestore(), "listings", listingId);
    await assertSucceeds(deleteDoc(ref));
  });

  test("buyer CANNOT delete seller's listing", async () => {
    await seedDoc("listings", listingId, { createdBy: sellerUid, title: "Stroller" });
    const ctx = authedContext(buyerUid);
    const ref = doc(ctx.firestore(), "listings", listingId);
    await assertFails(deleteDoc(ref));
  });

  // Saves sub-collection
  test("buyer can save a listing (creates saves/{userId} sub-doc)", async () => {
    await seedDoc("listings", listingId, { createdBy: sellerUid, title: "Stroller" });
    const ctx = authedContext(buyerUid);
    const ref = doc(ctx.firestore(), "listings", listingId, "saves", buyerUid);
    await assertSucceeds(
      setDoc(ref, { userId: buyerUid, savedAt: new Date().toISOString() })
    );
  });

  test("buyer CANNOT save with a different userId in sub-doc", async () => {
    await seedDoc("listings", listingId, { createdBy: sellerUid, title: "Stroller" });
    const ctx = authedContext(buyerUid);
    // doc path userId segment must match request.auth.uid
    const ref = doc(ctx.firestore(), "listings", listingId, "saves", "other_user_uid");
    await assertFails(
      setDoc(ref, { userId: "other_user_uid", savedAt: new Date().toISOString() })
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW B: Chat & Threading
// ─────────────────────────────────────────────────────────────────────────────

describe("Workflow B — chat & threading security", () => {
  const senderUid = "user_sender";
  const receiverUid = "user_receiver";
  const thirdPartyUid = "user_third";
  const groupId = "group_park_parents";
  const convoId = "convo_alice_bob";

  test("authenticated user can create a group message with correct senderId", async () => {
    const ctx = authedContext(senderUid);
    const ref = doc(ctx.firestore(), "group_messages", "msg_001");
    await assertSucceeds(
      setDoc(ref, {
        senderId: senderUid,
        groupId,
        text: "Hello park parents!",
        createdAt: new Date().toISOString(),
      })
    );
  });

  test("user CANNOT send message with spoofed senderId", async () => {
    const ctx = authedContext(senderUid);
    const ref = doc(ctx.firestore(), "group_messages", "msg_spoof");
    await assertFails(
      setDoc(ref, {
        senderId: "admin_uid", // spoofed
        groupId,
        text: "I am admin",
        createdAt: new Date().toISOString(),
      })
    );
  });

  test("any auth user can read group messages", async () => {
    await seedDoc("group_messages", "msg_001", { senderId: senderUid, groupId, text: "Hi" });
    const ctx = authedContext(receiverUid);
    const ref = doc(ctx.firestore(), "group_messages", "msg_001");
    await assertSucceeds(getDoc(ref));
  });

  test("sender can update their own message (edit text)", async () => {
    await seedDoc("group_messages", "msg_001", { senderId: senderUid, groupId, text: "Hi" });
    const ctx = authedContext(senderUid);
    const ref = doc(ctx.firestore(), "group_messages", "msg_001");
    await assertSucceeds(updateDoc(ref, { text: "Hi edited", updatedAt: new Date().toISOString() }));
  });

  test("non-sender CAN add a reaction (reactions field only)", async () => {
    await seedDoc("group_messages", "msg_001", {
      senderId: senderUid,
      groupId,
      text: "Hi",
      reactions: {},
      reactionUsers: {},
      updatedAt: "2024-01-01",
    });
    const ctx = authedContext(receiverUid);
    const ref = doc(ctx.firestore(), "group_messages", "msg_001");
    await assertSucceeds(
      updateDoc(ref, { reactions: { "👍": 1 }, reactionUsers: {}, updatedAt: new Date().toISOString() })
    );
  });

  test("non-sender CANNOT change message text (not in allowed fields)", async () => {
    await seedDoc("group_messages", "msg_001", { senderId: senderUid, groupId, text: "Hi" });
    const ctx = authedContext(receiverUid);
    const ref = doc(ctx.firestore(), "group_messages", "msg_001");
    await assertFails(updateDoc(ref, { text: "Hacked" }));
  });

  test("sender can delete (unsend) their own message", async () => {
    await seedDoc("group_messages", "msg_001", { senderId: senderUid, groupId, text: "Hi" });
    const ctx = authedContext(senderUid);
    const ref = doc(ctx.firestore(), "group_messages", "msg_001");
    await assertSucceeds(deleteDoc(ref));
  });

  test("non-sender CANNOT delete another user's message", async () => {
    await seedDoc("group_messages", "msg_001", { senderId: senderUid, groupId, text: "Hi" });
    const ctx = authedContext(thirdPartyUid);
    const ref = doc(ctx.firestore(), "group_messages", "msg_001");
    await assertFails(deleteDoc(ref));
  });

  // DM conversations
  test("participant can read their conversation", async () => {
    await seedDoc("conversations", convoId, {
      participantIds: [senderUid, receiverUid],
      createdAt: "2024-01-01",
    });
    const ctx = authedContext(senderUid);
    const ref = doc(ctx.firestore(), "conversations", convoId);
    await assertSucceeds(getDoc(ref));
  });

  test("third party CANNOT read a conversation they are not part of", async () => {
    await seedDoc("conversations", convoId, {
      participantIds: [senderUid, receiverUid],
    });
    const ctx = authedContext(thirdPartyUid);
    const ref = doc(ctx.firestore(), "conversations", convoId);
    await assertFails(getDoc(ref));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW G: Groups
// ─────────────────────────────────────────────────────────────────────────────

describe("Workflow G — groups security", () => {
  const creatorUid = "user_creator";
  const memberUid = "user_member";
  const outsiderUid = "user_outsider";
  const groupId = "group_park_parents";

  test("auth user can create a group if creatorUid == their uid", async () => {
    const ctx = authedContext(creatorUid);
    const ref = doc(ctx.firestore(), "groups", groupId);
    await assertSucceeds(
      setDoc(ref, {
        creatorUid,
        name: "Park Parents",
        borough: "Cambridge",
        memberIds: [creatorUid],
        memberCount: 1,
        createdAt: new Date().toISOString(),
      })
    );
  });

  test("user CANNOT create group with spoofed creatorUid", async () => {
    const ctx = authedContext(outsiderUid);
    const ref = doc(ctx.firestore(), "groups", "group_fake");
    await assertFails(
      setDoc(ref, { creatorUid, name: "Fake Group", memberIds: [outsiderUid] })
    );
  });

  test("any auth user can read group metadata", async () => {
    await seedDoc("groups", groupId, {
      creatorUid,
      name: "Park Parents",
      memberIds: [creatorUid],
    });
    const ctx = authedContext(outsiderUid);
    const ref = doc(ctx.firestore(), "groups", groupId);
    await assertSucceeds(getDoc(ref));
  });

  test("member can update allowed activity fields (lastMessage)", async () => {
    await seedDoc("groups", groupId, {
      creatorUid,
      name: "Park Parents",
      memberIds: [creatorUid, memberUid],
      lastMessage: "",
      lastMessageTime: "2024-01-01",
      lastActiveAt: "2024-01-01",
      memberCount: 2,
      lastSenderName: "",
    });
    const ctx = authedContext(memberUid);
    const ref = doc(ctx.firestore(), "groups", groupId);
    await assertSucceeds(
      updateDoc(ref, {
        lastMessage: "Hello!",
        lastMessageTime: new Date().toISOString(),
        lastActiveAt: new Date().toISOString(),
        memberCount: 2,
        memberIds: [creatorUid, memberUid],
        lastSenderName: "Member",
      })
    );
  });

  test("outsider CANNOT update group name (not allowed field)", async () => {
    await seedDoc("groups", groupId, {
      creatorUid,
      name: "Park Parents",
      memberIds: [creatorUid],
    });
    const ctx = authedContext(outsiderUid);
    const ref = doc(ctx.firestore(), "groups", groupId);
    await assertFails(updateDoc(ref, { name: "Hacked Name" }));
  });

  test("any auth user can self-join (add only themselves to memberIds)", async () => {
    await seedDoc("groups", groupId, {
      creatorUid,
      name: "Park Parents",
      memberIds: [creatorUid],
      memberCount: 1,
      updatedAt: "2024-01-01",
    });
    const ctx = authedContext(outsiderUid);
    const ref = doc(ctx.firestore(), "groups", groupId);
    // Self-join: update only memberIds, memberCount, updatedAt
    await assertSucceeds(
      updateDoc(ref, {
        memberIds: [creatorUid, outsiderUid],
        memberCount: 2,
        updatedAt: new Date().toISOString(),
      })
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW G: Polls
// ─────────────────────────────────────────────────────────────────────────────

describe("Workflow G — polls security", () => {
  const pollCreatorUid = "user_poll_creator";
  const voterUid = "user_voter";
  const pollId = "poll_park_meetup";

  test("auth user can create a poll with correct createdByUid", async () => {
    const ctx = authedContext(pollCreatorUid);
    const ref = doc(ctx.firestore(), "polls", pollId);
    await assertSucceeds(
      setDoc(ref, {
        createdByUid: pollCreatorUid,
        question: "Best day for meetup?",
        options: [
          { id: "a", text: "Saturday", votes: 0 },
          { id: "b", text: "Sunday", votes: 0 },
        ],
        voters: {},
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      })
    );
  });

  test("any auth user can read a poll", async () => {
    await seedDoc("polls", pollId, {
      createdByUid: pollCreatorUid,
      question: "Best day?",
      options: [],
      voters: {},
    });
    const ctx = authedContext(voterUid);
    const ref = doc(ctx.firestore(), "polls", pollId);
    await assertSucceeds(getDoc(ref));
  });

  test("voter can update options and voters fields (voting)", async () => {
    await seedDoc("polls", pollId, {
      createdByUid: pollCreatorUid,
      question: "Best day?",
      options: [{ id: "a", text: "Saturday", votes: 0 }],
      voters: {},
      updatedAt: "2024-01-01",
    });
    const ctx = authedContext(voterUid);
    const ref = doc(ctx.firestore(), "polls", pollId);
    await assertSucceeds(
      updateDoc(ref, {
        options: [{ id: "a", text: "Saturday", votes: 1 }],
        voters: { [voterUid]: "a" },
        updatedAt: new Date().toISOString(),
      })
    );
  });

  test("voter CANNOT update poll question (not an allowed field for non-creator)", async () => {
    await seedDoc("polls", pollId, {
      createdByUid: pollCreatorUid,
      question: "Best day?",
      options: [],
      voters: {},
    });
    const ctx = authedContext(voterUid);
    const ref = doc(ctx.firestore(), "polls", pollId);
    await assertFails(updateDoc(ref, { question: "Hacked question?" }));
  });

  test("creator can soft-delete their poll", async () => {
    await seedDoc("polls", pollId, {
      createdByUid: pollCreatorUid,
      question: "Best day?",
    });
    const ctx = authedContext(pollCreatorUid);
    const ref = doc(ctx.firestore(), "polls", pollId);
    await assertSucceeds(deleteDoc(ref));
  });

  test("non-creator CANNOT delete a poll", async () => {
    await seedDoc("polls", pollId, { createdByUid: pollCreatorUid, question: "Best day?" });
    const ctx = authedContext(voterUid);
    const ref = doc(ctx.firestore(), "polls", pollId);
    await assertFails(deleteDoc(ref));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW H: SEND Hub — privacy prefs + deadlines
// ─────────────────────────────────────────────────────────────────────────────

describe("Workflow H — SEND sensitive preferences security", () => {
  const sendUserUid = "user_send_parent";
  const otherUid = "user_other";

  test("owner can write their SEND deadline doc", async () => {
    const ctx = authedContext(sendUserUid);
    const ref = doc(ctx.firestore(), "users", sendUserUid, "deadlines", "deadline_001");
    await assertSucceeds(
      setDoc(ref, {
        uid: sendUserUid,
        title: "EHCP Review",
        dueDate: "2024-06-01",
        category: "ehcp",
        isCompleted: false,
        createdAt: new Date().toISOString(),
      })
    );
  });

  test("owner can read their own SEND deadline doc", async () => {
    await seedDoc(`users/${sendUserUid}/deadlines`, "deadline_001", {
      uid: sendUserUid,
      title: "EHCP Review",
      dueDate: "2024-06-01",
    });
    const ctx = authedContext(sendUserUid);
    const ref = doc(ctx.firestore(), "users", sendUserUid, "deadlines", "deadline_001");
    await assertSucceeds(getDoc(ref));
  });

  test("DIFFERENT USER cannot read SEND deadlines — sensitive data protected", async () => {
    await seedDoc(`users/${sendUserUid}/deadlines`, "deadline_001", {
      uid: sendUserUid,
      title: "EHCP Review",
    });
    const ctx = authedContext(otherUid);
    const ref = doc(ctx.firestore(), "users", sendUserUid, "deadlines", "deadline_001");
    await assertFails(getDoc(ref));
  });

  test("unauthenticated user cannot read SEND deadlines", async () => {
    await seedDoc(`users/${sendUserUid}/deadlines`, "deadline_001", {
      uid: sendUserUid,
      title: "EHCP Review",
    });
    const ctx = unauthedContext();
    const ref = doc(ctx.firestore(), "users", sendUserUid, "deadlines", "deadline_001");
    await assertFails(getDoc(ref));
  });

  // notifPrefs (privacy preferences)
  test("owner can write notification preferences", async () => {
    const ctx = authedContext(sendUserUid);
    const ref = doc(ctx.firestore(), "users", sendUserUid, "notifPrefs", "prefs");
    await assertSucceeds(
      setDoc(ref, {
        pushEnabled: true,
        groupMessages: true,
        showOnlineStatus: false,
        readReceipts: false,
        voiceMessageConsent: true,
      })
    );
  });

  test("owner can read their own notification preferences", async () => {
    await seedDoc(`users/${sendUserUid}/notifPrefs`, "prefs", {
      pushEnabled: true,
      showOnlineStatus: false,
    });
    const ctx = authedContext(sendUserUid);
    const ref = doc(ctx.firestore(), "users", sendUserUid, "notifPrefs", "prefs");
    await assertSucceeds(getDoc(ref));
  });

  test("OTHER USER cannot read another user's notification preferences", async () => {
    await seedDoc(`users/${sendUserUid}/notifPrefs`, "prefs", {
      pushEnabled: true,
      showOnlineStatus: false,
    });
    const ctx = authedContext(otherUid);
    const ref = doc(ctx.firestore(), "users", sendUserUid, "notifPrefs", "prefs");
    await assertFails(getDoc(ref));
  });

  // Top-level deadlines collection (send_navigator_service also uses this)
  test("owner can create top-level deadline doc with uid == own uid", async () => {
    const ctx = authedContext(sendUserUid);
    const ref = doc(ctx.firestore(), "deadlines", "tdl_001");
    await assertSucceeds(
      setDoc(ref, {
        uid: sendUserUid,
        title: "School Application",
        dueDate: "2024-10-01",
      })
    );
  });

  test("owner can read their top-level deadline doc", async () => {
    await seedDoc("deadlines", "tdl_001", { uid: sendUserUid, title: "School App" });
    const ctx = authedContext(sendUserUid);
    const ref = doc(ctx.firestore(), "deadlines", "tdl_001");
    await assertSucceeds(getDoc(ref));
  });

  test("other user CANNOT read top-level deadline with different uid", async () => {
    await seedDoc("deadlines", "tdl_001", { uid: sendUserUid, title: "School App" });
    const ctx = authedContext(otherUid);
    const ref = doc(ctx.firestore(), "deadlines", "tdl_001");
    await assertFails(getDoc(ref));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW D: Notifications — security
// ─────────────────────────────────────────────────────────────────────────────

describe("Workflow D — notifications security", () => {
  const recipientUid = "user_recipient";
  const otherUid = "user_sender_notif";

  test("recipient can read their own notification", async () => {
    await seedDoc("notifications", "notif_001", {
      recipientId: recipientUid,
      senderId: otherUid,
      type: "group_message",
      isRead: false,
    });
    const ctx = authedContext(recipientUid);
    const ref = doc(ctx.firestore(), "notifications", "notif_001");
    await assertSucceeds(getDoc(ref));
  });

  test("other user CANNOT read a notification for a different recipient", async () => {
    await seedDoc("notifications", "notif_001", {
      recipientId: recipientUid,
      senderId: otherUid,
      type: "group_message",
      isRead: false,
    });
    const ctx = authedContext(otherUid);
    const ref = doc(ctx.firestore(), "notifications", "notif_001");
    await assertFails(getDoc(ref));
  });

  test("recipient can mark notification as read (isRead + readAt only)", async () => {
    await seedDoc("notifications", "notif_001", {
      recipientId: recipientUid,
      senderId: otherUid,
      isRead: false,
      readAt: null,
    });
    const ctx = authedContext(recipientUid);
    const ref = doc(ctx.firestore(), "notifications", "notif_001");
    await assertSucceeds(
      updateDoc(ref, { isRead: true, readAt: new Date().toISOString() })
    );
  });

  test("client CANNOT hard-delete a notification", async () => {
    await seedDoc("notifications", "notif_001", {
      recipientId: recipientUid,
      senderId: otherUid,
      isRead: false,
    });
    const ctx = authedContext(recipientUid);
    const ref = doc(ctx.firestore(), "notifications", "notif_001");
    await assertFails(deleteDoc(ref));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// User subscriptions — write must be blocked from client
// ─────────────────────────────────────────────────────────────────────────────

describe("Subscription tier — client write blocked", () => {
  const uid = "user_subscriber";

  test("user can read their own subscription doc", async () => {
    await seedDoc("subscriptions", uid, { userId: uid, tier: "free", isActive: true });
    const ctx = authedContext(uid);
    const ref = doc(ctx.firestore(), "subscriptions", uid);
    await assertSucceeds(getDoc(ref));
  });

  test("client CANNOT write subscription doc (tier manipulation blocked)", async () => {
    const ctx = authedContext(uid);
    const ref = doc(ctx.firestore(), "subscriptions", uid);
    await assertFails(
      setDoc(ref, { userId: uid, tier: "premium", isActive: true })
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// LSS-1 — local_services verification cannot be forged
//
// Change A: verificationTier removed from the endorsement-aggregate hasOnly
//           allowlist — a non-owner can no longer write it via that branch.
// Change B: create rule now rejects any payload where verificationTier != 'none'
//           or isVerified != false — a client cannot stamp a pre-verified listing.
//
// boroughMatches() reads users_public/{uid}.borough via get(), so every
// create/owner-update test must first seed the writer's public borough doc.
// Non-owner update tests go through the hasOnly branch (no borough check).
// ─────────────────────────────────────────────────────────────────────────────

describe("LSS-1 — local_services verification cannot be forged", () => {
  const ownerUid    = "lss1_owner";
  const attackerUid = "lss1_attacker";
  const endorserUid = "lss1_endorser";
  const listingId   = "listing_lss1_001";

  // ── Change B tests: create rule ────────────────────────────────────────────

  test("DENY: client cannot create a pre-verified listing (verificationTier huddlVerified)", async () => {
    // boroughMatches() needs users_public/{owner}.borough
    await seedDoc("users_public", ownerUid, { borough: "Cambridge" });

    const ctx = authedContext(ownerUid);
    const ref = doc(ctx.firestore(), "local_services", listingId);
    await assertFails(
      setDoc(ref, {
        createdByUid:     ownerUid,
        borough:          "Cambridge",
        verificationTier: "huddlVerified",
        name:             "X",
      })
    );
  });

  test("DENY: client cannot create a listing with isVerified true", async () => {
    await seedDoc("users_public", ownerUid, { borough: "Cambridge" });

    const ctx = authedContext(ownerUid);
    const ref = doc(ctx.firestore(), "local_services", listingId);
    await assertFails(
      setDoc(ref, {
        createdByUid: ownerUid,
        borough:      "Cambridge",
        isVerified:   true,
        name:         "X",
      })
    );
  });

  test("ALLOW: client can create an unverified listing (verificationTier none / isVerified false)", async () => {
    await seedDoc("users_public", ownerUid, { borough: "Cambridge" });

    const ctx = authedContext(ownerUid);
    const ref = doc(ctx.firestore(), "local_services", listingId);
    await assertSucceeds(
      setDoc(ref, {
        createdByUid:     ownerUid,
        borough:          "Cambridge",
        name:             "X",
        verificationTier: "none",
        isVerified:       false,
      })
    );
  });

  // ── Change A tests: update / endorsement-aggregate branch ─────────────────

  test("DENY: a non-owner cannot update another listing's verificationTier via the endorsement allowlist", async () => {
    // Seed the owner's public borough (needed by seedDoc listing? No — seedDoc bypasses
    // rules. Only needed when an authed client write triggers boroughMatches().
    // The attacker goes through the hasOnly branch (no borough check), but we seed
    // the owner borough anyway for completeness and to keep the listing realistic.
    await seedDoc("users_public", ownerUid, { borough: "Cambridge" });
    await seedDoc("local_services", listingId, {
      createdByUid:     ownerUid,
      borough:          "Cambridge",
      name:             "X",
      verificationTier: "none",
      isVerified:       false,
      endorsementCount: 0,
    });

    const ctx = authedContext(attackerUid);
    const ref = doc(ctx.firestore(), "local_services", listingId);
    await assertFails(
      updateDoc(ref, {
        verificationTier: "huddlVerified",
        updatedAt:        new Date().toISOString(),
      })
    );
  });

  test("ALLOW (regression): a non-owner CAN still update endorsement counters", async () => {
    await seedDoc("users_public", ownerUid, { borough: "Cambridge" });
    await seedDoc("local_services", listingId, {
      createdByUid:     ownerUid,
      borough:          "Cambridge",
      name:             "X",
      verificationTier: "none",
      isVerified:       false,
      endorsementCount: 0,
      communityRating:  0,
      ratingCount:      0,
      updatedAt:        "2024-01-01",
    });

    const ctx = authedContext(endorserUid);
    const ref = doc(ctx.firestore(), "local_services", listingId);
    await assertSucceeds(
      updateDoc(ref, {
        endorsementCount: 1,
        communityRating:  4.5,
        ratingCount:      1,
        updatedAt:        new Date().toISOString(),
      })
    );
  });
});
