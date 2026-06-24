import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

// =============================================================================
// LAYER-19-NO-VERSION-GATE-1
//
// VersionGateService — checks the app_config/version_gate Firestore doc against
// the running build number (from package_info_plus) at splash time.
//
// CRITICAL: FAIL OPEN.  A Firestore read error, timeout, or missing doc MUST
// return updateRequired=false so that a transient network blip never locks out
// legitimate users.  The gate is advisory — it warns users they are behind; it
// is NOT a security boundary.  Fail-closed on a network error would be
// catastrophic: every user would be blocked during a Firestore hiccup.
//
// Firestore doc shape (create once in console):
//   collection : app_config
//   document   : version_gate
//   fields     :
//     minSupportedBuild   : number   (e.g. 109)
//     minSupportedVersion : string   (e.g. "1.1.49")   — for display only
//     updateUrlIos        : string   (App Store URL)
//     updateUrlAndroid    : string   (Play Store URL)
//     message             : string   (e.g. "Please update Huddl to continue.")
//
// To force-update: set minSupportedBuild to the first build you want to
// expire.  Every client with buildNumber < minSupportedBuild will be shown
// ForceUpdateScreen.
// =============================================================================

/// Immutable result returned by [VersionGateService.check].
class VersionGateResult {
  final bool updateRequired;
  final String? updateUrlIos;
  final String? updateUrlAndroid;
  final String message;

  const VersionGateResult({
    required this.updateRequired,
    this.updateUrlIos,
    this.updateUrlAndroid,
    this.message = 'A new version of Huddl is required to continue.',
  });

  /// Convenience factory: always passes (used on errors to fail open).
  const VersionGateResult.passThrough()
      : updateRequired = false,
        updateUrlIos = null,
        updateUrlAndroid = null,
        message = '';
}

class VersionGateService {
  // Private constructor — stateless utility class.
  VersionGateService._();

  /// Check whether the running build is still supported.
  ///
  /// Steps:
  ///   1. Read the running build number from [PackageInfo].
  ///   2. Fetch app_config/version_gate from Firestore with a 5 s timeout.
  ///   3. Compare currentBuild < minSupportedBuild → updateRequired.
  ///
  /// Any exception (network error, parse failure, Firestore unavailable,
  /// timeout) returns [VersionGateResult.passThrough] — FAIL OPEN.
  /// Missing doc also returns passThrough (not yet configured = no gate).
  static Future<VersionGateResult> check() async {
    try {
      // ── 1. Current build number ──────────────────────────────────────────
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      // ── 2. Fetch config doc with hard 5 s deadline ───────────────────────
      final snap = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version_gate')
          .get()
          .timeout(const Duration(seconds: 5));

      // Missing doc → gate not yet configured → pass through.
      if (!snap.exists) return const VersionGateResult.passThrough();

      final data = snap.data()!;

      // ── 3. Compare builds ────────────────────────────────────────────────
      final minBuild = (data['minSupportedBuild'] as num?)?.toInt() ?? 0;
      final required = currentBuild < minBuild;

      return VersionGateResult(
        updateRequired: required,
        updateUrlIos:
            data['updateUrlIos'] as String?,
        updateUrlAndroid:
            data['updateUrlAndroid'] as String?,
        message: (data['message'] as String?)?.isNotEmpty == true
            ? data['message'] as String
            : 'A new version of Huddl is required to continue.',
      );
    } catch (_) {
      // FAIL OPEN: any error (timeout, network, parse) → let the user in.
      return const VersionGateResult.passThrough();
    }
  }
}
