import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Biometric authentication service.
///
/// Responsibilities:
///   1. Detect device capability (Face ID / Touch ID / fingerprint).
///   2. Store the user's opt-in preference.
///   3. Store the enrolled phone number so the login screen can trigger
///      biometric auth without the user re-typing their number.
///   4. Expose [authenticate] for the login flow and [authenticateForApp]
///      for the splash-screen auto-login path.
class BiometricAuthService {
  static final BiometricAuthService _instance = BiometricAuthService._();
  factory BiometricAuthService() => _instance;
  BiometricAuthService._();

  final LocalAuthentication _auth = LocalAuthentication();

  // SharedPreferences keys
  static const String _enabledKey      = 'huddl_biometric_enabled';
  static const String _enrolledPhoneKey = 'huddl_biometric_phone';

  // ── Device capability ──────────────────────────────────────────────────

  /// True if the device OS supports biometric APIs at all.
  Future<bool> get isDeviceSupported async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// True if at least one biometric (fingerprint / face / iris) is enrolled.
  ///
  /// IMPORTANT: We intentionally use [getAvailableBiometrics()] here instead
  /// of [canCheckBiometrics]. On Android API 23+, calling [canCheckBiometrics]
  /// when no biometric is enrolled can trigger the system "Set up fingerprint"
  /// enrollment dialog — a system-level overlay that causes Firebase Test Lab
  /// Robo tests to report "Outside of app" / UiAutomator timeout, ending the
  /// test with "Test failed to run".
  ///
  /// [getAvailableBiometrics()] returns an empty list silently without ever
  /// showing any system UI, making it safe to call in any context.
  Future<bool> get canCheckBiometrics async {
    if (kIsWeb) return false;
    try {
      final biometrics = await _auth.getAvailableBiometrics()
          .timeout(const Duration(seconds: 3), onTimeout: () => []);
      return biometrics.isNotEmpty;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Combined check: device supports biometrics AND at least one is enrolled.
  Future<bool> get isAvailable async {
    if (kIsWeb) return false;
    try {
      // Check device support first (fast, no system UI)
      final supported = await isDeviceSupported;
      if (!supported) return false;
      // Then check enrollment via getAvailableBiometrics (no system dialog)
      return await canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// The list of enrolled biometric types on this device.
  ///
  /// Returns an empty list (never throws, never shows system UI) on any error.
  Future<List<BiometricType>> get availableBiometrics async {
    if (kIsWeb) return [];
    try {
      return await _auth.getAvailableBiometrics()
          .timeout(const Duration(seconds: 3), onTimeout: () => []);
    } on PlatformException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Human-readable label for the strongest available biometric.
  /// e.g. "Face ID", "Touch ID", "Fingerprint", or "Biometrics".
  Future<String> get biometricLabel async {
    if (kIsWeb) return 'Biometrics';
    final types = await availableBiometrics;
    if (types.contains(BiometricType.face)) return 'Face ID';
    if (types.contains(BiometricType.fingerprint)) return 'Fingerprint';
    if (types.contains(BiometricType.strong)) return 'Biometrics';
    return 'Biometrics';
  }

  /// Icon data for the strongest available biometric.
  Future<String> get biometricIconAsset async {
    final types = await availableBiometrics;
    if (types.contains(BiometricType.face)) return 'face_id';
    return 'fingerprint';
  }

  // ── User preference ────────────────────────────────────────────────────

  /// Whether the user has opted in to biometric login.
  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Enable or disable biometric login.
  /// When enabling, pass [phoneNumber] to store the enrolled phone number.
  Future<void> setEnabled(bool value, {String? phoneNumber}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (value && phoneNumber != null && phoneNumber.isNotEmpty) {
      await prefs.setString(_enrolledPhoneKey, phoneNumber);
    }
    if (!value) {
      await prefs.remove(_enrolledPhoneKey);
    }
  }

  // ── Enrolled phone number ──────────────────────────────────────────────

  /// The phone number that was registered when biometrics were enabled.
  /// Used to pre-fill / identify the account on the login screen.
  Future<String?> get enrolledPhone async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_enrolledPhoneKey);
  }

  /// Update the stored phone number (e.g. after a phone change in profile).
  Future<void> updateEnrolledPhone(String phoneNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    if (enabled) {
      await prefs.setString(_enrolledPhoneKey, phoneNumber);
    }
  }

  // ── Authentication ─────────────────────────────────────────────────────

  /// Prompt the user to authenticate.
  ///
  /// [reason] is the string shown in the system biometric dialog.
  /// Returns true if the user authenticated successfully.
  /// Returns false if they cancelled, failed, or the device doesn't support it.
  /// Returns true (pass-through) on web where biometrics are never available.
  Future<bool> authenticate({
    String reason = 'Use Face ID or fingerprint to log in to Huddl',
  }) async {
    if (kIsWeb) return true; // Web: always pass-through

    try {
      final available = await isAvailable;
      if (!available) return false;

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow device PIN/passcode as fallback
          sensitiveTransaction: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      // notAvailable, notEnrolled, lockedOut, permanentlyLockedOut
      if (kDebugMode) debugPrint('[BiometricAuth] PlatformException: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[BiometricAuth] Error: $e');
      return false;
    }
  }

  /// Convenience: authenticate specifically for the login/splash flow.
  /// Uses a Huddl-branded reason string.
  Future<bool> authenticateForLogin() => authenticate(
        reason: 'Use Face ID or fingerprint to log in to Huddl',
      );

  /// Convenience: authenticate to unlock the app after backgrounding.
  Future<bool> authenticateForAppUnlock() => authenticate(
        reason: 'Verify it\'s you to open Huddl',
      );

  // ── Enrolment flow helper ──────────────────────────────────────────────

  /// Verify biometric works on this device before enabling it.
  /// Shows the system prompt as a "test". Returns true if the user
  /// authenticated successfully — the caller can then call [setEnabled].
  Future<bool> verifyBeforeEnabling() => authenticate(
        reason: 'Confirm your biometric to enable quick login',
      );
}
