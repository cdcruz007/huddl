// ═══════════════════════════════════════════════════════════════════════════════
// PRESENCE-REAL-1 — real presence via lastActiveAt heartbeat
// ═══════════════════════════════════════════════════════════════════════════════
//
// Design:
//   • TIMESTAMP, NOT BOOLEAN. A boolean leaves ghosts: force-quit, crash, or
//     lost signal and the user appears "Online" forever.  Presence is derived
//     as "lastActiveAt within the last 3 minutes", which is self-healing.
//
//   • Writes to users_public/{uid}, NOT users/{uid}.  users/{uid} is mirrored
//     to users_public by the syncPublicProfile Cloud Function on every write.
//     Writing the heartbeat to users/{uid} would fire that CF once per user
//     per heartbeat (one Firestore write per minute per active user, just for a
//     field that needs no processing).  Writing straight to users_public avoids
//     it — allowed by the PRESENCE-REAL-1 narrow update rule in firestore.rules.
//
//   • set-with-merge CREATE concern: if users_public/{uid} does not yet exist
//     when the first heartbeat fires, set() is a CREATE and the rule denies it
//     (create: if false remains in place).  In practice, syncPublicProfile
//     (Firebase users/{uid} onCreate trigger) creates users_public/{uid} at
//     signup, so the doc should always pre-exist.  The write is wrapped in
//     try/catch and failures are logged in debug mode and swallowed silently —
//     a missing heartbeat is acceptable; a thrown exception is not.
//
// Cost estimate (100 concurrent users, 30 min/day average foreground time):
//   heartbeatInterval = 90 s → 20 writes/user/30 min → 2,000 writes/day/100 users
//   (plus 100 writes at session start, ≈2,100 total/day/100 users)
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PresenceService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  // ── Constants ─────────────────────────────────────────────────────────────

  /// How often the heartbeat is written to Firestore.
  /// 90 s is the chosen cost/accuracy balance — do not shorten below 60 s.
  static const Duration heartbeatInterval = Duration(seconds: 90);

  /// A user whose lastActiveAt is within this window is considered online.
  static const Duration onlineThreshold = Duration(minutes: 3);

  // ── State ──────────────────────────────────────────────────────────────────
  Timer? _timer;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Start the presence heartbeat.
  ///
  /// Writes lastActiveAt immediately (so presence is updated the moment the
  /// app enters the foreground), then repeats every [heartbeatInterval].
  /// Safe to call multiple times — the previous timer is cancelled first.
  void start() {
    _timer?.cancel();
    _writeHeartbeat(); // immediate write on start
    _timer = Timer.periodic(heartbeatInterval, (_) => _writeHeartbeat());
  }

  /// Stop the presence heartbeat.
  ///
  /// Does NOT write anything to Firestore — presence expires naturally after
  /// [onlineThreshold], which is the entire point of a timestamp approach.
  /// Writing "offline" on stop would reintroduce the ghost problem for crashes
  /// and force-quits.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Derives online state from a raw Firestore lastActiveAt Timestamp.
  ///
  /// Returns false when [lastActiveAt] is null (field missing — doc predates
  /// PRESENCE-REAL-1 or user has never gone online since the feature shipped).
  /// Returns true when the timestamp is within [onlineThreshold] of now.
  static bool isOnlineFrom(Timestamp? lastActiveAt) {
    if (lastActiveAt == null) return false;
    final elapsed = DateTime.now().difference(lastActiveAt.toDate());
    return elapsed < onlineThreshold;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _writeHeartbeat() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users_public')
          .doc(uid)
          .set(
            {'lastActiveAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
    } catch (e) {
      // A failed heartbeat must never surface to the user or throw.
      // Log in debug mode only — a silently failing heartbeat is exactly the
      // class of bug this codebase keeps producing.
      if (kDebugMode) {
        debugPrint('[PresenceService] heartbeat write failed: $e');
      }
    }
  }
}
