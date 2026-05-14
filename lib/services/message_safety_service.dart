import 'package:flutter/foundation.dart';
import 'ai_api_helper.dart';

// =============================================================================
// MESSAGE SAFETY SERVICE
//
// Lightweight Gemini safety pre-filter for outgoing messages.
// Called BEFORE every Firestore write in _sendMessage() to detect and hold
// content that may violate child-safety or community standards.
//
// Classification result:
//   MessageSafetyResult.safe    — message passes; allow Firestore write
//   MessageSafetyResult.hold    — message blocked; caller must show warning
//
// Categories flagged as UNSAFE (held from Firestore):
//   • Threats of violence / self-harm
//   • CSAM / grooming language
//   • Severe harassment / hate speech
//   • Explicit sexual content
//
// Timeouts / errors are SAFE-by-default: if the AI call fails (offline, quota
// exceeded, latency) the message is allowed through so the UX is not broken.
// The AI filter is a best-effort layer; human moderation via ReportService
// remains the primary enforcement path.
// =============================================================================

/// Result returned by [MessageSafetyService.classify].
enum MessageSafetyResult {
  /// Message is safe to send.
  safe,

  /// Message was flagged — do NOT write to Firestore; show warning to user.
  hold,
}

class MessageSafetyService {
  static final MessageSafetyService _instance = MessageSafetyService._internal();
  factory MessageSafetyService() => _instance;
  MessageSafetyService._internal();

  // ── Prompt ─────────────────────────────────────────────────────────────────

  static const String _systemInstruction = '''
You are a content safety classifier for a UK parenting community app used by parents and children.

Classify the following user message as SAFE or UNSAFE.

UNSAFE means the message contains ANY of:
- Threats of violence or self-harm directed at a specific person
- Child sexual abuse material (CSAM) or grooming language
- Severe, targeted harassment or hate speech
- Explicit sexual content

SAFE means everything else, including strong opinions, mild rudeness, complaints, or adult discussion topics that do not meet the above thresholds.

Respond with ONLY the single word SAFE or UNSAFE. No explanation.
''';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Classifies [message] text for safety.
  ///
  /// Returns [MessageSafetyResult.safe] on any error/timeout so that
  /// connectivity issues never silently block legitimate messages.
  Future<MessageSafetyResult> classify(String message) async {
    if (message.trim().isEmpty) return MessageSafetyResult.safe;

    try {
      final requestBody = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': '$_systemInstruction\n\nMessage to classify:\n"$message"'},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.0,
          'maxOutputTokens': 8,
          'topP': 1.0,
        },
      };

      final raw = await AiApiHelper.generateText(
        requestBody,
        timeout: const Duration(seconds: 10),
      );

      if (raw == null) {
        debugPrint('[MessageSafety] No response from AI — defaulting to safe');
        return MessageSafetyResult.safe;
      }

      final verdict = raw.trim().toUpperCase();
      if (kDebugMode) {
        debugPrint('[MessageSafety] verdict: $verdict for: "${message.substring(0, message.length.clamp(0, 60))}…"');
      }

      if (verdict.startsWith('UNSAFE')) return MessageSafetyResult.hold;
      return MessageSafetyResult.safe;
    } catch (e) {
      // Safe-by-default on any error (network, quota, parse)
      debugPrint('[MessageSafety] classify() error — allowing message: $e');
      return MessageSafetyResult.safe;
    }
  }
}
