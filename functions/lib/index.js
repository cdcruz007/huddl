"use strict";
/**
 * Huddl — AI Event Recommendation Engine Cloud Functions
 *
 * Four functions:
 *   1. generateEventRecommendations  — Firestore onCreate on events/{eventId}
 *   2. refreshUserRecommendations    — Firestore onUpdate on users/{userId}
 *   3. recordRecommendationFeedback  — HTTP callable (from Flutter app)
 *   4. cleanupExpiredRecommendations — Scheduled daily at 02:00 UTC
 *
 * Firestore schema used:
 *   events/{eventId}
 *   users/{userId}
 *   userRecommendations/{userId}/events/{eventId}
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanupExpiredRecommendations = exports.recordRecommendationFeedback = exports.refreshUserRecommendations = exports.generateEventRecommendations = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();
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
//# sourceMappingURL=index.js.map