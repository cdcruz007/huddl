import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

// =============================================================================
// AI API HELPER — SHARED ROUTING UTILITY
//
// Routes ALL AI calls through the vertexGenerateContent Cloud Function
// (europe-west2), which holds SA credentials in Secret Manager and proxies
// to the Vertex AI endpoint.
//
// The client-direct Gemini AI Studio fallback was REMOVED (audit KEY-1).
// The embedded API key shipped in the binary and was extractable from a
// decompiled APK/IPA. All AI traffic now exclusively flows through the CF.
// GeminiConfig and the direct HTTP fallback have been deleted from the project.
//
// When vertexGenerateContent is unavailable the methods return null / throw an
// "AI temporarily unavailable" exception — callers treat this identically to
// the previous total-failure path.
//
// TROUBLESHOOTING:
//   VERTEX_UNAVAILABLE → Check VERTEX_AI_SA_KEY secret in Firebase Secret Manager
//                        and Cloud Function logs in europe-west2.
// =============================================================================

class AiApiHelper {
  AiApiHelper._();

  /// POST a generateContent [requestBody] to Vertex AI via the
  /// vertexGenerateContent Cloud Function (europe-west2).
  ///
  /// Returns the parsed response map on success.
  /// Throws an "AI temporarily unavailable" exception on failure — callers
  /// should surface this as a transient error, not a permanent offline state.
  /// Method signature is unchanged from the previous two-provider version.
  static Future<Map<String, dynamic>> generateContent(
    Map<String, dynamic> requestBody, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
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
          'AiApiHelper: vertexGenerateContent failed (${e.code}/${e.message})',
        );
      }
      throw Exception('AI temporarily unavailable. Please try again later.');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AiApiHelper: vertexGenerateContent error — $e');
      }
      throw Exception('AI temporarily unavailable. Please try again later.');
    }
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
