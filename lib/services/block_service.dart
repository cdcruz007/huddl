import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'browser_storage.dart';

const String _blockedUsersKey = 'blocked_users_v1';

/// Service to manage blocked users.
///
/// Persistence strategy (dual-write):
///   1. BrowserStorage  — instant, offline-safe, in-memory cache.
///   2. Firestore       — users/{uid}/blocks/{targetUid}
///                        Loaded on initialize() so blocks survive new devices.
///
/// Firestore document schema:
///   users/{uid}/blocks/{targetUid} {
///     blockedAt : Timestamp
///     targetUid : String
///   }
///
/// Security rule (add to Firestore rules):
///   match /users/{uid}/blocks/{targetUid} {
///     allow read, write: if request.auth != null && request.auth.uid == uid;
///   }
class BlockService extends ChangeNotifier {
  static final BlockService _instance = BlockService._internal();
  factory BlockService() => _instance;
  BlockService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// In-memory set of blocked user IDs (source of truth for UI).
  final Set<String> _blockedUserIds = {};
  bool _initialized = false;

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Load block list from BrowserStorage first (instant), then merge any
  /// server-side blocks from Firestore so new-device installs are correct.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Step 1 — local cache (fast path, works offline)
    try {
      final raw = await BrowserStorage.getString(_blockedUsersKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _blockedUserIds.addAll(decoded.cast<String>());
      }
    } catch (_) {}

    // Step 2 — Firestore (authoritative, cross-device)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final snapshot = await _db
            .collection('users')
            .doc(uid)
            .collection('blocks')
            .get();
        for (final doc in snapshot.docs) {
          _blockedUserIds.add(doc.id); // doc.id == targetUid
        }
        // Persist merged set locally so next launch is fast even offline
        await _saveLocal();
        if (kDebugMode) debugPrint('[BlockService] Loaded ${snapshot.docs.length} block(s) from Firestore');
      } catch (e) {
        if (kDebugMode) debugPrint('[BlockService] Firestore load failed (offline?): $e');
        // Local cache is still usable — not fatal
      }
    }

    notifyListeners();
  }

  // ── Persistence helpers ─────────────────────────────────────────────────────

  Future<void> _saveLocal() async {
    try {
      await BrowserStorage.setString(
          _blockedUsersKey, json.encode(_blockedUserIds.toList()));
    } catch (_) {}
  }

  Future<bool> _writeToFirestore(String targetUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false; // not signed in → cannot persist
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('blocks')
          .doc(targetUid)
          .set({
        'targetUid': targetUid,
        'blockedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[BlockService] Firestore block write failed: $e');
      FirebaseCrashlytics.instance.recordError(e, StackTrace.current,
          reason: 'BlockService._writeToFirestore', fatal: false); // OBSERV-1
      return false;
    }
  }

  Future<void> _deleteFromFirestore(String targetUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('blocks')
          .doc(targetUid)
          .delete();
    } catch (e) {
      if (kDebugMode) debugPrint('[BlockService] Firestore unblock write failed: $e');
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Check if a user is blocked.
  bool isUserBlocked(String userId) => _blockedUserIds.contains(userId);

  /// Block a user. Optimistically updates UI, then confirms the authoritative
  /// Firestore write. Returns true if the block persisted; false if it failed
  /// (in which case the optimistic state is rolled back).
  Future<bool> blockUser(String userId) async {
    _blockedUserIds.add(userId); // optimistic
    notifyListeners();
    await _saveLocal();
    final ok = await _writeToFirestore(userId);
    if (!ok) {
      // Authoritative write failed — do NOT claim a block that won't be enforced.
      _blockedUserIds.remove(userId);
      await _saveLocal();
      notifyListeners();
    }
    return ok;
  }

  /// Unblock a user — removes from BrowserStorage + Firestore.
  Future<void> unblockUser(String userId) async {
    _blockedUserIds.remove(userId);
    notifyListeners();
    await _saveLocal();
    await _deleteFromFirestore(userId);
  }

  /// Toggle block state.
  /// Returns true  if the user is now BLOCKED (and the write succeeded).
  /// Returns false if the user is now UNBLOCKED, OR if a block write failed
  /// (caller must distinguish — check isUserBlocked() after the call, or
  ///  treat false-after-block as a failure requiring user feedback).
  Future<bool> toggleBlock(String userId) async {
    if (_blockedUserIds.contains(userId)) {
      await unblockUser(userId);
      return false;
    } else {
      final ok = await blockUser(userId);
      return ok; // true only if the block actually persisted
    }
  }

  /// Get all blocked user IDs.
  List<String> get blockedUserIds => _blockedUserIds.toList();

  /// Clear all blocked users — used for GDPR account deletion.
  Future<void> clearAll() async {
    final ids = List<String>.from(_blockedUserIds);
    _blockedUserIds.clear();
    notifyListeners();
    await _saveLocal();
    // Best-effort Firestore cleanup
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      for (final id in ids) {
        await _deleteFromFirestore(id);
      }
    }
  }
}
