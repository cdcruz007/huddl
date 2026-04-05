import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Centralised Gemini AI configuration.
///
/// All AI services must import their key, model, and base URL from here so
/// that a single edit is all that is needed when the key rotates.
class GeminiConfig {
  GeminiConfig._();

  // ── API credentials ────────────────────────────────────────────────────
  // TODO: Replace with a valid Gemini API key from
  //       https://aistudio.google.com/app/apikey
  static const String apiKey =
      'AIzaSyA3MOqpbEWR5shMm1EF6H06-O5mGVyxqIg';

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

  /// Light-weight ping to verify the key is accepted by Google.
  /// Returns `true` when the key works, `false` otherwise.
  /// Safe to call multiple times - only hits the network once.
  static Future<bool> validateKey() async {
    if (_validated) return _isValid;

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
      _isValid = response.statusCode == 200;

      if (!_isValid && kDebugMode) {
        debugPrint(
            'GeminiConfig: API key validation failed (${response.statusCode}): '
            '${response.body}');
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
