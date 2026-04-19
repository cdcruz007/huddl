import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'browser_storage.dart';
import 'package:http/http.dart' as http;

/// Service that collects user feedback and delivers it to the Huddl team.
///
/// Delivery chain (in order):
///   1. Firestore  — written first so the record is never lost.
///   2. EmailJS    — sends an email notification to welcome@huddlapp.co.uk.
///
/// If EmailJS fails (e.g. no network), the Firestore record is already saved
/// and can be read from the Firebase console at any time.
class FeedbackService extends ChangeNotifier {
  static final FeedbackService _instance = FeedbackService._internal();
  factory FeedbackService() => _instance;
  FeedbackService._internal();

  // ── Destination (never shown to users) ────────────────────────────────
  static const String _targetEmail = 'welcome@huddlapp.co.uk';

  // ── EmailJS credentials ────────────────────────────────────────────────
  // Sign up free at https://www.emailjs.com → Service → Gmail/SMTP
  // Replace the three values below with your EmailJS account details.
  static const String _emailJsServiceId  = 'service_huddl';
  static const String _emailJsTemplateId = 'template_feedback';
  static const String _emailJsPublicKey  = 'YOUR_EMAILJS_PUBLIC_KEY';

  // ── Local cache key (BrowserStorage fallback) ─────────────────────────
  static const String _storageKey = 'huddl_feedback_ratings';

  // ── Cached rating data ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _allRatings = [];
  bool _initialized = false;

  /// Always show 4.8 to users; the real average is for internal use only.
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
  /// Steps:
  ///   1. Persist to BrowserStorage (instant, offline-safe).
  ///   2. Write to Firestore `feedback` collection (permanent cloud record).
  ///   3. Send email to [_targetEmail] via EmailJS.
  ///
  /// Returns `true` on success. Never throws — failures are logged and
  /// the function returns `true` as long as local storage succeeded.
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

    // ── Step 1: local cache ──────────────────────────────────────────────
    _allRatings.add(entry);
    await BrowserStorage.setString(_storageKey, json.encode(_allRatings));
    notifyListeners();

    // ── Step 2: Firestore ────────────────────────────────────────────────
    String? firestoreDocId;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('feedback')
          .add({
        'feedback'   : feedbackText,
        'star_rating': starRating,
        'user_name'  : userName,
        'user_uid'   : uid,
        'submitted_at': FieldValue.serverTimestamp(),
        'platform'   : defaultTargetPlatform.name,
        'delivered'  : false, // flipped to true once email is confirmed sent
      });
      firestoreDocId = doc.id;
      debugPrint('[FeedbackService] Saved to Firestore: ${doc.id}');
    } catch (e) {
      // Firestore unavailable (offline / permissions) — continue anyway.
      debugPrint('[FeedbackService] Firestore write failed: $e');
    }

    // ── Step 3: Email via EmailJS ────────────────────────────────────────
    final emailSent = await _sendViaEmailJs(
      feedbackText : feedbackText,
      starRating   : starRating,
      userName     : userName,
      submittedAt  : now,
      docId        : firestoreDocId,
    );

    // Mark the Firestore doc as delivered if email succeeded.
    if (emailSent && firestoreDocId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('feedback')
            .doc(firestoreDocId)
            .update({'delivered': true});
      } catch (_) {}
    }

    return true;
  }

  /// POST to EmailJS REST API v1.
  ///
  /// EmailJS sends the email on our behalf — no server required.
  /// Template variables:
  ///   {{to_email}}      → welcome@huddlapp.co.uk
  ///   {{from_name}}     → userName
  ///   {{star_rating}}   → 0–5
  ///   {{feedback_text}} → the message body
  ///   {{submitted_at}}  → ISO timestamp
  ///   {{doc_id}}        → Firestore document ID (for reference)
  Future<bool> _sendViaEmailJs({
    required String feedbackText,
    required int starRating,
    required String userName,
    required DateTime submittedAt,
    String? docId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type' : 'application/json',
          'origin'       : 'https://huddl-connect.firebaseapp.com',
        },
        body: json.encode({
          'service_id' : _emailJsServiceId,
          'template_id': _emailJsTemplateId,
          'user_id'    : _emailJsPublicKey,
          'template_params': {
            'to_email'     : _targetEmail,
            'from_name'    : userName.isNotEmpty ? userName : 'Anonymous',
            'star_rating'  : starRating > 0 ? '$starRating / 5 ★' : 'Not rated',
            'feedback_text': feedbackText,
            'submitted_at' : submittedAt.toString().substring(0, 19),
            'doc_id'       : docId ?? 'n/a',
            'reply_to'     : _targetEmail,
          },
        }),
      ).timeout(const Duration(seconds: 10));

      final success = response.statusCode == 200;
      if (success) {
        debugPrint('[FeedbackService] Email sent via EmailJS ✓');
      } else {
        debugPrint(
            '[FeedbackService] EmailJS returned ${response.statusCode}: ${response.body}');
      }
      return success;
    } catch (e) {
      debugPrint('[FeedbackService] EmailJS request failed: $e');
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
      ..writeln('Recipient  : $_targetEmail')
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
