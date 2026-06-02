/**
 * Huddl — Firebase Storage Security Rules Tests
 * Workflow A: Voice note upload path + metadata + content-type guard
 * Workflow E: Marketplace image upload
 *
 * Run: STORAGE_EMULATOR_HOST=localhost:9199 npx jest storage_rules.test.ts
 */

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { ref, uploadBytes, getDownloadURL, deleteObject } from "firebase/storage";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "huddl-test-project";
const RULES_PATH = path.resolve(__dirname, "../../storage.rules");

let testEnv: RulesTestEnvironment;

// 1-pixel PNG fixture (37 bytes) — valid image content
const PNG_BYTES: Uint8Array = new Uint8Array(Buffer.from(
  "89504e470d0a1a0a0000000d49484452000000010000000108020000009001" +
  "2e000000014741004d410000b18f0bfc6105000000097048597300000ec400" +
  "000ec401952b0e1b0000000a4944415408d76360f8cf000001fe02fe95ceee" +
  "1b0000000049454e44ae426082",
  "hex"
));

// ~50 byte audio stub — content-type is what matters for rules
const AUDIO_BYTES: Uint8Array = new Uint8Array(
  Buffer.from("RIFF$\x00\x00\x00WAVEfmt ", "binary")
);

function makeBlob(bytes: Uint8Array, type: string): Blob {
  // Explicit cast to ArrayBuffer to satisfy TS strict BlobPart typing
  return new Blob([bytes.buffer as ArrayBuffer], { type });
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "localhost",
      port: 9199,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW A: Voice Notes
// ─────────────────────────────────────────────────────────────────────────────

describe("Workflow A — voice note storage rules", () => {
  const senderUid = "user_voice_sender";
  const otherUid = "user_other";

  test("authenticated user can upload an audio file to voice_notes/{segment}/{filename}", async () => {
    const ctx = testEnv.authenticatedContext(senderUid);
    const storageRef = ref(ctx.storage(), `voice_notes/${senderUid}/${senderUid}_1700000000.m4a`);
    await assertSucceeds(
      uploadBytes(storageRef, AUDIO_BYTES, { contentType: "audio/mp4" })
    );
  });

  test("unauthenticated user CANNOT upload voice note", async () => {
    const ctx = testEnv.unauthenticatedContext();
    const storageRef = ref(ctx.storage(), `voice_notes/convo_123/anon_1700000000.m4a`);
    await assertFails(
      uploadBytes(storageRef, AUDIO_BYTES, { contentType: "audio/mp4" })
    );
  });

  test("upload with image content-type to voice_notes is blocked (audio guard)", async () => {
    const ctx = testEnv.authenticatedContext(senderUid);
    const storageRef = ref(ctx.storage(), `voice_notes/${senderUid}/disguised.m4a`);
    await assertFails(
      uploadBytes(storageRef, PNG_BYTES, { contentType: "image/png" })
    );
  });

  test("authenticated user can read a voice note (download URL)", async () => {
    // Seed by uploading via admin (no rules)
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const r = ref(ctx.storage(), `voice_notes/${senderUid}/existing.m4a`);
      await uploadBytes(r, AUDIO_BYTES, { contentType: "audio/mp4" });
    });
    const ctx = testEnv.authenticatedContext(otherUid);
    const storageRef = ref(ctx.storage(), `voice_notes/${senderUid}/existing.m4a`);
    // read is allowed for any auth user
    await assertSucceeds(getDownloadURL(storageRef));
  });

  test("webm content-type (web recording) is allowed for voice notes", async () => {
    const ctx = testEnv.authenticatedContext(senderUid);
    const storageRef = ref(ctx.storage(), `voice_notes/${senderUid}/${senderUid}_web.webm`);
    await assertSucceeds(
      uploadBytes(storageRef, AUDIO_BYTES, { contentType: "video/webm" })
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW E: Marketplace Images
// ─────────────────────────────────────────────────────────────────────────────

describe("Workflow E — marketplace image storage rules", () => {
  const sellerUid = "user_seller_storage";
  const buyerUid = "user_buyer_storage";

  test("seller can upload an image to their marketplace_images/{uid}/... path", async () => {
    const ctx = testEnv.authenticatedContext(sellerUid);
    const storageRef = ref(ctx.storage(), `marketplace_images/${sellerUid}/stroller.jpg`);
    await assertSucceeds(
      uploadBytes(storageRef, PNG_BYTES, { contentType: "image/jpeg" })
    );
  });

  test("buyer CANNOT upload to seller's marketplace_images path", async () => {
    const ctx = testEnv.authenticatedContext(buyerUid);
    // buyer tries to upload to sellerUid's path
    const storageRef = ref(ctx.storage(), `marketplace_images/${sellerUid}/fake.jpg`);
    await assertFails(
      uploadBytes(storageRef, PNG_BYTES, { contentType: "image/jpeg" })
    );
  });

  test("unauthenticated user CANNOT upload marketplace image", async () => {
    const ctx = testEnv.unauthenticatedContext();
    const storageRef = ref(ctx.storage(), `marketplace_images/${sellerUid}/anon.jpg`);
    await assertFails(
      uploadBytes(storageRef, PNG_BYTES, { contentType: "image/jpeg" })
    );
  });

  test("non-image content type is blocked for marketplace_images", async () => {
    const ctx = testEnv.authenticatedContext(sellerUid);
    const storageRef = ref(ctx.storage(), `marketplace_images/${sellerUid}/malware.jpg`);
    await assertFails(
      uploadBytes(storageRef, AUDIO_BYTES, { contentType: "audio/mp4" })
    );
  });

  test("authenticated buyer can read marketplace images (display listings)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const r = ref(ctx.storage(), `marketplace_images/${sellerUid}/stroller.jpg`);
      await uploadBytes(r, PNG_BYTES, { contentType: "image/jpeg" });
    });
    const ctx = testEnv.authenticatedContext(buyerUid);
    const storageRef = ref(ctx.storage(), `marketplace_images/${sellerUid}/stroller.jpg`);
    await assertSucceeds(getDownloadURL(storageRef));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Profile photos
// ─────────────────────────────────────────────────────────────────────────────

describe("Profile photos storage rules", () => {
  const ownerUid = "user_profile_owner";
  const otherUid = "user_profile_other";

  test("owner can upload their own profile photo", async () => {
    const ctx = testEnv.authenticatedContext(ownerUid);
    const storageRef = ref(ctx.storage(), `profile_photos/${ownerUid}/avatar.jpg`);
    await assertSucceeds(
      uploadBytes(storageRef, PNG_BYTES, { contentType: "image/jpeg" })
    );
  });

  test("other user CANNOT upload to another user's profile_photos path", async () => {
    const ctx = testEnv.authenticatedContext(otherUid);
    const storageRef = ref(ctx.storage(), `profile_photos/${ownerUid}/hacked.jpg`);
    await assertFails(
      uploadBytes(storageRef, PNG_BYTES, { contentType: "image/jpeg" })
    );
  });

  test("profile photo with audio content-type is blocked", async () => {
    const ctx = testEnv.authenticatedContext(ownerUid);
    const storageRef = ref(ctx.storage(), `profile_photos/${ownerUid}/audio_disguised.jpg`);
    await assertFails(
      uploadBytes(storageRef, AUDIO_BYTES, { contentType: "audio/mp4" })
    );
  });

  test("any authenticated user can read profile photos (avatar display)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const r = ref(ctx.storage(), `profile_photos/${ownerUid}/avatar.jpg`);
      await uploadBytes(r, PNG_BYTES, { contentType: "image/jpeg" });
    });
    const ctx = testEnv.authenticatedContext(otherUid);
    const storageRef = ref(ctx.storage(), `profile_photos/${ownerUid}/avatar.jpg`);
    await assertSucceeds(getDownloadURL(storageRef));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Catch-all deny — paths not in rules should be blocked
// ─────────────────────────────────────────────────────────────────────────────

describe("Catch-all deny", () => {
  const uid = "user_catch";

  test("upload to an arbitrary unlisted path is blocked", async () => {
    const ctx = testEnv.authenticatedContext(uid);
    const storageRef = ref(ctx.storage(), `not_in_rules/${uid}/file.txt`);
    await assertFails(
      uploadBytes(storageRef, new Uint8Array(Buffer.from("data")), { contentType: "text/plain" })
    );
  });
});
