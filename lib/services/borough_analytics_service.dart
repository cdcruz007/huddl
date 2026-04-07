import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import 'borough_scope_guard.dart';

// =============================================================================
// BOROUGH ANALYTICS SERVICE  — STEP 12
//
// Tracks borough-scoped metrics for debug introspection, admin dashboards,
// and internal product analytics.
//
// Tracked events:
//   - Cross-borough blocks (feature, source borough, target borough)
//   - Borough migrations (old → new, timestamp)
//   - Feature usage per borough (groups joined, meetups created, DMs sent etc.)
//   - AI prompt borough injections (count by service)
//   - Cache hits / misses
//
// All data is persisted via BrowserStorage for offline access.
// Debug panel can be accessed from Profile → Settings → Borough Debug.
// =============================================================================

/// A single analytics event.
class BoroughAnalyticsEvent {
  final String type;
  final String? feature;
  final String? userBorough;
  final String? targetBorough;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  BoroughAnalyticsEvent({
    required this.type,
    this.feature,
    this.userBorough,
    this.targetBorough,
    DateTime? timestamp,
    this.metadata = const {},
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'type': type,
        'feature': feature,
        'userBorough': userBorough,
        'targetBorough': targetBorough,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };

  factory BoroughAnalyticsEvent.fromJson(Map<String, dynamic> json) =>
      BoroughAnalyticsEvent(
        type: json['type'] as String,
        feature: json['feature'] as String?,
        userBorough: json['userBorough'] as String?,
        targetBorough: json['targetBorough'] as String?,
        timestamp: DateTime.parse(json['timestamp'] as String),
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      );
}

class BoroughAnalyticsService {
  static final BoroughAnalyticsService _instance =
      BoroughAnalyticsService._internal();
  factory BoroughAnalyticsService() => _instance;
  BoroughAnalyticsService._internal();

  static const String _eventsKey = 'huddl_borough_analytics';
  static const String _countersKey = 'huddl_borough_counters';
  static const int _maxEvents = 200;

  final BoroughScopeGuard _guard = BoroughScopeGuard();

  List<BoroughAnalyticsEvent> _events = [];
  Map<String, int> _counters = {};
  bool _initialized = false;

  // ── Public getters ────────────────────────────────────────────────────────

  List<BoroughAnalyticsEvent> get events => List.unmodifiable(_events);
  Map<String, int> get counters => Map.unmodifiable(_counters);
  bool get isInitialized => _initialized;

  /// Count of cross-borough blocks recorded.
  int get crossBoroughBlocks => _counters['cross_borough_blocks'] ?? 0;

  /// Count of borough migrations.
  int get boroughMigrations => _counters['borough_migrations'] ?? 0;

  /// Total analytics events recorded.
  int get totalEvents => _events.length;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;

    final eventsJson = await BrowserStorage.getString(_eventsKey);
    if (eventsJson != null) {
      try {
        final list = json.decode(eventsJson) as List;
        _events = list
            .map((e) =>
                BoroughAnalyticsEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _events = [];
      }
    }

    final countersJson = await BrowserStorage.getString(_countersKey);
    if (countersJson != null) {
      try {
        final map = json.decode(countersJson) as Map<String, dynamic>;
        _counters = map.map((k, v) => MapEntry(k, v as int));
      } catch (_) {
        _counters = {};
      }
    }

    _initialized = true;
    _log('Loaded ${_events.length} events, ${_counters.length} counters');
  }

  // ── Track events ──────────────────────────────────────────────────────────

  /// Record a cross-borough block event.
  Future<void> trackCrossBoroughBlock({
    required HuddlFeature feature,
    String? targetBorough,
  }) async {
    await _record(BoroughAnalyticsEvent(
      type: 'cross_borough_block',
      feature: feature.name,
      userBorough: _guard.currentBorough,
      targetBorough: targetBorough,
    ));
    await _increment('cross_borough_blocks');
  }

  /// Record a borough migration event.
  Future<void> trackBoroughMigration({
    required String fromBorough,
    required String toBorough,
  }) async {
    await _record(BoroughAnalyticsEvent(
      type: 'borough_migration',
      userBorough: fromBorough,
      targetBorough: toBorough,
      metadata: {'direction': 'from_${fromBorough}_to_$toBorough'},
    ));
    await _increment('borough_migrations');
  }

  /// Record a feature usage event within the user's borough.
  Future<void> trackFeatureUsage({
    required String feature,
    Map<String, dynamic> metadata = const {},
  }) async {
    await _record(BoroughAnalyticsEvent(
      type: 'feature_usage',
      feature: feature,
      userBorough: _guard.currentBorough,
      metadata: metadata,
    ));
    await _increment('feature_$feature');
  }

  /// Record an AI borough context injection.
  Future<void> trackAiBoroughInjection({
    required String serviceName,
  }) async {
    await _increment('ai_borough_injection_$serviceName');
  }

  /// Record a cache hit or miss.
  Future<void> trackCacheEvent({required bool hit}) async {
    await _increment(hit ? 'cache_hits' : 'cache_misses');
  }

  // ── Debug summary ─────────────────────────────────────────────────────────

  /// Generate a human-readable debug summary.
  String debugSummary() {
    final sb = StringBuffer();
    sb.writeln('=== Borough Analytics Debug ===');
    sb.writeln('Current borough: ${_guard.currentBorough ?? "not set"}');
    sb.writeln('Total events: ${_events.length}');
    sb.writeln('Cross-borough blocks: $crossBoroughBlocks');
    sb.writeln('Borough migrations: $boroughMigrations');
    sb.writeln('');
    sb.writeln('Counters:');
    final sortedKeys = _counters.keys.toList()..sort();
    for (final key in sortedKeys) {
      sb.writeln('  $key: ${_counters[key]}');
    }
    if (_events.isNotEmpty) {
      sb.writeln('');
      sb.writeln('Recent events (last 10):');
      final recent = _events.length > 10
          ? _events.sublist(_events.length - 10)
          : _events;
      for (final e in recent.reversed) {
        sb.writeln(
            '  [${e.timestamp.toIso8601String().substring(0, 19)}] '
            '${e.type} — ${e.feature ?? "n/a"} '
            '(${e.userBorough ?? "?"} → ${e.targetBorough ?? "?"})');
      }
    }
    return sb.toString();
  }

  /// Returns all analytics data as a JSON-serialisable map for export.
  Map<String, dynamic> toExportMap() => {
        'events': _events.map((e) => e.toJson()).toList(),
        'counters': _counters,
        'currentBorough': _guard.currentBorough,
        'exportedAt': DateTime.now().toIso8601String(),
      };

  // ── Clear ─────────────────────────────────────────────────────────────────

  /// Clear all analytics data (GDPR-compliant).
  Future<void> clearAll() async {
    _events = [];
    _counters = {};
    _initialized = false;
    await Future.wait([
      BrowserStorage.remove(_eventsKey),
      BrowserStorage.remove(_countersKey),
    ]);
    _log('All analytics cleared');
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _record(BoroughAnalyticsEvent event) async {
    _events.add(event);
    // Trim to max events
    if (_events.length > _maxEvents) {
      _events = _events.sublist(_events.length - _maxEvents);
    }
    await _persist();
  }

  Future<void> _increment(String key) async {
    _counters[key] = (_counters[key] ?? 0) + 1;
    await _persistCounters();
  }

  Future<void> _persist() async {
    await BrowserStorage.setString(
        _eventsKey, json.encode(_events.map((e) => e.toJson()).toList()));
  }

  Future<void> _persistCounters() async {
    await BrowserStorage.setString(_countersKey, json.encode(_counters));
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('BoroughAnalyticsService: $message');
    }
  }
}
