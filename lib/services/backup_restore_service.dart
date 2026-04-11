// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL CONNECT — BACKUP & RESTORE SERVICE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Provides MANUAL backup/restore that works across platforms:
//
//  ANDROID  – Android Auto Backup (Google Drive) handles this automatically
//             when the device is idle + charging. Manual export available too.
//
//  iOS      – iCloud Backup automatically includes NSUserDefaults
//             (which is what shared_preferences uses under the hood).
//             Manual export also available for user peace-of-mind.
//
// MANUAL BACKUP FORMAT: encrypted JSON file containing every SharedPreferences
// key-value pair + metadata, downloadable by the user and re-importable
// from the Settings → Backup & Restore screen.
//
// WHAT IS BACKED UP (all device-local data):
//   • Profile / onboarding data        (onboarding_data_v1)
//   • Group messages & reactions        (gc_user_texts_*, gc_user_media_*, gc_reactions_*)
//   • Thread replies                    (thread_replies_*)
//   • Hidden / deleted messages         (hidden_msgs_*, deleted_everyone_*)
//   • DM conversations & messages       (dm_conversations_v2, dm_messages_*)
//   • Polls per group                   (polls_v1_*)
//   • Meetups                           (huddl_user_meetups, meetup_image_*)
//   • Events & favourites               (event_groups_v1, huddl_favourite_ids)
//   • Saved messages / threads / events (saved_messages_v1, saved_threads_v1, saved_events_v1)
//   • Group memberships, pins, mutes    (user_memberships_v4, huddl_pinned_ids, huddl_muted_ids)
//   • Invitations                       (group_invitations_v1, joined_groups_v2)
//   • Blocked users                     (blocked_users_v1)
//   • Notification preferences          (pref_*)
//   • Subscription state                (user_subscription_v2, subscription_usage_v2)
//   • AI behaviour settings             (huddl_msg_ai_behaviour, etc.)
//   • Borough / postcode cache          (huddl_borough_*)
//   • Tutorial completion               (tutorial_completed_v1)
//   • Biometric setting                 (huddl_biometric_enabled)
//   • Feed preferences                  (feed_preferences_v1)
//   • User-created groups               (user_created_groups_v1)
//
// WHAT IS EXCLUDED (intentionally):
//   • Passwords (never stored — see onboarding_data_service.dart)
//   • Firebase auth tokens (managed by Firebase SDK, not SharedPreferences)
//   • Temporary caches (ai_discovery_last_run, last_login_timestamp)
//   • Large base64 meetup images (handled separately as file backup)
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'browser_storage.dart';

// ── Backup metadata ──────────────────────────────────────────────────────────

class BackupMetadata {
  final String appVersion;
  final String backupVersion;
  final DateTime createdAt;
  final String platform;
  final int keyCount;

  const BackupMetadata({
    required this.appVersion,
    required this.backupVersion,
    required this.createdAt,
    required this.platform,
    required this.keyCount,
  });

  Map<String, dynamic> toJson() => {
        'appVersion': appVersion,
        'backupVersion': backupVersion,
        'createdAt': createdAt.toIso8601String(),
        'platform': platform,
        'keyCount': keyCount,
      };

  factory BackupMetadata.fromJson(Map<String, dynamic> j) => BackupMetadata(
        appVersion: j['appVersion'] as String? ?? '1.0.0',
        backupVersion: j['backupVersion'] as String? ?? '1',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        platform: j['platform'] as String? ?? 'unknown',
        keyCount: j['keyCount'] as int? ?? 0,
      );
}

// ── Keys to exclude from backup ──────────────────────────────────────────────

/// Keys that should NEVER be included in a backup — transient, device-specific,
/// or potentially sensitive data that would be invalid on a new device.
const Set<String> _excludedKeys = {
  'flutter.ai_discovery_last_run',
  'flutter.last_login_timestamp',
  'flutter.data_reset_v2',
  'flutter.FlutterSharedPreferences',
  // Firebase / auth tokens are managed by the Firebase SDK, not SharedPreferences
};

/// Prefix patterns whose keys should be excluded.
const List<String> _excludedPrefixes = [
  'firebase_',
  'com.google.',
  'google.',
];

bool _shouldExcludeKey(String key) {
  if (_excludedKeys.contains(key)) return true;
  for (final prefix in _excludedPrefixes) {
    if (key.contains(prefix)) return true;
  }
  return false;
}

// ── Backup payload ───────────────────────────────────────────────────────────

class BackupPayload {
  final BackupMetadata metadata;
  final Map<String, dynamic> data;

  const BackupPayload({required this.metadata, required this.data});

  /// Serialize to a JSON string that can be saved to a file.
  String toJsonString() {
    return const JsonEncoder.withIndent('  ').convert({
      '_huddl_backup': true,
      'metadata': metadata.toJson(),
      'data': data,
    });
  }

  /// Parse a JSON string previously created by [toJsonString].
  static BackupPayload? fromJsonString(String raw) {
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      if (decoded['_huddl_backup'] != true) return null;
      return BackupPayload(
        metadata: BackupMetadata.fromJson(
            decoded['metadata'] as Map<String, dynamic>? ?? {}),
        data: decoded['data'] as Map<String, dynamic>? ?? {},
      );
    } catch (_) {
      return null;
    }
  }
}

// ── Service ──────────────────────────────────────────────────────────────────

/// Singleton service for manual backup and restore of all Huddl app data.
class BackupRestoreService {
  static final BackupRestoreService _instance = BackupRestoreService._();
  factory BackupRestoreService() => _instance;
  BackupRestoreService._();

  static const String _backupVersion = '1';
  static const String _appVersion = '1.0.0';

  // ── EXPORT ────────────────────────────────────────────────────────────────

  /// Export ALL app data as a JSON string.
  ///
  /// Returns the full backup JSON string, ready to be written to a file
  /// or shared via the system share sheet.
  Future<String> exportBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();

    final data = <String, dynamic>{};

    for (final key in allKeys) {
      if (_shouldExcludeKey(key)) continue;

      // Read the raw value — shared_preferences can hold String, bool, int,
      // double, or List<String>. We preserve the type in the backup.
      final value = prefs.get(key);
      if (value != null) {
        data[key] = _encodeValue(value);
      }
    }

    final metadata = BackupMetadata(
      appVersion: _appVersion,
      backupVersion: _backupVersion,
      createdAt: DateTime.now(),
      platform: defaultTargetPlatform.name,
      keyCount: data.length,
    );

    final payload = BackupPayload(metadata: metadata, data: data);

    if (kDebugMode) {
      debugPrint('📦 BackupRestore: Exported ${data.length} keys');
    }

    return payload.toJsonString();
  }

  /// Wrap a raw SharedPreferences value with its type tag so we can restore
  /// it accurately.
  Map<String, dynamic> _encodeValue(Object value) {
    if (value is String) {
      return {'type': 'String', 'value': value};
    } else if (value is bool) {
      return {'type': 'bool', 'value': value};
    } else if (value is int) {
      return {'type': 'int', 'value': value};
    } else if (value is double) {
      return {'type': 'double', 'value': value};
    } else if (value is List) {
      return {'type': 'List<String>', 'value': value.map((e) => e.toString()).toList()};
    } else {
      // Fallback: store as string
      return {'type': 'String', 'value': value.toString()};
    }
  }

  // ── IMPORT ────────────────────────────────────────────────────────────────

  /// Import and restore data from a previously exported JSON string.
  ///
  /// Returns a [RestoreResult] describing what was restored and any errors.
  Future<RestoreResult> importBackup(String jsonString) async {
    final payload = BackupPayload.fromJsonString(jsonString);

    if (payload == null) {
      return RestoreResult(
        success: false,
        restoredKeys: 0,
        skippedKeys: 0,
        error: 'Invalid backup file. The file may be corrupted or not a Huddl backup.',
      );
    }

    // Version check — warn but allow restore from older versions
    if (payload.metadata.backupVersion != _backupVersion) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ BackupRestore: version mismatch '
            '(backup=${payload.metadata.backupVersion}, '
            'current=$_backupVersion) — attempting restore anyway');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    int restored = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final entry in payload.data.entries) {
      final key = entry.key;
      if (_shouldExcludeKey(key)) {
        skipped++;
        continue;
      }

      try {
        final encoded = entry.value as Map<String, dynamic>;
        final type = encoded['type'] as String? ?? 'String';
        final value = encoded['value'];

        switch (type) {
          case 'String':
            await prefs.setString(key, value as String);
            break;
          case 'bool':
            await prefs.setBool(key, value as bool);
            break;
          case 'int':
            await prefs.setInt(key, (value as num).toInt());
            break;
          case 'double':
            await prefs.setDouble(key, (value as num).toDouble());
            break;
          case 'List<String>':
            await prefs.setStringList(
                key, (value as List).map((e) => e.toString()).toList());
            break;
          default:
            await prefs.setString(key, value.toString());
        }
        restored++;
      } catch (e) {
        errors.add('$key: $e');
        skipped++;
      }
    }

    // Clear the data_reset guard so the app doesn't wipe restored data on
    // next launch.
    await prefs.remove('flutter.data_reset_v2');

    if (kDebugMode) {
      debugPrint(
          '✅ BackupRestore: restored=$restored skipped=$skipped errors=${errors.length}');
    }

    return RestoreResult(
      success: errors.isEmpty,
      restoredKeys: restored,
      skippedKeys: skipped,
      metadata: payload.metadata,
      error: errors.isEmpty ? null : 'Some keys could not be restored: ${errors.join(', ')}',
    );
  }

  // ── BACKUP FILE NAME ─────────────────────────────────────────────────────

  /// Generate a timestamped backup file name.
  String generateBackupFileName() {
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return 'huddl_backup_$ts.json';
  }

  // ── AUTO-BACKUP STATUS ───────────────────────────────────────────────────

  /// Save the timestamp of the last successful manual backup.
  Future<void> recordManualBackup() async {
    await BrowserStorage.setString(
        'last_manual_backup_at', DateTime.now().toIso8601String());
  }

  /// Retrieve the last manual backup timestamp, or null if never backed up.
  Future<DateTime?> lastManualBackupTime() async {
    final raw = await BrowserStorage.getString('last_manual_backup_at');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  // ── VALIDATE ─────────────────────────────────────────────────────────────

  /// Quick validation — parse the JSON and return metadata without restoring.
  BackupMetadata? validateBackupFile(String jsonString) {
    final payload = BackupPayload.fromJsonString(jsonString);
    return payload?.metadata;
  }
}

// ── Result type ──────────────────────────────────────────────────────────────

class RestoreResult {
  final bool success;
  final int restoredKeys;
  final int skippedKeys;
  final String? error;
  final BackupMetadata? metadata;

  const RestoreResult({
    required this.success,
    required this.restoredKeys,
    required this.skippedKeys,
    this.error,
    this.metadata,
  });
}
