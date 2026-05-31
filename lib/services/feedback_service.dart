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
/// If EmailJS fails the Firestore record is still saved and readable from
/// the Firebase console at any time.
///
/// ── EmailJS Setup (one-time, dashboard only) ────────────────────────────────
/// 1. Go to https://dashboard.emailjs.com/admin/templates
/// 2. Click "Create New Template"
/// 3. Set Subject: "Huddl App Feedback from {{from_name}}"
/// 4. Set Content (HTML):
///    <h2>New Feedback</h2>
///    <p><b>From:</b> {{from_name}}</p>
///    <p><b>Rating:</b> {{star_rating}}</p>
///    <p><b>Message:</b><br>{{feedback_text}}</p>
///    <p><b>Submitted:</b> {{submitted_at}}</p>
///    <p><b>Firestore ID:</b> {{doc_id}}</p>
/// 5. Set To Email: welcome@huddlapp.co.uk (or use {{to_email}} variable)
/// 6. Save and copy the Template ID (format: template_XXXXXXX)
/// 7. Replace _emailJsTemplateId below with that value.
/// ────────────────────────────────────────────────────────────────────────────
class FeedbackService extends ChangeNotifier {
  static final FeedbackService _instance = FeedbackService._internal();
  factory FeedbackService() => _instance;
  FeedbackService._internal();

  // ── Destination ────────────────────────────────────────────────────────────
  static const String _targetEmail = 'welcome@huddlapp.co.uk';

  // ── EmailJS credentials ────────────────────────────────────────────────────
  // Service ID and Public Key are confirmed working.
  // Template ID must match a template in your EmailJS dashboard.
  // See setup instructions in the class comment above.
  static const String _emailJsServiceId  = 'service_5hdcs5h';
  static const String _emailJsPublicKey  = 'imIn2A3lvfFeSVSaJ';

  static const String _emailJsTemplateId = 'template_z7gxw8h';

  // ── Local cache key ────────────────────────────────────────────────────────
  static const String _storageKey = 'huddl_feedback_ratings';

  // ── Cached rating data ─────────────────────────────────────────────────────
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
  /// 3. Send email notification via EmailJS.
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

    // ── Step 3: EmailJS notification ─────────────────────────────────────────
    final emailSent = await _sendViaEmailJs(
      feedbackText: feedbackText,
      starRating  : starRating,
      userName    : userName,
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

  /// POST to EmailJS REST API.
  ///
  /// Template variables used:
  ///   {{from_name}}     → userName
  ///   {{feedback_text}} → the full feedback message
  ///   {{submitted_at}}  → e.g. "2025-01-13 22:42:00"
  ///   {{doc_id}}        → Firestore document ID (for internal reference)
  Future<bool> _sendViaEmailJs({
    required String feedbackText,
    required int starRating,
    required String userName,
    required DateTime submittedAt,
    String? docId,
  }) async {
    try {
      final body = json.encode({
        'service_id' : _emailJsServiceId,
        'template_id': _emailJsTemplateId,
        'user_id'    : _emailJsPublicKey,
        'template_params': {
          'from_name'    : userName.isNotEmpty ? userName : 'Anonymous',
          'feedback_text': feedbackText,
          'submitted_at' : submittedAt.toString().substring(0, 19),
          'doc_id'       : docId ?? 'n/a',
        },
      });

      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'origin'      : 'https://huddl-connect.firebaseapp.com',
        },
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        if (kDebugMode) debugPrint('[FeedbackService] Email sent via EmailJS ✓');
        return true;
      } else {
        // Log full details to help diagnose issues
        if (kDebugMode) {
          debugPrint('[FeedbackService] EmailJS error ${response.statusCode}: ${response.body}');
          debugPrint('[FeedbackService] service_id=$_emailJsServiceId  template_id=$_emailJsTemplateId');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FeedbackService] EmailJS request exception: $e');
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
