import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for optional biometric authentication (P3 audit recommendation).
/// Allows users to protect the Messages tab with fingerprint / Face ID.
class BiometricAuthService {
  static final BiometricAuthService _instance = BiometricAuthService._();
  factory BiometricAuthService() => _instance;
  BiometricAuthService._();

  final LocalAuthentication _auth = LocalAuthentication();
  static const String _enabledKey = 'huddl_biometric_enabled';

  /// Whether the device supports biometric authentication.
  Future<bool> get isDeviceSupported async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// Whether any biometrics are enrolled on the device.
  Future<bool> get canCheckBiometrics async {
    try {
      return await _auth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  /// Available biometric types (fingerprint, face, iris).
  Future<List<BiometricType>> get availableBiometrics async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// Whether the user has opted-in to biometric lock for the chat tab.
  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Enable or disable biometric lock for chat.
  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Authenticate the user. Returns true on success, false on failure.
  Future<bool> authenticate({String reason = 'Authenticate to view messages'}) async {
    try {
      final supported = await isDeviceSupported;
      final canCheck = await canCheckBiometrics;
      if (!supported || !canCheck) return true; // Pass-through if not available

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow device PIN/passcode as fallback
        ),
      );
    } on PlatformException {
      return true; // Fail-open: don't lock user out on error
    }
  }
}
