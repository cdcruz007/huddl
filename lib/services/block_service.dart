import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';

const String _blockedUsersKey = 'blocked_users_v1';

/// Service to manage blocked users. Persists block state across sessions.
class BlockService extends ChangeNotifier {
  static final BlockService _instance = BlockService._internal();
  factory BlockService() => _instance;
  BlockService._internal();

  /// Set of blocked user IDs
  final Set<String> _blockedUserIds = {};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final raw = await BrowserStorage.getString(_blockedUsersKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _blockedUserIds.addAll(decoded.cast<String>());
      }
    } catch (_) {
      // silently fail
    }
    _initialized = true;
  }

  Future<void> _save() async {
    try {
      final encoded = json.encode(_blockedUserIds.toList());
      await BrowserStorage.setString(_blockedUsersKey, encoded);
    } catch (_) {
      // silently fail
    }
  }

  /// Check if a user is blocked.
  bool isUserBlocked(String userId) {
    return _blockedUserIds.contains(userId);
  }

  /// Block a user.
  Future<void> blockUser(String userId) async {
    _blockedUserIds.add(userId);
    await _save();
    notifyListeners();
  }

  /// Unblock a user.
  Future<void> unblockUser(String userId) async {
    _blockedUserIds.remove(userId);
    await _save();
    notifyListeners();
  }

  /// Toggle block state.
  Future<bool> toggleBlock(String userId) async {
    if (_blockedUserIds.contains(userId)) {
      await unblockUser(userId);
      return false;
    } else {
      await blockUser(userId);
      return true;
    }
  }

  /// Get all blocked user IDs.
  List<String> get blockedUserIds => _blockedUserIds.toList();
}
