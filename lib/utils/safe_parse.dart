import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Parses a list of raw items into models, isolating failures per-item.
/// A single malformed record is skipped (logged to Crashlytics) instead of
/// causing the whole list to fail/empty. (LAYER-5-PARSE-1)
List<T> safeParseList<T>(
  List<dynamic> raw,
  T Function(Map<String, dynamic>) fromJson, {
  String context = 'safeParseList',
}) {
  final out = <T>[];
  for (final item in raw) {
    try {
      if (item is Map<String, dynamic>) {
        out.add(fromJson(item));
      } else {
        if (kDebugMode) debugPrint('[$context] skipped non-map item');
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[$context] skipped malformed item: $e');
      FirebaseCrashlytics.instance.recordError(
        e, st, reason: '$context: malformed record skipped', fatal: false);
    }
  }
  return out;
}
