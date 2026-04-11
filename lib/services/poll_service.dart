import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../screens/groups/poll_detail_screen.dart';
import 'browser_storage.dart';

/// Singleton service that persists polls per group to BrowserStorage.
///
/// Key format: `polls_v1_<groupId>`
///
/// Both [group_chat_screen] and [group_polls_screen] read/write through
/// this service so they always see the same data.
class PollService extends ChangeNotifier {
  static final PollService _instance = PollService._internal();
  factory PollService() => _instance;
  PollService._internal();

  // In-memory cache: groupId → poll list
  final Map<String, List<ActivePoll>> _cache = {};

  static String _storageKey(String groupId) => 'polls_v1_$groupId';

  // ── Public API ──────────────────────────────────────────────────────────

  /// Load polls for a group (reads from storage the first time).
  Future<List<ActivePoll>> loadPolls(String groupId) async {
    if (_cache.containsKey(groupId)) return _cache[groupId]!;
    await _load(groupId);
    return _cache[groupId]!;
  }

  /// Live list for a group (empty until [loadPolls] is called).
  List<ActivePoll> getPolls(String groupId) => _cache[groupId] ?? [];

  /// Add a new poll and persist.
  Future<void> addPoll(String groupId, ActivePoll poll) async {
    _ensureCache(groupId);
    _cache[groupId]!.insert(0, poll);
    await _persist(groupId);
    notifyListeners();
  }

  /// Replace the entire poll list for a group and persist.
  /// Call this after any in-place mutation (vote, pin, delete).
  Future<void> savePolls(String groupId, List<ActivePoll> polls) async {
    _cache[groupId] = polls;
    await _persist(groupId);
    notifyListeners();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  void _ensureCache(String groupId) {
    _cache.putIfAbsent(groupId, () => []);
  }

  Future<void> _load(String groupId) async {
    _ensureCache(groupId);
    try {
      final raw = await BrowserStorage.getString(_storageKey(groupId));
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _cache[groupId] = decoded
            .map((j) => ActivePoll.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PollService._load error: $e');
      _cache[groupId] = [];
    }
  }

  Future<void> _persist(String groupId) async {
    try {
      final list = _cache[groupId] ?? [];
      final encoded = json.encode(list.map((p) => p.toJson()).toList());
      await BrowserStorage.setString(_storageKey(groupId), encoded);
    } catch (e) {
      if (kDebugMode) debugPrint('PollService._persist error: $e');
    }
  }
}
