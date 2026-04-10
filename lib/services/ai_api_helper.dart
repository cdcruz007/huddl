import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import '../config/vertex_ai_config.dart';

// =============================================================================
// AI API HELPER — SHARED ROUTING UTILITY
//
// Routes ALL AI calls to the fine-tuned Vertex AI model first
// (huddl-uk-parenting-assistant, europe-west4, project 334510232366),
// then falls back to Gemini AI Studio if Vertex AI is unavailable.
//
// The request/response shape is identical between Vertex AI's generateContent
// endpoint (for tuned Gemini models) and the Gemini AI Studio API, so the
// same requestBody can be sent to both — only the URL and auth header differ.
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
        throw Exception('Vertex AI 401 — token refreshed');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (kDebugMode) debugPrint('AiApiHelper: responded via Vertex AI ✅');
        return data;
      }

      throw Exception(
          'Vertex AI ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
    } catch (vertexErr) {
      if (kDebugMode) {
        debugPrint('AiApiHelper: Vertex AI failed ($vertexErr) — falling back to Gemini');
      }
    }

    // ── Fallback: Gemini AI Studio ────────────────────────────────────────
    if (!GeminiConfig.hasKey) {
      throw Exception('AiApiHelper: Gemini API key is empty — add GEMINI_API_KEY via --dart-define');
    }

    final geminiUrl = Uri.parse(GeminiConfig.generateContentUrl);

    final response = await http.post(
      geminiUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    ).timeout(timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (kDebugMode) debugPrint('AiApiHelper: responded via Gemini fallback ✅');
      return data;
    }

    if (kDebugMode) {
      debugPrint('AiApiHelper: Gemini fallback failed (${response.statusCode}): '
          '${response.body.substring(0, response.body.length.clamp(0, 300))}');
    }

    throw Exception(
        'Both AI providers failed. Gemini: ${response.statusCode} — ${response.body.substring(0, response.body.length.clamp(0, 200))}');
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
