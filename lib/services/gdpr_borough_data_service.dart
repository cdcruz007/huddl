import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import 'borough_scope_guard.dart';
import 'borough_cache_service.dart';
import 'borough_analytics_service.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

// =============================================================================
// GDPR BOROUGH DATA SERVICE  — STEP 13
//
// GDPR-compliant data isolation, export, and deletion for borough-scoped data.
//
// Responsibilities:
//   1. Catalogue all borough-scoped data stored on the device
//   2. Export borough-specific data in portable JSON format (Art. 20)
//   3. Delete all borough-specific data (Art. 17 — right to erasure)
//   4. Isolate borough data so cross-borough leakage is impossible
//   5. Provide audit trail of all borough data operations
//
// GDPR Articles covered:
//   - Art. 6:  Lawful basis — legitimate interest for community features
//   - Art. 15: Right of access — view all borough data
//   - Art. 17: Right to erasure — delete all borough data
//   - Art. 20: Data portability — export borough data as JSON
//   - Art. 25: Data protection by design — borough isolation by default
// =============================================================================

/// A catalogue entry describing one piece of stored borough data.
class BoroughDataEntry {
  final String category;
  final String key;
  final String description;
  final String? borough;
  final bool isBoroughScoped;

  const BoroughDataEntry({
    required this.category,
    required this.key,
    required this.description,
    this.borough,
    this.isBoroughScoped = true,
  });

  Map<String, dynamic> toJson() => {
        'category': category,
        'key': key,
        'description': description,
        'borough': borough,
        'isBoroughScoped': isBoroughScoped,
      };
}

class GdprBoroughDataService {
  static final GdprBoroughDataService _instance =
      GdprBoroughDataService._internal();
  factory GdprBoroughDataService() => _instance;
  GdprBoroughDataService._internal();

  static const String _auditKey = 'huddl_gdpr_borough_audit';

  final BoroughScopeGuard _guard = BoroughScopeGuard();
  final BoroughCacheService _cache = BoroughCacheService();
  final BoroughAnalyticsService _analytics = BoroughAnalyticsService();
  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcodeService = PostcodeService();

  // ── Data catalogue ────────────────────────────────────────────────────────

  /// Returns a list of all borough-scoped data entries stored on the device.
  Future<List<BoroughDataEntry>> catalogueBoroughData() async {
    await _cache.initialize();
    final borough = _guard.currentBorough ?? 'Unknown';
    final entries = <BoroughDataEntry>[];

    // 1. Borough cache data
    entries.add(BoroughDataEntry(
      category: 'Borough Cache',
      key: 'cached_borough',
      description: 'Your resolved borough name: ${_cache.cachedBorough ?? "none"}',
      borough: borough,
    ));
    entries.add(BoroughDataEntry(
      category: 'Borough Cache',
      key: 'cached_postcode',
      description: 'Postcode used for resolution: ${_cache.cachedPostcode ?? "none"}',
      borough: borough,
    ));
    if (_cache.previousBorough != null) {
      entries.add(BoroughDataEntry(
        category: 'Borough Cache',
        key: 'previous_borough',
        description: 'Previous borough: ${_cache.previousBorough}',
        borough: _cache.previousBorough,
      ));
    }

    // 2. Borough analytics
    entries.add(BoroughDataEntry(
      category: 'Borough Analytics',
      key: 'analytics_events',
      description: '${_analytics.totalEvents} analytics events recorded',
      borough: borough,
    ));
    entries.add(BoroughDataEntry(
      category: 'Borough Analytics',
      key: 'analytics_counters',
      description: '${_analytics.counters.length} counter categories',
      borough: borough,
    ));

    // 3. Onboarding data (borough-scoped portion)
    entries.add(BoroughDataEntry(
      category: 'Onboarding',
      key: 'user_postcode',
      description: 'Stored postcode: ${_onboarding.postcode ?? "none"}',
      borough: borough,
    ));

    // 4. Borough-scoped storage keys
    final boroughKeys = await _findBoroughScopedKeys();
    for (final key in boroughKeys) {
      entries.add(BoroughDataEntry(
        category: 'Local Storage',
        key: key,
        description: 'Borough-scoped preference/data',
        borough: borough,
      ));
    }

    return entries;
  }

  // ── Export (GDPR Art. 20) ─────────────────────────────────────────────────

  /// Export all borough-scoped data as a JSON map.
  /// This is appended to the main GDPR export.
  Future<Map<String, dynamic>> exportBoroughData() async {
    await _cache.initialize();
    await _analytics.initialize();

    final borough = _guard.currentBorough;
    final postcode = _onboarding.postcode;

    return {
      'gdpr_export_version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'borough_context': {
        'current_borough': borough,
        'postcode': postcode,
        'resolved_borough':
            postcode != null ? _postcodeService.getBoroughFromPostcode(postcode) : null,
        'previous_borough': _cache.previousBorough,
      },
      'borough_cache': _cache.toExportMap(),
      'borough_analytics': _analytics.toExportMap(),
      'borough_scope_rules': {
        'borough_only_features': HuddlFeature.values
            .where((f) => BoroughScopeGuard.isBoroughOnly(f))
            .map((f) => f.name)
            .toList(),
        'uk_wide_features': HuddlFeature.values
            .where((f) => BoroughScopeGuard.isUkWide(f))
            .map((f) => f.name)
            .toList(),
        'borough_aware_features': HuddlFeature.values
            .where((f) =>
                BoroughScopeGuard.scopeOf(f) == FeatureScope.boroughAware)
            .map((f) => f.name)
            .toList(),
      },
      'data_isolation_statement':
          'All borough-only features (chat, DMs, groups, meetups, marketplace, '
              'matchmaker) are restricted to your home borough ($borough). '
              'Cross-borough access is blocked by BoroughScopeGuard. '
              'Events are the only UK-wide feature.',
    };
  }

  /// Format the export as human-readable text for the GDPR export sheet.
  Future<String> exportAsText() async {
    final data = await exportBoroughData();
    final buffer = StringBuffer();
    buffer.writeln('');
    buffer.writeln('--- BOROUGH DATA (GDPR Art. 20) ---');
    buffer.writeln('  Current borough: ${data['borough_context']['current_borough'] ?? 'Not set'}');
    buffer.writeln('  Postcode: ${data['borough_context']['postcode'] ?? 'Not set'}');
    buffer.writeln('  Previous borough: ${data['borough_context']['previous_borough'] ?? 'None'}');
    buffer.writeln('');
    buffer.writeln('  Borough-only features: ${(data['borough_scope_rules']['borough_only_features'] as List).join(', ')}');
    buffer.writeln('  UK-wide features: ${(data['borough_scope_rules']['uk_wide_features'] as List).join(', ')}');
    buffer.writeln('');
    final analytics = data['borough_analytics'] as Map<String, dynamic>;
    final counters = analytics['counters'] as Map<String, dynamic>? ?? {};
    if (counters.isNotEmpty) {
      buffer.writeln('  Analytics counters:');
      for (final entry in counters.entries) {
        buffer.writeln('    ${entry.key}: ${entry.value}');
      }
    }
    buffer.writeln('');
    buffer.writeln('  Data isolation: ${data['data_isolation_statement']}');
    return buffer.toString();
  }

  // ── Deletion (GDPR Art. 17) ───────────────────────────────────────────────

  /// Delete all borough-scoped data from the device.
  /// Called during account deletion or explicit GDPR erasure request.
  ///
  /// GDPR-LOCAL-2: audit entry records a non-reversible boroughHash (first
  /// 8 hex chars of SHA-256) instead of the plaintext borough value, so the
  /// audit trail proves erasure occurred and is internally correlatable
  /// without retaining the identifying borough name post-deletion.
  Future<void> deleteAllBoroughData() async {
    // Collect keys BEFORE deletion so the count is accurate in the audit entry.
    final boroughKeys = await _findBoroughScopedKeys();

    // Audit BEFORE wiping — records proof of erasure without plaintext borough.
    // boroughHash: SHA-256(borough)[0..7] — correlatable, not reversible.
    await _recordAudit('borough_data_deletion', {
      'boroughHash': _shortHash(_guard.currentBorough),
      'keysRemoved': boroughKeys.length,
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Clear borough cache
    await _cache.clearAll();

    // Clear borough analytics
    await _analytics.clearAll();

    // Clear borough-scoped BrowserStorage keys
    for (final key in boroughKeys) {
      await BrowserStorage.remove(key);
    }

    _log('All borough-scoped data deleted (GDPR Art. 17)');
  }

  // ── Audit trail ───────────────────────────────────────────────────────────

  /// Record a GDPR audit event.
  Future<void> _recordAudit(
      String action, Map<String, dynamic> details) async {
    final audits = await _loadAuditTrail();
    audits.add({
      'action': action,
      'details': details,
      'timestamp': DateTime.now().toIso8601String(),
    });
    // Keep last 50 audit entries
    final trimmed = audits.length > 50 ? audits.sublist(audits.length - 50) : audits;
    await BrowserStorage.setString(_auditKey, json.encode(trimmed));
  }

  /// Load the GDPR audit trail.
  Future<List<Map<String, dynamic>>> _loadAuditTrail() async {
    final raw = await BrowserStorage.getString(_auditKey);
    if (raw == null) return [];
    try {
      final list = json.decode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Get the audit trail for display.
  Future<List<Map<String, dynamic>>> getAuditTrail() => _loadAuditTrail();

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns every BrowserStorage key that is currently populated and owned
  /// by a borough-scoped service.
  ///
  /// GDPR-LOCAL-1: Uses the DECLARED key lists from each service rather than
  /// prefix × suffix guessing, so erasure is exhaustive and self-maintaining.
  /// Any new key added to a service's boroughStorageKeys list is automatically
  /// covered here with no further changes required.
  ///
  /// Dead-guess removal: the old implementation also probed
  /// 'huddl_learning_borough_*' and 'huddl_migration_*' prefixes. A full
  /// codebase sweep found ZERO writers for either prefix outside this file —
  /// they were never real keys. Both prefixes are dropped.
  Future<List<String>> _findBoroughScopedKeys() async {
    // Union of all declared borough-scoped storage keys.
    final declared = <String>{
      ...BoroughCacheService.boroughStorageKeys,
      ...BoroughAnalyticsService.boroughStorageKeys,
    };

    // Return only keys that actually have a stored value (present on device).
    final present = <String>[];
    for (final key in declared) {
      if (await BrowserStorage.getString(key) != null) present.add(key);
    }
    return present;
  }

  /// Returns the first 8 hex characters of the SHA-256 digest of [value].
  ///
  /// Used by the erasure audit log (GDPR-LOCAL-2) to record a correlatable
  /// but non-reversible token in place of the plaintext borough name.
  /// 8 hex chars = 32 bits — sufficient for internal correlation across audit
  /// entries; not sufficient to reverse the original value.
  static String _shortHash(String? value) {
    if (value == null || value.isEmpty) return 'unknown';
    final digest = sha256.convert(utf8.encode(value));
    return digest.toString().substring(0, 8);
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('GdprBoroughDataService: $message');
    }
  }
}
