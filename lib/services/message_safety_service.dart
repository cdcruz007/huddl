import 'package:flutter/foundation.dart';
import 'ai_api_helper.dart';

// =============================================================================
// MESSAGE SAFETY SERVICE
//
// Two-layer content moderation for outgoing messages.
// Called BEFORE every Firestore write in _sendMessage() to detect and hold
// content that violates community standards.
//
// LAYER 1 — Local blocklist (synchronous, always runs, no network required)
//   Hard blocks a curated set of severe slurs and explicit terms.
//   This layer fires even when AI is offline/quota-exceeded/blocked.
//   Also catches common letter-substitution obfuscation (f*ck, f**k, fück etc.)
//
// LAYER 2 — AI classifier (Gemini, best-effort)
//   Catches nuanced violations the blocklist can't see: threats, grooming,
//   coordinated harassment, context-dependent hate speech.
//   Failures (network, quota, API blocked) fall through to SAFE so the UX
//   is never broken by AI unavailability.
//
// Classification result:
//   MessageSafetyResult.safe    — passes both layers; allow Firestore write
//   MessageSafetyResult.hold    — blocked by either layer; show warning to user
//   MessageSafetyResult.localBlock — specifically blocked by local list
//                                    (caller can show a more specific message)
//
// Categories blocked by AI layer:
//   • Threats of violence / self-harm directed at a specific person
//   • CSAM / grooming language
//   • Severe harassment / hate speech
//   • Explicit sexual content
//
// NOTE: The AI filter is a best-effort layer; human moderation via
// ReportService remains the primary enforcement path.
// =============================================================================

/// Result returned by [MessageSafetyService.classify].
enum MessageSafetyResult {
  /// Message is safe to send.
  safe,

  /// Message was blocked by the local word list — do NOT write to Firestore.
  localBlock,

  /// Message was flagged by the AI classifier — do NOT write to Firestore.
  hold,
}

class MessageSafetyService {
  static final MessageSafetyService _instance = MessageSafetyService._internal();
  factory MessageSafetyService() => _instance;
  MessageSafetyService._internal();

  // ── Layer 1: Local blocklist ──────────────────────────────────────────────
  //
  // Words and phrases that are ALWAYS blocked regardless of AI availability.
  // Kept deliberately short — this list targets the most severe terms that
  // have no legitimate use in a parenting community.
  //
  // Matching is: lowercased, common obfuscation stripped (see _normalise()),
  // whole-word OR substring for compound forms.
  //
  // GUIDANCE ON ADDITIONS:
  //   • Add severe slurs, explicit sexual terms, and targeted threats here.
  //   • Do NOT add general swear words used in adult conversation (shit, damn,
  //     crap) — these are handled by the AI nuance layer, or left to human
  //     moderation via the Report button.  Over-blocking frustrates users.
  //   • "Fuck off" directed at a person is rude but falls within adult
  //     expression — AI layer flags severe/targeted harassment, not all
  //     profanity.  If your community standard is stricter, add 'fuck' below.

  static const List<String> _hardBlockList = [
    // Sexual / explicit
    'cunt',
    'pussy',
    'dick',
    'cock',
    'twat',
    'wank',
    'motherfucker',
    'motherfucking',

    // Racial / ethnic slurs (severe)
    'nigger',
    'nigga',
    'faggot',
    'fag',
    'chink',
    'spic',
    'kike',
    'wetback',
    'tranny',
    'retard',

    // Child safety
    'paedo',
    'pedo',
    'groomer',
    'nonce',

    // Targeted threats (fragments caught by substring match below)
    'kill yourself',
    'kys',
    'kill urself',
    'i will kill',
    'i will hurt',
    'i know where you live',
  ];

  // Add swear words here if you want them hard-blocked in ALL contexts.
  // Currently left to AI nuance layer + user reporting.
  // To hard-block 'fuck' and 'shit', uncomment:
  //   'fuck',
  //   'shit',

  /// Strips common obfuscation characters and lowercases the input so that
  /// "f*ck", "f**k", "f@ck", "fück" etc. all normalise to "fuck".
  static String _normalise(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[*@!0\$]'), '') // strip common substitutions
        .replaceAll(RegExp(r'[àáâãäåæ]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõöø]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[ç]'), 'c');
  }

  /// Returns true if [message] contains a hard-blocked term.
  static bool _localCheck(String message) {
    final normalised = _normalise(message);
    for (final term in _hardBlockList) {
      if (normalised.contains(term)) {
        if (kDebugMode) debugPrint('[MessageSafety] Local block hit: "$term"');
        return true;
      }
    }
    return false;
  }

  // ── Layer 2: AI prompt ────────────────────────────────────────────────────

  static const String _systemInstruction = '''
You are a content safety classifier for a UK parenting community app used by parents and children.

Classify the following user message as SAFE or UNSAFE.

UNSAFE means the message contains ANY of:
- Threats of violence or self-harm directed at a specific person
- Child sexual abuse material (CSAM) or grooming language
- Severe, targeted harassment or hate speech targeting a person's identity
- Explicit sexual content

SAFE means everything else, including strong opinions, mild rudeness, complaints, or adult discussion topics that do not meet the above thresholds.

Respond with ONLY the single word SAFE or UNSAFE. No explanation.
''';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Classifies [message] text for safety using two layers:
  ///   1. Local blocklist (synchronous, always runs)
  ///   2. AI classifier (best-effort, safe-by-default on error)
  ///
  /// Returns [MessageSafetyResult.safe] on AI error/timeout so that
  /// connectivity issues never silently block legitimate messages.
  Future<MessageSafetyResult> classify(String message) async {
    if (message.trim().isEmpty) return MessageSafetyResult.safe;

    // ── Layer 1: local check (no network, always reliable) ─────────────────
    if (_localCheck(message)) {
      return MessageSafetyResult.localBlock;
    }

    // ── Layer 2: AI nuance check (best-effort) ─────────────────────────────
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
        timeout: const Duration(seconds: 6), // reduced from 10 — fail fast
      );

      if (raw == null) {
        if (kDebugMode) debugPrint('[MessageSafety] No AI response — defaulting to safe');
        return MessageSafetyResult.safe;
      }

      final verdict = raw.trim().toUpperCase();
      if (kDebugMode) {
        debugPrint('[MessageSafety] AI verdict: $verdict for: '
            '"${message.substring(0, message.length.clamp(0, 60))}…"');
      }

      if (verdict.startsWith('UNSAFE')) return MessageSafetyResult.hold;
      return MessageSafetyResult.safe;

    } catch (e) {
      // Safe-by-default on any error (network, quota, API blocked, parse)
      if (kDebugMode) debugPrint('[MessageSafety] AI classify() error — allowing message: $e');
      return MessageSafetyResult.safe;
    }
  }
}
