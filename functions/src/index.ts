/**
 * Huddl — Cloud Functions
 *
 * Nine functions:
 *   1. generateEventRecommendations  — Firestore onCreate on events/{eventId}
 *   2. refreshUserRecommendations    — Firestore onUpdate on users/{userId}
 *   3. recordRecommendationFeedback  — HTTP callable (from Flutter app)
 *   4. cleanupExpiredRecommendations — Scheduled daily at 02:00 UTC
 *   5. huddlCopilotChat              — §2C  Gemini API proxy via HTTP callable
 *   6. generateCopilotSuggestions    — §2D  Personalised chip generation
 *   7. vertexGenerateContent         — §3A  Fine-tuned Vertex AI proxy (server-side SA key)
 *   8. syncPublicProfile             — Firestore onWrite on users/{userId} → mirrors public fields to users_public/{userId}
 *   9. setUserBorough               — HTTPS callable; resolves postcode server-side, enforces Cambridge gate, writes geo fields via Admin SDK
 *  10. deleteUserData               — GDPR deletion callable; Phase 1+2+3: query-deletes, subcollection sweeps, group membership, anonymise (conversations + group_messages)
 *  11. verifyBusiness               — HTTPS callable; server-side UK business verification (Companies House / HMRC VAT); writes trust fields via Admin SDK (SUB-3 / ANN-1)
 *  12. moderateAndSendDM             — HTTPS callable; server-side moderated send-gate for DMs (MSG-SAFETY-1/4).
 *                                      DEPLOY BUT DORMANT — no client calls it yet (Stage 1 of staged rollout).
 *  13. onDmMessageCreated            — Firestore onCreate trigger on conversations/{cId}/messages/{mId}.
 *                                      Server-side DM notification dispatch (MSG-SAFETY Stage 2a-ii).
 *                                      Replaces client-side BackendApiService.notifyDmMessage calls.
 *  14. moderateAndSendGroupMessage   — HTTPS callable; server-side moderated send-gate for GROUP messages
 *                                      (GROUP-MSG-SAFETY Stage 1). DEPLOY BUT DORMANT — no client calls
 *                                      it yet. Reuses AI_HARD_BLOCKLIST, _normaliseDmText, and
 *                                      _geminiClassifyDmText from moderateAndSendDM.
 *  15. seedWelcomeSubscription       — Firestore onCreate on users/{userId}; seeds a welcome-tier
 *                                      subscriptions/{userId} doc via Admin SDK (bypasses if-false rule).
 *                                      Idempotent: skips write if the doc already exists (never downgrades
 *                                      a paid tier). Replaces the incorrect client-side batch write that
 *                                      triggered PERMISSION_DENIED (entitlements are server-authoritative).
 *
 * Firestore schema used:
 *   events/{eventId}
 *   users/{userId}
 *   userRecommendations/{userId}/events/{eventId}
 *   aiRateLimits/{userId}               (date + messageCount, per-tier daily AI budget)
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as https from "https";
import { JWT } from "google-auth-library";
import type { Bucket } from "@google-cloud/storage";

// Gemini API key — sourced exclusively from Firebase Secret Manager / env config.
// To set: firebase functions:secrets:set GEMINI_API_KEY
// The literal fallback has been removed. Rotate any previously exposed key immediately.
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
if (!GEMINI_API_KEY) {
  // Log at startup so a misconfigured deploy is immediately visible in Cloud Logging.
  // Functions that invoke the Gemini API will receive a 500 with a clear message
  // rather than silently using a stale or missing key.
  console.error("[huddl-functions] GEMINI_API_KEY environment variable is not set. " +
    "Run: firebase functions:secrets:set GEMINI_API_KEY — then redeploy.");
}
const GEMINI_MODEL = "gemini-2.0-flash";
// GEMINI_URL is a function so it always picks up the runtime env value and
// throws clearly if the key is absent, rather than silently building a bad URL.
function getGeminiUrl(): string {
  const key = process.env.GEMINI_API_KEY;
  if (!key) {
    throw new Error("GEMINI_API_KEY is not configured. " +
      "Set it via Firebase Secret Manager: firebase functions:secrets:set GEMINI_API_KEY");
  }
  return `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${key}`;
}

// ── Vertex AI fine-tuned model endpoint ────────────────────────────────────
// Project: huddl-connect (879152141283), Region: europe-west4
// Model:   huddl-uk-parenting-assistant (627673804901974016@1)
// Auth:    Service account OAuth 2.0 via VERTEX_AI_SA_KEY Secret Manager secret
// CF runs in europe-west2; outbound call crosses to europe-west4 on Google backbone.
const VERTEX_ENDPOINT =
  "https://europe-west4-aiplatform.googleapis.com/v1/projects/879152141283" +
  "/locations/europe-west4/models/627673804901974016@1:generateContent";

admin.initializeApp();
const db = admin.firestore();

// ── Storage bucket ────────────────────────────────────────────────────────────
// Bucket name confirmed from lib/config/firebase_options.dart (all platforms).
// In the emulator the admin SDK routes to FIREBASE_STORAGE_EMULATOR_HOST when set.
// GDPR_STORAGE_BUCKET env var allows test overrides (emulator isolation).
const STORAGE_BUCKET =
  process.env["GDPR_STORAGE_BUCKET"] ?? "huddl-connect.firebasestorage.app";

// ── Unified daily AI-action budget per tier (Audit: SUB-2) ──────────────────
// Shared across ALL AI CFs (copilot + vertex) via one aiRateLimits counter.
// 'partner' is a high backstop, not infinity. Start conservative; raise on
// real usage data.
const AI_DAILY_LIMITS: Record<string, number> = {
  welcome: 3,
  plus: 20,
  partner: 100,
};
const AI_DEFAULT_LIMIT = AI_DAILY_LIMITS.welcome; // fail-closed default

// Reads authoritative subscriptions/{uid}.tier (written ONLY by Stripe webhook
// via Admin SDK; client writes denied). Fails CLOSED to 'welcome' on missing
// doc (new user) or read error — ambiguity grants the LOWEST tier, never paid.
async function resolveDailyAiLimit(userId: string): Promise<number> {
  try {
    const snap = await db.collection("subscriptions").doc(userId).get();
    const tier = (snap.exists ? (snap.data()?.tier as string) : undefined) ?? "welcome";
    return AI_DAILY_LIMITS[tier] ?? AI_DEFAULT_LIMIT;
  } catch (e) {
    return AI_DEFAULT_LIMIT; // read failed → fail closed to free
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UserProfile {
  borough?: string;
  parentingStage?: string;
  childAgeMonths?: number;
  interests?: string[];
  joinedEvents?: string[];
  joinedMeetups?: string[];
  stagesOfLife?: string[];
  likedCategories?: string[];
  dislikedCategories?: string[];
}

interface EventDoc {
  title?: string;
  category?: string;
  scope?: string;
  borough?: string;
  suitableFor?: string[];
  date?: admin.firestore.Timestamp;
  isOnline?: boolean;
  isFree?: boolean;
}

interface MatchReason {
  icon: string;
  text: string;
  points: number;
}

interface RecommendationRecord {
  matchScore: number;
  matchReasons: MatchReason[];
  isDiscoverSomethingNew: boolean;
  feedbackGiven: string | null;
  feedbackAt: admin.firestore.Timestamp | null;
  generatedAt: admin.firestore.Timestamp;
}

// ═══════════════════════════════════════════════════════════════════════════
// SCORING ENGINE (shared by functions 1 & 2)
// ═══════════════════════════════════════════════════════════════════════════

const MIN_SCORE_THRESHOLD = 40; // Only persist records ≥ 40 (spec Section 4C)

/**
 * Compute a match score (0-100) and match reasons for a user-event pair.
 */
function computeMatchScore(
  user: UserProfile,
  event: EventDoc
): { score: number; reasons: MatchReason[] } {
  let total = 0;
  const reasons: MatchReason[] = [];

  // ── 1. Location / Scope match (0-25) ─────────────────────────────────
  const scope = (event.scope ?? "uk_wide").toLowerCase();
  const eventBorough = (event.borough ?? "").toLowerCase();
  const userBorough = (user.borough ?? "").toLowerCase();

  if (event.isOnline) {
    total += 18;
    reasons.push({ icon: "uk_wide", text: "Available online", points: 18 });
  } else if (scope === "uk_wide") {
    total += 15;
    reasons.push({ icon: "uk_wide", text: "Available UK-wide", points: 15 });
  } else if (scope === "borough" && eventBorough && eventBorough === userBorough) {
    total += 25;
    reasons.push({ icon: "location", text: "In your borough", points: 25 });
  } else if (scope === "borough" && eventBorough && eventBorough !== userBorough) {
    total += 5; // still shown, lower rank — NOT excluded
  } else if (scope === "local") {
    total += 10; // distance slider handles final inclusion at query time
  }

  // ── 2. Parenting stage match (0-20) ──────────────────────────────────
  const suitableFor = event.suitableFor ?? [];
  const userStage = (user.parentingStage ?? "").toLowerCase();
  const userStages = (user.stagesOfLife ?? []).map((s) => s.toLowerCase());

  if (suitableFor.includes("all_families")) {
    total += 15;
    reasons.push({ icon: "star", text: "Suitable for all families", points: 15 });
  } else {
    const stageMap: Record<string, string[]> = {
      expecting_parents: ["expecting", "pregnant"],
      new_parents:       ["newborn", "new_parent"],
      toddler_families:  ["toddler"],
      school_age_families: ["school-age", "school_age"],
    };
    let stageMatch = false;
    for (const [suitKey, stageValues] of Object.entries(stageMap)) {
      if (suitableFor.includes(suitKey)) {
        const matched = stageValues.some(
          (sv) => sv === userStage || userStages.includes(sv)
        );
        if (matched) {
          total += 20;
          const label = _stageFriendlyLabel(suitKey);
          reasons.push({ icon: "star", text: label, points: 20 });
          stageMatch = true;
          break;
        }
      }
    }
    if (!stageMatch) total += 3; // no stage match — small base score
  }

  // ── 3. Child age match (0-15) ────────────────────────────────────────
  const childAgeMonths = user.childAgeMonths ?? -1;
  if (childAgeMonths > 0) {
    const ageDisplay =
      childAgeMonths < 12
        ? `${childAgeMonths}-month-olds`
        : `${Math.floor(childAgeMonths / 12)}-year-olds`;
    // Rough match based on suitableFor categories
    if (
      (childAgeMonths <= 24 && suitableFor.some((s) => s.includes("new_parent") || s.includes("all"))) ||
      (childAgeMonths > 24 && childAgeMonths <= 60 && suitableFor.some((s) => s.includes("toddler") || s.includes("all"))) ||
      (childAgeMonths > 60 && suitableFor.some((s) => s.includes("school") || s.includes("all")))
    ) {
      total += 15;
      reasons.push({ icon: "age", text: `Perfect for ${ageDisplay}`, points: 15 });
    }
  }

  // ── 4. Category / interest match (0-15) ──────────────────────────────
  const eventCategory = (event.category ?? "").toLowerCase();
  const userInterests = (user.interests ?? []).map((i) => i.toLowerCase());
  const likedCategories = (user.likedCategories ?? []).map((c) => c.toLowerCase());
  const dislikedCategories = (user.dislikedCategories ?? []).map((c) => c.toLowerCase());

  if (dislikedCategories.includes(eventCategory)) {
    total -= 10; // negative signal from "Not for me" feedback
  } else if (likedCategories.includes(eventCategory) || userInterests.includes(eventCategory)) {
    total += 15;
    reasons.push({ icon: "category", text: `Matches your ${eventCategory} interest`, points: 15 });
  }

  // ── 5. Timing match (0-5+5) ──────────────────────────────────────────
  if (event.date) {
    const eventDate = event.date.toDate();
    const day = eventDate.getDay();
    const isWeekend = day === 0 || day === 6; // Sunday or Saturday
    if (isWeekend) {
      total += 5;
      reasons.push({ icon: "calendar", text: "Weekend event", points: 5 });
    }
    const now = new Date();
    const daysUntil = (eventDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24);
    if (daysUntil >= 0 && daysUntil <= 20) {
      total += 5; // still "New" — within 20-day window
    }
  }

  // Clamp final score to 0-100
  const finalScore = Math.max(0, Math.min(100, Math.round(total)));

  // Sort reasons by points descending; take top 4
  reasons.sort((a, b) => b.points - a.points);
  const topReasons = reasons.slice(0, 4);

  return { score: finalScore, reasons: topReasons };
}

/**
 * Compute isDiscoverSomethingNew:
 * Returns true only when the user has ≥5 joined events/meetups AND
 * the event's category is NOT in their last 5 unique categories.
 */
function computeIsDiscoverSomethingNew(
  user: UserProfile,
  event: EventDoc
): boolean {
  const joined = [...(user.joinedEvents ?? []), ...(user.joinedMeetups ?? [])];
  if (joined.length < 5) return false; // insufficient history

  // In this implementation, joinedEvents/joinedMeetups store event IDs.
  // The category lookup would require fetching each joined event document,
  // which is expensive. Instead we store categories in a denormalized
  // likedCategories array on the user profile (updated by recordRecommendationFeedback).
  // We use that as a proxy for "categories the user has engaged with".
  const engagedCategories = (user.likedCategories ?? []).map((c) => c.toLowerCase());
  const eventCategory = (event.category ?? "").toLowerCase();
  if (eventCategory && engagedCategories.length >= 3) {
    return !engagedCategories.includes(eventCategory);
  }
  return false;
}

function _stageFriendlyLabel(suitKey: string): string {
  switch (suitKey) {
    case "expecting_parents": return "Designed for expecting parents";
    case "new_parents":       return "Ideal for new parents";
    case "toddler_families":  return "Great for toddler families";
    case "school_age_families": return "Perfect for school-age kids";
    default: return "Matches your parenting stage";
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 1: generateEventRecommendations
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Triggered when a new event document is created in events/{eventId}.
 *
 * Iterates ALL active users in batches of 100, computes a match score for
 * each user, and writes a recommendation record to
 * userRecommendations/{userId}/events/{eventId} when score >= 40.
 *
 * Performance note: suitable for user bases < 50,000. Above that threshold,
 * fan out using a Pub/Sub topic.
 */
export const generateEventRecommendations = functions
  .region('europe-west2')                              // REGION-RESIDENCY-1
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .firestore.document("events/{eventId}")
  .onCreate(async (snap, context) => {
    const eventId = context.params.eventId;
    const event = snap.data() as EventDoc;

    functions.logger.info(`[generateEventRecommendations] New event: ${eventId}`);

    // Fetch all active users in batches of 100
    let lastDoc: admin.firestore.DocumentSnapshot | undefined;
    let processedUsers = 0;
    let writtenRecords = 0;

    while (true) {
      let query: admin.firestore.Query = db.collection("users").limit(100);
      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }
      const usersSnap = await query.get();
      if (usersSnap.empty) break;

      // Process batch
      const writes: Promise<void>[] = [];
      for (const userDoc of usersSnap.docs) {
        const userId = userDoc.id;
        const user = userDoc.data() as UserProfile;

        writes.push(
          (async () => {
            try {
              const { score, reasons } = computeMatchScore(user, event);
              if (score < MIN_SCORE_THRESHOLD) return; // skip low-relevance

              const isDiscoverSomethingNew = computeIsDiscoverSomethingNew(user, event);

              const record: RecommendationRecord = {
                matchScore: score,
                matchReasons: reasons,
                isDiscoverSomethingNew,
                feedbackGiven: null,
                feedbackAt: null,
                generatedAt: admin.firestore.Timestamp.now(),
              };

              await db
                .collection("userRecommendations")
                .doc(userId)
                .collection("events")
                .doc(eventId)
                .set(record);

              writtenRecords++;
            } catch (err) {
              functions.logger.error(
                `[generateEventRecommendations] Error for user ${userId}: ${err}`
              );
              // Use Promise.allSettled behaviour — one failure does not abort others
            }
          })()
        );
      }

      // Wait for entire batch to settle before moving to next
      await Promise.allSettled(writes);
      processedUsers += usersSnap.docs.length;
      lastDoc = usersSnap.docs[usersSnap.docs.length - 1];

      if (usersSnap.docs.length < 100) break; // last page
    }

    functions.logger.info(
      `[generateEventRecommendations] Done. Processed: ${processedUsers} users, ` +
      `Written: ${writtenRecords} records for event ${eventId}`
    );
  });

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 2: refreshUserRecommendations
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Triggered when a user document is updated in users/{userId}.
 *
 * Re-generates recommendation records for the updated user across all
 * future events. Preserves existing feedbackGiven / feedbackAt values.
 * Deletes stale records for events that now score below 40.
 */
export const refreshUserRecommendations = functions
  .region('europe-west2')                              // REGION-RESIDENCY-1
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .firestore.document("users/{userId}")
  .onUpdate(async (change, context) => {
    const userId = context.params.userId;
    const newUser = change.after.data() as UserProfile;
    const today = admin.firestore.Timestamp.now();

    functions.logger.info(`[refreshUserRecommendations] Profile updated for user: ${userId}`);

    // Fetch all future events (date >= today)
    // Also include events with scope=uk_wide (always relevant) or matching user borough
    const futureEventsSnap = await db
      .collection("events")
      .where("date", ">=", today)
      .get();

    if (futureEventsSnap.empty) {
      functions.logger.info(`[refreshUserRecommendations] No future events found.`);
      return;
    }

    // Fetch existing recommendation records for this user (to preserve feedback)
    const existingRecsSnap = await db
      .collection("userRecommendations")
      .doc(userId)
      .collection("events")
      .get();

    const existingFeedback: Record<string, { feedbackGiven: string | null; feedbackAt: admin.firestore.Timestamp | null }> = {};
    for (const recDoc of existingRecsSnap.docs) {
      const data = recDoc.data();
      existingFeedback[recDoc.id] = {
        feedbackGiven: data.feedbackGiven ?? null,
        feedbackAt: data.feedbackAt ?? null,
      };
    }

    // Collect event IDs from future events
    const futureEventIds = new Set(futureEventsSnap.docs.map((d) => d.id));

    // Delete stale records for events not in future set (past events)
    const toDelete: Promise<admin.firestore.WriteResult>[] = [];
    for (const existId of Object.keys(existingFeedback)) {
      if (!futureEventIds.has(existId)) {
        toDelete.push(
          db
            .collection("userRecommendations")
            .doc(userId)
            .collection("events")
            .doc(existId)
            .delete()
        );
      }
    }
    await Promise.allSettled(toDelete);

    // Re-score and write
    let rewritten = 0;
    let deleted = 0;

    const writes: Promise<void>[] = [];
    for (const eventDoc of futureEventsSnap.docs) {
      const eventId = eventDoc.id;
      const event = eventDoc.data() as EventDoc;

      writes.push(
        (async () => {
          try {
            const { score, reasons } = computeMatchScore(newUser, event);
            const recRef = db
              .collection("userRecommendations")
              .doc(userId)
              .collection("events")
              .doc(eventId);

            if (score < MIN_SCORE_THRESHOLD) {
              // Remove low-relevance record if it exists
              if (existingFeedback[eventId] !== undefined) {
                await recRef.delete();
                deleted++;
              }
              return;
            }

            const isDiscoverSomethingNew = computeIsDiscoverSomethingNew(newUser, event);

            // Preserve existing feedback — do NOT overwrite
            const preserved = existingFeedback[eventId] ?? { feedbackGiven: null, feedbackAt: null };

            const record: RecommendationRecord = {
              matchScore: score,
              matchReasons: reasons,
              isDiscoverSomethingNew,
              feedbackGiven: preserved.feedbackGiven,
              feedbackAt: preserved.feedbackAt,
              generatedAt: admin.firestore.Timestamp.now(),
            };

            await recRef.set(record);
            rewritten++;
          } catch (err) {
            functions.logger.error(
              `[refreshUserRecommendations] Error for event ${eventId}: ${err}`
            );
          }
        })()
      );
    }

    await Promise.allSettled(writes);

    functions.logger.info(
      `[refreshUserRecommendations] Done for ${userId}. ` +
      `Re-scored: ${futureEventsSnap.docs.length}, Written: ${rewritten}, Deleted: ${deleted}`
    );
  });

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 3: recordRecommendationFeedback
// ═══════════════════════════════════════════════════════════════════════════

/**
 * HTTP callable function — called from the Flutter app when user taps
 * "Yes, helpful" or "Not for me" on the recommendation feedback widget.
 *
 * Request payload: { eventId: string, feedback: "helpful" | "not_for_me" }
 * Response: { success: true }
 *
 * Side effects:
 *   - Writes feedbackGiven + feedbackAt to userRecommendations/{userId}/events/{eventId}
 *   - Updates likedCategories / dislikedCategories arrays on user profile
 */
export const recordRecommendationFeedback = functions
  .region('europe-west2')                              // REGION-RESIDENCY-1
  .https.onCall(
  async (data, context) => {
    // Validate authentication
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "This function requires authentication."
      );
    }

    const userId = context.auth.uid;
    const eventId = data.eventId as string | undefined;
    const feedback = data.feedback as string | undefined;

    if (!eventId || typeof eventId !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "eventId is required and must be a string."
      );
    }
    if (feedback !== "helpful" && feedback !== "not_for_me") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        'feedback must be "helpful" or "not_for_me".'
      );
    }

    functions.logger.info(
      `[recordRecommendationFeedback] user=${userId} event=${eventId} feedback=${feedback}`
    );

    // 1. Write feedback to recommendation record
    const recRef = db
      .collection("userRecommendations")
      .doc(userId)
      .collection("events")
      .doc(eventId);

    await recRef.set(
      {
        feedbackGiven: feedback,
        feedbackAt: admin.firestore.Timestamp.now(),
      },
      { merge: true } // preserve all other fields
    );

    // 2. Fetch event category for preference signal
    const eventDoc = await db.collection("events").doc(eventId).get();
    if (!eventDoc.exists) {
      functions.logger.warn(
        `[recordRecommendationFeedback] Event ${eventId} not found — preference signal skipped.`
      );
      return { success: true };
    }

    const eventData = eventDoc.data() as EventDoc;
    const category = eventData.category ?? "";
    if (!category) {
      return { success: true };
    }

    // 3. Update user preference arrays
    const userRef = db.collection("users").doc(userId);
    if (feedback === "helpful") {
      await userRef.update({
        likedCategories: admin.firestore.FieldValue.arrayUnion(category),
        dislikedCategories: admin.firestore.FieldValue.arrayRemove(category),
      });
    } else {
      await userRef.update({
        dislikedCategories: admin.firestore.FieldValue.arrayUnion(category),
        likedCategories: admin.firestore.FieldValue.arrayRemove(category),
      });
    }

    functions.logger.info(
      `[recordRecommendationFeedback] Updated preference for user ${userId}: ` +
      `${feedback === "helpful" ? "liked" : "disliked"} category "${category}"`
    );

    return { success: true };
  }
);

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 4: cleanupExpiredRecommendations
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Scheduled daily at 02:00 UTC via Cloud Scheduler.
 *
 * Deletes all userRecommendations/{userId}/events/{eventId} documents
 * for events whose date has passed, keeping the collection lean.
 *
 * Uses batched deletes (max 500 writes per Firestore batch).
 */
export const cleanupExpiredRecommendations = functions
  .region('europe-west2')                              // REGION-RESIDENCY-1
  .runWith({ timeoutSeconds: 540, memory: "256MB" })
  .pubsub.schedule("0 2 * * *")        // 02:00 UTC every day
  .timeZone("UTC")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    functions.logger.info(
      `[cleanupExpiredRecommendations] Starting cleanup at ${now.toDate().toISOString()}`
    );

    // Find all events whose date is in the past
    const expiredEventsSnap = await db
      .collection("events")
      .where("date", "<", now)
      .select() // fetch only document IDs (no field data needed)
      .get();

    if (expiredEventsSnap.empty) {
      functions.logger.info("[cleanupExpiredRecommendations] No expired events found.");
      return;
    }

    const expiredEventIds = expiredEventsSnap.docs.map((d) => d.id);
    functions.logger.info(
      `[cleanupExpiredRecommendations] Found ${expiredEventIds.length} expired events to clean up.`
    );

    let totalDeleted = 0;

    // For each expired event, delete all per-user recommendation records
    for (const eventId of expiredEventIds) {
      // Collect all userRecommendations docs for this eventId
      // Firestore does not support cross-collection queries by sub-collection path,
      // so we use a collectionGroup query on "events" sub-collection.
      const recsSnap = await db
        .collectionGroup("events")
        .where(admin.firestore.FieldPath.documentId(), ">=", `${eventId}`)
        .where(admin.firestore.FieldPath.documentId(), "<=", `${eventId}\uf8ff`)
        .get();

      // Filter to only documents whose path ends with /events/{eventId}
      const matchingDocs = recsSnap.docs.filter((doc) =>
        doc.ref.path.endsWith(`/events/${eventId}`)
      );

      if (matchingDocs.length === 0) continue;

      // Batch delete (max 500 per batch)
      const chunks: admin.firestore.DocumentReference[][] = [];
      for (let i = 0; i < matchingDocs.length; i += 500) {
        chunks.push(matchingDocs.slice(i, i + 500).map((d) => d.ref));
      }

      for (const chunk of chunks) {
        const batch = db.batch();
        for (const ref of chunk) {
          batch.delete(ref);
        }
        await batch.commit();
        totalDeleted += chunk.length;
      }
    }

    functions.logger.info(
      `[cleanupExpiredRecommendations] Cleanup complete. ` +
      `Deleted ${totalDeleted} recommendation records for ${expiredEventIds.length} expired events.`
    );
  });

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 5: huddlCopilotChat  (§2C)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * HTTP callable — Co-pilot chat proxy via Google Gemini API.
 *
 * Uses the same Gemini key and model already embedded in the Flutter app
 * (GeminiConfig._embeddedKey / gemini-2.0-flash) — no extra configuration.
 *
 * Request payload:
 *   {
 *     messages: Array<{ role: "user"|"assistant", content: string }>,
 *     userContext?: { userName?: string, borough?: string,
 *                     childrenSummary?: string, parentingStage?: string }
 *   }
 * Response:
 *   { reply: string }  |  error thrown
 */

// ── Helpers ────────────────────────────────────────────────────────────────

/** Build personalised system prompt from user context. */
function buildSystemPrompt(ctx: {
  userName?: string;
  borough?: string;
  childrenSummary?: string;
  parentingStage?: string;
}): string {
  const name = ctx.userName || "there";
  const borough = ctx.borough || "your area";
  const children = ctx.childrenSummary || "not specified";
  const stage = ctx.parentingStage || "not specified";

  return `You are the Huddl parenting assistant — a warm, knowledgeable, and locally-aware AI for parents in the UK. You know the user's name, their children's ages, their location (borough), and their parenting stage.

Your role is to:
- Answer parenting questions with warmth, accuracy, and practicality
- Help parents find local resources, groups, and events relevant to their family
- Assist with Huddl app features (how to join groups, list items, find meetups)
- Provide age-appropriate developmental guidance

You are NOT:
- A medical professional — always recommend consulting a GP or health visitor for medical concerns
- A legal advisor — direct SEND/EHCP questions to IPSEA (ipsea.org.uk)
- A replacement for human connection — encourage parents to connect with their local community

Keep responses concise and warm. Use plain language. Never use jargon. If you don't know something, say so honestly and suggest where to find help.

User context:
Name: ${name}
Borough: ${borough}
Children: ${children}
Parenting stage: ${stage}`;
}

/** Call Gemini generateContent API using Node.js built-in https. */
function callGemini(params: {
  system: string;
  messages: Array<{ role: string; content: string }>;
}): Promise<string> {
  return new Promise((resolve, reject) => {
    // Convert messages to Gemini format (role: user/model, parts: [{text}])
    const contents = params.messages.map((m) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.content }],
    }));

    const body = JSON.stringify({
      system_instruction: { parts: [{ text: params.system }] },
      contents,
      generationConfig: {
        temperature: 0.75,
        topP: 0.95,
        maxOutputTokens: 1024,
      },
      safetySettings: [
        { category: "HARM_CATEGORY_DANGEROUS_CONTENT",  threshold: "BLOCK_ONLY_HIGH" },
        { category: "HARM_CATEGORY_HARASSMENT",         threshold: "BLOCK_ONLY_HIGH" },
        { category: "HARM_CATEGORY_HATE_SPEECH",        threshold: "BLOCK_ONLY_HIGH" },
        { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",  threshold: "BLOCK_ONLY_HIGH" },
      ],
    });

    const url = new URL(getGeminiUrl());
    const options: https.RequestOptions = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(body),
      },
    };

    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.error) {
            reject(new Error(`Gemini error: ${parsed.error.message}`));
          } else {
            const text: string =
              parsed.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
            resolve(text);
          }
        } catch (e) {
          reject(new Error(`Failed to parse Gemini response: ${e}`));
        }
      });
    });

    req.on("error", (e) => reject(e));
    req.write(body);
    req.end();
  });
}

/** Check and increment rate limit. Returns false when limit exceeded. */
async function checkAndIncrementRateLimit(userId: string, dailyLimit: number): Promise<boolean> {
  const today = new Date().toISOString().slice(0, 10); // "YYYY-MM-DD"
  const ref = db.collection("aiRateLimits").doc(userId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() as { date?: string; messageCount?: number } | undefined;

    if (data?.date === today) {
      if ((data.messageCount ?? 0) >= dailyLimit) {
        return false; // limit reached
      }
      tx.update(ref, { messageCount: admin.firestore.FieldValue.increment(1) });
    } else {
      // New day — reset counter
      tx.set(ref, { date: today, messageCount: 1 });
    }
    return true;
  });
}

// ── Cloud Function ─────────────────────────────────────────────────────────

export const huddlCopilotChat = functions
  .region('europe-west2')
  .runWith({ timeoutSeconds: 60, memory: "256MB", secrets: ["GEMINI_API_KEY"] })
  .https.onCall(async (data, context) => {
    // Authentication guard
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required."
      );
    }
    const userId = context.auth.uid;

    // Rate limiting — tier-aware daily budget (Audit: SUB-2)
    const dailyLimit = await resolveDailyAiLimit(userId);
    const allowed = await checkAndIncrementRateLimit(userId, dailyLimit);
    if (!allowed) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "Daily AI limit reached. Upgrade for more, or come back tomorrow!"
      );
    }

    // Validate input
    const rawMessages = data.messages as Array<{ role: string; content: string }> | undefined;
    if (!rawMessages || !Array.isArray(rawMessages) || rawMessages.length === 0) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "messages array is required."
      );
    }

    // Take last 10 messages to keep context manageable
    const messages = rawMessages.slice(-10);

    // Build system prompt from user context
    const userContext = data.userContext as {
      userName?: string;
      borough?: string;
      childrenSummary?: string;
      parentingStage?: string;
    } | undefined;

    // Enrich user context from Firestore if partially missing
    let enrichedContext = { ...userContext };
    try {
      const userDoc = await db.collection("users").doc(userId).get();
      if (userDoc.exists) {
        const ud = userDoc.data() ?? {};
        enrichedContext = {
          userName: enrichedContext.userName || ud.name || ud.displayName,
          borough: enrichedContext.borough || ud.borough,
          childrenSummary: enrichedContext.childrenSummary || _buildChildrenSummary(ud),
          parentingStage: enrichedContext.parentingStage || _buildStageLabel(ud),
        };
      }
    } catch (e) {
      functions.logger.warn(`[huddlCopilotChat] Could not enrich context for ${userId}: ${e}`);
    }

    const systemPrompt = buildSystemPrompt(enrichedContext);

    try {
      const reply = await callGemini({ system: systemPrompt, messages });
      functions.logger.info(`[huddlCopilotChat] Reply generated for user ${userId}`);
      return { reply };
    } catch (e) {
      functions.logger.error(`[huddlCopilotChat] Gemini API error: ${e}`);
      throw new functions.https.HttpsError(
        "internal",
        "Something went wrong. Please try again."
      );
    }
  });

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 6: generateCopilotSuggestions  (§2D)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * HTTP callable — Generates 3 personalised suggestion chips for the Co-pilot
 * welcome screen, based on the user's Firestore profile.
 *
 * §2D Requirements:
 *   - Reads user profile: name, children (ages), parentingStage, borough
 *   - Computes youngest child's age in months
 *   - Returns 3 chip strings: age-based, stage-based, location-based
 *   - Falls back to 3 generic suggestions if profile is incomplete
 *   - Response is session-cached by the Flutter app (not re-fetched)
 *
 * Request payload: {} (empty — auth UID used)
 * Response: { suggestions: string[] }
 */

/**
 * Build a human-readable children summary from the user Firestore doc.
 *
 * AI-PII-1: emits AGES ONLY — children's names are never included so they
 * are not forwarded to the Gemini API (third-party LLM). Ages drive
 * developmental guidance; names are not functionally required.
 */
function _buildChildrenSummary(ud: Record<string, unknown>): string {
  const children = ud.children as Array<{ birthday?: string }> | undefined;
  if (!children || children.length === 0) {
    // Try legacy single-child fields (childName dropped — age only)
    const childBirthday = ud.childBirthday as string | undefined;
    if (childBirthday) {
      const ageMonths = _ageMonthsFromBirthday(childBirthday);
      const ageLabel = ageMonths < 12 ? `${ageMonths} months old` : `${Math.floor(ageMonths / 12)} years old`;
      return ageLabel;
    }
    return "not specified";
  }
  const ageLabels = children.map((c) => {
    const ageMonths = _ageMonthsFromBirthday(c.birthday ?? "");
    return ageMonths < 12 ? `${ageMonths} months` : `${Math.floor(ageMonths / 12)} years`;
  });
  if (ageLabels.length === 1) return `a ${ageLabels[0]}-old`;
  const last = ageLabels[ageLabels.length - 1];
  const rest = ageLabels.slice(0, -1);
  return `ages ${rest.join(", ")} and ${last}`;
}

/** Build a human-readable parenting stage label. */
function _buildStageLabel(ud: Record<string, unknown>): string {
  const stages = ud.stagesOfLife as string[] | undefined;
  const stage = stages?.[0] ?? (ud.parentingStage as string | undefined) ?? "";
  if (!stage) return "not specified";
  return stage;
}

/** Parse a birthday string ('YYYY-MM-DD' or 'YYYY') → age in months. */
function _ageMonthsFromBirthday(birthday: string): number {
  if (!birthday) return -1;
  try {
    const dob = birthday.length === 4
      ? new Date(`${birthday}-01-01`)
      : new Date(birthday);
    if (isNaN(dob.getTime())) return -1;
    return Math.floor((Date.now() - dob.getTime()) / (1000 * 60 * 60 * 24 * 30));
  } catch (_) {
    return -1;
  }
}

/** Return the youngest child's age in months from the user Firestore doc. */
function _youngestChildAgeMonths(ud: Record<string, unknown>): number {
  const children = ud.children as Array<{ birthday?: string }> | undefined;
  if (children && children.length > 0) {
    const ages = children
      .map((c) => _ageMonthsFromBirthday(c.birthday ?? ""))
      .filter((a) => a >= 0);
    if (ages.length > 0) return Math.min(...ages);
  }
  // Legacy childBirthday field
  const legacy = ud.childBirthday as string | undefined;
  if (legacy) return _ageMonthsFromBirthday(legacy);
  return -1;
}

export const generateCopilotSuggestions = functions
  .region('europe-west2')
  .https.onCall(
  async (_, context) => {
    // Authentication guard
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required."
      );
    }
    const userId = context.auth.uid;

    // Generic fallback suggestions
    const fallback = [
      "What should my child be doing this week?",
      "Help me find local parenting groups",
      "Tips for balancing work and family life",
    ];

    try {
      const userDoc = await db.collection("users").doc(userId).get();
      if (!userDoc.exists) {
        return { suggestions: fallback };
      }

      const ud = userDoc.data() ?? {};
      const borough = (ud.borough as string | undefined) || "your area";
      const stages = ud.stagesOfLife as string[] | undefined;
      const stage = (stages?.[0] ?? (ud.parentingStage as string | undefined) ?? "").toLowerCase();
      const childName = _getFirstChildName(ud);

      const suggestions: string[] = [];

      // ── Chip 1: Age-based ─────────────────────────────────────────────
      const ageMonths = _youngestChildAgeMonths(ud);
      if (ageMonths >= 0) {
        if (ageMonths <= 3) {
          const label = childName ? `${childName}` : "your baby";
          suggestions.push(`Sleep tips for ${label} (${ageMonths}-month-old)`);
        } else if (ageMonths <= 6) {
          suggestions.push(`Feeding and weaning advice for a ${ageMonths}-month-old`);
        } else if (ageMonths <= 12) {
          suggestions.push(`Milestones to expect at ${ageMonths} months`);
        } else if (ageMonths <= 24) {
          const years = Math.floor(ageMonths / 12);
          suggestions.push(`Activities for a ${years}-year-old`);
        } else if (ageMonths <= 48) {
          const years = Math.floor(ageMonths / 12);
          suggestions.push(`What should my ${years}-year-old know by now?`);
        } else {
          suggestions.push("What should my child be doing this week?");
        }
      } else {
        suggestions.push("What should my child be doing this week?");
      }

      // ── Chip 2: Stage-based ───────────────────────────────────────────
      if (stage.includes("expect") || stage.includes("pregnant")) {
        const dueDate = ud.dueDate as string | undefined;
        if (dueDate && dueDate.length >= 4) {
          const year = parseInt(dueDate.slice(0, 4), 10);
          if (!isNaN(year)) {
            suggestions.push(`What to prepare for your ${year} arrival`);
          } else {
            suggestions.push("What to expect in the third trimester");
          }
        } else {
          suggestions.push("What to expect in the third trimester");
        }
      } else if (stage.includes("newborn") || stage.includes("new_parent") || stage.includes("new parent")) {
        suggestions.push("Newborn feeding schedules and sleep routines");
      } else if (stage.includes("trying") || stage.includes("ttc")) {
        suggestions.push("Fertility and conception support resources near you");
      } else if (stage.includes("toddler")) {
        suggestions.push("Fun toddler activities for rainy days");
      } else {
        suggestions.push("Help me find parenting groups nearby");
      }

      // ── Chip 3: Location-based ────────────────────────────────────────
      suggestions.push(`Best parent groups in ${borough}`);

      return { suggestions: suggestions.slice(0, 3) };
    } catch (e) {
      functions.logger.error(`[generateCopilotSuggestions] Error for ${userId}: ${e}`);
      return { suggestions: fallback };
    }
  }
);

/** Extract the first child's name from the user Firestore doc. */
function _getFirstChildName(ud: Record<string, unknown>): string | null {
  const children = ud.children as Array<{ name?: string }> | undefined;
  if (children && children.length > 0 && children[0].name) {
    return children[0].name;
  }
  return (ud.childName as string | undefined) ?? null;
}

// ── 7. vertexGenerateContent ──────────────────────────────────────────────────
// Proxies generateContent requests to the Vertex AI fine-tuned model.
// Auth:    Service account OAuth 2.0 via VERTEX_AI_SA_KEY Secret Manager secret.
// Region:  CF runs in europe-west2; outbound HTTPS call to europe-west4-aiplatform.
// Fallback: throws HttpsError('unavailable', 'VERTEX_UNAVAILABLE') on any failure;
//           client catches and drops through to its Gemini AI Studio fallback.
export const vertexGenerateContent = functions
  .region("europe-west2")
  .runWith({
    timeoutSeconds: 60,
    memory: "512MB",
    secrets: ["VERTEX_AI_SA_KEY"],
  })
  .https.onCall(async (data, context) => {
    // ── Auth guard ────────────────────────────────────────────────────────────
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Request must be authenticated."
      );
    }
    const uid = context.auth.uid;

    // ── Rate limiting — tier-aware daily budget shared with copilot (Audit: SUB-2)
    const vertexDailyLimit = await resolveDailyAiLimit(uid);
    const vertexAllowed = await checkAndIncrementRateLimit(uid, vertexDailyLimit);
    if (!vertexAllowed) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "Daily AI limit reached. Upgrade for more, or come back tomorrow!"
      );
    }

    // ── Parse VERTEX_AI_SA_KEY from Secret Manager ────────────────────────────
    const saKeyRaw = process.env.VERTEX_AI_SA_KEY;
    if (!saKeyRaw) {
      functions.logger.error(
        "[vertexGenerateContent] VERTEX_AI_SA_KEY secret is not set or empty."
      );
      throw new functions.https.HttpsError(
        "unavailable",
        "VERTEX_UNAVAILABLE"
      );
    }

    let saKey: { client_email: string; private_key: string };
    try {
      saKey = JSON.parse(saKeyRaw) as {
        client_email: string;
        private_key: string;
      };
      if (!saKey.client_email || !saKey.private_key) {
        throw new Error("Missing client_email or private_key in SA JSON.");
      }
    } catch (parseErr) {
      functions.logger.error(
        `[vertexGenerateContent] Failed to parse VERTEX_AI_SA_KEY JSON: ${parseErr}`
      );
      throw new functions.https.HttpsError(
        "unavailable",
        "VERTEX_UNAVAILABLE"
      );
    }

    // ── Obtain Bearer token via google-auth-library JWT ───────────────────────
    let accessToken: string;
    try {
      const jwt = new JWT({
        email: saKey.client_email,
        key: saKey.private_key,
        scopes: ["https://www.googleapis.com/auth/cloud-platform"],
      });
      const tokenResponse = await jwt.authorize();
      if (!tokenResponse.access_token) {
        throw new Error("jwt.authorize() returned no access_token.");
      }
      accessToken = tokenResponse.access_token;
    } catch (tokenErr) {
      functions.logger.error(
        `[vertexGenerateContent] Failed to obtain Bearer token for uid=${uid}: ${tokenErr}`
      );
      throw new functions.https.HttpsError(
        "unavailable",
        "VERTEX_UNAVAILABLE"
      );
    }

    // ── POST to Vertex AI endpoint ────────────────────────────────────────────
    const requestBody = data.requestBody as Record<string, unknown>;
    if (!requestBody) {
      functions.logger.error(
        `[vertexGenerateContent] Missing requestBody in call data from uid=${uid}.`
      );
      throw new functions.https.HttpsError(
        "invalid-argument",
        "requestBody is required."
      );
    }

    return new Promise<{ data: unknown }>((resolve, reject) => {
      const bodyStr = JSON.stringify(requestBody);
      const url = new URL(VERTEX_ENDPOINT);

      const options: import("https").RequestOptions = {
        hostname: url.hostname,
        path: url.pathname + url.search,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${accessToken}`,
          "Content-Length": Buffer.byteLength(bodyStr),
        },
      };

      const req = https.request(options, (res) => {
        let raw = "";
        res.on("data", (chunk: Buffer) => { raw += chunk.toString(); });
        res.on("end", () => {
          if (res.statusCode === 200) {
            try {
              const parsed = JSON.parse(raw) as unknown;
              functions.logger.info(
                `[vertexGenerateContent] Success for uid=${uid}, status=200.`
              );
              resolve({ data: parsed });
            } catch (jsonErr) {
              functions.logger.warn(
                `[vertexGenerateContent] Vertex returned 200 but body not valid JSON for uid=${uid}: ${jsonErr}`
              );
              reject(
                new functions.https.HttpsError("unavailable", "VERTEX_UNAVAILABLE")
              );
            }
          } else {
            functions.logger.warn(
              `[vertexGenerateContent] Vertex returned HTTP ${res.statusCode} for uid=${uid}. Body: ${raw.slice(0, 500)}`
            );
            reject(
              new functions.https.HttpsError("unavailable", "VERTEX_UNAVAILABLE")
            );
          }
        });
      });

      req.on("error", (err: Error) => {
        functions.logger.warn(
          `[vertexGenerateContent] https.request network error for uid=${uid}: ${err.message}`
        );
        reject(
          new functions.https.HttpsError("unavailable", "VERTEX_UNAVAILABLE")
        );
      });

      req.write(bodyStr);
      req.end();
    });
  });

// ---------------------------------------------------------------------------
// 8. syncPublicProfile
// ---------------------------------------------------------------------------
// Mirrors the canonical public field set from users/{userId} to
// users_public/{userId} on every Firestore write (create, update, delete).
//
// On delete  → deletes users_public/{userId} for GDPR consistency.
// On create/update → copies PUBLIC_FIELDS via set({merge:true}).
//   merge:true: fields absent from this write are never overwritten in
//   users_public (safe for partial updates, e.g. only isOnline flipping).
//
// Borough + geo siblings (ward, wardCode, districtCode, region) are included
// so boroughMatches() in firestore.rules reads exclusively from users_public,
// making all borough-gated writes immune to client-side borough injection.
//
// Coexists with refreshUserRecommendations (.onUpdate same path) — two
// independent triggers per write, acceptable at current scale.
// ---------------------------------------------------------------------------
export const syncPublicProfile = functions
  .region("europe-west2")
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .firestore.document("users/{userId}")
  .onWrite(async (change, context) => {
    const userId = context.params.userId as string;
    const publicRef = db.collection("users_public").doc(userId);

    // ── Delete path ────────────────────────────────────────────────────────
    if (!change.after.exists) {
      functions.logger.info(
        `[syncPublicProfile] User ${userId} deleted — removing public mirror.`
      );
      await publicRef.delete();
      return;
    }

    // ── Create / Update path ───────────────────────────────────────────────
    const data = change.after.data() as Record<string, unknown>;

    // Canonical public field set.
    // borough is written here only by setUserBorough (Admin SDK) or by the
    // initial _createUserProfile (create rule, no affectedKeys guard).
    // Client update writes of borough are blocked by the F-09 affectedKeys rule.
    const PUBLIC_FIELDS = [
      "name",
      "photoUrl",
      "parentType",
      "borough",
      "isOnline",
      "stagesOfLife",
      "ward",
      "wardCode",
      "districtCode",
      "region",
    ] as const;

    const publicData: Record<string, unknown> = {};
    for (const field of PUBLIC_FIELDS) {
      if (data[field] !== undefined) {
        publicData[field] = data[field];
      }
    }

    // Guard: a write touching only private fields (e.g. stripeCustomerId)
    // produces an empty publicData — skip the mirror write to avoid a
    // no-op Firestore round-trip that only advances the doc's updateTime.
    if (Object.keys(publicData).length === 0) {
      functions.logger.info(
        `[syncPublicProfile] Write to users/${userId} contained no ` +
          `public fields — skipping mirror.`
      );
      return;
    }

    functions.logger.info(
      `[syncPublicProfile] Mirroring ${Object.keys(publicData).length} ` +
        `field(s) for user ${userId}: ${Object.keys(publicData).join(", ")}`
    );

    await publicRef.set(publicData, { merge: true });
  });

// ---------------------------------------------------------------------------
// 9. setUserBorough
// ---------------------------------------------------------------------------
// HTTPS callable — resolves a UK postcode server-side via postcodes.io,
// enforces the Cambridge launch-area gate, then writes the resolved borough
// and geo siblings to users/{uid} via Admin SDK (bypassing Firestore rules).
//
// Why Admin SDK? After F-09 lands, the owner update rule blocks client writes
// of borough/postcode/geo fields via affectedKeys(). Admin SDK ignores rules,
// so this is the only legitimate post-registration path for borough changes.
//
// The syncPublicProfile trigger fires automatically after the Admin SDK write,
// mirroring the new borough to users_public/{uid}.
//
// Cambridge gate (mirrors Dart PostcodeService._isCambridgeBorough exactly):
//   admin_district.toLowerCase() must be:
//     == 'cambridge'  OR  includes('cambridgeshire')  OR
//     == 'fenland'    OR  == 'huntingdonshire'
// Gate is enforced SERVER-SIDE to prevent direct SDK calls bypassing the UI.
// If outside the allowed set → HttpsError('failed-precondition', 'OUTSIDE_LAUNCH_AREA').
//
// Input:  { postcode: string }
// Output: { borough, ward, districtCode, wardCode, region }
// ---------------------------------------------------------------------------

/** Mirror of Dart PostcodeService._isCambridgeBorough. Update both together. */
function isAllowedBorough(borough: string): boolean {
  const lower = borough.toLowerCase();
  return (
    lower === "cambridge" ||
    lower.includes("cambridgeshire") ||
    lower === "fenland" ||
    lower === "huntingdonshire"
  );
}

export const setUserBorough = functions
  .region("europe-west2")
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (data, context) => {
    // ── Auth guard ─────────────────────────────────────────────────────────
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be signed in to update borough."
      );
    }
    const uid = context.auth.uid;

    // ── Input validation ───────────────────────────────────────────────────
    const rawPostcode = (data as Record<string, unknown>).postcode;
    if (typeof rawPostcode !== "string" || rawPostcode.trim() === "") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "postcode must be a non-empty string."
      );
    }
    // Normalise: trim, uppercase, collapse internal whitespace to single space
    const postcode = rawPostcode.trim().toUpperCase().replace(/\s+/g, " ");

    // ── postcodes.io lookup ────────────────────────────────────────────────
    // Uses the same https.request pattern as vertexGenerateContent.
    // Wraps the callback API in a Promise so we can await it.
    interface GeoResult {
      borough: string;
      ward: string;
      districtCode: string;
      wardCode: string;
      region: string;
    }

    const geo = await new Promise<GeoResult>((resolve, reject) => {
      const path = `/postcodes/${encodeURIComponent(postcode)}`;
      const options: import("https").RequestOptions = {
        hostname: "api.postcodes.io",
        path,
        method: "GET",
      };

      const req = https.request(options, (res) => {
        let raw = "";
        res.on("data", (chunk: Buffer) => { raw += chunk.toString(); });
        res.on("end", () => {
          if (res.statusCode === 404) {
            functions.logger.warn(
              `[setUserBorough] postcodes.io 404 for postcode="${postcode}" uid=${uid}`
            );
            reject(
              new functions.https.HttpsError(
                "not-found",
                "Postcode not recognised. Please check and try again."
              )
            );
            return;
          }
          if (res.statusCode !== 200) {
            functions.logger.warn(
              `[setUserBorough] postcodes.io returned HTTP ${res.statusCode} ` +
                `for postcode="${postcode}" uid=${uid}. Body: ${raw.slice(0, 200)}`
            );
            reject(
              new functions.https.HttpsError(
                "unavailable",
                "Postcode lookup service is temporarily unavailable. Please try again."
              )
            );
            return;
          }
          try {
            const parsed = JSON.parse(raw) as {
              result?: {
                admin_district?: string;
                admin_ward?: string;
                region?: string;
                codes?: {
                  admin_district?: string;
                  admin_ward?: string;
                };
              };
            };
            const result = parsed.result;
            const borough = result?.admin_district ?? "";
            const ward = result?.admin_ward ?? "";
            const districtCode = result?.codes?.admin_district ?? "";
            const wardCode = result?.codes?.admin_ward ?? "";
            const region = result?.region ?? "";

            if (!borough) {
              functions.logger.warn(
                `[setUserBorough] postcodes.io returned no admin_district ` +
                  `for postcode="${postcode}" uid=${uid}`
              );
              reject(
                new functions.https.HttpsError(
                  "not-found",
                  "Could not resolve a borough for this postcode."
                )
              );
              return;
            }
            resolve({ borough, ward, districtCode, wardCode, region });
          } catch (parseErr) {
            functions.logger.warn(
              `[setUserBorough] postcodes.io response parse error for ` +
                `postcode="${postcode}" uid=${uid}: ${parseErr}`
            );
            reject(
              new functions.https.HttpsError(
                "unavailable",
                "Postcode lookup service is temporarily unavailable. Please try again."
              )
            );
          }
        });
      });

      req.on("error", (err: Error) => {
        functions.logger.warn(
          `[setUserBorough] https.request network error for ` +
            `postcode="${postcode}" uid=${uid}: ${err.message}`
        );
        reject(
          new functions.https.HttpsError(
            "unavailable",
            "Postcode lookup service is temporarily unavailable. Please try again."
          )
        );
      });

      req.end();
    });

    // ── Cambridge gate ─────────────────────────────────────────────────────
    // Mirrors Dart PostcodeService._isCambridgeBorough exactly.
    // Update isAllowedBorough() and the Dart function together if launch
    // area ever expands.
    if (!isAllowedBorough(geo.borough)) {
      functions.logger.info(
        `[setUserBorough] Gate rejection: uid=${uid} postcode="${postcode}" ` +
          `resolved district="${geo.borough}" — outside Cambridge launch area.`
      );
      throw new functions.https.HttpsError(
        "failed-precondition",
        "OUTSIDE_LAUNCH_AREA"
      );
    }

    // ── Write via Admin SDK ────────────────────────────────────────────────
    // Admin SDK bypasses Firestore rules — this is intentional. The F-09
    // affectedKeys rule blocks owner client-writes of borough/geo fields.
    // This callable is the only post-registration path for legitimate borough
    // changes. syncPublicProfile fires automatically after this write.
    await db.collection("users").doc(uid).update({
      borough: geo.borough,
      postcode: postcode,
      ward: geo.ward,
      wardCode: geo.wardCode,
      districtCode: geo.districtCode,
      region: geo.region,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    functions.logger.info(
      `[setUserBorough] Success: uid=${uid} postcode="${postcode}" ` +
        `→ borough="${geo.borough}" ward="${geo.ward}"`
    );

    return {
      borough: geo.borough,
      ward: geo.ward,
      districtCode: geo.districtCode,
      wardCode: geo.wardCode,
      region: geo.region,
    };
  });

// ═══════════════════════════════════════════════════════════════════════════
// 10. deleteUserData — GDPR Deletion (Phase 1: simple query-deletes)
// ═══════════════════════════════════════════════════════════════════════════
//
// SECURITY INVARIANT (non-negotiable):
//   uid is taken EXCLUSIVELY from context.auth.uid.
//   The callable payload is intentionally narrow — only `dryRun?: boolean`.
//   A uid field in the payload is NOT read, NOT used, NOT forwarded.
//   Any authenticated user can only ever delete their own data.
//
// PHASE SCOPE:
//   Phase 1 handles the 9 simple top-level collection query-deletes
//   where a single uid-field equality query identifies all user-owned docs.
//   Later phases add: subcollection sweeps, collectionGroup sweeps,
//   Storage enumeration, group_messages (Admin SDK), and anonymise passes.
//
// RETURN SHAPE (per spec A.4):
//   {
//     success: boolean,
//     uid: string,
//     dryRun: boolean,
//     startedAt: string (ISO-8601),
//     completedAt: string (ISO-8601),
//     policy: GdprDeletionPolicy,
//     steps: { [stepKey]: StepResult },
//     error?: string,            // present only when success === false
//     retryable?: boolean,       // present only when success === false
//   }
//
// FIELD NAME VERIFICATION LEDGER (read from source — do not change without re-reading):
//   subscriptions     → field: "userId"        (firebase_auth_service.dart line 750)
//   notifications     → field: "userId"        (firebase_auth_service.dart line 769)
//   local_services    → field: "createdByUid"  (firebase_auth_service.dart line 853)
//   borough_feed      → field: "partnerUid"    (community_feed_service.dart — prior session)
//   feedback          → field: "user_uid"      (feedback_service.dart line 118)
//   community_wisdom  → field: "author_uid"    (ai_knowledge_flywheel_service.dart line 184)
//   group_messages    → field: "senderId"      (firebase_auth_service.dart line 755)
//   meetups           → fields: "createdBy" + "organiserId" (legacy alias, two passes)
//                                              (firebase_auth_service.dart lines 775-780)
//   marketplace       → field: "sellerId"      (firebase_auth_service.dart line 784)
//
//   REMOVED FROM ORIGINAL SPEC (not Firestore collections — verified by source inspection):
//   "offers"           → AiOffersService is pure RevGlue/AI client, zero Firestore writes
//   "polls"            → PollService uses BrowserStorage (localStorage) only, no Firestore
//   "partner_analytics" → BoroughAnalyticsService uses BrowserStorage only, no Firestore
//
//   community_wisdom is gated by the AUTHORED_CONTENT config switch.
//   Phase 1 reads the switch and honours it. Default = "anonymise" (scrub-but-retain).
// ═══════════════════════════════════════════════════════════════════════════

// ── Types ──────────────────────────────────────────────────────────────────

interface StepResult {
  status: "ok" | "skipped" | "error";
  count: number;         // docs deleted (or would-delete in dryRun)
  error?: string;        // present only when status === "error"
}

interface GdprDeletionPolicy {
  authored_content:          "delete" | "anonymise" | "retain";
  reports:                   "delete" | "retain";              // HARD LOCK: no anonymise
  feedback:                  "delete" | "retain";              // simplified: retain or delete
  invitations_sent:          "delete" | "retain";              // Phase 2: sent invitations
  created_content_meetups:   "delete" | "retain";              // meetups created by uid
  created_content_marketplace: "delete" | "retain";           // marketplace listings by uid
  dry_run_default: boolean;
}

interface DeleteUserDataResult {
  success: boolean;
  uid: string;
  dryRun: boolean;
  startedAt: string;
  completedAt: string;
  policy: GdprDeletionPolicy;
  steps: { [key: string]: StepResult };
  error?: string;
  retryable?: boolean;
}

// ── Sentinel constant ────────────────────────────────────────────────────────
//
// Written into the `message` field (and `content` if present) of any message
// that is anonymised rather than deleted. Single definition here so it is
// change-/localisation-safe in future.
const DELETED_CONTENT_SENTINEL = "[deleted]";

// ── Hardcoded policy defaults ───────────────────────────────────────────────
// Applied when _config/gdpr_deletion_policy is absent or a field is missing.
// authored_content default = "anonymise" — group messages scrubbed-but-retained;
// flip to "delete" only on solicitor sign-off.
const DEFAULT_GDPR_POLICY: GdprDeletionPolicy = {
  authored_content:            "anonymise", // group msgs + community_wisdom + borough_announcements scrubbed-but-retained
  reports:                     "retain",    // HARD LOCK — reports are legal records; retain unless explicit solicitor instruction
  feedback:                    "delete",    // platform feedback — delete by default
  invitations_sent:            "retain",    // legal hold potential — retain by default
  created_content_meetups:     "delete",    // user-created meetups — deleted by default
  created_content_marketplace: "delete",    // user-created marketplace listings — deleted by default
  dry_run_default:             false,
};

// ── Paginated-delete helper ────────────────────────────────────────────────
//
// Paginates through a query in batches of PAGE_SIZE, deleting each page.
// Uses orderBy(FieldPath.documentId()).startAfter(cursor) for stable pagination.
// Returns the total number of documents deleted.
//
// Every bulk delete in Phase 1 (and all subsequent phases) calls this helper.
// Never roll ad-hoc batch loops outside this function.
const PAGE_SIZE = 400;

async function paginatedDelete(
  query: admin.firestore.Query,
  dryRun: boolean
): Promise<number> {
  let totalDeleted = 0;
  let cursor: admin.firestore.DocumentSnapshot | null = null;

  // eslint-disable-next-line no-constant-condition
  while (true) {
    // Build paged query: ordered by document ID for stable cursor pagination.
    // startAfter(cursor) is only applied after the first page.
    let pagedQuery = query
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(PAGE_SIZE);

    if (cursor !== null) {
      pagedQuery = pagedQuery.startAfter(cursor);
    }

    const snapshot = await pagedQuery.get();

    if (snapshot.empty) {
      break; // no more documents
    }

    totalDeleted += snapshot.docs.length;

    if (!dryRun) {
      // Batch-delete this page. Firestore batch limit is 500 writes;
      // PAGE_SIZE=400 keeps us safely below it.
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
    }

    if (snapshot.docs.length < PAGE_SIZE) {
      break; // last page — fewer docs than the page size means we're done
    }

    // Advance cursor to the last doc of this page for the next iteration.
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }

  return totalDeleted;
}

// ── Paginated-anonymise helper ─────────────────────────────────────────────
//
// Paginates through a query, applying a per-doc field update() to each match.
// Uses the same cursor pattern as paginatedDelete for stable pagination.
// The `updateFields` map is applied verbatim to every matched document.
// In dryRun mode the pages are counted but no writes are issued.
// Returns the total number of documents touched (or would-touch in dryRun).
//
// CONCURRENCY SAFETY: each call is a targeted update() on specific fields of
// specific document IDs (not a collection-level overwrite). A concurrent write
// from another client to the same document updates DIFFERENT fields, so there
// is no clobber risk for the other participant's messages.
async function paginatedAnonymise(
  query: admin.firestore.Query,
  updateFields: Record<string, unknown>,
  dryRun: boolean
): Promise<number> {
  let totalTouched = 0;
  let cursor: admin.firestore.DocumentSnapshot | null = null;

  // eslint-disable-next-line no-constant-condition
  while (true) {
    let pagedQuery = query
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(PAGE_SIZE);
    if (cursor !== null) pagedQuery = pagedQuery.startAfter(cursor);

    const snapshot = await pagedQuery.get();
    if (snapshot.empty) break;

    totalTouched += snapshot.docs.length;

    if (!dryRun) {
      // Batch-update this page. Each update() touches only the listed fields.
      // PAGE_SIZE=400 keeps us safely below the Firestore batch limit of 500.
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        batch.update(doc.ref, updateFields);
      }
      await batch.commit();
    }

    if (snapshot.docs.length < PAGE_SIZE) break;
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }

  return totalTouched;
}

// ── Config-switch reader ────────────────────────────────────────────────────
//
// Reads _config/gdpr_deletion_policy once at CF start via Admin SDK.
// Merges with DEFAULT_GDPR_POLICY — any missing field falls back to the default.
// Returns the fully-resolved policy. Never throws; returns defaults on any error.
async function resolveGdprPolicy(): Promise<GdprDeletionPolicy> {
  try {
    const configDoc = await db.collection("_config").doc("gdpr_deletion_policy").get();
    if (!configDoc.exists) {
      functions.logger.info("[deleteUserData] No _config/gdpr_deletion_policy doc — using defaults.");
      return { ...DEFAULT_GDPR_POLICY };
    }
    const remote = configDoc.data() as Partial<GdprDeletionPolicy>;
    // Merge: remote fields override defaults; missing fields fall back to defaults.
    return {
      authored_content:            remote.authored_content            ?? DEFAULT_GDPR_POLICY.authored_content,
      reports:                     remote.reports                     ?? DEFAULT_GDPR_POLICY.reports,
      feedback:                    remote.feedback                    ?? DEFAULT_GDPR_POLICY.feedback,
      invitations_sent:            remote.invitations_sent            ?? DEFAULT_GDPR_POLICY.invitations_sent,
      created_content_meetups:     remote.created_content_meetups     ?? DEFAULT_GDPR_POLICY.created_content_meetups,
      created_content_marketplace: remote.created_content_marketplace ?? DEFAULT_GDPR_POLICY.created_content_marketplace,
      dry_run_default:             remote.dry_run_default             ?? DEFAULT_GDPR_POLICY.dry_run_default,
    };
  } catch (err) {
    functions.logger.error("[deleteUserData] resolveGdprPolicy error — falling back to defaults:", err);
    return { ...DEFAULT_GDPR_POLICY };
  }
}

// ── Cloud Function ─────────────────────────────────────────────────────────

export const deleteUserData = functions
  .region("europe-west2")
  .runWith({
    timeoutSeconds: 540,
    memory: "1GB",
    // GDPR-STRIPE-1: INTERNAL_SERVICE_SECRET needed to call Railway
    // /api/gdpr/anonymize-stripe service-to-service.
    secrets: ["INTERNAL_SERVICE_SECRET"],
  })
  .https.onCall(async (data: { dryRun?: boolean }, context): Promise<DeleteUserDataResult> => {

    // ══════════════════════════════════════════════════════════════════
    // SECURITY INVARIANT — THIS BLOCK IS THE MOST IMPORTANT CODE HERE.
    //
    // uid comes from context.auth.uid ONLY.
    // The payload (data) is NOT a source of uid under any circumstances.
    // If context.auth is null, we throw immediately and touch nothing.
    // ══════════════════════════════════════════════════════════════════
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "deleteUserData requires authentication. No uid accepted from payload."
      );
    }
    const uid: string = context.auth.uid;
    // Explicitly discard any uid-like field the caller may have put in the payload.
    // This is belt-and-suspenders: we never reference data.uid or data['uid'].
    // Only data.dryRun is read, and only as a boolean.

    const startedAt = new Date().toISOString();
    const dryRun: boolean = typeof data.dryRun === "boolean" ? data.dryRun : false;

    functions.logger.info(
      `[deleteUserData] START uid=${uid} dryRun=${dryRun} startedAt=${startedAt}`
    );

    // ── Resolve policy config ──────────────────────────────────────────────
    const policy = await resolveGdprPolicy();
    functions.logger.info("[deleteUserData] Resolved policy:", policy);

    // ══════════════════════════════════════════════════════════════════
    // PIECE 1a — GDPR ERASURE JOB RECORD (GDPR-STRIPE-1-R1)
    //
    // Write a durable audit record BEFORE any deletion phase.
    // This record MUST outlive the user doc wipe — it lives in
    // gdpr_erasure_jobs/{uid}, which is intentionally excluded from
    // every deleteUserData phase below (audit trail must never be swept).
    //
    // stripeCustomerId is read HERE while users/{uid} still exists.
    // It is captured into the job record so the reconciler can retry
    // the Stripe step without needing the user doc.
    //
    // dryRun: skip the Firestore write but log "would write" so that
    // dry-run test runs don't pollute the audit collection.
    // ══════════════════════════════════════════════════════════════════

    // Read stripeCustomerId while users/{uid} still exists.
    let erasureStripeCustomerId: string | null = null;
    try {
      const userSnap = await db.collection("users").doc(uid).get();
      erasureStripeCustomerId = userSnap.exists
        ? ((userSnap.data()?.stripeCustomerId as string) ?? null)
        : null;
    } catch (err) {
      // Non-fatal: log and continue.  Job record will have stripeCustomerId=null.
      functions.logger.warn(
        `[deleteUserData] PIECE-1a: could not read stripeCustomerId for uid=${uid}: ${String(err)}`
      );
    }

    // Write (or update) the durable erasure job record.
    const jobRef = db.collection("gdpr_erasure_jobs").doc(uid);
    if (!dryRun) {
      try {
        await jobRef.set(
          {
            uid,
            stripeCustomerId: erasureStripeCustomerId,
            status:           "pending",
            dryRun,
            requestedAt:      admin.firestore.FieldValue.serverTimestamp(),
            startedAt,
            steps:            {},
            retryCount:       0,
            lastUpdatedAt:    admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        functions.logger.info(
          `[deleteUserData] PIECE-1a: erasure job written gdpr_erasure_jobs/${uid} stripeCustomerId=${erasureStripeCustomerId}`
        );
      } catch (err) {
        // Non-fatal: the job record is for audit/reconciliation only.
        // A failure here must not abort the erasure pipeline.
        functions.logger.error(
          `[deleteUserData] PIECE-1a: failed to write erasure job for uid=${uid}: ${String(err)}`
        );
      }
    } else {
      functions.logger.info(
        `[deleteUserData] PIECE-1a: dryRun — would write gdpr_erasure_jobs/${uid} with stripeCustomerId=${erasureStripeCustomerId}`
      );
    }

    // ── Steps accumulator ──────────────────────────────────────────────────
    // Each step records its own StepResult. On any unhandled error in a step,
    // the step is marked error but we continue accumulating and return a
    // partial result with success=false rather than throwing and losing state.
    const steps: { [key: string]: StepResult } = {};

    // Helper: run one step, catch errors, populate steps[key].
    async function runStep(
      key: string,
      query: admin.firestore.Query | null,
      skipReason?: string
    ): Promise<void> {
      if (query === null || skipReason !== undefined) {
        steps[key] = { status: "skipped", count: 0, error: skipReason };
        return;
      }
      try {
        const count = await paginatedDelete(query, dryRun);
        steps[key] = { status: "ok", count };
        functions.logger.info(`[deleteUserData] ${key}: deleted ${count} docs (dryRun=${dryRun})`);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[key] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
      }
    }

    // ══════════════════════════════════════════════════════════════════
    // PHASE 0 — STRIPE PII ANONYMIZATION  (GDPR-STRIPE-1)
    //
    // CRITICAL ORDERING: stripeCustomerId lives on users/{uid}.
    // This phase runs BEFORE Phase 1 (which deletes subscriptions/{uid},
    // also containing stripeSubscriptionId) and before any users/{uid}
    // write, so the Railway service can read both fields from Firestore.
    //
    // The Railway endpoint calls anonymizeStripeCustomer(userId) which:
    //   • Scrubs name/email/phone/address/metadata on the Stripe Customer
    //   • Retains the Customer + all Invoices/Charges/PaymentIntents
    //   • Cancels any active subscription at-period-end
    //   • Returns { anonymized, customerId, subscriptionCancelled }
    //
    // dryRun: skip the POST, record as "skipped (dryRun)".
    // Fail-soft: if the POST errors/times out, record the error in steps[]
    //   and continue — Stripe failure must not block Firestore erasure.
    // ══════════════════════════════════════════════════════════════════

    await (async () => {
      const key = "stripe_anonymize";

      if (dryRun) {
        steps[key] = { status: "skipped", count: 0, error: "dryRun — would POST /api/gdpr/anonymize-stripe" };
        functions.logger.info(`[deleteUserData] ${key}: skipped (dryRun)`);
        return;
      }

      const secret = process.env.INTERNAL_SERVICE_SECRET;
      if (!secret) {
        // INTERNAL_SERVICE_SECRET not injected — log and skip rather than
        // hard-fail.  Operator must add the secret to deleteUserData runWith.
        steps[key] = { status: "error", count: 0, error: "INTERNAL_SERVICE_SECRET not set in functions runtime" };
        functions.logger.error(`[deleteUserData] ${key}: INTERNAL_SERVICE_SECRET not set — Stripe anonymization skipped`);
        return;
      }

      // Helper: POST to Railway /api/gdpr/anonymize-stripe with a 10 s timeout.
      // Returns { ok: true, body } or { ok: false, error }.
      const railwayStripeAnonymize = (): Promise<{ ok: boolean; body?: unknown; error?: string }> =>
        new Promise((resolve) => {
          const bodyStr = JSON.stringify({ userId: uid });

          const options: import("https").RequestOptions = {
            hostname: "api.huddlapp.co.uk",
            path:     "/api/gdpr/anonymize-stripe",
            method:   "POST",
            headers:  {
              "Content-Type":   "application/json",
              "Content-Length": Buffer.byteLength(bodyStr),
              "X-Service-Auth": secret,
            },
          };

          const timer = setTimeout(() => {
            req.destroy();
            resolve({ ok: false, error: "timeout after 10 s" });
          }, 10_000);

          const req = https.request(options, (res) => {
            const chunks: Buffer[] = [];
            res.on("data", (c: Buffer) => chunks.push(c));
            res.on("end", () => {
              clearTimeout(timer);
              const raw = Buffer.concat(chunks).toString("utf8");
              if (res.statusCode && res.statusCode >= 400) {
                resolve({ ok: false, error: `HTTP ${res.statusCode}: ${raw.substring(0, 200)}` });
              } else {
                try {
                  resolve({ ok: true, body: JSON.parse(raw) });
                } catch {
                  resolve({ ok: true, body: raw });
                }
              }
            });
          });

          req.on("error", (err: Error) => {
            clearTimeout(timer);
            resolve({ ok: false, error: err.message });
          });

          req.write(bodyStr);
          req.end();
        });

      try {
        const resp = await railwayStripeAnonymize();
        if (resp.ok) {
          const body = resp.body as Record<string, unknown> | undefined;
          const anonymized = body && body["anonymized"];
          const reason     = body && body["reason"];
          functions.logger.info(
            `[deleteUserData] ${key}: ok — anonymized=${anonymized} reason=${reason ?? "n/a"}`
          );
          steps[key] = { status: "ok", count: anonymized ? 1 : 0 };
        } else {
          // Fail-soft: record as error but do not abort.
          functions.logger.error(
            `[deleteUserData] ${key}: Railway error — ${resp.error} — continuing with Firestore deletion`
          );
          steps[key] = { status: "error", count: 0, error: resp.error };
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        functions.logger.error(`[deleteUserData] ${key}: unexpected error — ${msg}`);
        steps[key] = { status: "error", count: 0, error: msg };
      }
    })();

    // ══════════════════════════════════════════════════════════════════
    // PHASE 1 — SIMPLE QUERY-DELETES
    //
    // Nine top-level collections where a single uid-field equality query
    // identifies all user-owned docs. No subcollections, no group queries,
    // no Storage — those are Phases 2–6.
    //
    // Field names annotated with source verification (see ledger above).
    // ══════════════════════════════════════════════════════════════════

    // 1. subscriptions — field "userId" (firebase_auth_service.dart:750)
    await runStep(
      "subscriptions",
      db.collection("subscriptions").where("userId", "==", uid)
    );

    // 1b. stripe_sessions — field "userId" (stripe-service.js:176)
    //     LAYER-3-STRIPE-SESSIONS-1: stripe_sessions carries userId (backend-written
    //     checkout records). Anonymise (not delete) to match the Stripe-customer
    //     anonymise posture — retain financial record, remove linkable identity.
    //     Fields verified from stripe-service.js:175 write:
    //       userId       → null (identity field, must be scrubbed)
    //       productId    → retained (financial metadata, non-identifying)
    //       tier         → retained (financial metadata)
    //       billingPeriod → retained (financial metadata)
    //       status / createdAt → retained (operational)
    await (async () => {
      const key = "stripe_sessions";
      try {
        const query = db.collection("stripe_sessions").where("userId", "==", uid);
        const count = await paginatedAnonymise(query, { userId: null }, dryRun);
        steps[key] = { status: "ok", count };
        functions.logger.info(
          `[deleteUserData] ${key}: anonymised ${count} docs (dryRun=${dryRun})`
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[key] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
      }
    })();

    // 2. notifications — field "userId" (firebase_auth_service.dart:769)
    await runStep(
      "notifications",
      db.collection("notifications").where("userId", "==", uid)
    );

    // 3. local_services — field "createdByUid" (firebase_auth_service.dart:853)
    //    Note: ownerUid is partner-only; createdByUid is set on ALL user-created listings.
    await runStep(
      "local_services",
      db.collection("local_services").where("createdByUid", "==", uid)
    );

    // 4. borough_feed — field "partnerUid" (community_feed_service.dart — verified)
    await runStep(
      "borough_feed",
      db.collection("borough_feed").where("partnerUid", "==", uid)
    );

    // 5. feedback — field "user_uid" (feedback_service.dart:118)
    //    Gated by policy.feedback switch. Default = "delete".
    if (policy.feedback === "delete") {
      await runStep(
        "feedback",
        db.collection("feedback").where("user_uid", "==", uid)
      );
    } else {
      await runStep("feedback", null, `policy.feedback=${policy.feedback} — retained`);
    }

    // 6. community_wisdom — field "author_uid" (ai_knowledge_flywheel_service.dart:184)
    //    Gated by policy.authored_content switch. Default = "anonymise".
    //    Fields confirmed from ai_knowledge_flywheel_service.dart:
    //      author_uid, author_name, author_avatar → nulled on anonymise
    //      content_text → DELETED_CONTENT_SENTINEL on anonymise
    //    (same pattern as group_messages / borough_announcements authored posts)
    await (async () => {
      const key = "community_wisdom";
      try {
        const query = db.collection("community_wisdom").where("author_uid", "==", uid);
        if (policy.authored_content === "anonymise") {
          const count = await paginatedAnonymise(
            query,
            {
              author_uid:    null,
              author_name:   null,
              author_avatar: null,
              content_text:  DELETED_CONTENT_SENTINEL,
            },
            dryRun
          );
          steps[key] = { status: "ok", count };
          functions.logger.info(
            `[deleteUserData] ${key}: anonymised ${count} docs (dryRun=${dryRun})`
          );
        } else if (policy.authored_content === "delete") {
          const count = await paginatedDelete(query, dryRun);
          steps[key] = { status: "ok", count };
          functions.logger.info(
            `[deleteUserData] ${key}: deleted ${count} docs (dryRun=${dryRun})`
          );
        } else {
          // "retain"
          steps[key] = { status: "skipped", count: 0,
            error: `policy.authored_content=${policy.authored_content} — retained` };
          functions.logger.info(`[deleteUserData] ${key}: skipped — policy.authored_content=retain`);
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[key] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
      }
    })();

    // 6b. borough_announcements — authored posts + comments subcollection
    //     F-11 migration: comments now live in borough_announcements/{id}/comments.
    //     Two sub-operations, reported as one step:
    //       (a) authored announcement docs (authorId == uid) — per authored_content switch
    //       (b) comment docs collectionGroup('comments').where('authorId', ==, uid)
    //           + decrement parent commentCount for each deleted comment
    //     Fields on announcement doc:
    //       authorId        (string, required, UID of author)
    //     Fields on comment doc:
    //       authorId        (string, uid of commenter — F-11)
    //     commentCount on parent decremented per comment deleted (matching addComment coupling)
    await (async () => {
      const key = "borough_announcements";
      try {
        let count = 0;

        // ── (a) authored announcement docs ──────────────────────────────────
        const announcementQuery = db
          .collection("borough_announcements")
          .where("authorId", "==", uid);

        if (policy.authored_content === "anonymise") {
          count += await paginatedAnonymise(
            announcementQuery,
            { authorId: null },
            dryRun
          );
        } else if (policy.authored_content === "delete") {
          count += await paginatedDelete(announcementQuery, dryRun);
        }
        // "retain" → touch nothing

        // ── (b) comment docs authored by uid + commentCount decrement ────────
        //    Must run regardless of authored_content switch — user's comments are
        //    always deleted on GDPR request (identity in comment doc).
        //    commentCount on parent announcement is decremented per deleted comment
        //    to mirror the increment coupling in addComment (announcement_service.dart:693).
        const commentQuery = db
          .collectionGroup("comments")
          .where("authorId", "==", uid);

        if (!dryRun) {
          // Paginate: fetch, decrement parent, batch-delete
          let lastDoc: admin.firestore.QueryDocumentSnapshot | undefined;
          let pageCount = 0;
          do {
            const page: admin.firestore.QuerySnapshot = lastDoc
              ? await commentQuery.startAfter(lastDoc).limit(400).get()
              : await commentQuery.limit(400).get();
            if (page.empty) break;
            pageCount += page.docs.length;

            const batch = db.batch();
            for (const commentDoc of page.docs) {
              batch.delete(commentDoc.ref);
              // Decrement commentCount on parent announcement
              const parentRef = commentDoc.ref.parent.parent;
              if (parentRef) {
                batch.update(parentRef, {
                  commentCount: admin.firestore.FieldValue.increment(-1),
                });
              }
            }
            await batch.commit();
            lastDoc = page.docs[page.docs.length - 1];
          } while (true);
          count += pageCount;
        } else {
          // dryRun: just count
          const snap = await commentQuery.get();
          count += snap.size;
        }

        steps[key] = { status: "ok", count };
        functions.logger.info(
          `[deleteUserData] ${key}: processed ${count} announcement/comment docs ` +
          `(authored_content=${policy.authored_content}, dryRun=${dryRun})`
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[key] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
      }
    })();

    // 6c. reports — field "reportedByUid" (report_service.dart)
    //     HARD LOCK: reports are legal records. Default = "retain".
    //     Only deleted on explicit solicitor sign-off (authored_content_policy.reports="delete").
    await (async () => {
      const key = "reports";
      if (policy.reports === "delete") {
        await runStep(
          key,
          db.collection("reports").where("reportedByUid", "==", uid)
        );
      } else {
        steps[key] = { status: "skipped", count: 0,
          error: `policy.reports=${policy.reports} — legal records retained` };
        functions.logger.info(`[deleteUserData] ${key}: skipped — hard-lock retain`);
      }
    })();

    // 7. group_messages — field "senderId" (firestore_service.dart:362)
    //    F-03 lock: this is a cross-user collection; Admin SDK bypasses client rules.
    //    Phase 3: gated by policy.authored_content switch (default = "anonymise").
    //      "anonymise" → scrub identity fields in-place, preserve doc for group history
    //      "delete"    → delete the doc entirely (paginated-delete, same as Phase 1)
    //      "retain"    → skip entirely
    //    Fields confirmed from firestore_service.dart:362–365:
    //      senderId, senderName, senderAvatar, message
    //    NOTE: senderPhotoUrl does NOT exist on group_messages — the field is senderAvatar.
    await (async () => {
      const key = "group_messages";
      try {
        const query = db.collection("group_messages").where("senderId", "==", uid);
        if (policy.authored_content === "anonymise") {
          const count = await paginatedAnonymise(
            query,
            {
              senderId:    null,
              senderName:  null,
              senderAvatar: null,
              message:     DELETED_CONTENT_SENTINEL,
            },
            dryRun
          );
          steps[key] = { status: "ok", count };
          functions.logger.info(
            `[deleteUserData] ${key}: anonymised ${count} docs (dryRun=${dryRun})`
          );
        } else if (policy.authored_content === "delete") {
          const count = await paginatedDelete(query, dryRun);
          steps[key] = { status: "ok", count };
          functions.logger.info(
            `[deleteUserData] ${key}: deleted ${count} docs (dryRun=${dryRun})`
          );
        } else {
          // "retain"
          steps[key] = {
            status: "skipped",
            count: 0,
          };
          functions.logger.info(
            `[deleteUserData] ${key}: skipped — policy.authored_content=${policy.authored_content}`
          );
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[key] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
      }
    })();

    // 8. meetups — two passes for legacy field alias
    //    Gated by policy.created_content_meetups (default = "delete").
    //    Pass A: field "createdBy" (spec-aligned) (firebase_auth_service.dart:775)
    //    Pass B: field "organiserId" (legacy alias) (firebase_auth_service.dart:779)
    if (policy.created_content_meetups === "delete") {
      await runStep(
        "meetups_createdBy",
        db.collection("meetups").where("createdBy", "==", uid)
      );
      await runStep(
        "meetups_organiserId",
        db.collection("meetups").where("organiserId", "==", uid)
      );
    } else {
      await runStep("meetups_createdBy",   null, `policy.created_content_meetups=retain`);
      await runStep("meetups_organiserId", null, `policy.created_content_meetups=retain`);
    }

    // 9. marketplace — field "sellerId" (firebase_auth_service.dart:784)
    //    Gated by policy.created_content_marketplace (default = "delete").
    if (policy.created_content_marketplace === "delete") {
      await runStep(
        "marketplace",
        db.collection("marketplace").where("sellerId", "==", uid)
      );
    } else {
      await runStep("marketplace", null, `policy.created_content_marketplace=retain`);
    }

    // 10. events — field "creatorId" (event_service.dart — user-created events)
    //     LAYER-3-EVENTS-RETAIN-1: events collection had NO erasure step.
    //     Field verified: event_service.dart createEvent() path + EventDoc type.
    //     NOTE: the top-level events collection is currently written by the AI
    //     ingestion pipeline (admin SDK); EventDoc interface has no creatorId field.
    //     This step is a defensive sweep — returns 0 rows if no user-created events
    //     exist in Firestore, which is safe. If a direct client write path is added
    //     in future, this step will catch it automatically.
    //     Community content posture: retain doc, anonymise creator identity.
    //     Mirrors authored_content anonymise pattern.
    await (async () => {
      const key = "events";
      try {
        const query = db.collection("events").where("creatorId", "==", uid);
        if (policy.authored_content === "delete") {
          const count = await paginatedDelete(query, dryRun);
          steps[key] = { status: "ok", count };
        } else {
          // anonymise (default) or retain → scrub creator identity either way
          // Fields: creatorId confirmed from event_service.dart; no creatorName/
          // creatorAvatar on EventDoc (AI-ingested events have no creator identity).
          const count = await paginatedAnonymise(
            query,
            { creatorId: null, creatorName: null },
            dryRun
          );
          steps[key] = { status: "ok", count };
        }
        functions.logger.info(
          `[deleteUserData] ${key}: processed ${steps[key].count} docs (dryRun=${dryRun})`
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[key] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
      }
    })();

    // ══════════════════════════════════════════════════════════════════
    // PHASE 2 — SUBCOLLECTION SWEEPS, GROUP MEMBERSHIP, MEMBER ACTIVITY
    //
    // PHASE 2 VERIFICATION LEDGER (read from source — do not change without re-reading):
    //
    //  SUBCOLLECTIONS under users/{uid}/:
    //   saved_messages   → users/{uid}/saved_messages/{auto-id}
    //                      (saved_message_service.dart lines 119–136, 175–184)
    //                      NOTE: saved_threads and saved_events have NO Firestore
    //                      write path — BrowserStorage only. Not swept.
    //   notifPrefs       → users/{uid}/notifPrefs/settings  (single doc, point-delete)
    //                      (user_privacy_prefs_service.dart lines 82–87, 147–152)
    //   deadlines        → users/{uid}/deadlines/{auto-id}  (firebase_auth_service.dart:845)
    //   saved_items      → users/{uid}/saved_items/{auto-id} (firebase_auth_service.dart:821)
    //   blocks (forward) → users/{uid}/blocks/{targetUid}   (firebase_auth_service.dart:792)
    //   invitations (recv)→ users/{uid}/invitations/{invId} (invitation_service.dart:232–238)
    //
    //  user_rsvps subcollection:
    //   user_rsvps/{uid}/meetups/{meetupId}  (firestore_service.dart:1346–1354)
    //
    //  collectionGroup sweeps:
    //   blocks reverse   → collectionGroup('blocks').where('targetUid','==',uid)
    //                      field 'targetUid' IS a real document field
    //                      (block_service.dart line 97)
    //   endorsements     → collectionGroup('endorsements').where(documentId,'==',uid)
    //                      doc ID IS the endorser uid — not a field named 'documentId'
    //                      (local_services_service.dart lines 56–57, 604–606)
    //   invitations sent → collectionGroup('invitations').where('invitedById','==',uid)
    //                      field 'invitedById' is a real document field
    //                      (invitation_service.dart line 369: 'invitedById': inviterId)
    //                      GATED by policy.invitations_sent (default=retain)
    //
    //  PHASE 1 CORRECTIONS (found during Phase 2 investigation):
    //   polls (Firestore) → polls/{auto-id}.createdByUid
    //                      (firestore_service.dart line 1402: 'createdByUid': uid)
    //                      MISSED in Phase 1 — added here in Phase 2
    //   partner_analytics → partner_analytics/{uid}  (doc ID IS the uid — point-delete)
    //                      (local_services_service.dart line 721: .doc(ownerUid))
    //                      MISSED in Phase 1 — added here in Phase 2
    //
    //  PHANTOMS (Phase 2 scope):
    //   users/{uid}/saved_threads — BrowserStorage only, zero Firestore writes
    //   users/{uid}/saved_events  — BrowserStorage only, zero Firestore writes
    //   users/{uid}/notifPrefs (collection sweep) — only 1 doc ever ('settings')
    //                              swept as point-delete, not collection scan
    //
    //  groups.memberIds arrayRemove:
    //   Query groups where memberIds arrayContains uid → arrayRemove uid from each.
    //   This is NOT a delete of the group — only membership removal.
    //   Captured group IDs are stored for memberActivity sweep and Phase 4 (Storage).
    //   arrayRemove is idempotent (no-op if uid already absent).
    //
    //  memberActivity:
    //   groups/{gid}/memberActivity/{uid} — point-delete per group captured above
    //   (invitation_service.dart lines 531–543, group_chat_screen.dart line 5865)
    // ══════════════════════════════════════════════════════════════════

    // ── Phase 1 corrections: polls + partner_analytics ─────────────────────
    // (Discovered during Phase 2 source investigation — added here to keep
    //  the Phase 1 result shape backward-compatible.)

    // polls — field "createdByUid" (firestore_service.dart:1402)
    await runStep(
      "polls",
      db.collection("polls").where("createdByUid", "==", uid)
    );

    // partner_analytics — doc ID == uid (point-delete, not a query)
    // Uses a single-doc "query" pattern: get the doc then delete if it exists.
    // paginatedDelete on a doc-ID equality query won't work cleanly here;
    // we do an explicit get + delete so the step reports count 0 or 1.
    await (async () => {
      const key = "partner_analytics";
      try {
        const ref = db.collection("partner_analytics").doc(uid);
        const snap = await ref.get();
        if (snap.exists) {
          if (!dryRun) await ref.delete();
          steps[key] = { status: "ok", count: 1 };
          functions.logger.info(`[deleteUserData] ${key}: deleted 1 doc (dryRun=${dryRun})`);
        } else {
          steps[key] = { status: "ok", count: 0 };
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[key] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
      }
    })();

    // ── Subcollection sweeps (users/{uid}/…) ───────────────────────────────

    // saved_messages (saved_message_service.dart:119–136)
    await runStep(
      "users_saved_messages",
      db.collection("users").doc(uid).collection("saved_messages")
    );

    // notifPrefs/settings — point-delete (user_privacy_prefs_service.dart:82–87)
    // Only one document ever written ('settings'). Delete it directly.
    await (async () => {
      const key = "users_notifPrefs_settings";
      try {
        const ref = db.collection("users").doc(uid).collection("notifPrefs").doc("settings");
        const snap = await ref.get();
        if (snap.exists) {
          if (!dryRun) await ref.delete();
          steps[key] = { status: "ok", count: 1 };
          functions.logger.info(`[deleteUserData] ${key}: deleted 1 doc (dryRun=${dryRun})`);
        } else {
          steps[key] = { status: "ok", count: 0 };
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[key] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
      }
    })();

    // deadlines (firebase_auth_service.dart:845)
    await runStep(
      "users_deadlines",
      db.collection("users").doc(uid).collection("deadlines")
    );

    // saved_items (firebase_auth_service.dart:821)
    await runStep(
      "users_saved_items",
      db.collection("users").doc(uid).collection("saved_items")
    );

    // blocks forward: users/{uid}/blocks/{targetUid} (firebase_auth_service.dart:792)
    await runStep(
      "users_blocks_forward",
      db.collection("users").doc(uid).collection("blocks")
    );

    // invitations received: users/{uid}/invitations/{invId} (invitation_service.dart:232)
    await runStep(
      "users_invitations_received",
      db.collection("users").doc(uid).collection("invitations")
    );

    // user_rsvps: user_rsvps/{uid}/meetups/{meetupId} (firestore_service.dart:1346)
    await runStep(
      "user_rsvps_meetups",
      db.collection("user_rsvps").doc(uid).collection("meetups")
    );

    // ── collectionGroup sweeps ─────────────────────────────────────────────

    // blocks reverse: other users who blocked this uid
    // field 'targetUid' is a real document field (block_service.dart:97)
    await runStep(
      "blocks_reverse",
      db.collectionGroup("blocks").where("targetUid", "==", uid)
    );

    // endorsements: doc ID is the endorser uid, AND field 'uid' == endorser uid
    // (local_services_service.dart:180 — field 'uid' is written on every endorsement doc)
    // NOTE: collectionGroup + FieldPath.documentId() equality requires a FULL document path
    // (odd-segment bare uid is rejected by the SDK). Use the real 'uid' field instead.
    await runStep(
      "endorsements_by_uid",
      db.collectionGroup("endorsements")
        .where("uid", "==", uid)
    );

    // invitations sent: gated by policy.invitations_sent switch (default=retain)
    // field 'invitedById' is a real document field (invitation_service.dart:369)
    if (policy.invitations_sent === "delete") {
      await runStep(
        "invitations_sent",
        db.collectionGroup("invitations").where("invitedById", "==", uid)
      );
    } else {
      await runStep(
        "invitations_sent",
        null,
        `policy.invitations_sent=${policy.invitations_sent} — retained by default`
      );
    }

    // ERASURE-GAP-1 — residual collections not covered in Phase 1/2
    //
    // offers (buyer): marketplace/{listingId}/offers — field 'buyerId'
    //   (firestore_service.dart:1012–1030 — buyerId written on every offer)
    await runStep(
      "offers_buyer",
      db.collectionGroup("offers").where("buyerId", "==", uid)
    );

    // offers (seller): same sub-collection — field 'sellerId'
    //   (firestore_service.dart:1112 — sellerId queried, field confirmed real)
    await runStep(
      "offers_seller",
      db.collectionGroup("offers").where("sellerId", "==", uid)
    );

    // upvotes: community_wisdom/{articleId}/upvotes/{uid}
    //   field 'uid' added (ERASURE-GAP-1); doc ID == uid but bare-uid equality
    //   queries are unreliable on subcollection collectionGroups in the Admin SDK.
    //   Historical upvotes (pre-ERASURE-GAP-1) without the 'uid' field will
    //   be missed — known gap, documented as accepted cost.
    //   (ai_knowledge_flywheel_service.dart:643–665)
    await runStep(
      "upvotes_by_uid",
      db.collectionGroup("upvotes").where("uid", "==", uid)
    );

    // gdpr_exports: top-level audit log of data-export requests
    //   field 'userId' (profile_screen.dart:4669)
    //   NOTE: gdpr_erasure_jobs is the erasure audit log — that MUST NOT be
    //   deleted (preserved above). gdpr_exports is the user-triggered export
    //   log; legitimate to purge on account deletion.
    await runStep(
      "gdpr_exports",
      db.collection("gdpr_exports").where("userId", "==", uid)
    );

    // ── user_consents — INTENTIONAL RETENTION (LAYER-15-CONSENT-AUDIT-1) ──
    // user_consents/{uid} is NOT swept here.  It is the durable proof that
    // the user gave lawful basis for data processing (GDPR Art. 6(a)).
    // Deleting it would destroy the evidence that processing was consented to —
    // a compliance risk larger than the residual privacy risk of retaining it.
    // The record contains only consent metadata (dataProcessing bool, marketing
    // bool, policyVersion string, timestamps) — no PII beyond the uid link.
    // This is consistent with the gdpr_erasure_jobs HARD-LOCK posture (Layer 3).
    // If re-anonymisation is ever required (e.g. legal advice changes posture),
    // scrub userId from the doc rather than deleting the event fact + timestamps.

    // capturedConvIds: populated during conversations step, reused by Phase 4 Storage
    // (DM media enumerate-filter). Declared here so Phase 4 block can read it.
    const capturedConvIds: string[] = [];

    // ── groups.memberIds arrayRemove + capture group list ──────────────────
    //
    // This is NOT a delete of the group document.
    // It removes uid from the memberIds array only.
    // Captured group IDs are used immediately for memberActivity sweep
    // and stored in the step result for Phase 4 (group Storage enumeration).
    // arrayRemove is idempotent — safe to re-run.
    const capturedGroupIds: string[] = [];
    await (async () => {
      const key = "groups_membership_remove";
      try {
        // Paginate over groups this user belongs to (arrayContains query).
        // No cursor pagination needed here — arrayContains queries can't use
        // startAfter on documentId in the same pass. Instead we use limit
        // loops with the last doc as cursor on the group id field.
        // In practice group membership is bounded (< a few hundred groups),
        // so a single 500-limit fetch is safe. We still loop defensively.
        let totalUpdated = 0;
        let lastDoc: admin.firestore.QueryDocumentSnapshot | null = null;

        // eslint-disable-next-line no-constant-condition
        while (true) {
          let q = db.collection("groups")
            .where("memberIds", "array-contains", uid)
            .limit(500);
          if (lastDoc) q = q.startAfter(lastDoc);

          const snap = await q.get();
          if (snap.empty) break;

          // Collect group IDs for downstream steps
          for (const doc of snap.docs) {
            capturedGroupIds.push(doc.id);
          }

          if (!dryRun) {
            // Batch arrayRemove
            const batch = db.batch();
            for (const doc of snap.docs) {
              batch.update(doc.ref, {
                memberIds: admin.firestore.FieldValue.arrayRemove(uid),
                memberCount: admin.firestore.FieldValue.increment(-1),
              });
            }
            await batch.commit();
          }

          totalUpdated += snap.docs.length;
          if (snap.docs.length < 500) break;
          lastDoc = snap.docs[snap.docs.length - 1];
        }

        steps[key] = {
          status: "ok",
          count: totalUpdated,
          // Pass the captured group IDs downstream via the error field (repurposed as info)
          // — they are NOT an error, just additional data. Alternatively stored on result.
          // We store them separately on the result object below.
        };
        functions.logger.info(
          `[deleteUserData] ${key}: removed from ${totalUpdated} groups, capturedGroupIds=${JSON.stringify(capturedGroupIds)} (dryRun=${dryRun})`
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[key] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
      }
    })();

    // ── memberActivity sweep (one point-delete per captured group) ─────────
    //
    // groups/{gid}/memberActivity/{uid} — the doc ID is the uid.
    // (invitation_service.dart:531–543)
    // One delete per group; batched in groups of 499 for Firestore batch limit.
    await (async () => {
      const key = "member_activity";
      if (capturedGroupIds.length === 0) {
        steps[key] = { status: "ok", count: 0 };
        return;
      }
      try {
        let deleted = 0;
        // Process in batches of 499 (Firestore batch limit)
        for (let i = 0; i < capturedGroupIds.length; i += 499) {
          const chunk = capturedGroupIds.slice(i, i + 499);
          if (dryRun) {
            // In dryRun mode, check existence to report an accurate count
            const existenceChecks = await Promise.all(
              chunk.map(gid =>
                db.collection("groups").doc(gid).collection("memberActivity").doc(uid).get()
              )
            );
            deleted += existenceChecks.filter(s => s.exists).length;
          } else {
            const batch = db.batch();
            for (const gid of chunk) {
              const ref = db.collection("groups").doc(gid).collection("memberActivity").doc(uid);
              batch.delete(ref);
            }
            await batch.commit();
            deleted += chunk.length; // count attempted; idempotent if doc absent
          }
        }
        steps[key] = { status: "ok", count: deleted };
        functions.logger.info(`[deleteUserData] ${key}: swept ${deleted} memberActivity docs (dryRun=${dryRun})`);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[key] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
      }
    })();

    // ══════════════════════════════════════════════════════════════════
    // PHASE 3 — ANONYMISE OPERATIONS
    //
    // PHASE 3 VERIFICATION LEDGER (read from source — do not change without re-reading):
    //
    //  conversations/{conversationId}
    //    participants: string[]          (realtime_dm_service.dart:120)
    //    participantNames: {uid: name}   (realtime_dm_service.dart:121)
    //    participantAvatars: {uid: url}  (realtime_dm_service.dart:122)
    //    → query: where('participants', arrayContains, uid)
    //    → per-conversation: arrayRemove(uid) from participants
    //    → if participants becomes empty: delete conversation doc
    //    → if participants still has members: keep conversation doc
    //
    //  conversations/{conversationId}/messages/{messageId}
    //    senderId: String                (realtime_dm_service.dart:213)
    //    senderName: String              (realtime_dm_service.dart:214)
    //    senderAvatar: String            (realtime_dm_service.dart:215)
    //    message: String                 (realtime_dm_service.dart:216)
    //    → anonymise only messages where senderId == uid (per-doc update())
    //    → DO NOT TOUCH messages where senderId != uid
    //
    //  group_messages/{id}
    //    senderId: String                (firestore_service.dart:362)
    //    senderName: String              (firestore_service.dart:363)
    //    senderAvatar: String            (firestore_service.dart:364)  ← NOT senderPhotoUrl
    //    message: String                 (firestore_service.dart:365)
    //    → handled above in Phase 1/3 group_messages step (switch-gated)
    //
    //  PHANTOM NOTE: dm_service.dart is entirely BrowserStorage — not Firestore.
    //  Only realtime_dm_service.dart writes conversations to Firestore.
    // ══════════════════════════════════════════════════════════════════

    // ── Conversations: anonymise leaver's messages + arrayRemove from participants ──
    //
    // INVARIANT: conversations are NEVER switch-gated. Individual DM messages are
    // ALWAYS anonymised (senderId/senderName/senderAvatar→null, message→sentinel),
    // NEVER hard-deleted, regardless of authored_content. A DM is two-party:
    // hard-deleting one side's messages leaves the OTHER participant a broken,
    // contextless thread. Do not "fix" this to respect authored_content — it is intentional.
    //
    // For each conversation the leaver is in:
    //   1. Query conversations/{id}/messages where senderId == uid
    //      → per-doc update(): senderId=null, senderName=null, senderAvatar=null,
    //        message=DELETED_CONTENT_SENTINEL
    //   2. arrayRemove(uid) from conversations/{id}.participants
    //   3. Re-read the doc. If participants is now empty → delete the conversation.
    //      If one or more participants remain → keep it (other user's history survives).
    //
    // The leaver's messages are scrubbed but their identity cannot be inferred from
    // the remaining doc. The other participant's messages are NOT touched.
    //
    // Two sub-steps reported:
    //   conversations_messages  — count of message docs anonymised
    //   conversations_docs      — count of conversation docs deleted (empty) or
    //                             updated (non-empty; counted as 1 per conversation)
    await (async () => {
      const msgKey  = "conversations_messages";
      const convKey = "conversations_docs";
      try {
        let totalMsgsAnonymised = 0;
        let totalConvsDeleted   = 0;
        let totalConvsUpdated   = 0;

        // Page through conversations where uid is a participant
        // IDs are captured here and reused by Phase 4 Storage (DM media enumeration).
        let convCursor: admin.firestore.DocumentSnapshot | null = null;
        // eslint-disable-next-line no-constant-condition
        while (true) {
          let convQuery = db
            .collection("conversations")
            .where("participants", "array-contains", uid)
            .orderBy(admin.firestore.FieldPath.documentId())
            .limit(PAGE_SIZE);
          if (convCursor !== null) convQuery = convQuery.startAfter(convCursor);

          const convSnap = await convQuery.get();
          if (convSnap.empty) break;

          for (const convDoc of convSnap.docs) {
            capturedConvIds.push(convDoc.id);
            // ── Step A: anonymise this user's messages in the subcollection ──
            const msgsAnonymised = await paginatedAnonymise(
              convDoc.ref.collection("messages").where("senderId", "==", uid),
              {
                senderId:    null,
                senderName:  null,
                senderAvatar: null,
                message:     DELETED_CONTENT_SENTINEL,
              },
              dryRun
            );
            totalMsgsAnonymised += msgsAnonymised;

            // ── Step B: remove uid from participants ──
            if (!dryRun) {
              await convDoc.ref.update({
                participants: admin.firestore.FieldValue.arrayRemove(uid),
              });

              // Re-read after the update to check remaining participants
              const refreshed = await convDoc.ref.get();
              const remaining = (refreshed.data()?.["participants"] as string[] | undefined) ?? [];

              if (remaining.length === 0) {
                // Nobody left — delete the conversation doc
                await convDoc.ref.delete();
                totalConvsDeleted++;
              } else {
                // One or more participants remain — conversation survives
                totalConvsUpdated++;
              }
            } else {
              // In dryRun mode: check what WOULD happen without writing
              const currentParticipants =
                (convDoc.data()["participants"] as string[] | undefined) ?? [];
              const wouldRemain = currentParticipants.filter((p) => p !== uid);
              if (wouldRemain.length === 0) {
                totalConvsDeleted++;
              } else {
                totalConvsUpdated++;
              }
            }
          }

          if (convSnap.docs.length < PAGE_SIZE) break;
          convCursor = convSnap.docs[convSnap.docs.length - 1];
        }

        steps[msgKey]  = { status: "ok", count: totalMsgsAnonymised };
        steps[convKey] = { status: "ok", count: totalConvsDeleted + totalConvsUpdated };
        functions.logger.info(
          `[deleteUserData] conversations: anonymised ${totalMsgsAnonymised} messages, ` +
          `deleted ${totalConvsDeleted} conv docs (empty), ` +
          `retained ${totalConvsUpdated} conv docs (dryRun=${dryRun})`
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        steps[msgKey]  = { status: "error", count: 0, error: msg };
        steps[convKey] = { status: "error", count: 0, error: msg };
        functions.logger.error(`[deleteUserData] conversations: ERROR — ${msg}`);
      }
    })();

    // ══════════════════════════════════════════════════════════════════
    // PHASE 4 — STORAGE ENUMERATION + DELETION  (spec B.8)
    // ══════════════════════════════════════════════════════════════════
    //
    // Three sub-steps, each a separate steps[] key:
    //
    //   storage_prefix_delete  — uid IS the path prefix; direct deleteFiles().
    //     profile_photos/{uid}/
    //     marketplace_images/{uid}/
    //
    //   storage_dm_media       — uid is in the FILENAME ({uid}_{ts}.{ext}).
    //     dm_images/{convId}/         ← conversationId from Phase 3 capture
    //     dm_documents/{convId}/
    //     voice_notes/dm/{convId}/
    //     For each convId: list, filter filename.startsWith(uid + '_'), delete.
    //     Filter is a precise startsWith on the bare filename segment so that
    //     another user whose uid happens to contain uid as a substring is
    //     NEVER matched (contains-match is NOT used).
    //
    //   storage_group_media    — same enumerate-filter pattern, group-keyed.
    //     group_images/{groupId}/     ← groupId from Phase 2 capture
    //     group_documents/{groupId}/
    //     voice_notes/group/{groupId}/
    //     Filter: filename.startsWith(uid + '_') OR filename.startsWith('thread_' + uid + '_')
    //     (thread-reply files are named thread_{uid}_{ts}).
    //
    // dryRun: list + count, never delete.
    // 404 on individual delete → treat as success (already gone).
    //
    // Bucket: STORAGE_BUCKET constant (huddl-connect.firebasestorage.app).
    //         In emulator: FIREBASE_STORAGE_EMULATOR_HOST routes automatically.

    await (async () => {
      // ── Helper: delete a single file, treating 404 as success ────────────
      async function deleteFileIdempotent(
        bucket: Bucket,
        filePath: string
      ): Promise<void> {
        try {
          await bucket.file(filePath).delete();
        } catch (err) {
          const code = (err as { code?: number | string }).code;
          if (code === 404 || code === "404") return; // already gone — success
          throw err;
        }
      }

      // ── Helper: list + filter + delete files under a single prefix ────────
      // Returns the count of files touched (deleted in live run, listed in dryRun).
      // Filter function receives the bare filename (last path segment only).
      async function enumerateFilterDelete(
        bucket: Bucket,
        prefix: string,
        filterFn: (filename: string) => boolean,
        dry: boolean
      ): Promise<number> {
        const [files] = await bucket.getFiles({ prefix });
        const matched = files.filter((f) => {
          const filename = f.name.split("/").pop() ?? "";
          return filterFn(filename);
        });
        if (!dry) {
          for (const f of matched) {
            await deleteFileIdempotent(bucket, f.name);
          }
        }
        return matched.length;
      }

      const bucket = admin.storage().bucket(STORAGE_BUCKET);

      // ── Sub-step 1: simple prefix-delete ──────────────────────────────────
      await (async () => {
        const key = "storage_prefix_delete";
        try {
          let count = 0;
          const prefixes = [
            `profile_photos/${uid}/`,
            `marketplace_images/${uid}/`,
          ];
          // List-first pattern: gives accurate count in both live and dryRun modes,
          // and uses the idempotent per-file delete (404-safe) rather than the bulk
          // deleteFiles() which swallows the count.
          for (const prefix of prefixes) {
            const [files] = await bucket.getFiles({ prefix });
            count += files.length;
            if (!dryRun) {
              for (const f of files) {
                await deleteFileIdempotent(bucket, f.name);
              }
            }
          }
          steps[key] = { status: "ok", count };
          functions.logger.info(
            `[deleteUserData] ${key}: touched ${count} files (dryRun=${dryRun})`
          );
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          steps[key] = { status: "error", count: 0, error: msg };
          functions.logger.error(`[deleteUserData] storage_prefix_delete: ERROR — ${msg}`);
        }
      })();

      // ── Sub-step 2: DM media enumerate-filter-delete ──────────────────────
      await (async () => {
        const key = "storage_dm_media";
        try {
          let count = 0;
          const dmPrefixTemplates = [
            (cid: string) => `dm_images/${cid}/`,
            (cid: string) => `dm_documents/${cid}/`,
            (cid: string) => `voice_notes/dm/${cid}/`,
          ];
          // Filename filter: startsWith(uid + '_') — precise segment match.
          // A uid that is a substring of another uid will NOT match because
          // the character after uid must be '_', not another uid character.
          const dmFilter = (filename: string) => filename.startsWith(uid + "_");

          for (const convId of capturedConvIds) {
            for (const prefixFn of dmPrefixTemplates) {
              const n = await enumerateFilterDelete(
                bucket, prefixFn(convId), dmFilter, dryRun
              );
              count += n;
            }
          }
          steps[key] = { status: "ok", count };
          functions.logger.info(
            `[deleteUserData] ${key}: touched ${count} files across ` +
            `${capturedConvIds.length} conversations (dryRun=${dryRun})`
          );
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          steps[key] = { status: "error", count: 0, error: msg };
          functions.logger.error(`[deleteUserData] storage_dm_media: ERROR — ${msg}`);
        }
      })();

      // ── Sub-step 3: group media enumerate-filter-delete ───────────────────
      await (async () => {
        const key = "storage_group_media";
        try {
          let count = 0;
          const groupPrefixTemplates = [
            (gid: string) => `group_images/${gid}/`,
            (gid: string) => `group_documents/${gid}/`,
            (gid: string) => `voice_notes/group/${gid}/`,
          ];
          // Two filename patterns for group media:
          //   {uid}_{ts}.{ext}          — direct post/upload
          //   thread_{uid}_{ts}.{ext}   — thread reply (audit confirmed naming)
          const groupFilter = (filename: string) =>
            filename.startsWith(uid + "_") ||
            filename.startsWith("thread_" + uid + "_");

          for (const groupId of capturedGroupIds) {
            for (const prefixFn of groupPrefixTemplates) {
              const n = await enumerateFilterDelete(
                bucket, prefixFn(groupId), groupFilter, dryRun
              );
              count += n;
            }
          }
          steps[key] = { status: "ok", count };
          functions.logger.info(
            `[deleteUserData] ${key}: touched ${count} files across ` +
            `${capturedGroupIds.length} groups (dryRun=${dryRun})`
          );
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          steps[key] = { status: "error", count: 0, error: msg };
          functions.logger.error(`[deleteUserData] storage_group_media: ERROR — ${msg}`);
        }
      })();
    })();

    // ══════════════════════════════════════════════════════════════════
    // RESULT ASSEMBLY
    // ══════════════════════════════════════════════════════════════════

    const completedAt = new Date().toISOString();
    const anyError = Object.values(steps).some((s) => s.status === "error");

    const result: DeleteUserDataResult & { capturedGroupIds: string[]; capturedConvIds: string[] } = {
      success: !anyError,
      uid,
      dryRun,
      startedAt,
      completedAt,
      policy,
      steps,
      capturedGroupIds,  // Phase 4 Storage: group media enumeration
      capturedConvIds,   // Phase 4 Storage: DM media enumeration
      ...(anyError ? { error: "One or more steps failed — see steps for details.", retryable: true } : {}),
    };

    functions.logger.info(
      `[deleteUserData] COMPLETE uid=${uid} success=${result.success} dryRun=${dryRun} ` +
      `completedAt=${completedAt}`,
      { steps }
    );

    // ══════════════════════════════════════════════════════════════════
    // PIECE 1b — FINALIZE GDPR ERASURE JOB RECORD (GDPR-STRIPE-1-R1)
    //
    // Derive final status:
    //   • any step status === 'error'  → 'partial'  (reconciler can retry)
    //   • all steps ok / skipped       → 'complete'
    //
    // Writing the entire steps object once at the end is correct — the
    // steps accumulator holds the final state of all phases at this point.
    //
    // dryRun: skip the write (matching Piece 1a behaviour).
    // Fail-soft: a finalize failure must not mask the primary result.
    // ══════════════════════════════════════════════════════════════════
    const erasureJobStatus = anyError ? "partial" : "complete";

    if (!dryRun) {
      try {
        await jobRef.set(
          {
            status:        erasureJobStatus,
            steps,
            completedAt:   admin.firestore.FieldValue.serverTimestamp(),
            lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            success:       result.success,
          },
          { merge: true }
        );
        functions.logger.info(
          `[deleteUserData] PIECE-1b: erasure job finalized gdpr_erasure_jobs/${uid} status=${erasureJobStatus}`
        );
      } catch (err) {
        // Non-fatal: erasure has completed; only the audit record update failed.
        functions.logger.error(
          `[deleteUserData] PIECE-1b: failed to finalize erasure job for uid=${uid}: ${String(err)}`
        );
      }
    } else {
      functions.logger.info(
        `[deleteUserData] PIECE-1b: dryRun — would finalize gdpr_erasure_jobs/${uid} status=${erasureJobStatus}`
      );
    }

    return result;
  });

// ===========================================================================
// CLOUD FUNCTION 11: verifyBusiness
// ===========================================================================
// HTTPS callable — server-side UK business verification.
//
// Security model (SUB-3 / LSS-1 / ANN-1):
//   The client sends ONLY the raw identifier (companyNumber OR vatNumber) +
//   method. ALL trust fields (businessVerified, verifiedBusinessName,
//   verificationData, verificationMethod) are derived exclusively from the
//   authoritative API response and written via Admin SDK (bypasses F-09
//   Firestore rules that block client writes of those fields).
//   verifiedBusinessName is ALWAYS taken from the API — never from client
//   input — preventing impersonation of any registered business name.
//
// Supported methods:
//   companies_house — Companies House REST API (HTTP Basic, key from config)
//   hmrc_vat        — HMRC check-vat-number API (public, no key required)
//
// Uses Node 20 global fetch (no extra import needed).
// Config key: functions.config().companies_house.key
// Set with: firebase functions:config:set companies_house.key="YOUR_API_KEY"
// ===========================================================================

export const verifyBusiness = functions
  .region("europe-west2")
  .runWith({ secrets: ["COMPANIES_HOUSE_API_KEY"] })
  .https.onCall(async (data, context) => {
    // ── 1. Auth required ────────────────────────────────────────────────────
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = context.auth.uid;
    const method = (data as Record<string, unknown>)?.method;

    // ── Companies House path ─────────────────────────────────────────────────
    if (method === "companies_house") {
      const rawNum = String((data as Record<string, unknown>)?.companyNumber || "");
      const companyNumber = rawNum.trim().toUpperCase();

      // UK company numbers: 8 chars — 8 digits or 2 letters + 6 digits.
      if (!/^[A-Z0-9]{8}$/.test(companyNumber)) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Invalid company number format."
        );
      }

      // Companies House REST API: HTTP Basic auth — API key as username, blank password.
      const chKey = process.env.COMPANIES_HOUSE_API_KEY;
      if (!chKey) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Verification is not configured."
        );
      }
      const basic = Buffer.from(chKey + ":").toString("base64");

      let chResp: Response;
      try {
        chResp = await fetch(
          `https://api.company-information.service.gov.uk/company/${companyNumber}`,
          { headers: { Authorization: `Basic ${basic}` } }
        );
      } catch {
        throw new functions.https.HttpsError(
          "unavailable",
          "Verification service unreachable."
        );
      }

      if (chResp.status === 404) {
        throw new functions.https.HttpsError("not-found", "Company not found.");
      }
      if (chResp.status === 429) {
        throw new functions.https.HttpsError(
          "resource-exhausted",
          "Too many attempts. Try again shortly."
        );
      }
      if (!chResp.ok) {
        throw new functions.https.HttpsError(
          "unavailable",
          "Verification service unavailable."
        );
      }

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const company: any = await chResp.json();
      if (company.company_status !== "active") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Company is not active."
        );
      }

      // verifiedBusinessName is ALWAYS from the API response — never client input.
      const verifiedName: string = company.company_name;

      await admin.firestore().collection("users").doc(uid).set(
        {
          businessVerified:    true,
          verificationMethod:  "companies_house",
          verifiedBusinessName: verifiedName,
          verificationData: {
            companyNumber,
            companyStatus: company.company_status,
            verifiedAt:    admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );

      functions.logger.info(
        `[verifyBusiness] companies_house verified uid=${uid} company=${companyNumber} name="${verifiedName}"`
      );
      return { verified: true, businessName: verifiedName };
    }

    // ── HMRC VAT path ────────────────────────────────────────────────────────
    if (method === "hmrc_vat") {
      const rawVat = String((data as Record<string, unknown>)?.vatNumber || "");
      // Normalise: strip whitespace and optional GB prefix.
      const vatNumber = rawVat.replace(/\s/g, "").replace(/^GB/i, "").trim();

      // UK VAT numbers: 9 digits, or 12 digits (branch traders).
      if (!/^\d{9}(\d{3})?$/.test(vatNumber)) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Invalid VAT number format."
        );
      }

      // HMRC check-vat-number API is public — no API key required.
      let vatResp: Response;
      try {
        vatResp = await fetch(
          `https://api.service.hmrc.gov.uk/organisations/vat/check-vat-number/lookup/${vatNumber}`,
          { headers: { Accept: "application/vnd.hmrc.2.0+json" } }
        );
      } catch {
        throw new functions.https.HttpsError(
          "unavailable",
          "Verification service unreachable."
        );
      }

      if (vatResp.status === 404) {
        throw new functions.https.HttpsError("not-found", "VAT number not found.");
      }
      if (!vatResp.ok) {
        throw new functions.https.HttpsError(
          "unavailable",
          "Verification service unavailable."
        );
      }

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const vat: any = await vatResp.json();
      // HMRC returns { target: { name, vatNumber, address } } on success.
      const verifiedName: string | undefined = vat?.target?.name;
      if (!verifiedName) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "VAT record incomplete."
        );
      }

      await admin.firestore().collection("users").doc(uid).set(
        {
          businessVerified:    true,
          verificationMethod:  "hmrc_vat",
          verifiedBusinessName: verifiedName,
          verificationData: {
            vatNumber,
            verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );

      functions.logger.info(
        `[verifyBusiness] hmrc_vat verified uid=${uid} vat=${vatNumber} name="${verifiedName}"`
      );
      return { verified: true, businessName: verifiedName };
    }

    // ── Sole trader self-declaration ──────────────────────────────────────
    // A UTR cannot be verified against any public registry. This path therefore
    // does NOT set businessVerified — it records a self-declaration only. The
    // resulting state must render as a DISTINCT "self-declared" badge in the UI,
    // never as the verified badge. (Audit: SUB-3 sole-trader path.)
    if (method === "sole_trader_declaration") {
      const legalName   = String((data as Record<string, unknown>)?.legalName   || "").trim();
      const tradingName = String((data as Record<string, unknown>)?.tradingName  || "").trim();
      const rawUtr      = String((data as Record<string, unknown>)?.utrNumber    || "");
      const utrNumber   = rawUtr.replace(/\s/g, "").trim();

      if (!legalName || !tradingName) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Legal and trading name are required."
        );
      }
      // UK UTR is 10 digits. Validate format only — we cannot verify it is real.
      if (!/^\d{10}$/.test(utrNumber)) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Invalid UTR format (expected 10 digits)."
        );
      }

      // Hash the UTR server-side with sha256 — NEVER store the raw value,
      // and do NOT use String.hashCode (non-cryptographic, collidable).
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const crypto = require("crypto") as typeof import("crypto");
      const utrHash = crypto.createHash("sha256").update(utrNumber).digest("hex");

      // businessVerified is explicitly set false — a sole-trader declaration
      // must NEVER sit on top of a prior businessVerified: true from another source.
      await admin.firestore().collection("users").doc(uid).set(
        {
          businessVerified:     false,          // explicit downgrade / no-upgrade
          businessSelfDeclared: true,
          verificationMethod:   "sole_trader_declaration",
          verifiedBusinessName: tradingName,    // displayed under the self-declared badge only
          verificationData: {
            entityType:            "sole_trader",
            legalName,
            utrHash,
            declarationSignedAt:   admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );

      functions.logger.info(
        `[verifyBusiness] sole_trader_declaration recorded uid=${uid} trading="${tradingName}"`
      );
      return { verified: false, selfDeclared: true, businessName: tradingName };
    }

    // ── Unknown method ───────────────────────────────────────────────────────
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Unknown verification method."
    );
  });

// ═══════════════════════════════════════════════════════════════════════════
// 12. moderateAndSendDM
//
// MSG-SAFETY-1 / MSG-SAFETY-4  —  Stage 1: DEPLOY BUT DORMANT.
// No existing function, client code, or firestore.rules is modified.
// The client continues to write DMs directly via RealtimeDMService until
// Stage 2 routes calls here.
//
// PURPOSE: replicate RealtimeDMService.sendMessage's full write behaviour
// server-side, with TEXT moderation BEFORE the write, so a blocked message
// is never persisted to Firestore.
//
// TEXT MODERATION (two layers, defence-in-depth):
//   Layer 1 — WORDLIST (fail-CLOSED, no network dependency)
//             Synchronous; if hit, message is dropped immediately.
//   Layer 2 — AI NUANCE via Gemini flash (fail-OPEN-but-FLAG)
//             If Gemini is unavailable, message is written AND flagged
//             in moderationReview/{auto-id} for human review.
//
// IMAGE MODERATION: intentional future seam. All non-text types pass through
// to the write step without AI moderation. A future Stage adds
// Vision API classification on imageUrl before the write.
//
// WRITE: Admin SDK only — senderId is FORCED from context.auth.uid,
// senderName/Avatar resolved server-side from users/{uid}.
// participantAvatars use dot-notation field paths (set+merge) matching the
// client implementation exactly.
//
// RETURNS:
//   { status: 'sent',    messageId }  — message written
//   { status: 'flagged', messageId }  — written but queued for review
//   { status: 'blocked', reason: 'wordlist'|'ai' }  — not written
// ═══════════════════════════════════════════════════════════════════════════

// ── Module-level constant: hard-blocked terms (fail-CLOSED wordlist) ────────
// Match the client _normalise function: lowercase + strip * @ ! 0 $ chars.
// Terms are checked as substrings of the normalised message.
// Ordered from most-specific to avoid partial false-positives where possible.
const AI_HARD_BLOCKLIST: string[] = [
  "cunt", "pussy", "dick", "cock", "twat", "wank",
  "motherfucker", "motherfucking",
  "nigger", "nigga", "faggot", "fag", "chink", "spic", "kike", "wetback", "tranny",
  "retard", "paedo", "pedo", "groomer", "nonce",
  "kill yourself", "kys", "kill urself",
  "i will kill", "i will hurt", "i know where you live",
];

/** Normalise a message string to match the client _normalise function. */
function _normaliseDmText(text: string): string {
  return text
    .toLowerCase()
    .replace(/[*@!0$]/g, "");
}

/**
 * Call Gemini flash with a safety-classification system prompt.
 * Returns 'SAFE', 'UNSAFE', or null on error/timeout.
 */
async function _geminiClassifyDmText(text: string): Promise<"SAFE" | "UNSAFE" | null> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    functions.logger.warn("[moderateAndSendDM] GEMINI_API_KEY missing — skipping AI layer");
    return null;
  }

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}` +
    `:generateContent?key=${apiKey}`;

  const body = JSON.stringify({
    systemInstruction: {
      parts: [{
        text:
          "You are a content safety classifier for a UK parenting community app. " +
          "Classify the following user message as SAFE or UNSAFE. " +
          "UNSAFE means the message contains ANY of: threats of violence or self-harm " +
          "directed at a specific person; child sexual abuse material (CSAM) or grooming language; " +
          "severe, targeted harassment or hate speech targeting a person's identity; " +
          "explicit sexual content. " +
          "SAFE means everything else, including strong opinions, mild rudeness, complaints, " +
          "or adult discussion. " +
          "Respond with ONLY the single word SAFE or UNSAFE.",
      }],
    },
    contents: [{ role: "user", parts: [{ text }] }],
    generationConfig: { temperature: 0, maxOutputTokens: 8 },
  });

  return new Promise<"SAFE" | "UNSAFE" | null>((resolve) => {
    const timeout = setTimeout(() => {
      functions.logger.warn("[moderateAndSendDM] Gemini classify timeout — fail-open");
      resolve(null);
    }, 6000);

    const req = https.request(
      url,
      { method: "POST", headers: { "Content-Type": "application/json" } },
      (res) => {
        let raw = "";
        res.on("data", (chunk: Buffer) => { raw += chunk.toString(); });
        res.on("end", () => {
          clearTimeout(timeout);
          try {
            const parsed = JSON.parse(raw) as {
              candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
            };
            const verdict = (
              parsed?.candidates?.[0]?.content?.parts?.[0]?.text ?? ""
            ).trim().toUpperCase();
            if (verdict === "UNSAFE") { resolve("UNSAFE"); }
            else if (verdict === "SAFE") { resolve("SAFE"); }
            else {
              functions.logger.warn(
                `[moderateAndSendDM] Gemini returned unexpected verdict: "${verdict}" — fail-open`
              );
              resolve(null);
            }
          } catch {
            functions.logger.warn("[moderateAndSendDM] Gemini parse error — fail-open");
            resolve(null);
          }
        });
      }
    );
    req.on("error", (err: Error) => {
      clearTimeout(timeout);
      functions.logger.warn(`[moderateAndSendDM] Gemini request error: ${err.message} — fail-open`);
      resolve(null);
    });
    req.write(body);
    req.end();
  });
}

export const moderateAndSendDM = functions
  .region("europe-west2")
  .runWith({
    timeoutSeconds: 30,
    memory: "256MB",
    secrets: ["GEMINI_API_KEY"],
  })
  .https.onCall(async (data: Record<string, unknown>, context) => {

    // ── STEP 1: AUTH ────────────────────────────────────────────────────────
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required."
      );
    }
    const uid = context.auth.uid;

    // ── STEP 2: PARTICIPANT CHECK ────────────────────────────────────────────
    // Server-side enforcement — closes senderId spoofing that is possible when
    // the client writes directly. The CF resolves senderName/Avatar from
    // users/{uid} and forces senderId = uid (never from client payload).
    const conversationId = String(data.conversationId ?? "").trim();
    if (!conversationId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "conversationId is required."
      );
    }

    const convSnap = await db.collection("conversations").doc(conversationId).get();
    if (!convSnap.exists) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a participant."
      );
    }
    const convData = convSnap.data() ?? {};
    const participants: string[] = Array.isArray(convData["participants"])
      ? (convData["participants"] as string[])
      : [];
    if (!participants.includes(uid)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a participant."
      );
    }

    // ── STEP 2b: BLOCK CHECK (BLOCK-ENFORCE-1) ──────────────────────────────
    // If the recipient has blocked the sender, do NOT write the message at all.
    // (The post-write onDmMessageCreated trigger only suppressed the push; the
    //  message still landed. This stops it server-side, before the write.)
    const recipientId = participants.find((p) => p !== uid);
    if (recipientId) {
      const blockedSnap = await db
        .collection("users").doc(recipientId)
        .collection("blocks").doc(uid).get();
      if (blockedSnap.exists) {
        functions.logger.info(`[moderateAndSendDM] BLOCKED by recipient-block uid=${uid} recipient=${recipientId}`);
        return { status: "blocked", reason: "blocked_by_recipient" };
      }
    }

    // ── STEP 3: MODERATE (text only) ────────────────────────────────────────
    const type = String(data.type ?? "text");
    const rawText = String(data.message ?? "");
    const isTextMessage = type === "text";
    // Hoisted to function scope so the flag-doc path (after the write) can
    // read it without needing to re-enter the moderation block.
    let geminiVerdict: "SAFE" | "UNSAFE" | null = null;

    if (isTextMessage && rawText.trim().length > 0) {
      // 3a. WORDLIST — fail-CLOSED, synchronous, no network.
      const normalised = _normaliseDmText(rawText);
      for (const term of AI_HARD_BLOCKLIST) {
        if (normalised.includes(term)) {
          functions.logger.info(
            `[moderateAndSendDM] BLOCKED by wordlist uid=${uid} term="${term}"`
          );
          return { status: "blocked", reason: "wordlist" };
        }
      }

      // 3b. AI NUANCE — fail-OPEN-but-FLAG.
      // On UNSAFE: drop silently (return blocked, nothing written).
      // On null (error/timeout): write message + write moderationReview flag doc.
      geminiVerdict = await _geminiClassifyDmText(rawText);

      if (geminiVerdict === "UNSAFE") {
        functions.logger.info(
          `[moderateAndSendDM] BLOCKED by AI uid=${uid}`
        );
        return { status: "blocked", reason: "ai" };
      }
      // geminiVerdict === "SAFE"  → proceed to write, no flag.
      // geminiVerdict === null    → proceed to write, flag doc written after.
    }
    // Non-text types (image, voice_note, document, location, contact,
    // meetupInvite, etc.) pass through to the write step without AI moderation.
    // Image moderation via Vision API is a documented future seam (Stage N).

    // ── STEP 4: WRITE (Admin SDK) ────────────────────────────────────────────
    // Resolve senderName + senderAvatar from users/{uid} — never from client.
    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data() ?? {};
    const senderName: string = String(userData["name"] ?? "Unknown");
    const senderAvatar: string = String(userData["photoUrl"] ?? "");

    // Typed message fields — all optional, undefined if not supplied by caller.
    const messageText   = String(data.message ?? "");
    const replyToText   = data.replyToText   != null ? String(data.replyToText)   : null;
    const replyToSender = data.replyToSender != null ? String(data.replyToSender) : null;
    const imageUrl      = data.imageUrl      != null ? String(data.imageUrl)      : null;
    const audioUrl      = data.audioUrl      != null ? String(data.audioUrl)      : null;
    const audioDuration = data.audioDuration != null ? Number(data.audioDuration) : null;
    const documentName  = data.documentName  != null ? String(data.documentName)  : null;
    const documentSize  = data.documentSize  != null ? Number(data.documentSize)  : null;
    const latitude      = data.latitude      != null ? Number(data.latitude)      : null;
    const longitude     = data.longitude     != null ? Number(data.longitude)     : null;
    const locationLabel = data.locationLabel != null ? String(data.locationLabel) : null;
    const contactName   = data.contactName   != null ? String(data.contactName)   : null;
    const contactPhone  = data.contactPhone  != null ? String(data.contactPhone)  : null;
    const meetupData    = (data.meetupData   != null && typeof data.meetupData  === "object") ? (data.meetupData  as Record<string, unknown>) : null;
    const groupData     = (data.groupData    != null && typeof data.groupData   === "object") ? (data.groupData   as Record<string, unknown>) : null;
    const itemData      = (data.itemData     != null && typeof data.itemData    === "object") ? (data.itemData    as Record<string, unknown>) : null;
    const eventData     = (data.eventData    != null && typeof data.eventData   === "object") ? (data.eventData   as Record<string, unknown>) : null;
    const clientTempId  = data.clientTempId != null ? String(data.clientTempId) : null;

    // Create message document reference (auto-id).
    const msgRef = db
      .collection("conversations")
      .doc(conversationId)
      .collection("messages")
      .doc();
    const messageId = msgRef.id;

    // Build message payload — matches RealtimeDMService.sendMessage field list exactly.
    // senderId is FORCED from context.auth.uid — client-supplied value is ignored.
    const msgPayload: Record<string, unknown> = {
      id:            messageId,
      senderId:      uid,            // FORCED from auth — never from data
      senderName,                    // resolved from users/{uid} server-side
      senderAvatar,                  // resolved from users/{uid} server-side
      message:       messageText,
      timestamp:     admin.firestore.FieldValue.serverTimestamp(),
      type,
      status:        "sent",
      reactions:     {},
      replyToText,
      replyToSender,
      imageUrl,
      audioUrl,
      audioDuration,
      documentName,
      documentSize,
      latitude,
      longitude,
      locationLabel,
      contactName,
      contactPhone,
      meetupData,
      groupData,
      itemData,
      eventData,
      clientTempId,
    };

    await msgRef.set(msgPayload);

    // Build displayText for conversation summary — mirrors RealtimeDMService exactly.
    let displayText = messageText;
    if (groupData != null) {
      displayText = `\u{1F465} Group: ${String(groupData["name"] ?? "Group")}`;
    } else if (itemData != null) {
      displayText = `\u{1F4E6} Item: ${String(itemData["title"] ?? "Item")}`;
    } else if (meetupData != null) {
      displayText = `\u{1F4C5} Meetup: ${String(meetupData["title"] ?? "Meetup")}`;
    } else if (eventData != null) {
      displayText = `\u{1F4C5} Event: ${String(eventData["title"] ?? "Event")}`;
    } else if (type === "image") {
      displayText = "\u{1F4F7} Photo";
    } else if (type === "voice_note") {
      displayText = "\u{1F3A4} Voice message";
    } else if (type === "document") {
      displayText = `\u{1F4C4} ${documentName ?? "Document"}`;
    } else if (type === "location") {
      displayText = "\u{1F4CD} Location";
    }

    // Build unread increment — every participant except the sender gets +1.
    const summaryUpdate: Record<string, unknown> = {
      lastMessage:    displayText,
      lastSenderId:   uid,
      lastSenderName: senderName,
      lastMessageAt:  admin.firestore.FieldValue.serverTimestamp(),
      // Dot-notation field path so set+merge doesn't clobber other participants.
      [`participantAvatars.${uid}`]: senderAvatar,
    };
    for (const p of participants) {
      if (p !== uid) {
        summaryUpdate[`unreadCount.${p}`] = admin.firestore.FieldValue.increment(1);
      }
    }

    // set+merge so this doesn't throw if the conversation doc was deleted
    // between the participant check and here (edge case race).
    await db.collection("conversations").doc(conversationId).set(
      summaryUpdate,
      { merge: true }
    );

    functions.logger.info(
      `[moderateAndSendDM] sent conversationId=${conversationId} messageId=${messageId} uid=${uid} type=${type}`
    );

    // If the AI layer returned null (error/timeout), write a flag doc for
    // human review AFTER the message has been committed successfully.
    // Done post-write so a flag-doc failure never blocks delivery.
    if (isTextMessage && rawText.trim().length > 0 && geminiVerdict === null) {
      try {
        await db.collection("moderationReview").add({
          conversationId,
          senderId:  uid,
          messageId,
          text:      rawText,
          reason:    "ai_unavailable",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        functions.logger.info(
          `[moderateAndSendDM] flagged messageId=${messageId} uid=${uid} reason=ai_unavailable`
        );
      } catch (flagErr) {
        // Non-fatal: message is already written. Log and continue.
        functions.logger.error(
          `[moderateAndSendDM] flag doc write failed: ${String(flagErr)}`
        );
      }
      return { status: "flagged", messageId };
    }

    return { status: "sent", messageId };
  });

// ═══════════════════════════════════════════════════════════════════════════════
// 13. onDmMessageCreated
//
// MSG-SAFETY Stage 2a-ii — Firestore onCreate trigger.
//
// Fires whenever a new message document is created under
//   conversations/{conversationId}/messages/{messageId}
//
// PURPOSE: dispatch DM push notifications server-side, off the authoritative
// message write, so the notification cannot be spoofed or suppressed by the
// client. Replaces the client-side BackendApiService.notifyDmMessage() call
// removed from RealtimeDMService.sendMessage in Stage 2a-ii.
//
// FLOW:
//   1. Extract senderId from message doc.
//   2. Read conversations/{conversationId} to find the recipient.
//   3. Server-derive senderName from users/{senderId}.
//   4. Build messagePreview using the same displayText branch logic as
//      moderateAndSendDM / RealtimeDMService (must stay in sync).
//   5. POST to Railway /api/messages/notify-dm with X-Service-Auth header.
//      The Railway endpoint's isService path trusts the body because senderName
//      and recipientId are derived from authoritative Firestore data here, not
//      from a client payload.
//
// RELIABILITY: everything is wrapped in try/catch; errors are logged but never
// thrown. A failed notification must NOT cause the trigger to crash-retry —
// that would spam Cloud Logging and potentially duplicate notifications on
// retry if the notify call eventually succeeds.
//
// TIMEOUT: 6-second deadline on the Railway call. On timeout/error: log and
// return gracefully (fail-soft).
// ═══════════════════════════════════════════════════════════════════════════════

/** POST to the Railway notify-dm endpoint using the https module (no fetch in Node 18 CF runtime). */
function _postRailwayNotifyDm(payload: {
  conversationId: string;
  recipientId: string;
  senderName: string;
  messagePreview: string;
  secret: string;
}): Promise<void> {
  return new Promise((resolve) => {
    const body = JSON.stringify({
      conversationId:  payload.conversationId,
      recipientId:     payload.recipientId,
      senderName:      payload.senderName,
      messagePreview:  payload.messagePreview,
    });

    const options: import("https").RequestOptions = {
      hostname: "api.huddlapp.co.uk",
      path:     "/api/messages/notify-dm",
      method:   "POST",
      headers:  {
        "Content-Type":    "application/json",
        "Content-Length":  Buffer.byteLength(body),
        "X-Service-Auth":  payload.secret,
      },
    };

    const timeout = setTimeout(() => {
      functions.logger.warn("[onDmMessageCreated] Railway notify-dm timeout — skipping notification");
      req.destroy();
      resolve();
    }, 6000);

    const req = https.request(options, (res) => {
      // Drain the response so the socket is released; we don't need the body.
      res.resume();
      res.on("end", () => {
        clearTimeout(timeout);
        if (res.statusCode && res.statusCode >= 400) {
          functions.logger.warn(
            `[onDmMessageCreated] Railway notify-dm returned HTTP ${res.statusCode}`
          );
        }
        resolve();
      });
    });

    req.on("error", (err: Error) => {
      clearTimeout(timeout);
      functions.logger.warn(`[onDmMessageCreated] Railway notify-dm request error: ${err.message}`);
      resolve(); // fail-soft
    });

    req.write(body);
    req.end();
  });
}

export const onDmMessageCreated = functions
  .region("europe-west2")
  .runWith({
    timeoutSeconds: 30,
    memory: "256MB",
    secrets: ["INTERNAL_SERVICE_SECRET"],
  })
  .firestore.document("conversations/{conversationId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    try {
      const msg             = snap.data();
      const conversationId  = context.params.conversationId;
      const messageId       = context.params.messageId;

      // ── 1. Sender ──────────────────────────────────────────────────────────
      const senderId = String(msg.senderId ?? "").trim();
      if (!senderId) {
        functions.logger.warn(
          `[onDmMessageCreated] messageId=${messageId} has no senderId — skipping`
        );
        return;
      }

      // ── 2. Participants ────────────────────────────────────────────────────
      const convSnap = await db.collection("conversations").doc(conversationId).get();
      if (!convSnap.exists) {
        functions.logger.warn(
          `[onDmMessageCreated] conversation ${conversationId} not found — skipping`
        );
        return;
      }
      const participants: string[] = Array.isArray(convSnap.data()?.["participants"])
        ? (convSnap.data()!["participants"] as string[])
        : [];
      if (participants.length === 0) {
        functions.logger.warn(
          `[onDmMessageCreated] conversation ${conversationId} has no participants — skipping`
        );
        return;
      }

      // ── 3. Recipient ───────────────────────────────────────────────────────
      const recipientId = participants.find((p) => p !== senderId);
      if (!recipientId) {
        functions.logger.info(
          `[onDmMessageCreated] no recipient found for senderId=${senderId} — skipping (self-conversation?)`
        );
        return;
      }

      // ── 4. Block check — suppress push if recipient has blocked the sender ──
      const blk = await db.collection('users').doc(recipientId).collection('blocks').doc(senderId).get();
      if (blk.exists) return; // recipient blocked sender — skip push

      // ── 5. Derive senderName server-side ───────────────────────────────────
      const senderSnap = await db.collection("users").doc(senderId).get();
      const senderName: string = (senderSnap.exists && senderSnap.data()?.["name"])
        ? String(senderSnap.data()!["name"])
        : "Someone";

      // ── 5. Build messagePreview (same displayText logic as moderateAndSendDM) ──
      const type         = String(msg.type ?? "text");
      const rawMessage   = String(msg.message ?? "");
      const documentName = msg.documentName != null ? String(msg.documentName) : null;
      const groupData    = (msg.groupData   != null && typeof msg.groupData  === "object")
        ? (msg.groupData  as Record<string, unknown>) : null;
      const itemData     = (msg.itemData    != null && typeof msg.itemData   === "object")
        ? (msg.itemData   as Record<string, unknown>) : null;
      const meetupData   = (msg.meetupData  != null && typeof msg.meetupData === "object")
        ? (msg.meetupData as Record<string, unknown>) : null;
      const eventData    = (msg.eventData   != null && typeof msg.eventData  === "object")
        ? (msg.eventData  as Record<string, unknown>) : null;

      let messagePreview: string;
      if (groupData != null) {
        messagePreview = `\u{1F465} Group: ${String(groupData["name"] ?? "Group")}`;
      } else if (itemData != null) {
        messagePreview = `\u{1F4E6} Item: ${String(itemData["title"] ?? "Item")}`;
      } else if (meetupData != null) {
        messagePreview = `\u{1F4C5} Meetup: ${String(meetupData["title"] ?? "Meetup")}`;
      } else if (eventData != null) {
        messagePreview = `\u{1F4C5} Event: ${String(eventData["title"] ?? "Event")}`;
      } else if (type === "image") {
        messagePreview = "\u{1F4F7} Photo";
      } else if (type === "voice_note") {
        messagePreview = "\u{1F3A4} Voice message";
      } else if (type === "document") {
        messagePreview = `\u{1F4C4} ${documentName ?? "Document"}`;
      } else if (type === "location") {
        messagePreview = "\u{1F4CD} Location";
      } else {
        messagePreview = rawMessage;
      }
      messagePreview = messagePreview.substring(0, 100);

      // ── 6. POST to Railway ─────────────────────────────────────────────────
      const secret = process.env.INTERNAL_SERVICE_SECRET;
      if (!secret) {
        functions.logger.warn(
          "[onDmMessageCreated] INTERNAL_SERVICE_SECRET not set — notification skipped"
        );
        return;
      }

      await _postRailwayNotifyDm({
        conversationId,
        recipientId,
        senderName,
        messagePreview,
        secret,
      });

      functions.logger.info(
        `[onDmMessageCreated] notified recipientId=${recipientId} for messageId=${messageId} type=${type}`
      );

    } catch (err) {
      // Never throw from a Firestore trigger — retries could spam notifications.
      functions.logger.error(
        `[onDmMessageCreated] unhandled error for messageId=${context.params.messageId}: ${String(err)}`
      );
    }
  });

// ═══════════════════════════════════════════════════════════════════════════════
// 14. moderateAndSendGroupMessage
//
// GROUP-MSG-SAFETY Stage 1 — HTTPS callable; server-side moderated send-gate
// for group messages.
//
// DEPLOY BUT DORMANT — nothing calls this function yet. It will be wired to
// the Flutter group chat screen in a subsequent stage once tested.
//
// REUSES (does NOT duplicate) the shared primitives defined above:
//   • AI_HARD_BLOCKLIST    — wordlist for fail-CLOSED synchronous filter
//   • _normaliseDmText()   — text normaliser for the wordlist pass
//   • _geminiClassifyDmText() — Gemini AI nuance classifier (fail-open)
//
// FLOW:
//   1. AUTH        — unauthenticated callers are rejected.
//   2. MEMBERSHIP  — reads groups/{groupId}.memberIds; rejects non-members.
//   3. MODERATE    — text-only; wordlist (fail-CLOSED) then Gemini (fail-OPEN-but-FLAG).
//   4. WRITE       — Admin SDK add-then-stamp-id to group_messages/{auto};
//                    doc shape mirrors sendGroupMessage exactly (incl. conditional fields).
//                    Group summary updated (lastMessage/lastSenderName/lastMessageTime).
//                    Notifications intentionally omitted — handled by a later stage.
//
// RETURNS: { status: 'sent'|'blocked'|'flagged', messageId?: string, reason?: string }
// ═══════════════════════════════════════════════════════════════════════════════

export const moderateAndSendGroupMessage = functions
  .region("europe-west2")
  .runWith({
    timeoutSeconds: 30,
    memory: "256MB",
    secrets: ["GEMINI_API_KEY"],
  })
  .https.onCall(async (data: Record<string, unknown>, context) => {

    // ── STEP 1: AUTH ────────────────────────────────────────────────────────
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required."
      );
    }
    const uid = context.auth.uid;

    // ── STEP 2: MEMBERSHIP CHECK ────────────────────────────────────────────
    // Server-side enforcement — closes senderId spoofing + non-member posting.
    // senderName and senderAvatar are resolved from users/{uid} server-side;
    // the client-supplied senderId in the payload is never trusted.
    const groupId = String(data.groupId ?? "").trim();
    if (!groupId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "groupId is required."
      );
    }

    const groupSnap = await db.collection("groups").doc(groupId).get();
    if (!groupSnap.exists) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Group not found."
      );
    }
    const groupData = groupSnap.data() ?? {};
    const memberIds: string[] = Array.isArray(groupData["memberIds"])
      ? (groupData["memberIds"] as string[])
      : [];
    if (!memberIds.includes(uid)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not a group member."
      );
    }

    // ── STEP 3: MODERATE (text only) ────────────────────────────────────────
    const type         = String(data.type ?? "text");
    const rawText      = String(data.message ?? "");
    const isTextMsg    = type === "text";
    // Hoisted to function scope so the flag-doc path (post-write) can read it.
    let geminiVerdict: "SAFE" | "UNSAFE" | null = null;

    if (isTextMsg && rawText.trim().length > 0) {
      // 3a. WORDLIST — fail-CLOSED, synchronous, no network.
      //     Reuses the SHARED normaliser and blocklist — not duplicated.
      const normalised = _normaliseDmText(rawText);
      for (const term of AI_HARD_BLOCKLIST) {
        if (normalised.includes(term)) {
          functions.logger.info(
            `[moderateAndSendGroupMessage] BLOCKED by wordlist uid=${uid} groupId=${groupId} term="${term}"`
          );
          return { status: "blocked", reason: "wordlist" };
        }
      }

      // 3b. AI NUANCE — fail-OPEN-but-FLAG.
      //     Reuses the SHARED Gemini classifier — not duplicated.
      // On UNSAFE: drop silently (return blocked, nothing written).
      // On null (error/timeout): write message + write moderationReview flag doc.
      geminiVerdict = await _geminiClassifyDmText(rawText);

      if (geminiVerdict === "UNSAFE") {
        functions.logger.info(
          `[moderateAndSendGroupMessage] BLOCKED by AI uid=${uid} groupId=${groupId}`
        );
        return { status: "blocked", reason: "ai" };
      }
      // geminiVerdict === "SAFE"  → proceed to write, no flag.
      // geminiVerdict === null    → proceed to write, flag doc written after.
    }
    // Non-text types (image, voice_note, document, location, contact, poll, etc.)
    // pass through without AI moderation (image Vision API is a future seam).

    // ── STEP 4: WRITE (Admin SDK) ────────────────────────────────────────────
    // Resolve senderName + senderAvatar from users/{uid} server-side.
    // NEVER trust client-supplied senderId, senderName, or senderAvatar.
    const userSnap   = await db.collection("users").doc(uid).get();
    const userData   = userSnap.data() ?? {};
    const senderName: string = String(userData["name"] ?? "").trim() || "Anonymous";
    const senderAvatar: string = String(userData["photoUrl"] ?? "");

    // Extract all optional message fields — typed, null-coalesced.
    const messageText     = String(data.message ?? "");
    const replyToText     = data.replyToText     != null ? String(data.replyToText)     : null;
    const replyToSender   = data.replyToSender   != null ? String(data.replyToSender)   : null;
    const audioUrl        = data.audioUrl        != null ? String(data.audioUrl)        : null;
    const audioDuration   = data.audioDuration   != null ? Number(data.audioDuration)   : null;
    const imageUrl        = data.imageUrl        != null ? String(data.imageUrl)        : null;
    const latitude        = data.latitude        != null ? Number(data.latitude)        : null;
    const longitude       = data.longitude       != null ? Number(data.longitude)       : null;
    const locationLabel   = data.locationLabel   != null ? String(data.locationLabel)   : null;
    const liveUntil       = data.liveUntil       != null ? String(data.liveUntil)       : null;
    const contactName     = data.contactName     != null ? String(data.contactName)     : null;
    const contactPhone    = data.contactPhone    != null ? String(data.contactPhone)    : null;
    const documentUrl     = data.documentUrl     != null ? String(data.documentUrl)     : null;
    const documentName    = data.documentName    != null ? String(data.documentName)    : null;
    const documentSize    = data.documentSize    != null ? Number(data.documentSize)    : null;
    const documentMimeType = data.documentMimeType != null ? String(data.documentMimeType) : null;
    const pollQuestion    = data.pollQuestion    != null ? String(data.pollQuestion)    : null;
    const pollOptions     = (Array.isArray(data.pollOptions)) ? (data.pollOptions as string[]) : null;
    const pollAllowMultiple = data.pollAllowMultiple != null ? Boolean(data.pollAllowMultiple) : null;
    const pollExpiresAt   = data.pollExpiresAt   != null ? String(data.pollExpiresAt)   : null;
    const pollIsCalendarMode = data.pollIsCalendarMode != null ? Boolean(data.pollIsCalendarMode) : null;
    const pollFirestoreId = data.pollFirestoreId != null ? String(data.pollFirestoreId) : null;
    const clientTempId    = data.clientTempId    != null ? String(data.clientTempId)    : null;

    // Build message payload — mirrors sendGroupMessage field list exactly.
    // senderId FORCED from context.auth.uid — client value is ignored.
    // Always-present fields match sendGroupMessage's unconditional assignments.
    // Conditional fields use the same `if (x != null)` omit-when-null pattern.
    const msgData: Record<string, unknown> = {
      groupId,
      senderId:     uid,           // FORCED from auth — never from data
      senderName,                  // resolved from users/{uid} server-side
      senderAvatar,                // resolved from users/{uid} server-side
      message:      messageText,
      timestamp:    admin.firestore.FieldValue.serverTimestamp(),
      reactions:    {},
      pinned:       false,
      isSystem:     false,
      isMeetupCard: false,
      attachments:  [],
      replyToText,
      replyToSender,
      meetupData:   null,
      type,
      audioUrl,
      audioDuration,
      liveExpired:  false,
      clientTempId,
      // Conditional fields — omitted (not set to null) when not provided,
      // matching the `if (x != null)` pattern in sendGroupMessage exactly.
      ...(imageUrl        != null && { imageUrl }),
      ...(latitude        != null && { latitude }),
      ...(longitude       != null && { longitude }),
      ...(locationLabel   != null && { locationLabel }),
      ...(liveUntil       != null && { liveUntil }),
      ...(contactName     != null && { contactName }),
      ...(contactPhone    != null && { contactPhone }),
      ...(documentUrl     != null && { documentUrl }),
      ...(documentName    != null && { documentName }),
      ...(documentSize    != null && { documentSize }),
      ...(documentMimeType != null && { documentMimeType }),
      ...(pollQuestion    != null && { pollQuestion }),
      ...(pollOptions     != null && { pollOptions }),
      ...(pollAllowMultiple != null && { pollAllowMultiple }),
      ...(pollExpiresAt   != null && { pollExpiresAt }),
      ...(pollIsCalendarMode != null && { pollIsCalendarMode }),
      ...(pollFirestoreId != null && { pollFirestoreId }),
    };

    // add-then-stamp-id — mirrors the sendGroupMessage pattern exactly.
    const ref = await db.collection("group_messages").add(msgData);
    await ref.update({ id: ref.id });
    const messageId = ref.id;

    // Update group summary — mirrors sendGroupMessage exactly.
    await db.collection("groups").doc(groupId).update({
      lastMessage:     messageText,
      lastSenderName:  senderName,
      lastMessageTime: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Notifications intentionally omitted at Stage 1 (handled by a later stage).

    functions.logger.info(
      `[moderateAndSendGroupMessage] sent groupId=${groupId} messageId=${messageId} uid=${uid} type=${type}`
    );

    // If the AI layer returned null (error/timeout), write a flag doc for
    // human review AFTER the message has been committed successfully.
    // Done post-write so a flag-doc failure never blocks delivery.
    if (isTextMsg && rawText.trim().length > 0 && geminiVerdict === null) {
      try {
        await db.collection("moderationReview").add({
          groupId,
          senderId:  uid,
          messageId,
          text:      rawText,
          reason:    "ai_unavailable",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        functions.logger.info(
          `[moderateAndSendGroupMessage] flagged messageId=${messageId} uid=${uid} reason=ai_unavailable`
        );
      } catch (flagErr) {
        // Non-fatal: message is already written. Log and continue.
        functions.logger.error(
          `[moderateAndSendGroupMessage] flag doc write failed: ${String(flagErr)}`
        );
      }
      return { status: "flagged", messageId };
    }

    return { status: "sent", messageId };
  });

// ===========================================================================
// CLOUD FUNCTION 20: reconcileGdprErasures  (GDPR-STRIPE-1-R1)
// ===========================================================================
// Scheduled daily at 03:00 UTC, europe-west2 (REGION-RESIDENCY-1 consistent).
//
// Purpose: retry failed Stripe anonymization steps from GDPR erasure runs that
// completed with status='pending' or 'partial'.  The Firestore sweep phases
// are idempotent (paginatedDelete on already-deleted docs = 0 rows) but
// re-running them is unnecessary; the ONLY externally-dependent step that
// meaningfully benefits from a retry is Stripe anonymization.
//
// Flow:
//   1. Query gdpr_erasure_jobs for status='pending' OR status='partial',
//      requestedAt older than 1 hour (give in-flight runs breathing room).
//      Two separate snapshot queries are merged in memory (avoids any
//      Firestore 'in' array-size constraints and is cheaper on index reads).
//   2. For each job: check steps.stripe_anonymize — if missing or 'error',
//      POST to Railway /api/gdpr/anonymize-stripe (idempotent via Piece 2).
//   3. On success: update steps.stripe_anonymize='done', recompute status.
//      On failure: increment retryCount, leave status 'partial'.
//   4. retryCount >= 10 → mark status='failed_permanent', log loudly for
//      manual review.  Never retry a failed_permanent job.
//
// Idempotency: jobs already at 'complete' or 'failed_permanent' are excluded
// by the WHERE clause.  The Stripe anonymize endpoint is idempotent via
// Piece 2 (customers.retrieve guard).  Multiple reconciler runs are safe.
// ===========================================================================

export const reconcileGdprErasures = functions
  .region("europe-west2")
  .runWith({
    timeoutSeconds: 540,
    memory: "512MB",
    secrets: ["INTERNAL_SERVICE_SECRET"],
  })
  .pubsub.schedule("0 3 * * *")
  .timeZone("UTC")
  .onRun(async () => {
    functions.logger.info("[reconcileGdprErasures] START");

    const secret = process.env.INTERNAL_SERVICE_SECRET;
    if (!secret) {
      functions.logger.error(
        "[reconcileGdprErasures] INTERNAL_SERVICE_SECRET not set — aborting reconciler"
      );
      return;
    }

    // ── 1. Collect jobs that need reconciliation ──────────────────────────
    // Age gate: requestedAt < now - 1 hour.  Gives in-flight deleteUserData
    // calls time to complete before we treat them as stale.
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);

    let jobs: admin.firestore.QueryDocumentSnapshot[] = [];
    try {
      const [pendingSnap, partialSnap] = await Promise.all([
        db
          .collection("gdpr_erasure_jobs")
          .where("status", "==", "pending")
          .where("requestedAt", "<", oneHourAgo)
          .get(),
        db
          .collection("gdpr_erasure_jobs")
          .where("status", "==", "partial")
          .where("requestedAt", "<", oneHourAgo)
          .get(),
      ]);
      jobs = [...pendingSnap.docs, ...partialSnap.docs];
    } catch (err) {
      functions.logger.error(
        `[reconcileGdprErasures] Firestore query failed: ${String(err)}`
      );
      return;
    }

    functions.logger.info(
      `[reconcileGdprErasures] found ${jobs.length} job(s) to reconcile`
    );

    if (jobs.length === 0) return;

    // ── 2. Helper: POST to Railway anonymize-stripe endpoint ──────────────
    // Mirrors railwayStripeAnonymize in deleteUserData.
    // Uses the Node built-in https module (no new dependencies).
    const postAnonymizeStripe = (
      userId: string
    ): Promise<{ ok: boolean; body?: unknown; error?: string }> =>
      new Promise((resolve) => {
        const bodyStr = JSON.stringify({ userId });

        const options: import("https").RequestOptions = {
          hostname: "api.huddlapp.co.uk",
          path:     "/api/gdpr/anonymize-stripe",
          method:   "POST",
          headers:  {
            "Content-Type":   "application/json",
            "Content-Length": Buffer.byteLength(bodyStr),
            "X-Service-Auth": secret,
          },
        };

        const timer = setTimeout(() => {
          req.destroy();
          resolve({ ok: false, error: "timeout after 15 s" });
        }, 15_000);

        const req = https.request(options, (res) => {
          const chunks: Buffer[] = [];
          res.on("data", (c: Buffer) => chunks.push(c));
          res.on("end", () => {
            clearTimeout(timer);
            const raw = Buffer.concat(chunks).toString("utf8");
            if (res.statusCode && res.statusCode >= 400) {
              resolve({ ok: false, error: `HTTP ${res.statusCode}: ${raw.substring(0, 200)}` });
            } else {
              try {
                resolve({ ok: true, body: JSON.parse(raw) });
              } catch {
                resolve({ ok: true, body: raw });
              }
            }
          });
        });

        req.on("error", (err: Error) => {
          clearTimeout(timer);
          resolve({ ok: false, error: err.message });
        });

        req.write(bodyStr);
        req.end();
      });

    // ── 3. Process each job ────────────────────────────────────────────────
    for (const doc of jobs) {
      const jobData = doc.data() as {
        uid: string;
        stripeCustomerId: string | null;
        status: string;
        steps: { [key: string]: { status: string; [k: string]: unknown } };
        retryCount?: number;
      };

      const { uid: jobUid, stripeCustomerId, steps } = jobData;
      const retryCount =
        typeof jobData.retryCount === "number" ? jobData.retryCount : 0;

      functions.logger.info(
        `[reconcileGdprErasures] processing uid=${jobUid} status=${jobData.status} retryCount=${retryCount}`
      );

      // ── 3a. Retry cap ───────────────────────────────────────────────────
      if (retryCount >= 10) {
        functions.logger.error(
          `[reconcileGdprErasures] uid=${jobUid} retryCount=${retryCount} >= 10 — ` +
          `marking failed_permanent. MANUAL REVIEW REQUIRED.`
        );
        try {
          await doc.ref.set(
            {
              status:        "failed_permanent",
              lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        } catch (err) {
          functions.logger.error(
            `[reconcileGdprErasures] failed to mark failed_permanent for uid=${jobUid}: ${String(err)}`
          );
        }
        continue;
      }

      // ── 3b. Determine if Stripe step needs retrying ─────────────────────
      const stripeStep = steps && steps["stripe_anonymize"];
      const stripeNeedsRetry = !stripeStep || stripeStep.status === "error";

      if (!stripeNeedsRetry) {
        // Stripe step is already ok/skipped.  Recompute overall status and
        // close out the job if it's now clean.
        const anyError = Object.values(steps || {}).some(
          (s) =>
            typeof s === "object" &&
            s !== null &&
            (s as { status: string }).status === "error"
        );
        const newStatus = anyError ? "partial" : "complete";
        if (newStatus !== jobData.status) {
          try {
            await doc.ref.set(
              {
                status:        newStatus,
                lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
            functions.logger.info(
              `[reconcileGdprErasures] uid=${jobUid} status recomputed → ${newStatus} (no Stripe retry needed)`
            );
          } catch (err) {
            functions.logger.error(
              `[reconcileGdprErasures] failed to recompute status for uid=${jobUid}: ${String(err)}`
            );
          }
        }
        continue;
      }

      // ── 3c. No stripeCustomerId — nothing to retry; close as complete ───
      if (!stripeCustomerId) {
        functions.logger.info(
          `[reconcileGdprErasures] uid=${jobUid} has no stripeCustomerId — marking complete.`
        );
        try {
          await doc.ref.set(
            {
              status:        "complete",
              lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
              "steps.stripe_anonymize": {
                status: "skipped",
                count:  0,
                error:  "no_customer",
              },
            },
            { merge: true }
          );
        } catch (err) {
          functions.logger.error(
            `[reconcileGdprErasures] failed to close no-stripe job for uid=${jobUid}: ${String(err)}`
          );
        }
        continue;
      }

      // ── 3d. POST to Railway — retry the Stripe anonymize step ──────────
      let resp: { ok: boolean; body?: unknown; error?: string };
      try {
        resp = await postAnonymizeStripe(jobUid);
      } catch (err) {
        resp = { ok: false, error: String(err) };
      }

      if (resp.ok) {
        // Stripe retry succeeded.  Recompute overall job status.
        const updatedSteps: {
          [key: string]: { status: string; [k: string]: unknown };
        } = {
          ...(steps || {}),
          stripe_anonymize: { status: "ok", count: 1 },
        };
        const anyRemainingError = Object.values(updatedSteps).some(
          (s) =>
            typeof s === "object" &&
            s !== null &&
            (s as { status: string }).status === "error"
        );
        const newStatus = anyRemainingError ? "partial" : "complete";

        functions.logger.info(
          `[reconcileGdprErasures] uid=${jobUid} Stripe retry succeeded — new status=${newStatus}`
        );

        try {
          await doc.ref.set(
            {
              status:        newStatus,
              steps:         updatedSteps,
              retryCount:    retryCount + 1,
              lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        } catch (err) {
          functions.logger.error(
            `[reconcileGdprErasures] failed to persist success for uid=${jobUid}: ${String(err)}`
          );
        }
      } else {
        // Stripe retry failed again.  Increment retryCount, leave 'partial'.
        functions.logger.warn(
          `[reconcileGdprErasures] uid=${jobUid} Stripe retry failed ` +
          `(attempt ${retryCount + 1}): ${resp.error}`
        );

        try {
          await doc.ref.set(
            {
              status:        "partial",
              retryCount:    retryCount + 1,
              lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
              "steps.stripe_anonymize": {
                status:      "error",
                count:       0,
                error:       resp.error ?? "unknown",
                lastAttempt: new Date().toISOString(),
              },
            },
            { merge: true }
          );
        } catch (err) {
          functions.logger.error(
            `[reconcileGdprErasures] failed to persist failure for uid=${jobUid}: ${String(err)}`
          );
        }
      }
    } // end for (jobs)

    functions.logger.info(
      `[reconcileGdprErasures] DONE — processed ${jobs.length} job(s)`
    );
  });

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 15: seedWelcomeSubscription
// ═══════════════════════════════════════════════════════════════════════════
//
// WHY THIS EXISTS
// ───────────────
// The Firestore rule for subscriptions/{userId} is `allow write: if false` —
// entitlements are SERVER-AUTHORITATIVE and must never be written by a client
// SDK.  Previously the onboarding batch in firebase_auth_service.dart wrote
// this doc directly, which triggered PERMISSION_DENIED and broke onboarding.
//
// This CF fires via a Firestore onCreate trigger on users/{userId} (the doc
// written by the onboarding batch), runs as Admin SDK, and seeds the welcome-
// tier subscription doc.  Admin SDK bypasses Firestore security rules entirely.
//
// IDEMPOTENCY GUARANTEE
// ─────────────────────
// Before writing, the function checks whether subscriptions/{userId} already
// exists.  If it does — either because a previous CF invocation succeeded, or
// because the Stripe webhook has already set a paid tier — the write is
// skipped entirely.  This means:
//   • A CF retry cannot duplicate the doc.
//   • A paid user who somehow re-triggers onCreate (e.g. a fluke duplicate
//     user doc write) will NOT have their paid tier downgraded to welcome.
//
// SubscriptionService in Flutter falls back to UserSubscription.welcome() when
// the subscription doc is absent, so the user sees the welcome tier
// immediately while this CF runs asynchronously in the background.
//
// PAYLOAD SHAPE (mirrors the former client-side write exactly)
// ─────────────────────────────────────────────────────────────
// {
//   userId:             <uid>,
//   tier:               'welcome',
//   billingPeriod:      'monthly',
//   status:             'active',
//   platform:           'unknown',   // server cannot determine device platform
//   startDate:          <ISO now>,
//   renewalDate:        null,
//   isActive:           true,
//   isTrial:            false,
//   trialDaysRemaining: 0,
//   isFoundingMember:   false,
//   createdAt:          FieldValue.serverTimestamp(),
//   updatedAt:          FieldValue.serverTimestamp(),
// }
// ═══════════════════════════════════════════════════════════════════════════

export const seedWelcomeSubscription = functions
  .region("europe-west2")                              // REGION-RESIDENCY-1
  .firestore.document("users/{userId}")
  .onCreate(async (_snap, context) => {
    const userId = context.params.userId;

    functions.logger.info(
      `[seedWelcomeSubscription] Triggered for userId=${userId}`
    );

    const subRef = db.collection("subscriptions").doc(userId);

    // ── IDEMPOTENCY CHECK ─────────────────────────────────────────────────
    // Read before write.  If the doc already exists (Stripe already set a real
    // tier, or a previous CF invocation succeeded) do nothing — never clobber.
    const existing = await subRef.get();
    if (existing.exists) {
      functions.logger.info(
        `[seedWelcomeSubscription] subscriptions/${userId} already exists ` +
        `(tier=${existing.data()?.tier ?? "unknown"}) — skipping seed.`
      );
      return;
    }

    // ── SEED WELCOME DOC ──────────────────────────────────────────────────
    const now = new Date().toISOString();
    try {
      await subRef.set({
        userId:             userId,
        tier:               "welcome",
        billingPeriod:      "monthly",
        status:             "active",
        // Server cannot determine the client's device platform.
        // Flutter SubscriptionService reads the doc for tier/status only;
        // 'platform' is informational.  Stripe webhook overwrites on upgrade.
        platform:           "unknown",
        startDate:          now,
        renewalDate:        null,
        isActive:           true,
        isTrial:            false,         // Welcome is free-forever, not a trial
        trialDaysRemaining: 0,             // No time limit on Welcome tier
        isFoundingMember:   false,
        createdAt:          admin.firestore.FieldValue.serverTimestamp(),
        updatedAt:          admin.firestore.FieldValue.serverTimestamp(),
      });

      functions.logger.info(
        `[seedWelcomeSubscription] Successfully seeded welcome subscription for userId=${userId}`
      );
    } catch (err) {
      // Log and re-throw so Cloud Functions marks this invocation as failed
      // and Cloud Tasks / the retry policy will attempt again.
      functions.logger.error(
        `[seedWelcomeSubscription] Failed to seed subscription for userId=${userId}: ${String(err)}`
      );
      throw err;
    }
  });
