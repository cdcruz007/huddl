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
  childSafetyConcern,
  other,
}

extension ReportTypeLabel on ReportType {
  String get label => switch (this) {
        ReportType.spam                 => 'Spam',
        ReportType.harassment           => 'Harassment or bullying',
        ReportType.hateSpeech           => 'Hate speech',
        ReportType.inappropriateContent => 'Inappropriate content',
        ReportType.misinformation       => 'Misinformation',
        ReportType.scam                 => 'Scam or fraud',
        ReportType.childSafetyConcern   => 'Child safety concern',
        ReportType.other                => 'Other',
      };

  String get firestoreValue => switch (this) {
        ReportType.spam                 => 'spam',
        ReportType.harassment           => 'harassment',
        ReportType.hateSpeech           => 'hate_speech',
        ReportType.inappropriateContent => 'inappropriate_content',
        ReportType.misinformation       => 'misinformation',
        ReportType.scam                 => 'scam',
        ReportType.childSafetyConcern   => 'child_safety_concern',
        ReportType.other                => 'other',
      };
}

/// Context in which the report was filed.
enum ReportContext { groupMessage, dmMessage, listing, userProfile }

extension ReportContextValue on ReportContext {
  String get firestoreValue => switch (this) {
        ReportContext.groupMessage => 'group_message',
        ReportContext.dmMessage    => 'dm_message',
        ReportContext.listing      => 'listing',
        ReportContext.userProfile  => 'user_profile',
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
///     reason         : String   — Human-readable label of the report type
///     context        : String   — ReportContext.firestoreValue
///     groupId        : String?  — set for group_message reports
///     chatName       : String?  — group name, DM partner name, or listing title
///     messagePreview : String?  — first 300 chars of the reported message/content
///     status         : String   — 'pending' on creation
///     timestamp      : Timestamp
///   }
/// ```
class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Submit a report for a message, listing, or user profile.
  ///
  /// [messagePreview] — the text of the reported message (truncated to 300 chars).
  ///   Pass null for profile/listing reports where there is no message body.
  /// [chatName] — the group name, DM recipient name, or listing title.
  ///   Denormalised at write time so the admin dashboard never needs a
  ///   secondary Firestore lookup for the chat/context name.
  ///
  /// Returns `true` on success, `false` if the write failed (e.g. offline).
  Future<bool> submitReport({
    required String contentId,
    required String targetUserId,
    required ReportType type,
    required ReportContext context,
    String? groupId,
    String? chatName,
    String? messagePreview,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('[ReportService] Not authenticated — cannot file report');
      return false;
    }

    // Truncate message preview to 300 chars to keep document size reasonable
    final preview = messagePreview != null && messagePreview.trim().isNotEmpty
        ? messagePreview.trim().substring(0, messagePreview.trim().length.clamp(0, 300))
        : null;

    try {
      final doc = _db.collection('reports').doc();
      await doc.set({
        'messageId'   : contentId,
        'reporterId'  : uid,
        'targetUserId': targetUserId,
        'type'        : type.firestoreValue,
        'reason'      : type.label,
        'context'     : context.firestoreValue,
        if (groupId  != null) 'groupId'       : groupId,
        if (chatName != null) 'chatName'       : chatName,
        if (preview  != null) 'messagePreview' : preview,
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
