import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Centralised Gemini AI configuration.
///
/// All AI services must import their key, model, and base URL from here so
/// that a single edit is all that is needed when the key rotates.
///
/// The API key is loaded from the GEMINI_API_KEY environment variable at
/// build time via --dart-define. For local development, pass:
///   flutter run --dart-define=GEMINI_API_KEY=your_key_here
/// For CI/CD, set the env var in your build pipeline.
///
/// SETUP REQUIRED: The Generative Language API must be enabled in the
/// huddl-connect Google Cloud project for the embedded key to work:
///   https://console.developers.google.com/apis/api/generativelanguage.googleapis.com/overview?project=879152141283
class GeminiConfig {
  GeminiConfig._();

  // ── API credentials ────────────────────────────────────────────────────
  // ⚠️  TODO (BUG 4): The key below is the Firebase web browser API key
  // (project huddl-connect, 879152141283). A Firebase web key and a Gemini
  // AI Studio key are DIFFERENT credentials even though both start with AIzaSy.
  // This key does NOT have the Generative Language API scope — the copilot will
  // always fail validation and show "Offline mode" until a real Gemini key is
  // supplied.
  //
  // To fix:
  //   Step 1: Go to https://aistudio.google.com/app/apikey
  //   Step 2: Create a new API key for the huddl-connect project
  //   Step 3: Enable the Generative Language API at:
  //     https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect
  //   Step 4: Replace the placeholder below with the real key, OR
  //           pass it at build time via --dart-define=GEMINI_API_KEY=AIza...
  //           so the key never lives in source control.
  //
  // Production build command:
  //   flutter build web --dart-define=GEMINI_API_KEY=YOUR_REAL_GEMINI_KEY
  //   flutter build appbundle --dart-define=GEMINI_API_KEY=YOUR_REAL_GEMINI_KEY
  //
  // ⚠️  NEVER commit a real Gemini API key to source control.
  //     Use --dart-define at build time or a secrets manager in CI/CD.
  static const String _embeddedKey = 'REPLACE_WITH_GEMINI_AI_STUDIO_KEY';

  static const String apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    // Fall back to embedded key so the app works out-of-the-box.
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

  /// Whether the API key has been checked at least once.
  static bool get wasValidated => _validated;

  /// Whether the last validation succeeded.
  static bool get isKeyValid => _isValid;

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
            '${response.body}');
        if (response.statusCode == 403) {
          debugPrint(
              'GeminiConfig: 403 usually means the Generative Language API '
              'is not enabled for this project. Enable it at: '
              'https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect');
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
  }
}
