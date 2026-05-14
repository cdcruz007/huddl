import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Report types for messages and listings.
enum ReportType {
  spam,
  harassment,
  hateSpeech,
  inappropriateContent,
  misinformation,
  scam,
  other,
}

extension ReportTypeLabel on ReportType {
  String get label => switch (this) {
        ReportType.spam              => 'Spam',
        ReportType.harassment        => 'Harassment or bullying',
        ReportType.hateSpeech        => 'Hate speech',
        ReportType.inappropriateContent => 'Inappropriate content',
        ReportType.misinformation    => 'Misinformation',
        ReportType.scam              => 'Scam or fraud',
        ReportType.other             => 'Other',
      };

  String get firestoreValue => switch (this) {
        ReportType.spam              => 'spam',
        ReportType.harassment        => 'harassment',
        ReportType.hateSpeech        => 'hate_speech',
        ReportType.inappropriateContent => 'inappropriate_content',
        ReportType.misinformation    => 'misinformation',
        ReportType.scam              => 'scam',
        ReportType.other             => 'other',
      };
}

/// Context in which the report was filed.
enum ReportContext { groupMessage, dmMessage, listing }

extension ReportContextValue on ReportContext {
  String get firestoreValue => switch (this) {
        ReportContext.groupMessage => 'group_message',
        ReportContext.dmMessage    => 'dm_message',
        ReportContext.listing      => 'listing',
      };
}

/// Service that writes content reports to Firestore `reports/{reportId}`.
///
/// Firestore document schema:
/// ```
///   reports/{reportId} {
///     messageId      : String   — ID of the message or listing being reported
///     reporterId     : String   — UID of the user filing the report
///     targetUserId   : String   — UID of the content author
///     type           : String   — ReportType.firestoreValue
///     context        : String   — ReportContext.firestoreValue
///     groupId        : String?  — set for group_message reports
///     status         : String   — 'pending' on creation
///     timestamp      : Timestamp
///   }
/// ```
///
/// Security rule (add to Firestore rules):
///   match /reports/{reportId} {
///     allow create: if request.auth != null
///                   && request.resource.data.reporterId == request.auth.uid;
///     allow read, update, delete: if false; // admin only via Console/SDK
///   }
class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Submit a report for a message or listing.
  ///
  /// Returns `true` on success, `false` if the write failed (e.g. offline).
  Future<bool> submitReport({
    required String contentId,
    required String targetUserId,
    required ReportType type,
    required ReportContext context,
    String? groupId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('[ReportService] Not authenticated — cannot file report');
      return false;
    }

    try {
      final doc = _db.collection('reports').doc();
      await doc.set({
        'messageId'   : contentId,
        'reporterId'  : uid,
        'targetUserId': targetUserId,
        'type'        : type.firestoreValue,
        'context'     : context.firestoreValue,
        if (groupId != null) 'groupId': groupId,
        'status'      : 'pending',
        'timestamp'   : FieldValue.serverTimestamp(),
      });
      debugPrint('[ReportService] Report filed: ${doc.id}');
      return true;
    } catch (e) {
      debugPrint('[ReportService] Failed to file report: $e');
      return false;
    }
  }
}
