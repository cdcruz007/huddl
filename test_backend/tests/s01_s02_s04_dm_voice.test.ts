/**
 * Huddl — S-01 / S-02 / S-04 DM Media + Voice Notes Storage Rule Tests
 *
 * Tests the three companion fixes delivered together:
 *
 *   S-01  dm_images/{conversationId}/{fileName}
 *         participant read/write gated on conversations/{cid}.participants
 *
 *   S-02  dm_documents/{conversationId}/{fileName}
 *         same participant-scoping pattern as dm_images
 *
 *   S-04  voice_notes/dm/{conversationId}/{fileName}   — DM participant gate
 *         voice_notes/group/{groupId}/{fileName}        — group member gate
 *
 * Cross-service dependency:
 *   Storage rules call firestore.get(/databases/(default)/documents/…) to check
 *   membership. Firestore emulator (port 8180) must run simultaneously with
 *   Storage emulator (port 9299). initializeTestEnvironment wires them together.
 *
 * Personas:
 *   alice  — participant in conv_alpha; member of group_alpha
 *   bob    — NOT a participant in conv_alpha; NOT a member of group_alpha
 *   carol  — participant in conv_beta (different conversation); member of group_beta
 *
 * Pre-creation race:
 *   T-S01-img-missing-conv — upload to dm_images/{cid}/… where the conversation doc
 *   does NOT exist → DENIED. This proves why _ensureConversationId() must be called
 *   before the upload: the rule does firestore.get(conversations/{cid}).participants;
 *   a missing doc returns null → membership check fails → denied.
 *
 * Old flat path closure:
 *   T-S01-flat-path-denied — upload to the OLD dm_images/{file} (one segment, no cid)
 *   → DENIED by catch-all /{allPaths=**}.
 *   T-S02-flat-path-denied — same for dm_documents/{file}.
 *   T-S04-flat-voice-denied — same for old voice_notes/{segment}/{file}.
 *
 * Tests (22):
 *
 *   dm_images — READ (4)
 *   T-S01-img-participant-read     alice reads conv_alpha image → SUCCEEDS
 *   T-S01-img-nonparticipant-read  bob reads conv_alpha image → DENIED
 *   T-S01-img-crossconv-read       carol (conv_beta) reads conv_alpha image → DENIED
 *   T-S01-img-unauthed-read        unauthenticated read → DENIED
 *
 *   dm_images — WRITE (5)
 *   T-S01-img-participant-write    alice uploads image/jpeg to conv_alpha → SUCCEEDS
 *   T-S01-img-nonparticipant-write bob uploads image/jpeg to conv_alpha → DENIED
 *   T-S01-img-missing-conv         alice uploads to cid where conv doc missing → DENIED
 *   T-S01-img-wrong-mime           alice uploads audio/mpeg to dm_images → DENIED
 *   T-S01-img-oversize             alice uploads >20 MB image to dm_images → DENIED
 *
 *   dm_images old flat path (1)
 *   T-S01-flat-path-denied         alice writes to dm_images/{file} (old flat) → DENIED
 *
 *   dm_documents — READ (2)
 *   T-S02-doc-participant-read     alice reads conv_alpha doc → SUCCEEDS
 *   T-S02-doc-nonparticipant-read  bob reads conv_alpha doc → DENIED
 *
 *   dm_documents — WRITE (4)
 *   T-S02-doc-participant-write    alice uploads PDF to conv_alpha → SUCCEEDS
 *   T-S02-doc-nonparticipant-write bob uploads PDF to conv_alpha → DENIED
 *   T-S02-doc-octet-stream-denied  alice uploads application/octet-stream → DENIED
 *   T-S02-flat-path-denied         alice writes to dm_documents/{file} (old flat) → DENIED
 *
 *   voice_notes/dm — (3)
 *   T-S04-dm-participant-write     alice uploads audio to voice_notes/dm/conv_alpha → SUCCEEDS
 *   T-S04-dm-nonparticipant-write  bob uploads audio to voice_notes/dm/conv_alpha → DENIED
 *   T-S04-dm-participant-read      alice reads (getDownloadURL) dm voice note → SUCCEEDS
 *
 *   voice_notes/group — (2)
 *   T-S04-grp-member-write         alice uploads audio to voice_notes/group/group_alpha → SUCCEEDS
 *   T-S04-grp-nonmember-write      bob uploads audio to voice_notes/group/group_alpha → DENIED
 *
 *   old flat voice path (1)
 *   T-S04-flat-voice-denied        alice writes to voice_notes/{segment}/{file} → DENIED
 *
 * Run (from test_backend/):
 *   FIRESTORE_EMULATOR_HOST=localhost:8180 \
 *   FIREBASE_STORAGE_EMULATOR_HOST=localhost:9299 \
 *   npx jest --testPathPattern='s01_s02_s04' \
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
} from "firebase/firestore";
import {
  ref,
  uploadBytes,
  getDownloadURL,
} from "firebase/storage";
import * as fs from "fs";
import * as path from "path";

// ─── Constants ────────────────────────────────────────────────────────────────

const PROJECT_ID  = "huddl-s01s02s04-project";
const RULES_PATH  = path.resolve(__dirname, "../../storage.rules");
const FS_RULES    = path.resolve(__dirname, "../../firestore.rules");

const ALICE_UID   = "alice_s0104_uid";
const BOB_UID     = "bob_s0104_uid";
const CAROL_UID   = "carol_s0104_uid";

// Conversations
const CONV_ALPHA  = "conv_alpha_s0104";   // alice + carol NOT bob
const CONV_BETA   = "conv_beta_s0104";    // carol (different conv)
const CONV_GHOST  = "conv_ghost_s0104";   // no Firestore doc — race scenario

// Groups
const GROUP_ALPHA = "group_alpha_s0104";  // alice IN, bob OUT
const GROUP_BETA  = "group_beta_s0104";   // carol IN

// Pre-seeded filenames (written via admin bypass to test READ paths)
const EXISTING_IMAGE = "alice_s0104_1700000000000.jpg";
const EXISTING_DOC   = "alice_s0104_1700000000001.pdf";
const EXISTING_VOICE = "alice_s0104_1700000000002.m4a";

// ─── Byte fixtures ────────────────────────────────────────────────────────────

// Minimal JPEG header — rules check content type not actual bytes
const SMALL_IMAGE = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
// Minimal PDF header
const SMALL_PDF   = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2D]);  // %PDF-
// Plain text
const SMALL_TXT   = new TextEncoder().encode("hello world");
// Minimal MP3 ID3 header
const SMALL_AUDIO = new Uint8Array([0x49, 0x44, 0x33, 0x03, 0x00]);  // ID3
// Binary blob (octet-stream)
const SMALL_BIN   = new Uint8Array([0xDE, 0xAD, 0xBE, 0xEF]);
// 21 MB buffer — exceeds maxSize(20) for dm_images/dm_documents
const OVERSIZE_BYTES = new Uint8Array(21 * 1024 * 1024);

// ─── Test environment ─────────────────────────────────────────────────────────

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(FS_RULES,   "utf8"),
      host:  "localhost",
      port:  8180,
    },
    storage: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host:  "localhost",
      port:  9299,
    },
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

afterAll(async () => {
  await testEnv.cleanup();
});

// ─── Seed helpers ─────────────────────────────────────────────────────────────

/**
 * Seed Firestore conversation and group docs (security-rules-disabled).
 * CONV_GHOST is intentionally NOT seeded — it simulates the pre-creation race.
 */
async function seedFirestore() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // conversations/{cid}.participants — same field as realtime_dm_service.dart:120
    // CONV_ALPHA: alice only. carol is only in conv_beta. bob is in neither.
    await setDoc(doc(db, "conversations", CONV_ALPHA), {
      participants: [ALICE_UID],             // bob OUT, carol OUT
      type:         "dm",
      createdAt:    new Date(),
    });
    await setDoc(doc(db, "conversations", CONV_BETA), {
      participants: [CAROL_UID],
      type:         "dm",
      createdAt:    new Date(),
    });

    // groups/{gid}.memberIds — same field as firestore_service.dart / S-03 isGroupMember()
    await setDoc(doc(db, "groups", GROUP_ALPHA), {
      memberIds: [ALICE_UID],               // bob excluded
      name:      "Alpha Group",
      privacy:   "private",
    });
    await setDoc(doc(db, "groups", GROUP_BETA), {
      memberIds: [CAROL_UID],
      name:      "Beta Group",
      privacy:   "private",
    });
  });
}

/**
 * Seed Storage files so READ tests have an object to fetch.
 * Uses security-rules-disabled bypass — seeding never touches the rules.
 */
async function seedStorage() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const storage = ctx.storage();

    await uploadBytes(
      ref(storage, `dm_images/${CONV_ALPHA}/${EXISTING_IMAGE}`),
      SMALL_IMAGE,
      { contentType: "image/jpeg" }
    );
    await uploadBytes(
      ref(storage, `dm_documents/${CONV_ALPHA}/${EXISTING_DOC}`),
      SMALL_PDF,
      { contentType: "application/pdf" }
    );
    await uploadBytes(
      ref(storage, `voice_notes/dm/${CONV_ALPHA}/${EXISTING_VOICE}`),
      SMALL_AUDIO,
      { contentType: "audio/mp4" }
    );
  });
}

async function seedAll() {
  await seedFirestore();
  await seedStorage();
}

// =============================================================================
// S-01 — dm_images READ
// =============================================================================

describe("S-01 dm_images — READ", () => {
  beforeEach(seedAll);

  it("T-S01-img-participant-read: alice reads conv_alpha image → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      getDownloadURL(
        ref(alice.storage(), `dm_images/${CONV_ALPHA}/${EXISTING_IMAGE}`)
      )
    );
  });

  it("T-S01-img-nonparticipant-read: bob reads conv_alpha image → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      getDownloadURL(
        ref(bob.storage(), `dm_images/${CONV_ALPHA}/${EXISTING_IMAGE}`)
      )
    );
  });

  it("T-S01-img-crossconv-read: carol (only in conv_beta) reads conv_alpha image → DENIED", async () => {
    // carol IS authenticated and IS in some conversation — but not conv_alpha
    const carol = testEnv.authenticatedContext(CAROL_UID);
    await assertFails(
      getDownloadURL(
        ref(carol.storage(), `dm_images/${CONV_ALPHA}/${EXISTING_IMAGE}`)
      )
    );
  });

  it("T-S01-img-unauthed-read: unauthenticated read of conv_alpha image → DENIED", async () => {
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      getDownloadURL(
        ref(anon.storage(), `dm_images/${CONV_ALPHA}/${EXISTING_IMAGE}`)
      )
    );
  });
});

// =============================================================================
// S-01 — dm_images WRITE
// =============================================================================

describe("S-01 dm_images — WRITE", () => {
  beforeEach(seedFirestore);  // no need to seed Storage files for write tests

  it("T-S01-img-participant-write: alice uploads image/jpeg to conv_alpha → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      uploadBytes(
        ref(alice.storage(), `dm_images/${CONV_ALPHA}/alice_${Date.now()}.jpg`),
        SMALL_IMAGE,
        { contentType: "image/jpeg" }
      )
    );
  });

  it("T-S01-img-nonparticipant-write: bob uploads image/jpeg to conv_alpha → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      uploadBytes(
        ref(bob.storage(), `dm_images/${CONV_ALPHA}/bob_inject_${Date.now()}.jpg`),
        SMALL_IMAGE,
        { contentType: "image/jpeg" }
      )
    );
  });

  it("T-S01-img-missing-conv: alice uploads to dm_images where conversation doc does NOT exist → DENIED (race proof)", async () => {
    // CONV_GHOST has NO Firestore document. The rule does:
    //   firestore.get(conversations/CONV_GHOST).data.participants
    // which returns null → the `in` check fails → write denied.
    // This is exactly what happened before _ensureConversationId() was added:
    // the upload fired before getOrCreateConversation() had run.
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `dm_images/${CONV_GHOST}/alice_race_${Date.now()}.jpg`),
        SMALL_IMAGE,
        { contentType: "image/jpeg" }
      )
    );
  });

  it("T-S01-img-wrong-mime: alice uploads audio/mpeg to dm_images → DENIED (MIME guard)", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `dm_images/${CONV_ALPHA}/alice_audio_${Date.now()}.mp3`),
        SMALL_AUDIO,
        { contentType: "audio/mpeg" }
      )
    );
  });

  it("T-S01-img-oversize: alice uploads >20 MB to dm_images → DENIED (size guard)", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `dm_images/${CONV_ALPHA}/alice_big_${Date.now()}.jpg`),
        OVERSIZE_BYTES,
        { contentType: "image/jpeg" }
      )
    );
  }, 60000);  // oversize upload can take longer
});

// =============================================================================
// S-01 — old flat path closed by catch-all
// =============================================================================

describe("S-01 dm_images — old flat path closure", () => {
  beforeEach(seedFirestore);

  it("T-S01-flat-path-denied: alice writes to dm_images/{file} (OLD one-segment path) → DENIED by catch-all", async () => {
    // Old path: dm_images/alice_photo.jpg (no conversationId segment).
    // The match /dm_images/{conversationId}/{fileName} requires TWO segments.
    // One-segment path falls through to match /{allPaths=**} { allow read, write: if false }.
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `dm_images/alice_flat_${Date.now()}.jpg`),
        SMALL_IMAGE,
        { contentType: "image/jpeg" }
      )
    );
  });
});

// =============================================================================
// S-02 — dm_documents READ
// =============================================================================

describe("S-02 dm_documents — READ", () => {
  beforeEach(seedAll);

  it("T-S02-doc-participant-read: alice reads conv_alpha doc → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      getDownloadURL(
        ref(alice.storage(), `dm_documents/${CONV_ALPHA}/${EXISTING_DOC}`)
      )
    );
  });

  it("T-S02-doc-nonparticipant-read: bob reads conv_alpha doc → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      getDownloadURL(
        ref(bob.storage(), `dm_documents/${CONV_ALPHA}/${EXISTING_DOC}`)
      )
    );
  });
});

// =============================================================================
// S-02 — dm_documents WRITE
// =============================================================================

describe("S-02 dm_documents — WRITE", () => {
  beforeEach(seedFirestore);

  it("T-S02-doc-participant-write: alice uploads PDF to conv_alpha → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      uploadBytes(
        ref(alice.storage(), `dm_documents/${CONV_ALPHA}/alice_${Date.now()}.pdf`),
        SMALL_PDF,
        { contentType: "application/pdf" }
      )
    );
  });

  it("T-S02-doc-nonparticipant-write: bob uploads PDF to conv_alpha → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      uploadBytes(
        ref(bob.storage(), `dm_documents/${CONV_ALPHA}/bob_inject_${Date.now()}.pdf`),
        SMALL_PDF,
        { contentType: "application/pdf" }
      )
    );
  });

  it("T-S02-doc-octet-stream-denied: alice uploads application/octet-stream to dm_documents → DENIED (MIME guard)", async () => {
    // media_attach_service.dart returns 'application/octet-stream' for unknown extensions.
    // The isDocument() helper does NOT include octet-stream — picker uses FileType.custom
    // with explicit allowedExtensions so unknown types should never reach upload.
    // This test proves the rule correctly blocks it even if that guard were bypassed.
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `dm_documents/${CONV_ALPHA}/alice_unknown_${Date.now()}.bin`),
        SMALL_BIN,
        { contentType: "application/octet-stream" }
      )
    );
  });

  it("T-S02-flat-path-denied: alice writes to dm_documents/{file} (OLD one-segment path) → DENIED by catch-all", async () => {
    // Same catch-all closure proof as T-S01-flat-path-denied.
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `dm_documents/alice_flat_${Date.now()}.pdf`),
        SMALL_PDF,
        { contentType: "application/pdf" }
      )
    );
  });
});

// =============================================================================
// S-04 — voice_notes/dm (DM participant gate)
// =============================================================================

describe("S-04 voice_notes/dm — READ + WRITE", () => {
  beforeEach(seedAll);

  it("T-S04-dm-participant-write: alice uploads audio to voice_notes/dm/conv_alpha → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      uploadBytes(
        ref(alice.storage(), `voice_notes/dm/${CONV_ALPHA}/alice_${Date.now()}.m4a`),
        SMALL_AUDIO,
        { contentType: "audio/mp4" }
      )
    );
  });

  it("T-S04-dm-nonparticipant-write: bob uploads audio to voice_notes/dm/conv_alpha → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      uploadBytes(
        ref(bob.storage(), `voice_notes/dm/${CONV_ALPHA}/bob_inject_${Date.now()}.m4a`),
        SMALL_AUDIO,
        { contentType: "audio/mp4" }
      )
    );
  });

  it("T-S04-dm-participant-read: alice reads (getDownloadURL) her own dm voice note → SUCCEEDS", async () => {
    // EXISTING_VOICE is seeded in voice_notes/dm/CONV_ALPHA by seedStorage()
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      getDownloadURL(
        ref(alice.storage(), `voice_notes/dm/${CONV_ALPHA}/${EXISTING_VOICE}`)
      )
    );
  });
});

// =============================================================================
// S-04 — voice_notes/group (group member gate)
// =============================================================================

describe("S-04 voice_notes/group — WRITE", () => {
  beforeEach(seedFirestore);

  it("T-S04-grp-member-write: alice (member) uploads audio to voice_notes/group/group_alpha → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      uploadBytes(
        ref(alice.storage(), `voice_notes/group/${GROUP_ALPHA}/alice_${Date.now()}.m4a`),
        SMALL_AUDIO,
        { contentType: "audio/mp4" }
      )
    );
  });

  it("T-S04-grp-nonmember-write: bob (non-member) uploads audio to voice_notes/group/group_alpha → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      uploadBytes(
        ref(bob.storage(), `voice_notes/group/${GROUP_ALPHA}/bob_inject_${Date.now()}.m4a`),
        SMALL_AUDIO,
        { contentType: "audio/mp4" }
      )
    );
  });
});

// =============================================================================
// S-04 — old flat voice path closed by catch-all
// =============================================================================

describe("S-04 voice_notes — old flat path closure", () => {
  beforeEach(seedFirestore);

  it("T-S04-flat-voice-denied: alice writes to voice_notes/{segment}/{file} (OLD two-segment path) → DENIED by catch-all", async () => {
    // Old path: voice_notes/CONV_ALPHA/alice_1234.m4a  — two segments,
    // but no 'dm' or 'group' prefix, so it matches neither
    //   /voice_notes/dm/{cid}/{file}
    //   /voice_notes/group/{gid}/{file}
    // and falls through to the catch-all.
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `voice_notes/${CONV_ALPHA}/alice_${Date.now()}.m4a`),
        SMALL_AUDIO,
        { contentType: "audio/mp4" }
      )
    );
  });
});
