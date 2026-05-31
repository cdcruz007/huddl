import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import '../config/vertex_ai_config.dart';

// =============================================================================
// AI API HELPER — SHARED ROUTING UTILITY
//
// Routes ALL AI calls to the fine-tuned Vertex AI model first
// (huddl-uk-parenting-assistant, europe-west4, project 879152141283),
// then falls back to Gemini AI Studio if Vertex AI is unavailable.
//
// The request/response shape is identical between Vertex AI's generateContent
// endpoint (for tuned Gemini models) and the Gemini AI Studio API, so the
// same requestBody can be sent to both — only the URL and auth header differ.
//
// TROUBLESHOOTING:
//   Vertex AI 404 → Check projectNumber in vertex_ai_config.dart matches
//                   google-services.json project_number (879152141283).
//   Gemini 403    → Enable the Generative Language API for the project at:
//                   https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect
//                   OR supply a dedicated key via --dart-define=GEMINI_API_KEY=AIza...
// =============================================================================

class AiApiHelper {
  AiApiHelper._();

  /// POST a generateContent [requestBody] to Vertex AI (fine-tuned model).
  /// On failure, automatically falls back to Gemini AI Studio.
  ///
  /// Returns the parsed response map from the successful provider.
  /// Throws if both providers fail.
  static Future<Map<String, dynamic>> generateContent(
    Map<String, dynamic> requestBody, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    // ── Primary: Vertex AI fine-tuned model ──────────────────────────────
    try {
      final token = await VertexAiConfig.getBearerToken();
      final url   = Uri.parse(VertexAiConfig.generateContentUrl);

      if (kDebugMode) {
        debugPrint('AiApiHelper: → Vertex AI ${VertexAiConfig.generateContentUrl}');
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      ).timeout(timeout);

      if (response.statusCode == 401) {
        // Stale token — invalidate so next call refreshes
        VertexAiConfig.invalidateToken();
        throw Exception('Vertex AI 401 — token refreshed, will retry via Gemini');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (kDebugMode) debugPrint('AiApiHelper: Vertex AI ✅');
        return data;
      }

      // Log the actual status + first 300 chars so we can diagnose misconfigs
      if (kDebugMode) {
        debugPrint('AiApiHelper: Vertex AI ${response.statusCode}: '
            '${response.body.substring(0, response.body.length.clamp(0, 300))}');
      }

      throw Exception(
          'Vertex AI ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
    } catch (vertexErr) {
      if (kDebugMode) {
        debugPrint('AiApiHelper: Vertex AI failed — $vertexErr');
        debugPrint('AiApiHelper: Falling back to Gemini AI Studio…');
      }
    }

    // ── Fallback: Gemini AI Studio ────────────────────────────────────────
    if (!GeminiConfig.hasKey) {
      throw Exception(
          'AiApiHelper: Gemini API key is empty — '
          'add GEMINI_API_KEY via --dart-define or enable the Generative '
          'Language API in the Google Cloud Console.');
    }

    if (kDebugMode) {
      debugPrint('AiApiHelper: → Gemini ${GeminiConfig.model}');
    }

    final geminiUrl = Uri.parse(GeminiConfig.generateContentUrl);

    final geminiResponse = await http.post(
      geminiUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    ).timeout(timeout);

    if (geminiResponse.statusCode == 200) {
      final data = jsonDecode(geminiResponse.body) as Map<String, dynamic>;
      if (kDebugMode) debugPrint('AiApiHelper: Gemini fallback ✅');
      return data;
    }

    // Detailed Gemini error logging
    if (kDebugMode) {
      debugPrint('AiApiHelper: Gemini failed (${geminiResponse.statusCode}): '
          '${geminiResponse.body.substring(0, geminiResponse.body.length.clamp(0, 400))}');
      if (geminiResponse.statusCode == 403) {
        debugPrint(
            'AiApiHelper: ⚠️  Gemini 403 — The Generative Language API is '
            'not enabled for project huddl-connect. Enable it at:\n'
            'https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect\n'
            'Or supply a dedicated key: flutter run --dart-define=GEMINI_API_KEY=AIza...');
      }
    }

    // 403 with API_KEY_SERVICE_BLOCKED means the Generative Language API is not
    // enabled on the GCP project — this is a permanent configuration issue, NOT
    // a transient network failure. Throw a specific error so callers (e.g.
    // AiCopilotService) can distinguish "misconfigured" from "offline" and avoid
    // setting _isApiOnline=false, which would show a permanent "Offline" badge.
    if (geminiResponse.statusCode == 403 &&
        geminiResponse.body.contains('API_KEY_SERVICE_BLOCKED')) {
      throw Exception(
          'GEMINI_API_NOT_ENABLED: The Generative Language API is not enabled '
          'for project huddl-connect. '
          'Enable it at: https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect '
          'or pass --dart-define=GEMINI_API_KEY=<AI_Studio_key>.');
    }

    throw Exception(
        'Both AI providers failed. '
        'Vertex AI: see above. '
        'Gemini: HTTP ${geminiResponse.statusCode}');
  }

  /// Convenience: call [generateContent] and extract the first text part.
  /// Returns null if no text content is found.
  static Future<String?> generateText(
    Map<String, dynamic> requestBody, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final data       = await generateContent(requestBody, timeout: timeout);
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final parts = candidates[0]['content']?['parts'] as List?;
    if (parts == null || parts.isEmpty) return null;
    return parts[0]['text'] as String?;
  }
}
