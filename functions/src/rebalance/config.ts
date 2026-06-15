/**
 * rebalance/config.ts
 * ────────────────────
 * Firestore config doc reader and gating logic for the elastic rebalance engine.
 *
 * Firestore document: config/rebalance
 * Schema (all fields optional — defaults below are used when absent):
 *
 *   enabled:          boolean   — GLOBAL master switch. false = engine OFF everywhere.
 *                                 Launch state. Guaranteed instant kill-switch.
 *   observeOnly:      boolean   — true = run full analysis, log to rebalance_log,
 *                                 send NO offers, write NO membership changes.
 *   boroughMode:      "all" | "list"
 *                               — "all" = every borough in scope;
 *                                 "list" = only boroughs in enabledBoroughs.
 *   enabledBoroughs:  string[]  — used only when boroughMode == "list".
 *                                 Empty array = act on nothing.
 *   CEILING:          number    — member count above which a group is crowded.
 *   FLOOR:            number    — member count below which a group is quiet.
 *   HYSTERESIS:       number    — fractional buffer, e.g. 0.2 = ±20%.
 *   ACTIVE_WINDOW_DAYS: number  — days to look back for activity signals.
 *   SMOOTHING_WEEKS:  number    — rolling-average window in weeks.
 *
 * Gating order (strict — the global master MUST short-circuit before any
 * borough/scope logic):
 *   1. enabled == false  →  exit immediately, do nothing.
 *   2. enabled == true   →  determine scope from boroughMode / enabledBoroughs.
 *   3. observeOnly       →  full analysis + log, no offers, no membership writes.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

// ── Defaults (used when Firestore fields are absent) ──────────────────────

export const DEFAULT_CONFIG = {
  enabled:            false,   // OFF at launch — must be explicitly flipped
  observeOnly:        true,    // safe default: log only, never act
  boroughMode:        "list" as "all" | "list",
  enabledBoroughs:    [] as string[],
  CEILING:            180,
  FLOOR:              30,
  HYSTERESIS:         0.2,
  ACTIVE_WINDOW_DAYS: 30,
  SMOOTHING_WEEKS:       4,
  // Activity veto thresholds — tunable from the config doc during observe phase.
  // Lower QUIET_SCORE_THRESHOLD or raise LIVELY_SCORE_THRESHOLD to widen the
  // "no action" band and reduce offer noise during initial rollout.
  QUIET_SCORE_THRESHOLD:  0.5,   // msg/active-member/week; below = genuinely quiet
  LIVELY_SCORE_THRESHOLD: 2.0,   // msg/active-member/week; above = genuinely lively
};

export type RebalanceConfig = {
  enabled:            boolean;
  observeOnly:        boolean;
  boroughMode:        "all" | "list";
  enabledBoroughs:    string[];
  CEILING:            number;
  FLOOR:              number;
  HYSTERESIS:         number;
  ACTIVE_WINDOW_DAYS: number;
  SMOOTHING_WEEKS:       number;
  QUIET_SCORE_THRESHOLD:  number;   // msg/active-member/week below which → genuinely quiet
  LIVELY_SCORE_THRESHOLD: number;   // msg/active-member/week above which → genuinely lively
};

// ── Config reader ─────────────────────────────────────────────────────────

/**
 * Read config/rebalance from Firestore and merge with defaults.
 * Missing fields fall back to DEFAULT_CONFIG values — callers always
 * receive a fully-typed RebalanceConfig.
 *
 * A missing config doc is safe: DEFAULT_CONFIG.enabled = false means
 * the engine never runs without an explicit Firestore flip.
 */
export async function readConfig(
  db: admin.firestore.Firestore
): Promise<RebalanceConfig> {
  const snap = await db.collection("config").doc("rebalance").get();
  const raw  = snap.exists ? (snap.data() ?? {}) : {};

  return {
    enabled:            (raw["enabled"]            as boolean           | undefined) ?? DEFAULT_CONFIG.enabled,
    observeOnly:        (raw["observeOnly"]        as boolean           | undefined) ?? DEFAULT_CONFIG.observeOnly,
    boroughMode:        (raw["boroughMode"]        as "all" | "list"    | undefined) ?? DEFAULT_CONFIG.boroughMode,
    enabledBoroughs:    (raw["enabledBoroughs"]    as string[]          | undefined) ?? DEFAULT_CONFIG.enabledBoroughs,
    CEILING:            (raw["CEILING"]            as number            | undefined) ?? DEFAULT_CONFIG.CEILING,
    FLOOR:              (raw["FLOOR"]              as number            | undefined) ?? DEFAULT_CONFIG.FLOOR,
    HYSTERESIS:         (raw["HYSTERESIS"]         as number            | undefined) ?? DEFAULT_CONFIG.HYSTERESIS,
    ACTIVE_WINDOW_DAYS: (raw["ACTIVE_WINDOW_DAYS"] as number            | undefined) ?? DEFAULT_CONFIG.ACTIVE_WINDOW_DAYS,
    SMOOTHING_WEEKS:        (raw["SMOOTHING_WEEKS"]        as number | undefined) ?? DEFAULT_CONFIG.SMOOTHING_WEEKS,
    QUIET_SCORE_THRESHOLD:  (raw["QUIET_SCORE_THRESHOLD"]  as number | undefined) ?? DEFAULT_CONFIG.QUIET_SCORE_THRESHOLD,
    LIVELY_SCORE_THRESHOLD: (raw["LIVELY_SCORE_THRESHOLD"] as number | undefined) ?? DEFAULT_CONFIG.LIVELY_SCORE_THRESHOLD,
  };
}

// ── Gating helpers ────────────────────────────────────────────────────────

/**
 * STEP 1 — Global master gate.
 *
 * Returns true if the engine should proceed at all.
 * Returns false if enabled == false → caller MUST exit immediately without
 * reading any group docs, sending any offers, or writing anything.
 *
 * This is the guaranteed instant kill-switch. It MUST be the very first
 * check in every engine entry point, before any borough or scope logic.
 */
export function isEngineEnabled(cfg: RebalanceConfig): boolean {
  return cfg.enabled === true;
}

/**
 * STEP 2 — Scope filter (called only after isEngineEnabled() == true).
 *
 * Returns true if the given borough is in scope for this run.
 *
 * boroughMode == "all"  → every borough is in scope.
 * boroughMode == "list" → borough must appear in enabledBoroughs
 *                         (case-insensitive). Empty list → nothing in scope.
 */
export function isBoroughInScope(
  cfg:     RebalanceConfig,
  borough: string
): boolean {
  if (cfg.boroughMode === "all") return true;
  const lc = borough.toLowerCase();
  return cfg.enabledBoroughs.some((b) => b.toLowerCase() === lc);
}

// ── Hysteresis thresholds ─────────────────────────────────────────────────

/**
 * Crowded threshold: CEILING * (1 + HYSTERESIS).
 * A group must exceed this to trigger a split offer.
 * The buffer prevents flapping when membership hovers near CEILING.
 */
export function crowdedThreshold(cfg: RebalanceConfig): number {
  return cfg.CEILING * (1 + cfg.HYSTERESIS);
}

/**
 * Quiet threshold: FLOOR * (1 - HYSTERESIS).
 * A group must fall below this to trigger a rollup offer.
 * The buffer prevents flapping when membership hovers near FLOOR.
 */
export function quietThreshold(cfg: RebalanceConfig): number {
  return cfg.FLOOR * (1 - cfg.HYSTERESIS);
}

// ── observeOnly log writer ────────────────────────────────────────────────

export type RebalanceLogEntry = {
  runAt:         admin.firestore.Timestamp;
  groupId:       string;
  groupName:     string;
  level:         string;   // "borough" | "ward" | "region"
  borough:       string;
  memberCount:   number;
  activityScore: number;   // messages-per-active-member, SMOOTHING_WEEKS rolling avg
  action:        "rollup_offer" | "split_offer" | "no_action";
  reason:        string;   // human-readable explanation of decision
  offerCount:    number;   // how many offer notifications would be sent (0 for no_action)
  observeOnly:   true;     // always true — this collection is read-only audit trail
};

/**
 * Write one observeOnly log entry to rebalance_log/{auto-id}.
 *
 * Called in place of sending real offers when observeOnly == true.
 * The rebalance_log collection is the primary instrument for the
 * observeOnly → single-borough → wide rollout runbook.
 *
 * Errors are swallowed and logged — this must never block the engine
 * run or surface to end users.
 */
export async function writeObserveLog(
  db:    admin.firestore.Firestore,
  entry: RebalanceLogEntry
): Promise<void> {
  try {
    await db.collection("rebalance_log").add(entry);
  } catch (err) {
    functions.logger.error("[rebalance/config] writeObserveLog error:", err);
  }
}
