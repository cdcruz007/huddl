"use strict";
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
 *
 * Firestore schema used:
 *   events/{eventId}
 *   users/{userId}
 *   userRecommendations/{userId}/events/{eventId}
 *   copilotRateLimits/{userId}          (date + messageCount for 20/day limit)
 */
var _a;
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteUserData = exports.setUserBorough = exports.syncPublicProfile = exports.vertexGenerateContent = exports.generateCopilotSuggestions = exports.huddlCopilotChat = exports.cleanupExpiredRecommendations = exports.recordRecommendationFeedback = exports.refreshUserRecommendations = exports.generateEventRecommendations = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const https = require("https");
const google_auth_library_1 = require("google-auth-library");
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
function getGeminiUrl() {
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
const VERTEX_ENDPOINT = "https://europe-west4-aiplatform.googleapis.com/v1/projects/879152141283" +
    "/locations/europe-west4/models/627673804901974016@1:generateContent";
admin.initializeApp();
const db = admin.firestore();
// ── Storage bucket ────────────────────────────────────────────────────────────
// Bucket name confirmed from lib/config/firebase_options.dart (all platforms).
// In the emulator the admin SDK routes to FIREBASE_STORAGE_EMULATOR_HOST when set.
// GDPR_STORAGE_BUCKET env var allows test overrides (emulator isolation).
const STORAGE_BUCKET = (_a = process.env["GDPR_STORAGE_BUCKET"]) !== null && _a !== void 0 ? _a : "huddl-connect.firebasestorage.app";
// ═══════════════════════════════════════════════════════════════════════════
// SCORING ENGINE (shared by functions 1 & 2)
// ═══════════════════════════════════════════════════════════════════════════
const MIN_SCORE_THRESHOLD = 40; // Only persist records ≥ 40 (spec Section 4C)
/**
 * Compute a match score (0-100) and match reasons for a user-event pair.
 */
function computeMatchScore(user, event) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
    let total = 0;
    const reasons = [];
    // ── 1. Location / Scope match (0-25) ─────────────────────────────────
    const scope = ((_a = event.scope) !== null && _a !== void 0 ? _a : "uk_wide").toLowerCase();
    const eventBorough = ((_b = event.borough) !== null && _b !== void 0 ? _b : "").toLowerCase();
    const userBorough = ((_c = user.borough) !== null && _c !== void 0 ? _c : "").toLowerCase();
    if (event.isOnline) {
        total += 18;
        reasons.push({ icon: "uk_wide", text: "Available online", points: 18 });
    }
    else if (scope === "uk_wide") {
        total += 15;
        reasons.push({ icon: "uk_wide", text: "Available UK-wide", points: 15 });
    }
    else if (scope === "borough" && eventBorough && eventBorough === userBorough) {
        total += 25;
        reasons.push({ icon: "location", text: "In your borough", points: 25 });
    }
    else if (scope === "borough" && eventBorough && eventBorough !== userBorough) {
        total += 5; // still shown, lower rank — NOT excluded
    }
    else if (scope === "local") {
        total += 10; // distance slider handles final inclusion at query time
    }
    // ── 2. Parenting stage match (0-20) ──────────────────────────────────
    const suitableFor = (_d = event.suitableFor) !== null && _d !== void 0 ? _d : [];
    const userStage = ((_e = user.parentingStage) !== null && _e !== void 0 ? _e : "").toLowerCase();
    const userStages = ((_f = user.stagesOfLife) !== null && _f !== void 0 ? _f : []).map((s) => s.toLowerCase());
    if (suitableFor.includes("all_families")) {
        total += 15;
        reasons.push({ icon: "star", text: "Suitable for all families", points: 15 });
    }
    else {
        const stageMap = {
            expecting_parents: ["expecting", "pregnant"],
            new_parents: ["newborn", "new_parent"],
            toddler_families: ["toddler"],
            school_age_families: ["school-age", "school_age"],
        };
        let stageMatch = false;
        for (const [suitKey, stageValues] of Object.entries(stageMap)) {
            if (suitableFor.includes(suitKey)) {
                const matched = stageValues.some((sv) => sv === userStage || userStages.includes(sv));
                if (matched) {
                    total += 20;
                    const label = _stageFriendlyLabel(suitKey);
                    reasons.push({ icon: "star", text: label, points: 20 });
                    stageMatch = true;
                    break;
                }
            }
        }
        if (!stageMatch)
            total += 3; // no stage match — small base score
    }
    // ── 3. Child age match (0-15) ────────────────────────────────────────
    const childAgeMonths = (_g = user.childAgeMonths) !== null && _g !== void 0 ? _g : -1;
    if (childAgeMonths > 0) {
        const ageDisplay = childAgeMonths < 12
            ? `${childAgeMonths}-month-olds`
            : `${Math.floor(childAgeMonths / 12)}-year-olds`;
        // Rough match based on suitableFor categories
        if ((childAgeMonths <= 24 && suitableFor.some((s) => s.includes("new_parent") || s.includes("all"))) ||
            (childAgeMonths > 24 && childAgeMonths <= 60 && suitableFor.some((s) => s.includes("toddler") || s.includes("all"))) ||
            (childAgeMonths > 60 && suitableFor.some((s) => s.includes("school") || s.includes("all")))) {
            total += 15;
            reasons.push({ icon: "age", text: `Perfect for ${ageDisplay}`, points: 15 });
        }
    }
    // ── 4. Category / interest match (0-15) ──────────────────────────────
    const eventCategory = ((_h = event.category) !== null && _h !== void 0 ? _h : "").toLowerCase();
    const userInterests = ((_j = user.interests) !== null && _j !== void 0 ? _j : []).map((i) => i.toLowerCase());
    const likedCategories = ((_k = user.likedCategories) !== null && _k !== void 0 ? _k : []).map((c) => c.toLowerCase());
    const dislikedCategories = ((_l = user.dislikedCategories) !== null && _l !== void 0 ? _l : []).map((c) => c.toLowerCase());
    if (dislikedCategories.includes(eventCategory)) {
        total -= 10; // negative signal from "Not for me" feedback
    }
    else if (likedCategories.includes(eventCategory) || userInterests.includes(eventCategory)) {
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
function computeIsDiscoverSomethingNew(user, event) {
    var _a, _b, _c, _d;
    const joined = [...((_a = user.joinedEvents) !== null && _a !== void 0 ? _a : []), ...((_b = user.joinedMeetups) !== null && _b !== void 0 ? _b : [])];
    if (joined.length < 5)
        return false; // insufficient history
    // In this implementation, joinedEvents/joinedMeetups store event IDs.
    // The category lookup would require fetching each joined event document,
    // which is expensive. Instead we store categories in a denormalized
    // likedCategories array on the user profile (updated by recordRecommendationFeedback).
    // We use that as a proxy for "categories the user has engaged with".
    const engagedCategories = ((_c = user.likedCategories) !== null && _c !== void 0 ? _c : []).map((c) => c.toLowerCase());
    const eventCategory = ((_d = event.category) !== null && _d !== void 0 ? _d : "").toLowerCase();
    if (eventCategory && engagedCategories.length >= 3) {
        return !engagedCategories.includes(eventCategory);
    }
    return false;
}
function _stageFriendlyLabel(suitKey) {
    switch (suitKey) {
        case "expecting_parents": return "Designed for expecting parents";
        case "new_parents": return "Ideal for new parents";
        case "toddler_families": return "Great for toddler families";
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
exports.generateEventRecommendations = functions
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .firestore.document("events/{eventId}")
    .onCreate(async (snap, context) => {
    const eventId = context.params.eventId;
    const event = snap.data();
    functions.logger.info(`[generateEventRecommendations] New event: ${eventId}`);
    // Fetch all active users in batches of 100
    let lastDoc;
    let processedUsers = 0;
    let writtenRecords = 0;
    while (true) {
        let query = db.collection("users").limit(100);
        if (lastDoc) {
            query = query.startAfter(lastDoc);
        }
        const usersSnap = await query.get();
        if (usersSnap.empty)
            break;
        // Process batch
        const writes = [];
        for (const userDoc of usersSnap.docs) {
            const userId = userDoc.id;
            const user = userDoc.data();
            writes.push((async () => {
                try {
                    const { score, reasons } = computeMatchScore(user, event);
                    if (score < MIN_SCORE_THRESHOLD)
                        return; // skip low-relevance
                    const isDiscoverSomethingNew = computeIsDiscoverSomethingNew(user, event);
                    const record = {
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
                }
                catch (err) {
                    functions.logger.error(`[generateEventRecommendations] Error for user ${userId}: ${err}`);
                    // Use Promise.allSettled behaviour — one failure does not abort others
                }
            })());
        }
        // Wait for entire batch to settle before moving to next
        await Promise.allSettled(writes);
        processedUsers += usersSnap.docs.length;
        lastDoc = usersSnap.docs[usersSnap.docs.length - 1];
        if (usersSnap.docs.length < 100)
            break; // last page
    }
    functions.logger.info(`[generateEventRecommendations] Done. Processed: ${processedUsers} users, ` +
        `Written: ${writtenRecords} records for event ${eventId}`);
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
exports.refreshUserRecommendations = functions
    .runWith({ timeoutSeconds: 300, memory: "512MB" })
    .firestore.document("users/{userId}")
    .onUpdate(async (change, context) => {
    var _a, _b;
    const userId = context.params.userId;
    const newUser = change.after.data();
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
    const existingFeedback = {};
    for (const recDoc of existingRecsSnap.docs) {
        const data = recDoc.data();
        existingFeedback[recDoc.id] = {
            feedbackGiven: (_a = data.feedbackGiven) !== null && _a !== void 0 ? _a : null,
            feedbackAt: (_b = data.feedbackAt) !== null && _b !== void 0 ? _b : null,
        };
    }
    // Collect event IDs from future events
    const futureEventIds = new Set(futureEventsSnap.docs.map((d) => d.id));
    // Delete stale records for events not in future set (past events)
    const toDelete = [];
    for (const existId of Object.keys(existingFeedback)) {
        if (!futureEventIds.has(existId)) {
            toDelete.push(db
                .collection("userRecommendations")
                .doc(userId)
                .collection("events")
                .doc(existId)
                .delete());
        }
    }
    await Promise.allSettled(toDelete);
    // Re-score and write
    let rewritten = 0;
    let deleted = 0;
    const writes = [];
    for (const eventDoc of futureEventsSnap.docs) {
        const eventId = eventDoc.id;
        const event = eventDoc.data();
        writes.push((async () => {
            var _a;
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
                const preserved = (_a = existingFeedback[eventId]) !== null && _a !== void 0 ? _a : { feedbackGiven: null, feedbackAt: null };
                const record = {
                    matchScore: score,
                    matchReasons: reasons,
                    isDiscoverSomethingNew,
                    feedbackGiven: preserved.feedbackGiven,
                    feedbackAt: preserved.feedbackAt,
                    generatedAt: admin.firestore.Timestamp.now(),
                };
                await recRef.set(record);
                rewritten++;
            }
            catch (err) {
                functions.logger.error(`[refreshUserRecommendations] Error for event ${eventId}: ${err}`);
            }
        })());
    }
    await Promise.allSettled(writes);
    functions.logger.info(`[refreshUserRecommendations] Done for ${userId}. ` +
        `Re-scored: ${futureEventsSnap.docs.length}, Written: ${rewritten}, Deleted: ${deleted}`);
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
exports.recordRecommendationFeedback = functions.https.onCall(async (data, context) => {
    var _a;
    // Validate authentication
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "This function requires authentication.");
    }
    const userId = context.auth.uid;
    const eventId = data.eventId;
    const feedback = data.feedback;
    if (!eventId || typeof eventId !== "string") {
        throw new functions.https.HttpsError("invalid-argument", "eventId is required and must be a string.");
    }
    if (feedback !== "helpful" && feedback !== "not_for_me") {
        throw new functions.https.HttpsError("invalid-argument", 'feedback must be "helpful" or "not_for_me".');
    }
    functions.logger.info(`[recordRecommendationFeedback] user=${userId} event=${eventId} feedback=${feedback}`);
    // 1. Write feedback to recommendation record
    const recRef = db
        .collection("userRecommendations")
        .doc(userId)
        .collection("events")
        .doc(eventId);
    await recRef.set({
        feedbackGiven: feedback,
        feedbackAt: admin.firestore.Timestamp.now(),
    }, { merge: true } // preserve all other fields
    );
    // 2. Fetch event category for preference signal
    const eventDoc = await db.collection("events").doc(eventId).get();
    if (!eventDoc.exists) {
        functions.logger.warn(`[recordRecommendationFeedback] Event ${eventId} not found — preference signal skipped.`);
        return { success: true };
    }
    const eventData = eventDoc.data();
    const category = (_a = eventData.category) !== null && _a !== void 0 ? _a : "";
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
    }
    else {
        await userRef.update({
            dislikedCategories: admin.firestore.FieldValue.arrayUnion(category),
            likedCategories: admin.firestore.FieldValue.arrayRemove(category),
        });
    }
    functions.logger.info(`[recordRecommendationFeedback] Updated preference for user ${userId}: ` +
        `${feedback === "helpful" ? "liked" : "disliked"} category "${category}"`);
    return { success: true };
});
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
exports.cleanupExpiredRecommendations = functions
    .runWith({ timeoutSeconds: 540, memory: "256MB" })
    .pubsub.schedule("0 2 * * *") // 02:00 UTC every day
    .timeZone("UTC")
    .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    functions.logger.info(`[cleanupExpiredRecommendations] Starting cleanup at ${now.toDate().toISOString()}`);
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
    functions.logger.info(`[cleanupExpiredRecommendations] Found ${expiredEventIds.length} expired events to clean up.`);
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
        const matchingDocs = recsSnap.docs.filter((doc) => doc.ref.path.endsWith(`/events/${eventId}`));
        if (matchingDocs.length === 0)
            continue;
        // Batch delete (max 500 per batch)
        const chunks = [];
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
    functions.logger.info(`[cleanupExpiredRecommendations] Cleanup complete. ` +
        `Deleted ${totalDeleted} recommendation records for ${expiredEventIds.length} expired events.`);
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
function buildSystemPrompt(ctx) {
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
function callGemini(params) {
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
                { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_ONLY_HIGH" },
                { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_ONLY_HIGH" },
                { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_ONLY_HIGH" },
                { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_ONLY_HIGH" },
            ],
        });
        const url = new URL(getGeminiUrl());
        const options = {
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
                var _a, _b, _c, _d, _e, _f;
                try {
                    const parsed = JSON.parse(data);
                    if (parsed.error) {
                        reject(new Error(`Gemini error: ${parsed.error.message}`));
                    }
                    else {
                        const text = (_f = (_e = (_d = (_c = (_b = (_a = parsed.candidates) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.content) === null || _c === void 0 ? void 0 : _c.parts) === null || _d === void 0 ? void 0 : _d[0]) === null || _e === void 0 ? void 0 : _e.text) !== null && _f !== void 0 ? _f : "";
                        resolve(text);
                    }
                }
                catch (e) {
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
async function checkAndIncrementRateLimit(userId) {
    const today = new Date().toISOString().slice(0, 10); // "YYYY-MM-DD"
    const ref = db.collection("copilotRateLimits").doc(userId);
    return db.runTransaction(async (tx) => {
        var _a;
        const snap = await tx.get(ref);
        const data = snap.data();
        if ((data === null || data === void 0 ? void 0 : data.date) === today) {
            if (((_a = data.messageCount) !== null && _a !== void 0 ? _a : 0) >= 20) {
                return false; // limit reached
            }
            tx.update(ref, { messageCount: admin.firestore.FieldValue.increment(1) });
        }
        else {
            // New day — reset counter
            tx.set(ref, { date: today, messageCount: 1 });
        }
        return true;
    });
}
// ── Cloud Function ─────────────────────────────────────────────────────────
exports.huddlCopilotChat = functions
    .region('europe-west2')
    .runWith({ timeoutSeconds: 60, memory: "256MB", secrets: ["GEMINI_API_KEY"] })
    .https.onCall(async (data, context) => {
    var _a;
    // Authentication guard
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    const userId = context.auth.uid;
    // Rate limiting — 20 messages per user per day
    const allowed = await checkAndIncrementRateLimit(userId);
    if (!allowed) {
        throw new functions.https.HttpsError("resource-exhausted", "Daily chat limit reached. Come back tomorrow!");
    }
    // Validate input
    const rawMessages = data.messages;
    if (!rawMessages || !Array.isArray(rawMessages) || rawMessages.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "messages array is required.");
    }
    // Take last 10 messages to keep context manageable
    const messages = rawMessages.slice(-10);
    // Build system prompt from user context
    const userContext = data.userContext;
    // Enrich user context from Firestore if partially missing
    let enrichedContext = Object.assign({}, userContext);
    try {
        const userDoc = await db.collection("users").doc(userId).get();
        if (userDoc.exists) {
            const ud = (_a = userDoc.data()) !== null && _a !== void 0 ? _a : {};
            enrichedContext = {
                userName: enrichedContext.userName || ud.name || ud.displayName,
                borough: enrichedContext.borough || ud.borough,
                childrenSummary: enrichedContext.childrenSummary || _buildChildrenSummary(ud),
                parentingStage: enrichedContext.parentingStage || _buildStageLabel(ud),
            };
        }
    }
    catch (e) {
        functions.logger.warn(`[huddlCopilotChat] Could not enrich context for ${userId}: ${e}`);
    }
    const systemPrompt = buildSystemPrompt(enrichedContext);
    try {
        const reply = await callGemini({ system: systemPrompt, messages });
        functions.logger.info(`[huddlCopilotChat] Reply generated for user ${userId}`);
        return { reply };
    }
    catch (e) {
        functions.logger.error(`[huddlCopilotChat] Gemini API error: ${e}`);
        throw new functions.https.HttpsError("internal", "Something went wrong. Please try again.");
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
function _buildChildrenSummary(ud) {
    const children = ud.children;
    if (!children || children.length === 0) {
        // Try legacy fields
        const childName = ud.childName;
        const childBirthday = ud.childBirthday;
        if (childName && childBirthday) {
            const ageMonths = _ageMonthsFromBirthday(childBirthday);
            const ageLabel = ageMonths < 12 ? `${ageMonths} months` : `${Math.floor(ageMonths / 12)} years`;
            return `${childName} (${ageLabel})`;
        }
        return "not specified";
    }
    return children
        .map((c) => {
        var _a;
        if (!c.name)
            return "child";
        const ageMonths = _ageMonthsFromBirthday((_a = c.birthday) !== null && _a !== void 0 ? _a : "");
        const ageLabel = ageMonths < 12 ? `${ageMonths} months` : `${Math.floor(ageMonths / 12)} years`;
        return `${c.name} (${ageLabel})`;
    })
        .join(", ");
}
/** Build a human-readable parenting stage label. */
function _buildStageLabel(ud) {
    var _a, _b;
    const stages = ud.stagesOfLife;
    const stage = (_b = (_a = stages === null || stages === void 0 ? void 0 : stages[0]) !== null && _a !== void 0 ? _a : ud.parentingStage) !== null && _b !== void 0 ? _b : "";
    if (!stage)
        return "not specified";
    return stage;
}
/** Parse a birthday string ('YYYY-MM-DD' or 'YYYY') → age in months. */
function _ageMonthsFromBirthday(birthday) {
    if (!birthday)
        return -1;
    try {
        const dob = birthday.length === 4
            ? new Date(`${birthday}-01-01`)
            : new Date(birthday);
        if (isNaN(dob.getTime()))
            return -1;
        return Math.floor((Date.now() - dob.getTime()) / (1000 * 60 * 60 * 24 * 30));
    }
    catch (_) {
        return -1;
    }
}
/** Return the youngest child's age in months from the user Firestore doc. */
function _youngestChildAgeMonths(ud) {
    const children = ud.children;
    if (children && children.length > 0) {
        const ages = children
            .map((c) => { var _a; return _ageMonthsFromBirthday((_a = c.birthday) !== null && _a !== void 0 ? _a : ""); })
            .filter((a) => a >= 0);
        if (ages.length > 0)
            return Math.min(...ages);
    }
    // Legacy childBirthday field
    const legacy = ud.childBirthday;
    if (legacy)
        return _ageMonthsFromBirthday(legacy);
    return -1;
}
exports.generateCopilotSuggestions = functions
    .region('europe-west2')
    .https.onCall(async (_, context) => {
    var _a, _b, _c;
    // Authentication guard
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
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
        const ud = (_a = userDoc.data()) !== null && _a !== void 0 ? _a : {};
        const borough = ud.borough || "your area";
        const stages = ud.stagesOfLife;
        const stage = ((_c = (_b = stages === null || stages === void 0 ? void 0 : stages[0]) !== null && _b !== void 0 ? _b : ud.parentingStage) !== null && _c !== void 0 ? _c : "").toLowerCase();
        const childName = _getFirstChildName(ud);
        const suggestions = [];
        // ── Chip 1: Age-based ─────────────────────────────────────────────
        const ageMonths = _youngestChildAgeMonths(ud);
        if (ageMonths >= 0) {
            if (ageMonths <= 3) {
                const label = childName ? `${childName}` : "your baby";
                suggestions.push(`Sleep tips for ${label} (${ageMonths}-month-old)`);
            }
            else if (ageMonths <= 6) {
                suggestions.push(`Feeding and weaning advice for a ${ageMonths}-month-old`);
            }
            else if (ageMonths <= 12) {
                suggestions.push(`Milestones to expect at ${ageMonths} months`);
            }
            else if (ageMonths <= 24) {
                const years = Math.floor(ageMonths / 12);
                suggestions.push(`Activities for a ${years}-year-old`);
            }
            else if (ageMonths <= 48) {
                const years = Math.floor(ageMonths / 12);
                suggestions.push(`What should my ${years}-year-old know by now?`);
            }
            else {
                suggestions.push("What should my child be doing this week?");
            }
        }
        else {
            suggestions.push("What should my child be doing this week?");
        }
        // ── Chip 2: Stage-based ───────────────────────────────────────────
        if (stage.includes("expect") || stage.includes("pregnant")) {
            const dueDate = ud.dueDate;
            if (dueDate && dueDate.length >= 4) {
                const year = parseInt(dueDate.slice(0, 4), 10);
                if (!isNaN(year)) {
                    suggestions.push(`What to prepare for your ${year} arrival`);
                }
                else {
                    suggestions.push("What to expect in the third trimester");
                }
            }
            else {
                suggestions.push("What to expect in the third trimester");
            }
        }
        else if (stage.includes("newborn") || stage.includes("new_parent") || stage.includes("new parent")) {
            suggestions.push("Newborn feeding schedules and sleep routines");
        }
        else if (stage.includes("trying") || stage.includes("ttc")) {
            suggestions.push("Fertility and conception support resources near you");
        }
        else if (stage.includes("toddler")) {
            suggestions.push("Fun toddler activities for rainy days");
        }
        else {
            suggestions.push("Help me find parenting groups nearby");
        }
        // ── Chip 3: Location-based ────────────────────────────────────────
        suggestions.push(`Best parent groups in ${borough}`);
        return { suggestions: suggestions.slice(0, 3) };
    }
    catch (e) {
        functions.logger.error(`[generateCopilotSuggestions] Error for ${userId}: ${e}`);
        return { suggestions: fallback };
    }
});
/** Extract the first child's name from the user Firestore doc. */
function _getFirstChildName(ud) {
    var _a;
    const children = ud.children;
    if (children && children.length > 0 && children[0].name) {
        return children[0].name;
    }
    return (_a = ud.childName) !== null && _a !== void 0 ? _a : null;
}
// ── 7. vertexGenerateContent ──────────────────────────────────────────────────
// Proxies generateContent requests to the Vertex AI fine-tuned model.
// Auth:    Service account OAuth 2.0 via VERTEX_AI_SA_KEY Secret Manager secret.
// Region:  CF runs in europe-west2; outbound HTTPS call to europe-west4-aiplatform.
// Fallback: throws HttpsError('unavailable', 'VERTEX_UNAVAILABLE') on any failure;
//           client catches and drops through to its Gemini AI Studio fallback.
exports.vertexGenerateContent = functions
    .region("europe-west2")
    .runWith({
    timeoutSeconds: 60,
    memory: "512MB",
    secrets: ["VERTEX_AI_SA_KEY"],
})
    .https.onCall(async (data, context) => {
    // ── Auth guard ────────────────────────────────────────────────────────────
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Request must be authenticated.");
    }
    const uid = context.auth.uid;
    // ── Parse VERTEX_AI_SA_KEY from Secret Manager ────────────────────────────
    const saKeyRaw = process.env.VERTEX_AI_SA_KEY;
    if (!saKeyRaw) {
        functions.logger.error("[vertexGenerateContent] VERTEX_AI_SA_KEY secret is not set or empty.");
        throw new functions.https.HttpsError("unavailable", "VERTEX_UNAVAILABLE");
    }
    let saKey;
    try {
        saKey = JSON.parse(saKeyRaw);
        if (!saKey.client_email || !saKey.private_key) {
            throw new Error("Missing client_email or private_key in SA JSON.");
        }
    }
    catch (parseErr) {
        functions.logger.error(`[vertexGenerateContent] Failed to parse VERTEX_AI_SA_KEY JSON: ${parseErr}`);
        throw new functions.https.HttpsError("unavailable", "VERTEX_UNAVAILABLE");
    }
    // ── Obtain Bearer token via google-auth-library JWT ───────────────────────
    let accessToken;
    try {
        const jwt = new google_auth_library_1.JWT({
            email: saKey.client_email,
            key: saKey.private_key,
            scopes: ["https://www.googleapis.com/auth/cloud-platform"],
        });
        const tokenResponse = await jwt.authorize();
        if (!tokenResponse.access_token) {
            throw new Error("jwt.authorize() returned no access_token.");
        }
        accessToken = tokenResponse.access_token;
    }
    catch (tokenErr) {
        functions.logger.error(`[vertexGenerateContent] Failed to obtain Bearer token for uid=${uid}: ${tokenErr}`);
        throw new functions.https.HttpsError("unavailable", "VERTEX_UNAVAILABLE");
    }
    // ── POST to Vertex AI endpoint ────────────────────────────────────────────
    const requestBody = data.requestBody;
    if (!requestBody) {
        functions.logger.error(`[vertexGenerateContent] Missing requestBody in call data from uid=${uid}.`);
        throw new functions.https.HttpsError("invalid-argument", "requestBody is required.");
    }
    return new Promise((resolve, reject) => {
        const bodyStr = JSON.stringify(requestBody);
        const url = new URL(VERTEX_ENDPOINT);
        const options = {
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
            res.on("data", (chunk) => { raw += chunk.toString(); });
            res.on("end", () => {
                if (res.statusCode === 200) {
                    try {
                        const parsed = JSON.parse(raw);
                        functions.logger.info(`[vertexGenerateContent] Success for uid=${uid}, status=200.`);
                        resolve({ data: parsed });
                    }
                    catch (jsonErr) {
                        functions.logger.warn(`[vertexGenerateContent] Vertex returned 200 but body not valid JSON for uid=${uid}: ${jsonErr}`);
                        reject(new functions.https.HttpsError("unavailable", "VERTEX_UNAVAILABLE"));
                    }
                }
                else {
                    functions.logger.warn(`[vertexGenerateContent] Vertex returned HTTP ${res.statusCode} for uid=${uid}. Body: ${raw.slice(0, 500)}`);
                    reject(new functions.https.HttpsError("unavailable", "VERTEX_UNAVAILABLE"));
                }
            });
        });
        req.on("error", (err) => {
            functions.logger.warn(`[vertexGenerateContent] https.request network error for uid=${uid}: ${err.message}`);
            reject(new functions.https.HttpsError("unavailable", "VERTEX_UNAVAILABLE"));
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
exports.syncPublicProfile = functions
    .region("europe-west2")
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .firestore.document("users/{userId}")
    .onWrite(async (change, context) => {
    const userId = context.params.userId;
    const publicRef = db.collection("users_public").doc(userId);
    // ── Delete path ────────────────────────────────────────────────────────
    if (!change.after.exists) {
        functions.logger.info(`[syncPublicProfile] User ${userId} deleted — removing public mirror.`);
        await publicRef.delete();
        return;
    }
    // ── Create / Update path ───────────────────────────────────────────────
    const data = change.after.data();
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
    ];
    const publicData = {};
    for (const field of PUBLIC_FIELDS) {
        if (data[field] !== undefined) {
            publicData[field] = data[field];
        }
    }
    // Guard: a write touching only private fields (e.g. stripeCustomerId)
    // produces an empty publicData — skip the mirror write to avoid a
    // no-op Firestore round-trip that only advances the doc's updateTime.
    if (Object.keys(publicData).length === 0) {
        functions.logger.info(`[syncPublicProfile] Write to users/${userId} contained no ` +
            `public fields — skipping mirror.`);
        return;
    }
    functions.logger.info(`[syncPublicProfile] Mirroring ${Object.keys(publicData).length} ` +
        `field(s) for user ${userId}: ${Object.keys(publicData).join(", ")}`);
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
function isAllowedBorough(borough) {
    const lower = borough.toLowerCase();
    return (lower === "cambridge" ||
        lower.includes("cambridgeshire") ||
        lower === "fenland" ||
        lower === "huntingdonshire");
}
exports.setUserBorough = functions
    .region("europe-west2")
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data, context) => {
    // ── Auth guard ─────────────────────────────────────────────────────────
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in to update borough.");
    }
    const uid = context.auth.uid;
    // ── Input validation ───────────────────────────────────────────────────
    const rawPostcode = data.postcode;
    if (typeof rawPostcode !== "string" || rawPostcode.trim() === "") {
        throw new functions.https.HttpsError("invalid-argument", "postcode must be a non-empty string.");
    }
    // Normalise: trim, uppercase, collapse internal whitespace to single space
    const postcode = rawPostcode.trim().toUpperCase().replace(/\s+/g, " ");
    const geo = await new Promise((resolve, reject) => {
        const path = `/postcodes/${encodeURIComponent(postcode)}`;
        const options = {
            hostname: "api.postcodes.io",
            path,
            method: "GET",
        };
        const req = https.request(options, (res) => {
            let raw = "";
            res.on("data", (chunk) => { raw += chunk.toString(); });
            res.on("end", () => {
                var _a, _b, _c, _d, _e, _f, _g;
                if (res.statusCode === 404) {
                    functions.logger.warn(`[setUserBorough] postcodes.io 404 for postcode="${postcode}" uid=${uid}`);
                    reject(new functions.https.HttpsError("not-found", "Postcode not recognised. Please check and try again."));
                    return;
                }
                if (res.statusCode !== 200) {
                    functions.logger.warn(`[setUserBorough] postcodes.io returned HTTP ${res.statusCode} ` +
                        `for postcode="${postcode}" uid=${uid}. Body: ${raw.slice(0, 200)}`);
                    reject(new functions.https.HttpsError("unavailable", "Postcode lookup service is temporarily unavailable. Please try again."));
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    const result = parsed.result;
                    const borough = (_a = result === null || result === void 0 ? void 0 : result.admin_district) !== null && _a !== void 0 ? _a : "";
                    const ward = (_b = result === null || result === void 0 ? void 0 : result.admin_ward) !== null && _b !== void 0 ? _b : "";
                    const districtCode = (_d = (_c = result === null || result === void 0 ? void 0 : result.codes) === null || _c === void 0 ? void 0 : _c.admin_district) !== null && _d !== void 0 ? _d : "";
                    const wardCode = (_f = (_e = result === null || result === void 0 ? void 0 : result.codes) === null || _e === void 0 ? void 0 : _e.admin_ward) !== null && _f !== void 0 ? _f : "";
                    const region = (_g = result === null || result === void 0 ? void 0 : result.region) !== null && _g !== void 0 ? _g : "";
                    if (!borough) {
                        functions.logger.warn(`[setUserBorough] postcodes.io returned no admin_district ` +
                            `for postcode="${postcode}" uid=${uid}`);
                        reject(new functions.https.HttpsError("not-found", "Could not resolve a borough for this postcode."));
                        return;
                    }
                    resolve({ borough, ward, districtCode, wardCode, region });
                }
                catch (parseErr) {
                    functions.logger.warn(`[setUserBorough] postcodes.io response parse error for ` +
                        `postcode="${postcode}" uid=${uid}: ${parseErr}`);
                    reject(new functions.https.HttpsError("unavailable", "Postcode lookup service is temporarily unavailable. Please try again."));
                }
            });
        });
        req.on("error", (err) => {
            functions.logger.warn(`[setUserBorough] https.request network error for ` +
                `postcode="${postcode}" uid=${uid}: ${err.message}`);
            reject(new functions.https.HttpsError("unavailable", "Postcode lookup service is temporarily unavailable. Please try again."));
        });
        req.end();
    });
    // ── Cambridge gate ─────────────────────────────────────────────────────
    // Mirrors Dart PostcodeService._isCambridgeBorough exactly.
    // Update isAllowedBorough() and the Dart function together if launch
    // area ever expands.
    if (!isAllowedBorough(geo.borough)) {
        functions.logger.info(`[setUserBorough] Gate rejection: uid=${uid} postcode="${postcode}" ` +
            `resolved district="${geo.borough}" — outside Cambridge launch area.`);
        throw new functions.https.HttpsError("failed-precondition", "OUTSIDE_LAUNCH_AREA");
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
    functions.logger.info(`[setUserBorough] Success: uid=${uid} postcode="${postcode}" ` +
        `→ borough="${geo.borough}" ward="${geo.ward}"`);
    return {
        borough: geo.borough,
        ward: geo.ward,
        districtCode: geo.districtCode,
        wardCode: geo.wardCode,
        region: geo.region,
    };
});
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
const DEFAULT_GDPR_POLICY = {
    authored_content: "anonymise", // group msgs + community_wisdom + borough_announcements scrubbed-but-retained
    reports: "retain", // HARD LOCK — reports are legal records; retain unless explicit solicitor instruction
    feedback: "delete", // platform feedback — delete by default
    invitations_sent: "retain", // legal hold potential — retain by default
    created_content_meetups: "delete", // user-created meetups — deleted by default
    created_content_marketplace: "delete", // user-created marketplace listings — deleted by default
    dry_run_default: false,
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
async function paginatedDelete(query, dryRun) {
    let totalDeleted = 0;
    let cursor = null;
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
async function paginatedAnonymise(query, updateFields, dryRun) {
    let totalTouched = 0;
    let cursor = null;
    // eslint-disable-next-line no-constant-condition
    while (true) {
        let pagedQuery = query
            .orderBy(admin.firestore.FieldPath.documentId())
            .limit(PAGE_SIZE);
        if (cursor !== null)
            pagedQuery = pagedQuery.startAfter(cursor);
        const snapshot = await pagedQuery.get();
        if (snapshot.empty)
            break;
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
        if (snapshot.docs.length < PAGE_SIZE)
            break;
        cursor = snapshot.docs[snapshot.docs.length - 1];
    }
    return totalTouched;
}
// ── Config-switch reader ────────────────────────────────────────────────────
//
// Reads _config/gdpr_deletion_policy once at CF start via Admin SDK.
// Merges with DEFAULT_GDPR_POLICY — any missing field falls back to the default.
// Returns the fully-resolved policy. Never throws; returns defaults on any error.
async function resolveGdprPolicy() {
    var _a, _b, _c, _d, _e, _f, _g;
    try {
        const configDoc = await db.collection("_config").doc("gdpr_deletion_policy").get();
        if (!configDoc.exists) {
            functions.logger.info("[deleteUserData] No _config/gdpr_deletion_policy doc — using defaults.");
            return Object.assign({}, DEFAULT_GDPR_POLICY);
        }
        const remote = configDoc.data();
        // Merge: remote fields override defaults; missing fields fall back to defaults.
        return {
            authored_content: (_a = remote.authored_content) !== null && _a !== void 0 ? _a : DEFAULT_GDPR_POLICY.authored_content,
            reports: (_b = remote.reports) !== null && _b !== void 0 ? _b : DEFAULT_GDPR_POLICY.reports,
            feedback: (_c = remote.feedback) !== null && _c !== void 0 ? _c : DEFAULT_GDPR_POLICY.feedback,
            invitations_sent: (_d = remote.invitations_sent) !== null && _d !== void 0 ? _d : DEFAULT_GDPR_POLICY.invitations_sent,
            created_content_meetups: (_e = remote.created_content_meetups) !== null && _e !== void 0 ? _e : DEFAULT_GDPR_POLICY.created_content_meetups,
            created_content_marketplace: (_f = remote.created_content_marketplace) !== null && _f !== void 0 ? _f : DEFAULT_GDPR_POLICY.created_content_marketplace,
            dry_run_default: (_g = remote.dry_run_default) !== null && _g !== void 0 ? _g : DEFAULT_GDPR_POLICY.dry_run_default,
        };
    }
    catch (err) {
        functions.logger.error("[deleteUserData] resolveGdprPolicy error — falling back to defaults:", err);
        return Object.assign({}, DEFAULT_GDPR_POLICY);
    }
}
// ── Cloud Function ─────────────────────────────────────────────────────────
exports.deleteUserData = functions
    .region("europe-west2")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (data, context) => {
    // ══════════════════════════════════════════════════════════════════
    // SECURITY INVARIANT — THIS BLOCK IS THE MOST IMPORTANT CODE HERE.
    //
    // uid comes from context.auth.uid ONLY.
    // The payload (data) is NOT a source of uid under any circumstances.
    // If context.auth is null, we throw immediately and touch nothing.
    // ══════════════════════════════════════════════════════════════════
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "deleteUserData requires authentication. No uid accepted from payload.");
    }
    const uid = context.auth.uid;
    // Explicitly discard any uid-like field the caller may have put in the payload.
    // This is belt-and-suspenders: we never reference data.uid or data['uid'].
    // Only data.dryRun is read, and only as a boolean.
    const startedAt = new Date().toISOString();
    const dryRun = typeof data.dryRun === "boolean" ? data.dryRun : false;
    functions.logger.info(`[deleteUserData] START uid=${uid} dryRun=${dryRun} startedAt=${startedAt}`);
    // ── Resolve policy config ──────────────────────────────────────────────
    const policy = await resolveGdprPolicy();
    functions.logger.info("[deleteUserData] Resolved policy:", policy);
    // ── Steps accumulator ──────────────────────────────────────────────────
    // Each step records its own StepResult. On any unhandled error in a step,
    // the step is marked error but we continue accumulating and return a
    // partial result with success=false rather than throwing and losing state.
    const steps = {};
    // Helper: run one step, catch errors, populate steps[key].
    async function runStep(key, query, skipReason) {
        if (query === null || skipReason !== undefined) {
            steps[key] = { status: "skipped", count: 0, error: skipReason };
            return;
        }
        try {
            const count = await paginatedDelete(query, dryRun);
            steps[key] = { status: "ok", count };
            functions.logger.info(`[deleteUserData] ${key}: deleted ${count} docs (dryRun=${dryRun})`);
        }
        catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            steps[key] = { status: "error", count: 0, error: msg };
            functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
        }
    }
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
    await runStep("subscriptions", db.collection("subscriptions").where("userId", "==", uid));
    // 2. notifications — field "userId" (firebase_auth_service.dart:769)
    await runStep("notifications", db.collection("notifications").where("userId", "==", uid));
    // 3. local_services — field "createdByUid" (firebase_auth_service.dart:853)
    //    Note: ownerUid is partner-only; createdByUid is set on ALL user-created listings.
    await runStep("local_services", db.collection("local_services").where("createdByUid", "==", uid));
    // 4. borough_feed — field "partnerUid" (community_feed_service.dart — verified)
    await runStep("borough_feed", db.collection("borough_feed").where("partnerUid", "==", uid));
    // 5. feedback — field "user_uid" (feedback_service.dart:118)
    //    Gated by policy.feedback switch. Default = "delete".
    if (policy.feedback === "delete") {
        await runStep("feedback", db.collection("feedback").where("user_uid", "==", uid));
    }
    else {
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
                const count = await paginatedAnonymise(query, {
                    author_uid: null,
                    author_name: null,
                    author_avatar: null,
                    content_text: DELETED_CONTENT_SENTINEL,
                }, dryRun);
                steps[key] = { status: "ok", count };
                functions.logger.info(`[deleteUserData] ${key}: anonymised ${count} docs (dryRun=${dryRun})`);
            }
            else if (policy.authored_content === "delete") {
                const count = await paginatedDelete(query, dryRun);
                steps[key] = { status: "ok", count };
                functions.logger.info(`[deleteUserData] ${key}: deleted ${count} docs (dryRun=${dryRun})`);
            }
            else {
                // "retain"
                steps[key] = { status: "skipped", count: 0,
                    error: `policy.authored_content=${policy.authored_content} — retained` };
                functions.logger.info(`[deleteUserData] ${key}: skipped — policy.authored_content=retain`);
            }
        }
        catch (err) {
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
                count += await paginatedAnonymise(announcementQuery, { authorId: null }, dryRun);
            }
            else if (policy.authored_content === "delete") {
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
                let lastDoc;
                let pageCount = 0;
                do {
                    const page = lastDoc
                        ? await commentQuery.startAfter(lastDoc).limit(400).get()
                        : await commentQuery.limit(400).get();
                    if (page.empty)
                        break;
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
            }
            else {
                // dryRun: just count
                const snap = await commentQuery.get();
                count += snap.size;
            }
            steps[key] = { status: "ok", count };
            functions.logger.info(`[deleteUserData] ${key}: processed ${count} announcement/comment docs ` +
                `(authored_content=${policy.authored_content}, dryRun=${dryRun})`);
        }
        catch (err) {
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
            await runStep(key, db.collection("reports").where("reportedByUid", "==", uid));
        }
        else {
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
                const count = await paginatedAnonymise(query, {
                    senderId: null,
                    senderName: null,
                    senderAvatar: null,
                    message: DELETED_CONTENT_SENTINEL,
                }, dryRun);
                steps[key] = { status: "ok", count };
                functions.logger.info(`[deleteUserData] ${key}: anonymised ${count} docs (dryRun=${dryRun})`);
            }
            else if (policy.authored_content === "delete") {
                const count = await paginatedDelete(query, dryRun);
                steps[key] = { status: "ok", count };
                functions.logger.info(`[deleteUserData] ${key}: deleted ${count} docs (dryRun=${dryRun})`);
            }
            else {
                // "retain"
                steps[key] = {
                    status: "skipped",
                    count: 0,
                };
                functions.logger.info(`[deleteUserData] ${key}: skipped — policy.authored_content=${policy.authored_content}`);
            }
        }
        catch (err) {
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
        await runStep("meetups_createdBy", db.collection("meetups").where("createdBy", "==", uid));
        await runStep("meetups_organiserId", db.collection("meetups").where("organiserId", "==", uid));
    }
    else {
        await runStep("meetups_createdBy", null, `policy.created_content_meetups=retain`);
        await runStep("meetups_organiserId", null, `policy.created_content_meetups=retain`);
    }
    // 9. marketplace — field "sellerId" (firebase_auth_service.dart:784)
    //    Gated by policy.created_content_marketplace (default = "delete").
    if (policy.created_content_marketplace === "delete") {
        await runStep("marketplace", db.collection("marketplace").where("sellerId", "==", uid));
    }
    else {
        await runStep("marketplace", null, `policy.created_content_marketplace=retain`);
    }
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
    await runStep("polls", db.collection("polls").where("createdByUid", "==", uid));
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
                if (!dryRun)
                    await ref.delete();
                steps[key] = { status: "ok", count: 1 };
                functions.logger.info(`[deleteUserData] ${key}: deleted 1 doc (dryRun=${dryRun})`);
            }
            else {
                steps[key] = { status: "ok", count: 0 };
            }
        }
        catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            steps[key] = { status: "error", count: 0, error: msg };
            functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
        }
    })();
    // ── Subcollection sweeps (users/{uid}/…) ───────────────────────────────
    // saved_messages (saved_message_service.dart:119–136)
    await runStep("users_saved_messages", db.collection("users").doc(uid).collection("saved_messages"));
    // notifPrefs/settings — point-delete (user_privacy_prefs_service.dart:82–87)
    // Only one document ever written ('settings'). Delete it directly.
    await (async () => {
        const key = "users_notifPrefs_settings";
        try {
            const ref = db.collection("users").doc(uid).collection("notifPrefs").doc("settings");
            const snap = await ref.get();
            if (snap.exists) {
                if (!dryRun)
                    await ref.delete();
                steps[key] = { status: "ok", count: 1 };
                functions.logger.info(`[deleteUserData] ${key}: deleted 1 doc (dryRun=${dryRun})`);
            }
            else {
                steps[key] = { status: "ok", count: 0 };
            }
        }
        catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            steps[key] = { status: "error", count: 0, error: msg };
            functions.logger.error(`[deleteUserData] ${key}: ERROR — ${msg}`);
        }
    })();
    // deadlines (firebase_auth_service.dart:845)
    await runStep("users_deadlines", db.collection("users").doc(uid).collection("deadlines"));
    // saved_items (firebase_auth_service.dart:821)
    await runStep("users_saved_items", db.collection("users").doc(uid).collection("saved_items"));
    // blocks forward: users/{uid}/blocks/{targetUid} (firebase_auth_service.dart:792)
    await runStep("users_blocks_forward", db.collection("users").doc(uid).collection("blocks"));
    // invitations received: users/{uid}/invitations/{invId} (invitation_service.dart:232)
    await runStep("users_invitations_received", db.collection("users").doc(uid).collection("invitations"));
    // user_rsvps: user_rsvps/{uid}/meetups/{meetupId} (firestore_service.dart:1346)
    await runStep("user_rsvps_meetups", db.collection("user_rsvps").doc(uid).collection("meetups"));
    // ── collectionGroup sweeps ─────────────────────────────────────────────
    // blocks reverse: other users who blocked this uid
    // field 'targetUid' is a real document field (block_service.dart:97)
    await runStep("blocks_reverse", db.collectionGroup("blocks").where("targetUid", "==", uid));
    // endorsements: doc ID is the endorser uid, AND field 'uid' == endorser uid
    // (local_services_service.dart:180 — field 'uid' is written on every endorsement doc)
    // NOTE: collectionGroup + FieldPath.documentId() equality requires a FULL document path
    // (odd-segment bare uid is rejected by the SDK). Use the real 'uid' field instead.
    await runStep("endorsements_by_uid", db.collectionGroup("endorsements")
        .where("uid", "==", uid));
    // invitations sent: gated by policy.invitations_sent switch (default=retain)
    // field 'invitedById' is a real document field (invitation_service.dart:369)
    if (policy.invitations_sent === "delete") {
        await runStep("invitations_sent", db.collectionGroup("invitations").where("invitedById", "==", uid));
    }
    else {
        await runStep("invitations_sent", null, `policy.invitations_sent=${policy.invitations_sent} — retained by default`);
    }
    // capturedConvIds: populated during conversations step, reused by Phase 4 Storage
    // (DM media enumerate-filter). Declared here so Phase 4 block can read it.
    const capturedConvIds = [];
    // ── groups.memberIds arrayRemove + capture group list ──────────────────
    //
    // This is NOT a delete of the group document.
    // It removes uid from the memberIds array only.
    // Captured group IDs are used immediately for memberActivity sweep
    // and stored in the step result for Phase 4 (group Storage enumeration).
    // arrayRemove is idempotent — safe to re-run.
    const capturedGroupIds = [];
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
            let lastDoc = null;
            // eslint-disable-next-line no-constant-condition
            while (true) {
                let q = db.collection("groups")
                    .where("memberIds", "array-contains", uid)
                    .limit(500);
                if (lastDoc)
                    q = q.startAfter(lastDoc);
                const snap = await q.get();
                if (snap.empty)
                    break;
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
                if (snap.docs.length < 500)
                    break;
                lastDoc = snap.docs[snap.docs.length - 1];
            }
            steps[key] = {
                status: "ok",
                count: totalUpdated,
                // Pass the captured group IDs downstream via the error field (repurposed as info)
                // — they are NOT an error, just additional data. Alternatively stored on result.
                // We store them separately on the result object below.
            };
            functions.logger.info(`[deleteUserData] ${key}: removed from ${totalUpdated} groups, capturedGroupIds=${JSON.stringify(capturedGroupIds)} (dryRun=${dryRun})`);
        }
        catch (err) {
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
                    const existenceChecks = await Promise.all(chunk.map(gid => db.collection("groups").doc(gid).collection("memberActivity").doc(uid).get()));
                    deleted += existenceChecks.filter(s => s.exists).length;
                }
                else {
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
        }
        catch (err) {
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
        var _a, _b, _c;
        const msgKey = "conversations_messages";
        const convKey = "conversations_docs";
        try {
            let totalMsgsAnonymised = 0;
            let totalConvsDeleted = 0;
            let totalConvsUpdated = 0;
            // Page through conversations where uid is a participant
            // IDs are captured here and reused by Phase 4 Storage (DM media enumeration).
            let convCursor = null;
            // eslint-disable-next-line no-constant-condition
            while (true) {
                let convQuery = db
                    .collection("conversations")
                    .where("participants", "array-contains", uid)
                    .orderBy(admin.firestore.FieldPath.documentId())
                    .limit(PAGE_SIZE);
                if (convCursor !== null)
                    convQuery = convQuery.startAfter(convCursor);
                const convSnap = await convQuery.get();
                if (convSnap.empty)
                    break;
                for (const convDoc of convSnap.docs) {
                    capturedConvIds.push(convDoc.id);
                    // ── Step A: anonymise this user's messages in the subcollection ──
                    const msgsAnonymised = await paginatedAnonymise(convDoc.ref.collection("messages").where("senderId", "==", uid), {
                        senderId: null,
                        senderName: null,
                        senderAvatar: null,
                        message: DELETED_CONTENT_SENTINEL,
                    }, dryRun);
                    totalMsgsAnonymised += msgsAnonymised;
                    // ── Step B: remove uid from participants ──
                    if (!dryRun) {
                        await convDoc.ref.update({
                            participants: admin.firestore.FieldValue.arrayRemove(uid),
                        });
                        // Re-read after the update to check remaining participants
                        const refreshed = await convDoc.ref.get();
                        const remaining = (_b = (_a = refreshed.data()) === null || _a === void 0 ? void 0 : _a["participants"]) !== null && _b !== void 0 ? _b : [];
                        if (remaining.length === 0) {
                            // Nobody left — delete the conversation doc
                            await convDoc.ref.delete();
                            totalConvsDeleted++;
                        }
                        else {
                            // One or more participants remain — conversation survives
                            totalConvsUpdated++;
                        }
                    }
                    else {
                        // In dryRun mode: check what WOULD happen without writing
                        const currentParticipants = (_c = convDoc.data()["participants"]) !== null && _c !== void 0 ? _c : [];
                        const wouldRemain = currentParticipants.filter((p) => p !== uid);
                        if (wouldRemain.length === 0) {
                            totalConvsDeleted++;
                        }
                        else {
                            totalConvsUpdated++;
                        }
                    }
                }
                if (convSnap.docs.length < PAGE_SIZE)
                    break;
                convCursor = convSnap.docs[convSnap.docs.length - 1];
            }
            steps[msgKey] = { status: "ok", count: totalMsgsAnonymised };
            steps[convKey] = { status: "ok", count: totalConvsDeleted + totalConvsUpdated };
            functions.logger.info(`[deleteUserData] conversations: anonymised ${totalMsgsAnonymised} messages, ` +
                `deleted ${totalConvsDeleted} conv docs (empty), ` +
                `retained ${totalConvsUpdated} conv docs (dryRun=${dryRun})`);
        }
        catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            steps[msgKey] = { status: "error", count: 0, error: msg };
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
        async function deleteFileIdempotent(bucket, filePath) {
            try {
                await bucket.file(filePath).delete();
            }
            catch (err) {
                const code = err.code;
                if (code === 404 || code === "404")
                    return; // already gone — success
                throw err;
            }
        }
        // ── Helper: list + filter + delete files under a single prefix ────────
        // Returns the count of files touched (deleted in live run, listed in dryRun).
        // Filter function receives the bare filename (last path segment only).
        async function enumerateFilterDelete(bucket, prefix, filterFn, dry) {
            const [files] = await bucket.getFiles({ prefix });
            const matched = files.filter((f) => {
                var _a;
                const filename = (_a = f.name.split("/").pop()) !== null && _a !== void 0 ? _a : "";
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
                functions.logger.info(`[deleteUserData] ${key}: touched ${count} files (dryRun=${dryRun})`);
            }
            catch (err) {
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
                    (cid) => `dm_images/${cid}/`,
                    (cid) => `dm_documents/${cid}/`,
                    (cid) => `voice_notes/dm/${cid}/`,
                ];
                // Filename filter: startsWith(uid + '_') — precise segment match.
                // A uid that is a substring of another uid will NOT match because
                // the character after uid must be '_', not another uid character.
                const dmFilter = (filename) => filename.startsWith(uid + "_");
                for (const convId of capturedConvIds) {
                    for (const prefixFn of dmPrefixTemplates) {
                        const n = await enumerateFilterDelete(bucket, prefixFn(convId), dmFilter, dryRun);
                        count += n;
                    }
                }
                steps[key] = { status: "ok", count };
                functions.logger.info(`[deleteUserData] ${key}: touched ${count} files across ` +
                    `${capturedConvIds.length} conversations (dryRun=${dryRun})`);
            }
            catch (err) {
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
                    (gid) => `group_images/${gid}/`,
                    (gid) => `group_documents/${gid}/`,
                    (gid) => `voice_notes/group/${gid}/`,
                ];
                // Two filename patterns for group media:
                //   {uid}_{ts}.{ext}          — direct post/upload
                //   thread_{uid}_{ts}.{ext}   — thread reply (audit confirmed naming)
                const groupFilter = (filename) => filename.startsWith(uid + "_") ||
                    filename.startsWith("thread_" + uid + "_");
                for (const groupId of capturedGroupIds) {
                    for (const prefixFn of groupPrefixTemplates) {
                        const n = await enumerateFilterDelete(bucket, prefixFn(groupId), groupFilter, dryRun);
                        count += n;
                    }
                }
                steps[key] = { status: "ok", count };
                functions.logger.info(`[deleteUserData] ${key}: touched ${count} files across ` +
                    `${capturedGroupIds.length} groups (dryRun=${dryRun})`);
            }
            catch (err) {
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
    const result = Object.assign({ success: !anyError, uid,
        dryRun,
        startedAt,
        completedAt,
        policy,
        steps,
        capturedGroupIds, // Phase 4 Storage: group media enumeration
        capturedConvIds }, (anyError ? { error: "One or more steps failed — see steps for details.", retryable: true } : {}));
    functions.logger.info(`[deleteUserData] COMPLETE uid=${uid} success=${result.success} dryRun=${dryRun} ` +
        `completedAt=${completedAt}`, { steps });
    return result;
});
//# sourceMappingURL=index.js.map