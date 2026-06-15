/**
 * rebalance/scoring.ts
 * ─────────────────────
 * Activity scoring engine for the elastic rebalance engine.
 *
 * Exports:
 *   GroupDoc          — typed mirror of the Firestore group document fields read here.
 *   ActivityScore     — result of scoreGroup() for one group.
 *   scoreGroup()      — reads memberActivity subcollection, returns ActivityScore.
 *   runRebalancePass()— full engine pass over all in-scope resident groups;
 *                       scores each group, applies gating, either writes to
 *                       rebalance_log (observeOnly) or delegates to the offer
 *                       senders injected as parameters (Pieces 3 & 4).
 *
 * Activity score = messages-per-active-member per week, cfg.SMOOTHING_WEEKS rolling avg.
 *
 * Activity veto thresholds (cfg.QUIET_SCORE_THRESHOLD / cfg.LIVELY_SCORE_THRESHOLD):
 *   Both are in the Firestore config doc and included in DEFAULT_CONFIG so they
 *   can be tuned during the observe phase without redeploying.
 *
 * Interest groups are excluded entirely — their membership counts must not
 * feed any resident-group activity calculation.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  RebalanceConfig,
  RebalanceLogEntry,
  isBoroughInScope,
  crowdedThreshold,
  quietThreshold,
  writeObserveLog,
} from "./config";

// ── Types ─────────────────────────────────────────────────────────────────

export interface GroupDoc {
  id:               string;
  name:             string;
  borough:          string;
  level:            string;           // "borough" | "ward" | "region"
  groupType:        string;           // must be "resident" to be processed
  memberIds:        string[];
  memberCount:      number;
  lastMessageTime:  admin.firestore.Timestamp | null;
  parentGroupId:    string | null;    // ward→borough FK; null for borough-level
  parentRegionName: string | null;    // borough→region stable name; null when absent
  ward:             string | null;    // ward name from geo stack
  wardCode:         string | null;
  districtCode:     string | null;
  region:           string | null;
}

export interface ActivityScore {
  groupId:            string;
  memberCount:        number;
  activeMembers:      number;   // members with lastActiveAt within ACTIVE_WINDOW_DAYS
  totalMessages:      number;   // sum of messageCount across all memberActivity docs
  weeklyVolume:       number;   // totalMessages / SMOOTHING_WEEKS
  score:              number;   // weeklyVolume / activeMembers (0 when activeMembers == 0)
  isGenuinelyQuiet:   boolean;  // score < QUIET_SCORE_THRESHOLD AND window elapsed
  isGenuinelyLively:  boolean;  // score > LIVELY_SCORE_THRESHOLD AND recently active
}

// ── scoreGroup ────────────────────────────────────────────────────────────

/**
 * Read the memberActivity subcollection for one group and compute its
 * ActivityScore.
 *
 * A missing or empty memberActivity subcollection is treated as zero
 * activity — not as missing data.  Resident groups whose members have
 * never sent a message are genuinely quiet.
 *
 * lastMessageTime guards prevent acting on transient signals:
 *
 *   isGenuinelyQuiet — score < cfg.QUIET_SCORE_THRESHOLD AND windowElapsed.
 *     windowElapsed = lastMessageTime is older than ACTIVE_WINDOW_DAYS (or null).
 *     Blocks rollup offers during a mid-window lull: if the group had
 *     activity recently, the window has not fully elapsed and the flag stays
 *     false regardless of the current score.  A null lastMessageTime (never
 *     messaged) satisfies windowElapsed trivially.
 *
 *   isGenuinelyLively — score > cfg.LIVELY_SCORE_THRESHOLD AND recentlyActive.
 *     recentlyActive = lastMessageTime is within ACTIVE_WINDOW_DAYS.
 *     Blocks split offers based purely on historical volume: a group that
 *     scored high months ago but has gone silent is not lively.
 *
 * Interest groups must never be passed here; the caller filters them out.
 */
export async function scoreGroup(
  db:              admin.firestore.Firestore,
  groupId:         string,
  cfg:             RebalanceConfig,
  now:             Date,
  lastMessageTime: admin.firestore.Timestamp | null
): Promise<ActivityScore> {
  const activeWindowMs = cfg.ACTIVE_WINDOW_DAYS * 24 * 60 * 60 * 1000;
  const cutoffMs       = now.getTime() - activeWindowMs;

  // Read all memberActivity docs for this group in one subcollection fetch.
  // Missing/empty subcollection → zero activity (not missing data).
  const activitySnap = await db
    .collection("groups")
    .doc(groupId)
    .collection("memberActivity")
    .get();

  let activeMembers = 0;
  let totalMessages = 0;

  for (const doc of activitySnap.docs) {
    const d          = doc.data();
    const msgCount   = (d["messageCount"] as number                           | undefined) ?? 0;
    const lastActive = (d["lastActiveAt"]  as admin.firestore.Timestamp | undefined);

    totalMessages += msgCount;

    if (lastActive && lastActive.toMillis() >= cutoffMs) {
      activeMembers++;
    }
  }

  const weeklyVolume = totalMessages / cfg.SMOOTHING_WEEKS;
  const score        = activeMembers > 0 ? weeklyVolume / activeMembers : 0;

  // Convert lastMessageTime to ms once.
  // null → 0 (epoch), which is always < cutoffMs → windowElapsed = true,
  // recentlyActive = false.  Correct for both flags.
  const lastMsgMs = lastMessageTime != null ? lastMessageTime.toMillis() : 0;

  // windowElapsed: the full active window has passed since the last message.
  // Prevents acting on a temporary mid-window lull.
  const windowElapsed = lastMsgMs < cutoffMs;

  // recentlyActive: there was a message within the active window.
  // Confirms liveness is current, not merely historical.
  const recentlyActive = lastMsgMs >= cutoffMs;

  // Both flags require their score gate AND the lastMessageTime guard.
  const isGenuinelyQuiet  = score < cfg.QUIET_SCORE_THRESHOLD  && windowElapsed;
  const isGenuinelyLively = score > cfg.LIVELY_SCORE_THRESHOLD && recentlyActive;

  return {
    groupId,
    memberCount:  0,        // caller fills this from the group doc
    activeMembers,
    totalMessages,
    weeklyVolume,
    score,
    isGenuinelyQuiet,
    isGenuinelyLively,
  };
}

// ── runRebalancePass ──────────────────────────────────────────────────────

/**
 * Full engine pass over all resident groups in scope.
 *
 * For each group:
 *   1. Borough scope check (isBoroughInScope).
 *   2. scoreGroup() — reads memberActivity subcollection; passes
 *      group.lastMessageTime for the activity guards.
 *   3. Apply count + activity gate to determine action.
 *   4a. observeOnly == true  → writeObserveLog(), no further writes.
 *   4b. observeOnly == false → call sendRollupOffers() / sendSplitOffers()
 *       (injected as parameters; stubs until Pieces 3 & 4 are applied).
 *
 * Idempotent: offer de-dupe is enforced by per-member declinedRollups /
 * declinedSplits flags written by the accept/decline handlers (Piece 5).
 */
export async function runRebalancePass(
  db:               admin.firestore.Firestore,
  cfg:              RebalanceConfig,
  // Offer senders injected so this file compiles without Pieces 3 & 4.
  // Replaced with real implementations once those pieces land.
  sendRollupOffers: (db: admin.firestore.Firestore, group: GroupDoc, cfg: RebalanceConfig, score: ActivityScore) => Promise<number>,
  sendSplitOffers:  (db: admin.firestore.Firestore, group: GroupDoc, cfg: RebalanceConfig, score: ActivityScore) => Promise<number>
): Promise<void> {
  const now     = new Date();
  const runAt   = admin.firestore.Timestamp.fromDate(now);
  const qThresh = quietThreshold(cfg);
  const cThresh = crowdedThreshold(cfg);

  functions.logger.info(
    `[rebalance] Pass starting. observeOnly=${cfg.observeOnly} ` +
    `boroughMode=${cfg.boroughMode} ` +
    `FLOOR=${cfg.FLOOR} CEILING=${cfg.CEILING} HYSTERESIS=${cfg.HYSTERESIS} ` +
    `quietThresh=${qThresh.toFixed(1)} crowdedThresh=${cThresh.toFixed(1)} ` +
    `QUIET_SCORE_THRESHOLD=${cfg.QUIET_SCORE_THRESHOLD} ` +
    `LIVELY_SCORE_THRESHOLD=${cfg.LIVELY_SCORE_THRESHOLD}`
  );

  // Query all resident groups. Interest groups excluded at the query level.
  // Belt-and-suspenders: groupType check also applied inside the loop.
  const residentSnap = await db
    .collection("groups")
    .where("groupType", "==", "resident")
    .get();

  let processed  = 0;
  let outOfScope = 0;
  let skipped    = 0;
  let rollups    = 0;
  let splits     = 0;
  let noAction   = 0;

  for (const groupDocSnap of residentSnap.docs) {
    const d = groupDocSnap.data();

    // Belt-and-suspenders interest-group exclusion.
    if (d["groupType"] !== "resident") { skipped++; continue; }

    const borough = (d["borough"] as string | undefined) ?? "";

    // STEP 2: Borough scope check.
    if (!isBoroughInScope(cfg, borough)) { outOfScope++; continue; }

    const group: GroupDoc = {
      id:               groupDocSnap.id,
      name:             (d["name"]             as string                           | undefined) ?? "",
      borough,
      level:            (d["level"]            as string                           | undefined) ?? "borough",
      groupType:        (d["groupType"]        as string                           | undefined) ?? "resident",
      memberIds:        (d["memberIds"]        as string[]                         | undefined) ?? [],
      memberCount:      (d["memberCount"]      as number                           | undefined) ?? 0,
      lastMessageTime:  (d["lastMessageTime"]  as admin.firestore.Timestamp | undefined) ?? null,
      parentGroupId:    (d["parentGroupId"]    as string                           | undefined) ?? null,
      parentRegionName: (d["parentRegionName"] as string                           | undefined) ?? null,
      ward:             (d["ward"]             as string                           | undefined) ?? null,
      wardCode:         (d["wardCode"]         as string                           | undefined) ?? null,
      districtCode:     (d["districtCode"]     as string                           | undefined) ?? null,
      region:           (d["region"]           as string                           | undefined) ?? null,
    };

    // memberIds.length is the authoritative membership count.
    const memberCount = group.memberIds.length > 0
      ? group.memberIds.length
      : group.memberCount;

    // Score the group — pass lastMessageTime for the activity guards.
    const rawScore = await scoreGroup(db, group.id, cfg, now, group.lastMessageTime);
    const score: ActivityScore = { ...rawScore, memberCount };

    // ── Action decision ──────────────────────────────────────────────────
    // Count gate applied first; activity veto second.
    // ROLLUP: below quiet threshold AND genuinely quiet.
    // SPLIT:  above crowded threshold AND genuinely lively.
    // VETO:   never split a quiet group; never rollup a lively-but-small group.

    let action:    RebalanceLogEntry["action"] = "no_action";
    let reason     = "";
    let offerCount = 0;

    if (memberCount < qThresh && score.isGenuinelyQuiet) {
      action = "rollup_offer";
      reason =
        `memberCount=${memberCount} < quietThresh=${qThresh.toFixed(1)}, ` +
        `score=${score.score.toFixed(2)} < QUIET_SCORE_THRESHOLD=${cfg.QUIET_SCORE_THRESHOLD}, ` +
        `windowElapsed=true`;
    } else if (memberCount < qThresh && !score.isGenuinelyQuiet) {
      action = "no_action";
      reason =
        `memberCount=${memberCount} < quietThresh but score=${score.score.toFixed(2)} ` +
        `or windowElapsed=false — activity veto on rollup`;
    } else if (memberCount > cThresh && score.isGenuinelyLively) {
      action = "split_offer";
      reason =
        `memberCount=${memberCount} > crowdedThresh=${cThresh.toFixed(1)}, ` +
        `score=${score.score.toFixed(2)} > LIVELY_SCORE_THRESHOLD=${cfg.LIVELY_SCORE_THRESHOLD}, ` +
        `recentlyActive=true`;
    } else if (memberCount > cThresh && !score.isGenuinelyLively) {
      action = "no_action";
      reason =
        `memberCount=${memberCount} > crowdedThresh but score=${score.score.toFixed(2)} ` +
        `or recentlyActive=false — activity veto on split`;
    } else {
      reason =
        `memberCount=${memberCount} within thresholds ` +
        `[${qThresh.toFixed(1)}, ${cThresh.toFixed(1)}]`;
    }

    // ── observeOnly branch ───────────────────────────────────────────────
    if (cfg.observeOnly) {
      await writeObserveLog(db, {
        runAt,
        groupId:       group.id,
        groupName:     group.name,
        level:         group.level,
        borough:       group.borough,
        memberCount,
        activityScore: score.score,
        action,
        reason,
        offerCount:    0,   // no offers sent in observeOnly mode
        observeOnly:   true,
      });
      if (action !== "no_action") {
        functions.logger.info(
          `[rebalance][observeOnly] ${group.name}: ${action} — ${reason}`
        );
      }
      processed++;
      if      (action === "rollup_offer") rollups++;
      else if (action === "split_offer")  splits++;
      else                                noAction++;
      continue;
    }

    // ── Live branch — delegate to offer senders ──────────────────────────
    if (action === "rollup_offer") {
      offerCount = await sendRollupOffers(db, group, cfg, score);
      rollups++;
      functions.logger.info(
        `[rebalance] ROLLUP sent for "${group.name}": ${offerCount} offer(s). ${reason}`
      );
    } else if (action === "split_offer") {
      offerCount = await sendSplitOffers(db, group, cfg, score);
      splits++;
      functions.logger.info(
        `[rebalance] SPLIT sent for "${group.name}": ${offerCount} offer(s). ${reason}`
      );
    } else {
      noAction++;
    }

    // Suppress unused-variable warning on offerCount in the no_action path.
    void offerCount;
    processed++;
  }

  functions.logger.info(
    `[rebalance] Pass complete. processed=${processed} outOfScope=${outOfScope} ` +
    `skipped=${skipped} rollups=${rollups} splits=${splits} noAction=${noAction}`
  );
}
