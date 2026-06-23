import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import 'clearable_user_state.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

// =============================================================================
// BOROUGH CACHE SERVICE  — STEP 11
//
// Provides persistent offline caching for borough-related data so the app
// remains functional even when the network is unavailable or postcode
// resolution is slow.
//
// Cached items:
//   1. Resolved borough name (from postcode)
//   2. Borough resolution timestamp
//   3. Previous borough (for migration detection)
//   4. Borough member count (approximate, for UI hints)
//   5. Last known borough directory snapshot
//
// Cache invalidation:
//   - On postcode change → clear and re-resolve
//   - On explicit refresh → re-resolve and update timestamp
//   - TTL: 24 hours for borough directory, indefinite for resolved name
// =============================================================================

class BoroughCacheService implements ClearableUserState {
  static final BoroughCacheService _instance = BoroughCacheService._internal();
  factory BoroughCacheService() => _instance;
  BoroughCacheService._internal() {
    UserStateRegistry.register(this);
  }

  static const String _keyBorough = 'huddl_borough_cached';
  static const String _keyPostcode = 'huddl_borough_postcode';
  static const String _keyTimestamp = 'huddl_borough_ts';
  static const String _keyPrevBorough = 'huddl_borough_prev';
  static const String _keyMemberCount = 'huddl_borough_members';
  static const String _keyDirectory = 'huddl_borough_directory';
  static const String _keyDirTimestamp = 'huddl_borough_dir_ts';

  /// All BrowserStorage keys owned by this service.
  ///
  /// GDPR-LOCAL-1: consumed by GdprBoroughDataService._findBoroughScopedKeys
  /// to guarantee exhaustive erasure (Art. 17). Add any new key here the
  /// moment it is declared above — the erasure path is then automatically
  /// complete without further changes to the GDPR service.
  static const List<String> boroughStorageKeys = [
    _keyBorough,
    _keyPostcode,
    _keyTimestamp,
    _keyPrevBorough,
    _keyMemberCount,
    _keyDirectory,
    _keyDirTimestamp,
  ];

  final PostcodeService _postcodeService = PostcodeService();
  final OnboardingDataService _onboarding = OnboardingDataService();

  // In-memory cache (populated from storage on init)
  String? _cachedBorough;
  String? _cachedPostcode;
  String? _previousBorough;
  int _memberCount = 0;
  DateTime? _resolvedAt;
  Map<String, dynamic>? _directory;
  bool _initialized = false;

  // ── Public getters ────────────────────────────────────────────────────────

  /// The cached borough name, or null if not yet resolved.
  String? get cachedBorough => _cachedBorough;

  /// The postcode that was used to resolve the cached borough.
  String? get cachedPostcode => _cachedPostcode;

  /// The previous borough (set after a borough change/migration).
  String? get previousBorough => _previousBorough;

  /// Approximate member count for the cached borough.
  int get memberCount => _memberCount;

  /// When the borough was last resolved.
  DateTime? get resolvedAt => _resolvedAt;

  /// True if cache has been loaded from storage.
  bool get isInitialized => _initialized;

  /// True if a cached borough is available (even offline).
  bool get hasCachedBorough =>
      _cachedBorough != null && _cachedBorough!.isNotEmpty;

  /// Cached borough directory (parks, libraries, cafes etc).
  Map<String, dynamic>? get directory => _directory;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Load cached borough data from persistent storage.
  Future<void> initialize() async {
    if (_initialized) return;

    _cachedBorough = await BrowserStorage.getString(_keyBorough);
    _cachedPostcode = await BrowserStorage.getString(_keyPostcode);
    _previousBorough = await BrowserStorage.getString(_keyPrevBorough);

    final tsStr = await BrowserStorage.getString(_keyTimestamp);
    if (tsStr != null) _resolvedAt = DateTime.tryParse(tsStr);

    final countStr = await BrowserStorage.getString(_keyMemberCount);
    if (countStr != null) _memberCount = int.tryParse(countStr) ?? 0;

    final dirJson = await BrowserStorage.getString(_keyDirectory);
    if (dirJson != null) {
      try {
        _directory = json.decode(dirJson) as Map<String, dynamic>;
      } catch (_) {
        _directory = null;
      }
    }

    _initialized = true;
    _log('Loaded cache: borough=$_cachedBorough, '
        'postcode=$_cachedPostcode, prev=$_previousBorough');
  }

  // ── Resolution & refresh ──────────────────────────────────────────────────

  /// Resolve the user's borough from their onboarding postcode and cache it.
  /// Returns the resolved borough name or the cached value if resolution fails.
  Future<String?> resolveAndCache() async {
    await _onboarding.initialize();
    final pc = _onboarding.postcode;
    if (pc == null || pc.isEmpty) return _cachedBorough;

    final resolved = _postcodeService.getBoroughFromPostcode(pc);
    if (resolved == null || resolved.isEmpty) return _cachedBorough;

    // Detect borough change
    if (_cachedBorough != null &&
        _cachedBorough!.isNotEmpty &&
        _cachedBorough!.toLowerCase() != resolved.toLowerCase()) {
      _previousBorough = _cachedBorough;
      await BrowserStorage.setString(_keyPrevBorough, _cachedBorough!);
      _log('Borough changed: $_cachedBorough → $resolved');
    }

    _cachedBorough = resolved;
    _cachedPostcode = pc;
    _resolvedAt = DateTime.now();

    await Future.wait([
      BrowserStorage.setString(_keyBorough, resolved),
      BrowserStorage.setString(_keyPostcode, pc),
      BrowserStorage.setString(
          _keyTimestamp, _resolvedAt!.toIso8601String()),
    ]);

    _log('Cached borough: $resolved (from $pc)');
    return resolved;
  }

  /// Update the cached member count for the current borough.
  Future<void> updateMemberCount(int count) async {
    _memberCount = count;
    await BrowserStorage.setString(_keyMemberCount, count.toString());
  }

  /// Cache a borough directory snapshot (parks, libraries, cafes etc).
  Future<void> cacheDirectory(Map<String, dynamic> dir) async {
    _directory = dir;
    await BrowserStorage.setString(_keyDirectory, json.encode(dir));
    await BrowserStorage.setString(
        _keyDirTimestamp, DateTime.now().toIso8601String());
  }

  /// Returns true if the directory cache is stale (> 24 hours).
  Future<bool> isDirectoryStale() async {
    final tsStr = await BrowserStorage.getString(_keyDirTimestamp);
    if (tsStr == null) return true;
    final ts = DateTime.tryParse(tsStr);
    if (ts == null) return true;
    return DateTime.now().difference(ts).inHours > 24;
  }

  // ── Clear on logout / account deletion ────────────────────────────────────

  /// Clear all cached borough data (GDPR-compliant).
  Future<void> clearAll() async {
    _cachedBorough = null;
    _cachedPostcode = null;
    _previousBorough = null;
    _memberCount = 0;
    _resolvedAt = null;
    _directory = null;
    _initialized = false;

    await Future.wait([
      BrowserStorage.remove(_keyBorough),
      BrowserStorage.remove(_keyPostcode),
      BrowserStorage.remove(_keyTimestamp),
      BrowserStorage.remove(_keyPrevBorough),
      BrowserStorage.remove(_keyMemberCount),
      BrowserStorage.remove(_keyDirectory),
      BrowserStorage.remove(_keyDirTimestamp),
    ]);

    _log('All borough cache cleared');
  }

  /// Clear only the previous borough marker (after migration is complete).
  Future<void> clearPreviousBorough() async {
    _previousBorough = null;
    await BrowserStorage.remove(_keyPrevBorough);
  }

  // ── Debug / export ────────────────────────────────────────────────────────

  /// Returns all cached borough data as a JSON-serialisable map.
  /// Used by GDPR export and debug panel.
  Map<String, dynamic> toExportMap() => {
        'cachedBorough': _cachedBorough,
        'cachedPostcode': _cachedPostcode,
        'previousBorough': _previousBorough,
        'memberCount': _memberCount,
        'resolvedAt': _resolvedAt?.toIso8601String(),
        'hasDirectory': _directory != null,
      };

  // ── Logging ───────────────────────────────────────────────────────────────

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('BoroughCacheService: $message');
    }
  }
  /// [ClearableUserState] — clears resolved-borough user keys on sign-out.
  /// PRESERVES _keyDirectory + _keyDirTimestamp (geographic data, not user data).
  @override
  Future<void> clearUserState() async {
    _cachedBorough = null;
    _cachedPostcode = null;
    _previousBorough = null;
    await BrowserStorage.remove(_keyBorough);
    await BrowserStorage.remove(_keyPostcode);
    await BrowserStorage.remove(_keyTimestamp);
    await BrowserStorage.remove(_keyPrevBorough);
    await BrowserStorage.remove(_keyMemberCount);
    // _keyDirectory + _keyDirTimestamp intentionally preserved.
  }

}
