import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Centralised Gemini AI configuration.
///
/// All AI services import key, model and base URL from here — one edit
/// covers the whole app when the key rotates.
class GeminiConfig {
  GeminiConfig._();

  // ── AI Studio key (google.generativeai / Gemini 2.0 Flash) ─────────────
  // Provided by Conrad. Works with the Generative Language API directly.
  // Override at build time if needed:
  //   flutter run    --dart-define=GEMINI_API_KEY=AIza...
  //   flutter build web --dart-define=GEMINI_API_KEY=AIza...
  static const String _embeddedKey = 'AIzaSyAbqDOrDBgR4o-HyCITHUSndq0TrxXJr5Y';

  static const String apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: _embeddedKey,
  );

  static const String model = 'gemini-2.0-flash';
  static const String baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  // ── Full generate-content endpoint ───────────────────────────────────────
  static String get generateContentUrl =>
      '$baseUrl/$model:generateContent?key=$apiKey';

  // ── Runtime key validation ─────────────────────────────────────────────
  static bool _validated = false;
  static bool _isValid   = false;
  static String? _blockReason;

  static bool get wasValidated => _validated;
  static bool get isKeyValid   => _isValid;
  static String? get blockReason => _blockReason;
  static bool get hasKey => apiKey.isNotEmpty;

  /// Light-weight ping to verify the key is accepted by Google.
  /// Returns true when the key works (200) or is quota-limited (429 = valid).
  /// Safe to call multiple times — only hits the network once per session.
  static Future<bool> validateKey() async {
    if (_validated) return _isValid;

    if (!hasKey) {
      _validated = true;
      _isValid = false;
      if (kDebugMode) debugPrint('GeminiConfig: no API key set');
      return false;
    }

    try {
      final url = Uri.parse(generateContentUrl);
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': 'Hello'}]}],
          'generationConfig': {'maxOutputTokens': 5},
        }),
      ).timeout(const Duration(seconds: 10));

      _validated = true;
      // 429 = quota-limited but key is valid — treat as online
      _isValid = response.statusCode == 200 || response.statusCode == 429;

      if (!_isValid && kDebugMode) {
        debugPrint('GeminiConfig: validation failed (${response.statusCode})');
        if (response.statusCode == 403) {
          _blockReason = response.body.contains('API_KEY_SERVICE_BLOCKED')
              ? 'API_KEY_SERVICE_BLOCKED — check AI Studio key is active'
              : 'HTTP 403: ${response.body.substring(0, response.body.length.clamp(0, 200))}';
          debugPrint('GeminiConfig: ⚠️  $_blockReason');
        }
      } else if (kDebugMode) {
        debugPrint('GeminiConfig: key valid ✅ (${response.statusCode})');
      }
    } catch (e) {
      _validated = true;
      _isValid = false;
      if (kDebugMode) debugPrint('GeminiConfig: validation error: $e');
    }
    return _isValid;
  }

  /// Force re-validation (e.g. after key rotation at runtime).
  static void resetValidation() {
    _validated = false;
    _isValid   = false;
    _blockReason = null;
  }
}
