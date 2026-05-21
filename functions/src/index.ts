/**
 * Huddl — Cloud Functions
 *
 * Six functions:
 *   1. generateEventRecommendations  — Firestore onCreate on events/{eventId}
 *   2. refreshUserRecommendations    — Firestore onUpdate on users/{userId}
 *   3. recordRecommendationFeedback  — HTTP callable (from Flutter app)
 *   4. cleanupExpiredRecommendations — Scheduled daily at 02:00 UTC
 *   5. huddlCopilotChat              — §2C  Claude API proxy via HTTP callable
 *   6. generateCopilotSuggestions    — §2D  Personalised chip generation
 *
 * Firestore schema used:
 *   events/{eventId}
 *   users/{userId}
 *   userRecommendations/{userId}/events/{eventId}
 *   copilotRateLimits/{userId}          (date + messageCount for 20/day limit)
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as https from "https";

// Gemini API key — same key already used in the Flutter app (GeminiConfig._embeddedKey)
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || "AIzaSyBk2hsDAYRFj1eLM8XZD5aQndLJBiXTZp4";
const GEMINI_MODEL = "gemini-2.0-flash";
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

admin.initializeApp();
const db = admin.firestore();

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
export const recordRecommendationFeedback = functions.https.onCall(
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

  return `You are the Huddl parenting assistant — a warm, knowledgeable, and locally-aware AI for parents in the UK. You know the user's name, their children's ages and names, their location (borough), and their parenting stage.

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

    const url = new URL(GEMINI_URL);
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
async function checkAndIncrementRateLimit(userId: string): Promise<boolean> {
  const today = new Date().toISOString().slice(0, 10); // "YYYY-MM-DD"
  const ref = db.collection("copilotRateLimits").doc(userId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() as { date?: string; messageCount?: number } | undefined;

    if (data?.date === today) {
      if ((data.messageCount ?? 0) >= 20) {
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
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onCall(async (data, context) => {
    // Authentication guard
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required."
      );
    }
    const userId = context.auth.uid;

    // Rate limiting — 20 messages per user per day
    const allowed = await checkAndIncrementRateLimit(userId);
    if (!allowed) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "Daily chat limit reached. Come back tomorrow!"
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

/** Build a human-readable children summary from the user Firestore doc. */
function _buildChildrenSummary(ud: Record<string, unknown>): string {
  const children = ud.children as Array<{ name?: string; birthday?: string }> | undefined;
  if (!children || children.length === 0) {
    // Try legacy fields
    const childName = ud.childName as string | undefined;
    const childBirthday = ud.childBirthday as string | undefined;
    if (childName && childBirthday) {
      const ageMonths = _ageMonthsFromBirthday(childBirthday);
      const ageLabel = ageMonths < 12 ? `${ageMonths} months` : `${Math.floor(ageMonths / 12)} years`;
      return `${childName} (${ageLabel})`;
    }
    return "not specified";
  }
  return children
    .map((c) => {
      if (!c.name) return "child";
      const ageMonths = _ageMonthsFromBirthday(c.birthday ?? "");
      const ageLabel = ageMonths < 12 ? `${ageMonths} months` : `${Math.floor(ageMonths / 12)} years`;
      return `${c.name} (${ageLabel})`;
    })
    .join(", ");
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

export const generateCopilotSuggestions = functions.https.onCall(
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
