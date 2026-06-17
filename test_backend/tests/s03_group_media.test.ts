/**
 * Huddl — S-03 Group Media Storage Rule Fix Tests
 *
 * Tests the S-03 fix to group_images/{groupId}/{fileName} and
 * group_documents/{groupId}/{fileName}.
 *
 *   BEFORE (broken):
 *     allow read/write: if isAuth()
 *     Any authenticated user could read or write any group's media without
 *     being a member of that group. listAll() on group_images/{groupId} was
 *     open to all auth users. Non-members could inject images/docs into any
 *     group's storage path.
 *
 *   AFTER (S-03):
 *     allow read/write: if isAuth()
 *       && request.auth.uid in
 *           firestore.get(/databases/(default)/documents/groups/$(groupId))
 *             .data.memberIds;
 *     + existing MIME type + size guards on write.
 *
 * Cross-service dependency: Storage rules call firestore.get() to check
 * groups/{groupId}.memberIds. Both Storage (port 9299) and Firestore (port 8180)
 * emulators must run simultaneously. The @firebase/rules-unit-testing v3 SDK
 * wires them together automatically when both are declared in initializeTestEnvironment.
 *
 * Personas:
 *   alice  — member of group_alpha
 *   bob    — NOT a member of group_alpha
 *   carol  — member of group_beta (different group)
 *
 * Tests (14):
 *
 *   group_images — member reads
 *   T-S03-img-member-read          — alice reads a group_alpha image → SUCCEEDS
 *   T-S03-img-nonmember-read       — bob reads a group_alpha image → DENIED
 *   T-S03-img-crossgroup-read      — carol reads a group_alpha image → DENIED
 *   T-S03-img-unauthed-read        — unauthenticated read → DENIED
 *
 *   group_images — member writes
 *   T-S03-img-member-write         — alice uploads image to group_alpha → SUCCEEDS
 *   T-S03-img-nonmember-write      — bob uploads image to group_alpha → DENIED
 *   T-S03-img-wrong-mime-write     — alice uploads audio as image MIME → DENIED
 *   T-S03-img-oversize-write       — alice uploads oversized image → DENIED
 *
 *   group_documents — member reads
 *   T-S03-doc-member-read          — alice reads a group_alpha doc → SUCCEEDS
 *   T-S03-doc-nonmember-read       — bob reads a group_alpha doc → DENIED
 *
 *   group_documents — member writes
 *   T-S03-doc-member-write-pdf     — alice uploads PDF to group_alpha → SUCCEEDS
 *   T-S03-doc-member-write-txt     — alice uploads text/plain → SUCCEEDS
 *   T-S03-doc-nonmember-write      — bob uploads doc to group_alpha → DENIED
 *   T-S03-doc-wrong-mime-write     — alice uploads audio as doc MIME → DENIED
 *
 * Run (from test_backend/):
 *   FIRESTORE_EMULATOR_HOST=localhost:8180 \
 *   FIREBASE_STORAGE_EMULATOR_HOST=localhost:9299 \
 *   npx jest --testPathPattern='s03_group_media' \
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

const PROJECT_ID   = "huddl-s03-project";
const RULES_PATH   = path.resolve(__dirname, "../../storage.rules");
const FS_RULES     = path.resolve(__dirname, "../../firestore.rules");

const ALICE_UID    = "alice_s03_uid";
const BOB_UID      = "bob_s03_uid";
const CAROL_UID    = "carol_s03_uid";

const GROUP_ALPHA  = "group_alpha_s03";
const GROUP_BETA   = "group_beta_s03";

// Filenames that exist in Storage (seeded via admin bypass)
const EXISTING_IMAGE = "alice_1700000000000.jpg";
const EXISTING_DOC   = "alice_1700000000001.pdf";

// Large buffer > 10 MB for oversize test
const OVERSIZE_BYTES  = new Uint8Array(11 * 1024 * 1024);  // 11 MB
const SMALL_IMAGE     = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0]); // fake JPEG header
const SMALL_PDF       = new Uint8Array([0x25, 0x50, 0x44, 0x46]); // fake PDF header
const SMALL_TXT       = new TextEncoder().encode("hello world");
const SMALL_AUDIO     = new Uint8Array([0x49, 0x44, 0x33]); // fake MP3 ID3 header

// ─── Test environment ─────────────────────────────────────────────────────────

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules:  fs.readFileSync(FS_RULES,    "utf8"),
      host:   "localhost",
      port:   8180,
    },
    storage: {
      rules:  fs.readFileSync(RULES_PATH,  "utf8"),
      host:   "localhost",
      port:   9299,
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

// ─── Seed ─────────────────────────────────────────────────────────────────────

async function seedAll() {
  // Seed Firestore groups (memberIds arrays)
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "groups", GROUP_ALPHA), {
      name:      "Alpha Group",
      memberIds: [ALICE_UID],           // alice IN, bob OUT, carol OUT
      privacy:   "private",
    });
    await setDoc(doc(db, "groups", GROUP_BETA), {
      name:      "Beta Group",
      memberIds: [CAROL_UID],           // carol IN
      privacy:   "private",
    });
  });

  // Seed Storage files via admin bypass
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const storage = ctx.storage();
    await uploadBytes(
      ref(storage, `group_images/${GROUP_ALPHA}/${EXISTING_IMAGE}`),
      SMALL_IMAGE,
      { contentType: "image/jpeg" }
    );
    await uploadBytes(
      ref(storage, `group_documents/${GROUP_ALPHA}/${EXISTING_DOC}`),
      SMALL_PDF,
      { contentType: "application/pdf" }
    );
  });
}

// ─── group_images — READ tests ────────────────────────────────────────────────

describe("S-03 group_images — READ", () => {
  beforeEach(seedAll);

  it("T-S03-img-member-read: alice reads group_alpha image → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      getDownloadURL(ref(alice.storage(), `group_images/${GROUP_ALPHA}/${EXISTING_IMAGE}`))
    );
  });

  it("T-S03-img-nonmember-read: bob reads group_alpha image → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      getDownloadURL(ref(bob.storage(), `group_images/${GROUP_ALPHA}/${EXISTING_IMAGE}`))
    );
  });

  it("T-S03-img-crossgroup-read: carol (member of beta) reads group_alpha image → DENIED", async () => {
    const carol = testEnv.authenticatedContext(CAROL_UID);
    await assertFails(
      getDownloadURL(ref(carol.storage(), `group_images/${GROUP_ALPHA}/${EXISTING_IMAGE}`))
    );
  });

  it("T-S03-img-unauthed-read: unauthenticated read of group_alpha image → DENIED", async () => {
    const unauthed = testEnv.unauthenticatedContext();
    await assertFails(
      getDownloadURL(ref(unauthed.storage(), `group_images/${GROUP_ALPHA}/${EXISTING_IMAGE}`))
    );
  });
});

// ─── group_images — WRITE tests ───────────────────────────────────────────────

describe("S-03 group_images — WRITE", () => {
  beforeEach(seedAll);

  it("T-S03-img-member-write: alice uploads image to group_alpha → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      uploadBytes(
        ref(alice.storage(), `group_images/${GROUP_ALPHA}/alice_new_${Date.now()}.jpg`),
        SMALL_IMAGE,
        { contentType: "image/jpeg" }
      )
    );
  });

  it("T-S03-img-nonmember-write: bob uploads image to group_alpha → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      uploadBytes(
        ref(bob.storage(), `group_images/${GROUP_ALPHA}/bob_inject_${Date.now()}.jpg`),
        SMALL_IMAGE,
        { contentType: "image/jpeg" }
      )
    );
  });

  it("T-S03-img-wrong-mime-write: alice uploads audio MIME to group_images → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `group_images/${GROUP_ALPHA}/alice_audio_${Date.now()}.mp3`),
        SMALL_AUDIO,
        { contentType: "audio/mpeg" }
      )
    );
  });

  it("T-S03-img-oversize-write: alice uploads >10 MB to group_images → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `group_images/${GROUP_ALPHA}/alice_big_${Date.now()}.jpg`),
        OVERSIZE_BYTES,
        { contentType: "image/jpeg" }
      )
    );
  });
});

// ─── group_documents — READ tests ─────────────────────────────────────────────

describe("S-03 group_documents — READ", () => {
  beforeEach(seedAll);

  it("T-S03-doc-member-read: alice reads group_alpha doc → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      getDownloadURL(ref(alice.storage(), `group_documents/${GROUP_ALPHA}/${EXISTING_DOC}`))
    );
  });

  it("T-S03-doc-nonmember-read: bob reads group_alpha doc → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      getDownloadURL(ref(bob.storage(), `group_documents/${GROUP_ALPHA}/${EXISTING_DOC}`))
    );
  });
});

// ─── group_documents — WRITE tests ────────────────────────────────────────────

describe("S-03 group_documents — WRITE", () => {
  beforeEach(seedAll);

  it("T-S03-doc-member-write-pdf: alice uploads PDF to group_alpha → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      uploadBytes(
        ref(alice.storage(), `group_documents/${GROUP_ALPHA}/alice_${Date.now()}.pdf`),
        SMALL_PDF,
        { contentType: "application/pdf" }
      )
    );
  });

  it("T-S03-doc-member-write-txt: alice uploads text/plain to group_alpha → SUCCEEDS", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertSucceeds(
      uploadBytes(
        ref(alice.storage(), `group_documents/${GROUP_ALPHA}/alice_${Date.now()}.txt`),
        SMALL_TXT,
        { contentType: "text/plain" }
      )
    );
  });

  it("T-S03-doc-nonmember-write: bob uploads doc to group_alpha → DENIED", async () => {
    const bob = testEnv.authenticatedContext(BOB_UID);
    await assertFails(
      uploadBytes(
        ref(bob.storage(), `group_documents/${GROUP_ALPHA}/bob_inject_${Date.now()}.pdf`),
        SMALL_PDF,
        { contentType: "application/pdf" }
      )
    );
  });

  it("T-S03-doc-wrong-mime-write: alice uploads audio MIME to group_documents → DENIED", async () => {
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `group_documents/${GROUP_ALPHA}/alice_audio_${Date.now()}.mp3`),
        SMALL_AUDIO,
        { contentType: "audio/mpeg" }
      )
    );
  });

  it("T-S03-doc-octet-stream-denied: alice uploads application/octet-stream → DENIED (catch-all closed)", async () => {
    // Verifies octet-stream was removed from isDocument().
    // picker is FileType.custom / allowedExtensions — unknown extensions never
    // reach the upload path. Allowing octet-stream would defeat the MIME guard.
    const alice = testEnv.authenticatedContext(ALICE_UID);
    await assertFails(
      uploadBytes(
        ref(alice.storage(), `group_documents/${GROUP_ALPHA}/alice_unknown_${Date.now()}.bin`),
        new Uint8Array([0x00, 0x01, 0x02, 0x03]),
        { contentType: "application/octet-stream" }
      )
    );
  });
});
