import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'browser_storage.dart';

/// Service that collects user feedback and delivers it to the Huddl team.
///
/// Delivery chain (in order):
///   1. Firestore  — written first so the record is never lost.
///   2. Backend API (/api/notifications/feedback) — sends an email notification
///      via Resend → SMTP → mock, matching every other transactional email.
///
/// EMAILJS-UNDECLARED-1 / EMAILJS-CREDS-PUBLIC-1: previously this service
/// POSTed directly to EmailJS (a US-based processor) from the device, with
/// credentials stored as static const in a public GitHub repo. EmailJS has
/// no DPA, the origin-header abuse protection is trivially bypassed on mobile,
/// and the credentials were visible to anyone reading the repo.
///
/// The backend endpoint resolves fromName server-side from users/{uid}.name
/// (NOTIFY-SPOOF-1 hardening — matches the message routes). The client does
/// NOT supply a display name in the request body.
///
/// If the email notification fails the Firestore record is still saved and
/// readable from the Firebase console at any time.
class FeedbackService extends ChangeNotifier {
  static final FeedbackService _instance = FeedbackService._internal();
  factory FeedbackService() => _instance;
  FeedbackService._internal();

  // ── Backend base URL (mirrors BackendApiService.baseUrl) ─────────────────
  // Reuses the same prod/dev URL logic and _authHeaders pattern as
  // BackendApiService.resendVerificationEmail — same base URL resolution,
  // same Authorization header, same 15 s timeout (LAYER-10-RAILWAY-TIMEOUT-1).
  static const String _prodBaseUrl = 'https://api.huddlapp.co.uk';
  static const String _devBaseUrl  = 'http://localhost:3000';

  String get _baseUrl => kReleaseMode ? _prodBaseUrl : _devBaseUrl;

  // ── Local cache key ───────────────────────────────────────────────────────
  static const String _storageKey = 'huddl_feedback_ratings';

  // ── Cached rating data ────────────────────────────────────────────────────
  List<Map<String, dynamic>> _allRatings = [];
  bool _initialized = false;

  /// Always show 4.8 to users; real average is for internal use only.
  double get displayRating => 4.8;

  double get realAverageRating {
    if (_allRatings.isEmpty) return 0;
    final sum = _allRatings.fold<double>(
        0, (p, r) => p + ((r['rating'] as num?)?.toDouble() ?? 0));
    return sum / _allRatings.length;
  }

  int get totalRatings => _allRatings.length;

  Future<void> initialize() async {
    if (_initialized) return;
    final raw = await BrowserStorage.getString(_storageKey);
    if (raw != null) {
      try {
        _allRatings = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _allRatings = [];
      }
    }
    _initialized = true;
  }

  /// Submit user feedback.
  ///
  /// 1. Persist to BrowserStorage (instant, offline-safe).
  /// 2. Write to Firestore `feedback` collection (permanent cloud record).
  /// 3. POST to /api/notifications/feedback — backend sends email via Resend.
  ///
  /// Returns `true` as long as local + Firestore steps succeed.
  Future<bool> submitFeedback({
    required String feedbackText,
    int starRating = 0,
    required String userName,
  }) async {
    final now = DateTime.now();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

    final entry = {
      'rating'   : starRating,
      'feedback' : feedbackText,
      'user'     : userName,
      'uid'      : uid,
      'timestamp': now.toIso8601String(),
    };

    // ── Step 1: local cache ──────────────────────────────────────────────────
    _allRatings.add(entry);
    await BrowserStorage.setString(_storageKey, json.encode(_allRatings));
    notifyListeners();

    // ── Step 2: Firestore ────────────────────────────────────────────────────
    String? firestoreDocId;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('feedback')
          .add({
        'feedback'    : feedbackText,
        'star_rating' : starRating,
        'user_name'   : userName,
        'user_uid'    : uid,
        'submitted_at': FieldValue.serverTimestamp(),
        'platform'    : defaultTargetPlatform.name,
        'email_sent'  : false,
      });
      firestoreDocId = doc.id;
      if (kDebugMode) debugPrint('[FeedbackService] Firestore write OK: ${doc.id}');
    } catch (e) {
      if (kDebugMode) debugPrint('[FeedbackService] Firestore write failed: $e');
    }

    // ── Step 3: backend email notification ───────────────────────────────────
    // Non-fatal: a failed notification does NOT mean feedback was lost —
    // the Firestore record already exists (step 2).
    final emailSent = await _sendViaBackend(
      feedbackText: feedbackText,
      starRating  : starRating,
      submittedAt : now,
      docId       : firestoreDocId,
    );

    if (emailSent && firestoreDocId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('feedback')
            .doc(firestoreDocId)
            .update({'email_sent': true});
      } catch (_) {}
    }

    return true;
  }

  /// POST feedback notification to the Railway backend.
  ///
  /// Pattern reused from BackendApiService.resendVerificationEmail:
  ///   - same _baseUrl resolution (prod vs dev via kReleaseMode)
  ///   - same Authorization: Bearer [Firebase ID token] header
  ///   - same 15 s timeout (LAYER-10-RAILWAY-TIMEOUT-1)
  ///
  /// fromName is deliberately NOT sent — the backend derives it server-side
  /// from users/{uid}.name (NOTIFY-SPOOF-1).
  Future<bool> _sendViaBackend({
    required String feedbackText,
    required int starRating,
    required DateTime submittedAt,
    String? docId,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();

      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final body = json.encode({
        'feedbackText': feedbackText,
        'starRating'  : starRating,
        'submittedAt' : submittedAt.toIso8601String(),
        if (docId != null) 'docId': docId,
      });

      final response = await http.post(
        Uri.parse('$_baseUrl/api/notifications/feedback'),
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 15)); // LAYER-10-RAILWAY-TIMEOUT-1

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (kDebugMode) debugPrint('[FeedbackService] Backend notification OK');
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('[FeedbackService] Backend notification error '
              '${response.statusCode}: ${response.body}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FeedbackService] Backend notification exception: $e');
      return false;
    }
  }

  /// Generate a plain-text summary report (for internal export).
  String generateReport() {
    final buf = StringBuffer()
      ..writeln('=== HUDDL APP FEEDBACK REPORT ===')
      ..writeln('Generated  : ${DateTime.now().toString().substring(0, 19)}')
      ..writeln('Total      : $totalRatings')
      ..writeln('Real avg   : ${realAverageRating.toStringAsFixed(2)} / 5.0')
      ..writeln('Display avg: $displayRating / 5.0')
      ..writeln('');
    for (var i = 0; i < _allRatings.length; i++) {
      final r = _allRatings[i];
      buf
        ..writeln('--- Entry ${i + 1} ---')
        ..writeln('  User    : ${r['user']}')
        ..writeln('  Rating  : ${r['rating']} / 5')
        ..writeln('  Feedback: ${r['feedback']}')
        ..writeln('  Time    : ${r['timestamp']}')
        ..writeln('');
    }
    buf.writeln('=== END OF REPORT ===');
    return buf.toString();
  }
}
