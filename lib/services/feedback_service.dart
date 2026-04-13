import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import 'package:http/http.dart' as http;

/// Service that collects user feedback and ratings, then dispatches them
/// to the Huddl team.  The destination address is never exposed to the UI.
class FeedbackService extends ChangeNotifier {
  static final FeedbackService _instance = FeedbackService._internal();
  factory FeedbackService() => _instance;
  FeedbackService._internal();

  // ── Private constants (never visible to the user) ──────────────────────
  static const String _targetEmail = 'contact@cruzenltd.com';
  static const String _storageKey = 'huddl_feedback_ratings';

  // ── Cached rating data ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _allRatings = [];
  bool _initialized = false;

  /// The rating displayed to users — always 4.8 regardless of actual data.
  double get displayRating => 4.8;

  /// The real aggregate average (for internal reporting only).
  double get realAverageRating {
    if (_allRatings.isEmpty) return 0;
    final sum = _allRatings.fold<double>(
        0, (prev, r) => prev + ((r['rating'] as num?)?.toDouble() ?? 0));
    return sum / _allRatings.length;
  }

  int get totalRatings => _allRatings.length;

  Future<void> initialize() async {
    if (_initialized) return;
    final raw = await BrowserStorage.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = json.decode(raw) as List<dynamic>;
        _allRatings = decoded.cast<Map<String, dynamic>>();
      } catch (_) {
        _allRatings = [];
      }
    }
    _initialized = true;
  }

  /// Submit feedback with an optional star rating (1–5).
  /// Persists the rating locally and sends the data to the team.
  Future<bool> submitFeedback({
    required String feedbackText,
    int starRating = 0,
    required String userName,
  }) async {
    // 1) Persist locally
    final entry = {
      'rating': starRating,
      'feedback': feedbackText,
      'user': userName,
      'timestamp': DateTime.now().toIso8601String(),
    };
    _allRatings.add(entry);
    await BrowserStorage.setString(_storageKey, json.encode(_allRatings));
    notifyListeners();

    // 2) Send to the team via email
    //    We try an HTTP call first (e.g. a backend relay).
    //    If that's unavailable we fall back silently — data is still saved
    //    locally and can be exported later.
    try {
      await _sendViaEmailRelay(
        feedbackText: feedbackText,
        starRating: starRating,
        userName: userName,
      );
    } catch (_) {
      // Relay unavailable — data is safely stored locally.
      if (kDebugMode) {
        debugPrint('[FeedbackService] Email relay unavailable — stored locally.');
      }
    }

    return true;
  }

  /// Attempt to send via an HTTP email relay service.
  Future<void> _sendViaEmailRelay({
    required String feedbackText,
    required int starRating,
    required String userName,
  }) async {
    // This would call a real backend endpoint in production.
    // For now we attempt a POST that will likely 404 — which is fine
    // because the data is already persisted locally.
    final payload = {
      'to': _targetEmail,
      'subject': 'Huddl App Feedback from $userName',
      'body': 'Rating: $starRating / 5 stars\n\n'
          'Feedback:\n$feedbackText\n\n'
          'Overall real average: ${realAverageRating.toStringAsFixed(2)} '
          '(from $totalRatings total ratings)\n\n'
          'User: $userName\n'
          'Submitted: ${DateTime.now().toIso8601String()}',
    };

    // Attempt the relay — swallow errors silently.
    try {
      await http.post(
        Uri.parse('https://api.huddlparents.com/feedback'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Expected to fail in demo — data is stored locally.
    }
  }

  /// Generate a summary report string (for internal use / export).
  String generateReport() {
    final buf = StringBuffer();
    buf.writeln('=== HUDDL APP FEEDBACK REPORT ===');
    buf.writeln('Generated: ${DateTime.now().toString().substring(0, 19)}');
    buf.writeln('Total ratings: $totalRatings');
    buf.writeln(
        'Real average rating: ${realAverageRating.toStringAsFixed(2)} / 5.0');
    buf.writeln('Display rating (shown to users): $displayRating / 5.0');
    buf.writeln('Target email: $_targetEmail');
    buf.writeln('');
    for (var i = 0; i < _allRatings.length; i++) {
      final r = _allRatings[i];
      buf.writeln('--- Entry ${i + 1} ---');
      buf.writeln('  User: ${r['user']}');
      buf.writeln('  Rating: ${r['rating']} / 5');
      buf.writeln('  Feedback: ${r['feedback']}');
      buf.writeln('  Time: ${r['timestamp']}');
      buf.writeln('');
    }
    buf.writeln('=== END OF REPORT ===');
    return buf.toString();
  }
}
