import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Centralised Gemini AI configuration.
///
/// All AI services must import their key, model, and base URL from here so
/// that a single edit is all that is needed when the key rotates.
///
/// ── QUICK SETUP ────────────────────────────────────────────────────────────
/// The embedded Firebase web API key is currently blocked for the Generative
/// Language API (error: API_KEY_SERVICE_BLOCKED).
///
/// To fix, choose ONE of these two options:
///
/// OPTION A — Enable the API for the existing key (free, recommended):
///   1. Open: https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect
///   2. Click "Enable"
///   3. Wait ~5 minutes for propagation
///   4. The embedded key will then work automatically (no code change needed)
///
/// OPTION B — Use a dedicated AI Studio key (isolated quota, best practice):
///   1. Get a key at: https://aistudio.google.com/app/apikey
///   2. Inject at build time:
///        flutter run    --dart-define=GEMINI_API_KEY=AIza...
///        flutter build web --dart-define=GEMINI_API_KEY=AIza...
///        flutter build appbundle --dart-define=GEMINI_API_KEY=AIza...
///   3. For CI/CD set GEMINI_API_KEY as a pipeline secret
/// ────────────────────────────────────────────────────────────────────────────
class GeminiConfig {
  GeminiConfig._();

  // ── API credentials ────────────────────────────────────────────────────
  // Firebase web API key for huddl-connect (project 879152141283).
  //
  // STATUS: The Generative Language API is NOT currently enabled for this key.
  //   → error: API_KEY_SERVICE_BLOCKED (confirmed 2025-07-03)
  //   → Fix Option A: enable API at https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect
  //   → Fix Option B: inject a dedicated AI Studio key via --dart-define=GEMINI_API_KEY=AIza...
  //
  // The Cloud Function (Claude Sonnet) primary path in AiCopilotService is
  // unaffected — it uses its own server-side key. The Gemini path is the
  // fallback only; the app degrades gracefully to local responses if both fail.
  static const String _embeddedKey = 'AIzaSyBk2hsDAYRFj1eLM8XZD5aQndLJBiXTZp4';

  static const String apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    // Falls back to embedded key; only works once Generative Language API is
    // enabled on the huddl-connect GCP project (see Option A above).
    defaultValue: _embeddedKey,
  );

  static const String model = 'gemini-2.0-flash';
  static const String baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  // ── Convenience getter for the full generate-content endpoint ────────
  static String get generateContentUrl =>
      '$baseUrl/$model:generateContent?key=$apiKey';

  // ── Runtime key validation ─────────────────────────────────────────────
  static bool _validated = false;
  static bool _isValid = false;
  // Reason string populated when _isValid=false after a 403 config error.
  static String? _blockReason;

  /// Whether the API key has been checked at least once.
  static bool get wasValidated => _validated;

  /// Whether the last validation succeeded.
  static bool get isKeyValid => _isValid;

  /// Non-null when the key is blocked due to a GCP configuration issue
  /// (e.g. Generative Language API not enabled). Distinct from a transient
  /// network failure.
  static String? get blockReason => _blockReason;

  /// Whether the API key has been provided via build-time environment.
  static bool get hasKey => apiKey.isNotEmpty;

  /// Light-weight ping to verify the key is accepted by Google.
  /// Returns `true` when the key works, `false` otherwise.
  /// Safe to call multiple times - only hits the network once.
  static Future<bool> validateKey() async {
    if (_validated) return _isValid;

    if (!hasKey) {
      _validated = true;
      _isValid = false;
      if (kDebugMode) {
        debugPrint(
            'GeminiConfig: No API key provided. '
            'Pass --dart-define=GEMINI_API_KEY=your_key to enable AI features.');
      }
      return false;
    }

    try {
      final url = Uri.parse(generateContentUrl);
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': 'Hello'}
                  ]
                }
              ],
              'generationConfig': {
                'maxOutputTokens': 5,
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      _validated = true;
      // 200 = working, 429 = key is valid but quota-limited (still "online")
      _isValid = response.statusCode == 200 || response.statusCode == 429;

      if (!_isValid && kDebugMode) {
        debugPrint(
            'GeminiConfig: API key validation failed (${response.statusCode}): '
            '${response.body.substring(0, response.body.length.clamp(0, 300))}');
        if (response.statusCode == 403) {
          final isBlocked = response.body.contains('API_KEY_SERVICE_BLOCKED');
          _blockReason = isBlocked
              ? 'API_KEY_SERVICE_BLOCKED: Enable the Generative Language API at '
                'https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect '
                'or inject --dart-define=GEMINI_API_KEY=<AI_Studio_key>'
              : 'HTTP 403: ${response.body.substring(0, response.body.length.clamp(0, 200))}';
          debugPrint('GeminiConfig: \u26a0\ufe0f  $_blockReason');
        }
      }
    } catch (e) {
      _validated = true;
      _isValid = false;
      if (kDebugMode) {
        debugPrint('GeminiConfig: Key validation error: $e');
      }
    }
    return _isValid;
  }

  /// Force re-validation (e.g. after swapping the key at runtime).
  static void resetValidation() {
    _validated = false;
    _isValid = false;
    _blockReason = null;
  }
}
