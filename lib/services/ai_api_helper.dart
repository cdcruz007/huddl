import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';

// =============================================================================
// AI API HELPER — SHARED ROUTING UTILITY
//
// Routes ALL AI calls to the fine-tuned Vertex AI model first via the
// `vertexGenerateContent` Cloud Function (europe-west2), which holds SA
// credentials in Secret Manager and proxies to the Vertex AI endpoint.
// Falls back to Gemini AI Studio if the CF returns VERTEX_UNAVAILABLE or any
// other exception occurs.
//
// The request/response shape is identical between Vertex AI's generateContent
// endpoint (for tuned Gemini models) and the Gemini AI Studio API, so the
// same requestBody can be sent to both — only the transport differs.
//
// TROUBLESHOOTING:
//   VERTEX_UNAVAILABLE → Check VERTEX_AI_SA_KEY secret in Firebase Secret Manager
//                        and Cloud Function logs in europe-west2.
//   Gemini 403         → Enable the Generative Language API for the project at:
//                        https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect
//                        OR supply a dedicated key via --dart-define=GEMINI_API_KEY=AIza...
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
    // ── Primary: vertexGenerateContent Cloud Function (europe-west2) ────────
    try {
      if (kDebugMode) {
        debugPrint('AiApiHelper: → vertexGenerateContent (europe-west2 CF)');
      }
      final callable = FirebaseFunctions
          .instanceFor(region: 'europe-west2')
          .httpsCallable(
            'vertexGenerateContent',
            options: HttpsCallableOptions(timeout: timeout),
          );
      final result =
          await callable.call<Map<String, dynamic>>({'requestBody': requestBody});
      final data = (result.data['data'] as Map?)?.cast<String, dynamic>();
      if (data != null) {
        if (kDebugMode) {
          debugPrint('AiApiHelper: vertexGenerateContent ✅');
        }
        return data;
      }
      throw Exception('vertexGenerateContent: empty data in response');
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'AiApiHelper: vertexGenerateContent failed '
          '(${e.code}/${e.message}) — falling back to Gemini AI Studio…',
        );
      }
    } catch (vertexErr) {
      if (kDebugMode) {
        debugPrint(
          'AiApiHelper: vertexGenerateContent error — '
          '$vertexErr — falling back to Gemini AI Studio…',
        );
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
      if (kDebugMode) {
        debugPrint('AiApiHelper: → Gemini ${GeminiConfig.model}');
      }
    }

    final geminiUrl = Uri.parse(GeminiConfig.generateContentUrl);

    final geminiResponse = await http.post(
      geminiUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    ).timeout(timeout);

    if (geminiResponse.statusCode == 200) {
      final data = jsonDecode(geminiResponse.body) as Map<String, dynamic>;
      if (kDebugMode) {
        if (kDebugMode) debugPrint('AiApiHelper: Gemini fallback ✅');
      }
      return data;
    }

    // Detailed Gemini error logging
    if (kDebugMode) {
      if (kDebugMode) {
        debugPrint('AiApiHelper: Gemini failed (${geminiResponse.statusCode}): '
        '${geminiResponse.body.substring(0, geminiResponse.body.length.clamp(0, 400))}');
      }
      if (geminiResponse.statusCode == 403) {
        if (kDebugMode) {
          debugPrint(
          'AiApiHelper: ⚠️  Gemini 403 — The Generative Language API is '
          'not enabled for project huddl-connect. Enable it at:\n'
          'https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com?project=huddl-connect\n'
          'Or supply a dedicated key: flutter run --dart-define=GEMINI_API_KEY=AIza...');
        }
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
