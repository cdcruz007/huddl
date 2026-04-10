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
  // Key is embedded directly so the Gemini fallback always works without
  // requiring --dart-define=GEMINI_API_KEY at build time.
  //
  // This is the huddl-connect Firebase web API key (project 879152141283).
  // For this to work, the Generative Language API must be enabled at:
  //   https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect
  //
  // Alternatively, create a dedicated Gemini AI Studio key at:
  //   https://aistudio.google.com/app/apikey
  // and pass it via --dart-define=GEMINI_API_KEY=AIza... at build time.
  static const String _embeddedKey = 'AIzaSyBk2hsDAYRFj1eLM8XZD5aQndLJBiXTZp4';

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
