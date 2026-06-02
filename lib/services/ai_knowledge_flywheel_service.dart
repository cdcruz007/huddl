import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'ai_api_helper.dart';
import 'ai_knowledge_base_service.dart';

// =============================================================================
// AI KNOWLEDGE FLYWHEEL SERVICE — HUDDL WISDOM ENGINE
//
// Implements the Community Knowledge Extraction loop:
//
//   Community conversations
//       ↓  (weekly AI pass)
//   High-quality discussions identified
//       ↓  (moderator / author consent)
//   CommunityWisdomArticle published
//       ↓  (searchable Huddl Wisdom feed)
//   Future parents find answers → more parents join → more conversations
//
// Firestore schema:
//   community_wisdom/{articleId}   — published / in-review articles
//
// Article lifecycle:
//   pending_review  → moderator queues article for consent
//   consent_pending → author notified, awaiting approval
//   approved        → author consented; ready to publish
//   published       → live in the Insights feed
//   rejected        → author declined or moderator dismissed
//
// Contributor credit format:
//   "{firstName}, Cambridge parent"   (never surname, never UID exposed)
// =============================================================================

// ─── Enums ────────────────────────────────────────────────────────────────────

enum WisdomArticleStatus {
  pendingReview,
  consentPending,
  approved,
  published,
  rejected,
}

extension WisdomArticleStatusX on WisdomArticleStatus {
  String get firestoreValue => switch (this) {
        WisdomArticleStatus.pendingReview  => 'pending_review',
        WisdomArticleStatus.consentPending => 'consent_pending',
        WisdomArticleStatus.approved       => 'approved',
        WisdomArticleStatus.published      => 'published',
        WisdomArticleStatus.rejected       => 'rejected',
      };

  String get displayLabel => switch (this) {
        WisdomArticleStatus.pendingReview  => 'Pending Review',
        WisdomArticleStatus.consentPending => 'Awaiting Consent',
        WisdomArticleStatus.approved       => 'Approved',
        WisdomArticleStatus.published      => 'Published',
        WisdomArticleStatus.rejected       => 'Rejected',
      };

  static WisdomArticleStatus fromString(String v) => switch (v) {
        'consent_pending' => WisdomArticleStatus.consentPending,
        'approved'        => WisdomArticleStatus.approved,
        'published'       => WisdomArticleStatus.published,
        'rejected'        => WisdomArticleStatus.rejected,
        _                 => WisdomArticleStatus.pendingReview,
      };
}

// ─── Model ────────────────────────────────────────────────────────────────────

/// A community-sourced wisdom article extracted from group chat conversations.
///
/// Extends the concept of [KnowledgeArticle] with provenance, consent, and
/// contributor credit fields.  Stored in Firestore `community_wisdom/{id}`.
class CommunityWisdomArticle {
  final String id;

  // Content
  final String title;
  final String summary;
  final String body;
  final KnowledgeCategory category;
  final List<String> tags;

  // Provenance — links back to the source conversation
  final String groupId;
  final String groupName;
  final List<String> originalMessageIds;

  // Contributor credit (privacy-safe: first name + borough label only)
  final String contributorFirstName;
  final String contributorBorough;
  final String contributorCredit; // e.g. "Sarah, Cambridge parent"

  // AI extraction metadata
  final String aiGeneratedSummary;
  final double engagementScore; // 0.0–1.0, derived from reaction / reply count

  // Lifecycle
  final WisdomArticleStatus status;
  final String? moderatorId;
  final DateTime? moderatorReviewedAt;
  final DateTime? approvedAt;
  final DateTime? publishedAt;
  final DateTime extractedAt;

  // Engagement on the published article
  final int upvotes;
  final int viewCount;

  // Author consent tracking
  final String authorUid;         // UID of the contributing parent (internal)
  final bool consentGranted;

  // Optional hero image URL — set by moderator when publishing
  final String? heroImageUrl;

  // Parent-shared link — true when submitted via the + FAB compose sheet
  final bool isParentShared;

  // External URL for parent-shared link cards
  final String? externalUrl;

  const CommunityWisdomArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
    required this.category,
    required this.tags,
    required this.groupId,
    required this.groupName,
    required this.originalMessageIds,
    required this.contributorFirstName,
    required this.contributorBorough,
    required this.contributorCredit,
    required this.aiGeneratedSummary,
    required this.engagementScore,
    required this.status,
    required this.extractedAt,
    required this.authorUid,
    required this.consentGranted,
    this.moderatorId,
    this.moderatorReviewedAt,
    this.approvedAt,
    this.publishedAt,
    this.upvotes = 0,
    this.viewCount = 0,
    this.heroImageUrl,
    this.isParentShared = false,
    this.externalUrl,
  });

  // ── Firestore serialisation ────────────────────────────────────────────────

  Map<String, dynamic> toFirestore() => {
        'title':                  title,
        'summary':                summary,
        'body':                   body,
        'category':               category.name,
        'tags':                   tags,
        'group_id':               groupId,
        'group_name':             groupName,
        'original_message_ids':   originalMessageIds,
        'contributor_first_name': contributorFirstName,
        'contributor_borough':    contributorBorough,
        'contributor_credit':     contributorCredit,
        'ai_generated_summary':   aiGeneratedSummary,
        'engagement_score':       engagementScore,
        'status':                 status.firestoreValue,
        'moderator_id':           moderatorId,
        'moderator_reviewed_at':  moderatorReviewedAt != null
            ? Timestamp.fromDate(moderatorReviewedAt!)
            : null,
        'approved_at':            approvedAt != null
            ? Timestamp.fromDate(approvedAt!)
            : null,
        'published_at':           publishedAt != null
            ? Timestamp.fromDate(publishedAt!)
            : null,
        'extracted_at':           Timestamp.fromDate(extractedAt),
        'author_uid':             authorUid,
        'consent_granted':        consentGranted,
        'upvotes':                upvotes,
        'view_count':             viewCount,
        if (heroImageUrl != null) 'hero_image_url': heroImageUrl,
        if (isParentShared) 'is_parent_shared': true,
        if (externalUrl != null) 'external_url': externalUrl,
      };

  factory CommunityWisdomArticle.fromFirestore(
    Map<String, dynamic> data,
    String docId,
  ) {
    DateTime? ts(String key) {
      final v = data[key];
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      return null;
    }

    KnowledgeCategory cat(String? v) {
      try {
        return KnowledgeCategory.values.firstWhere(
          (e) => e.name == (v ?? ''),
          orElse: () => KnowledgeCategory.parentalWellbeing,
        );
      } catch (_) {
        return KnowledgeCategory.parentalWellbeing;
      }
    }

    return CommunityWisdomArticle(
      id:                    docId,
      title:                 data['title'] as String? ?? '',
      summary:               data['summary'] as String? ?? '',
      body:                  data['body'] as String? ?? '',
      category:              cat(data['category'] as String?),
      tags:                  List<String>.from(data['tags'] as List? ?? []),
      groupId:               data['group_id'] as String? ?? '',
      groupName:             data['group_name'] as String? ?? '',
      originalMessageIds:    List<String>.from(data['original_message_ids'] as List? ?? []),
      contributorFirstName:  data['contributor_first_name'] as String? ?? '',
      contributorBorough:    data['contributor_borough'] as String? ?? '',
      contributorCredit:     data['contributor_credit'] as String? ?? '',
      aiGeneratedSummary:    data['ai_generated_summary'] as String? ?? '',
      engagementScore:       (data['engagement_score'] as num?)?.toDouble() ?? 0.0,
      status:                WisdomArticleStatusX.fromString(data['status'] as String? ?? ''),
      extractedAt:           ts('extracted_at') ?? DateTime.now(),
      authorUid:             data['author_uid'] as String? ?? '',
      consentGranted:        data['consent_granted'] as bool? ?? false,
      moderatorId:           data['moderator_id'] as String?,
      moderatorReviewedAt:   ts('moderator_reviewed_at'),
      approvedAt:            ts('approved_at'),
      publishedAt:           ts('published_at'),
      upvotes:               data['upvotes'] as int? ?? 0,
      viewCount:             data['view_count'] as int? ?? 0,
      heroImageUrl:          data['hero_image_url'] as String?,
      isParentShared:        data['is_parent_shared'] as bool? ?? false,
      externalUrl:           data['external_url'] as String?,
    );
  }

  CommunityWisdomArticle copyWith({
    WisdomArticleStatus? status,
    String? moderatorId,
    DateTime? moderatorReviewedAt,
    DateTime? approvedAt,
    DateTime? publishedAt,
    bool? consentGranted,
    int? upvotes,
    int? viewCount,
    String? heroImageUrl,
    bool? isParentShared,
    String? externalUrl,
  }) =>
      CommunityWisdomArticle(
        id:                    id,
        title:                 title,
        summary:               summary,
        body:                  body,
        category:              category,
        tags:                  tags,
        groupId:               groupId,
        groupName:             groupName,
        originalMessageIds:    originalMessageIds,
        contributorFirstName:  contributorFirstName,
        contributorBorough:    contributorBorough,
        contributorCredit:     contributorCredit,
        aiGeneratedSummary:    aiGeneratedSummary,
        engagementScore:       engagementScore,
        status:                status ?? this.status,
        extractedAt:           extractedAt,
        authorUid:             authorUid,
        consentGranted:        consentGranted ?? this.consentGranted,
        moderatorId:           moderatorId ?? this.moderatorId,
        moderatorReviewedAt:   moderatorReviewedAt ?? this.moderatorReviewedAt,
        approvedAt:            approvedAt ?? this.approvedAt,
        publishedAt:           publishedAt ?? this.publishedAt,
        upvotes:               upvotes ?? this.upvotes,
        viewCount:             viewCount ?? this.viewCount,
        heroImageUrl:          heroImageUrl ?? this.heroImageUrl,
        isParentShared:        isParentShared ?? this.isParentShared,
        externalUrl:           externalUrl ?? this.externalUrl,
      );
}

// ─── Candidate message (transient, not stored) ────────────────────────────────

/// A group message identified by the AI pass as a potential wisdom candidate.
class FlywheelCandidate {
  final String messageId;
  final String messageText;
  final String senderId;
  final String senderFirstName;
  final String senderBorough;
  final int reactionCount;
  final int replyCount;
  final DateTime sentAt;
  final double engagementScore;

  const FlywheelCandidate({
    required this.messageId,
    required this.messageText,
    required this.senderId,
    required this.senderFirstName,
    required this.senderBorough,
    required this.reactionCount,
    required this.replyCount,
    required this.sentAt,
    required this.engagementScore,
  });
}

// ─── Service ──────────────────────────────────────────────────────────────────

class AiKnowledgeFlywheelService {
  static final AiKnowledgeFlywheelService _instance =
      AiKnowledgeFlywheelService._internal();
  factory AiKnowledgeFlywheelService() => _instance;
  AiKnowledgeFlywheelService._internal();

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Firestore references ───────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _wisdomCol =>
      _firestore.collection('community_wisdom');

  // ── Public read API ────────────────────────────────────────────────────────

  /// Stream of published wisdom articles, sorted by publishedAt desc.
  Stream<List<CommunityWisdomArticle>> publishedArticlesStream() =>
      _wisdomCol
          .where('status', isEqualTo: WisdomArticleStatus.published.firestoreValue)
          .snapshots()
          .map((snap) {
        final articles = snap.docs
            .map((d) => CommunityWisdomArticle.fromFirestore(d.data(), d.id))
            .toList();
        articles.sort((a, b) =>
            (b.publishedAt ?? b.extractedAt)
                .compareTo(a.publishedAt ?? a.extractedAt));
        return articles;
      });

  /// Stream of articles pending moderator review.
  Stream<List<CommunityWisdomArticle>> pendingReviewStream() =>
      _wisdomCol
          .where('status', isEqualTo: WisdomArticleStatus.pendingReview.firestoreValue)
          .snapshots()
          .map((snap) {
        final articles = snap.docs
            .map((d) => CommunityWisdomArticle.fromFirestore(d.data(), d.id))
            .toList();
        articles.sort((a, b) => b.extractedAt.compareTo(a.extractedAt));
        return articles;
      });

  /// Fetch a single article by ID.
  Future<CommunityWisdomArticle?> getArticle(String id) async {
    try {
      final doc = await _wisdomCol.doc(id).get();
      if (!doc.exists) return null;
      return CommunityWisdomArticle.fromFirestore(doc.data()!, doc.id);
    } catch (e) {
      if (kDebugMode) debugPrint('[Flywheel] getArticle error: $e');
      return null;
    }
  }

  // ── AI extraction pass ────────────────────────────────────────────────────

  /// Runs the AI pass over a batch of group messages and returns
  /// [FlywheelCandidate] objects ranked by engagement + AI quality score.
  ///
  /// [messages] — list of raw message maps:
  ///   { 'id', 'text', 'sender_id', 'sender_name', 'reaction_count', 'reply_count', 'sent_at' }
  ///
  /// Typically called by a Cloud Function on a weekly schedule, but can also
  /// be triggered manually from the Admin Dashboard for testing.
  Future<List<FlywheelCandidate>> runFlywheelPass({
    required String groupId,
    required List<Map<String, dynamic>> messages,
    required String borough,
  }) async {
    if (messages.isEmpty) return [];

    // Step 1: Filter by engagement threshold (saves AI quota)
    final engaged = messages.where((m) {
      final reactions = (m['reaction_count'] as num?)?.toInt() ?? 0;
      final replies   = (m['reply_count']   as num?)?.toInt() ?? 0;
      return reactions + replies >= 2; // minimum engagement gate
    }).toList();

    if (engaged.isEmpty) return [];

    // Step 2: AI quality scoring
    final candidates = <FlywheelCandidate>[];
    for (final msg in engaged.take(50)) {
      // Cap at 50 per pass to manage costs
      final text = msg['text'] as String? ?? '';
      if (text.length < 40) continue; // skip very short messages

      final score = await _scoreMessageQuality(text);
      if (score < 0.5) continue; // below quality threshold

      final reactions  = (msg['reaction_count'] as num?)?.toInt() ?? 0;
      final replies    = (msg['reply_count']   as num?)?.toInt() ?? 0;
      final engagement = ((reactions * 0.6 + replies * 0.4) / 10.0).clamp(0.0, 1.0);
      final combined   = (score * 0.6 + engagement * 0.4).clamp(0.0, 1.0);

      // Parse sender name → first name only for privacy
      final fullName   = msg['sender_name'] as String? ?? 'Parent';
      final firstName  = fullName.split(' ').first;

      DateTime sentAt;
      final sentRaw = msg['sent_at'];
      if (sentRaw is Timestamp) {
        sentAt = sentRaw.toDate();
      } else {
        sentAt = DateTime.now();
      }

      candidates.add(FlywheelCandidate(
        messageId:      msg['id'] as String? ?? '',
        messageText:    text,
        senderId:       msg['sender_id'] as String? ?? '',
        senderFirstName: firstName,
        senderBorough:  borough,
        reactionCount:  reactions,
        replyCount:     replies,
        sentAt:         sentAt,
        engagementScore: combined,
      ));
    }

    candidates.sort((a, b) => b.engagementScore.compareTo(a.engagementScore));
    return candidates.take(10).toList(); // top 10 per group per pass
  }

  /// Asks Gemini to score a message for educational / community value.
  /// Returns a score 0.0–1.0.  Returns 0.0 on error (conservative).
  Future<double> _scoreMessageQuality(String text) async {
    try {
      final prompt = '''
You are evaluating messages from a UK parenting community for educational value.

Rate the following message on a scale from 0.0 to 1.0 based on:
- Practical parenting advice or helpful information (high score)
- Local knowledge useful to other parents (high score)
- Emotional support or lived experience worth preserving (medium score)
- Generic chat, jokes, or logistical messages (low score)
- Any harmful or inappropriate content (0.0)

Respond with ONLY a decimal number between 0.0 and 1.0. No other text.

Message:
"$text"
''';

      final requestBody = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 8,
          'topP': 1.0,
        },
      };

      final raw = await AiApiHelper.generateText(
        requestBody,
        timeout: const Duration(seconds: 10),
      );
      if (raw == null) return 0.0;

      return double.tryParse(raw.trim()) ?? 0.0;
    } catch (e) {
      if (kDebugMode) debugPrint('[Flywheel] _scoreMessageQuality error: $e');
      return 0.0;
    }
  }

  // ── Article generation ─────────────────────────────────────────────────────

  /// Generates a full [CommunityWisdomArticle] from a [FlywheelCandidate]
  /// and saves it to Firestore with status `pending_review`.
  Future<CommunityWisdomArticle?> generateAndSaveArticle({
    required FlywheelCandidate candidate,
    required String groupId,
    required String groupName,
  }) async {
    try {
      final articleContent = await _generateArticleContent(candidate.messageText);
      if (articleContent == null) return null;

      final category = _inferCategory(candidate.messageText);
      final credit   =
          '${candidate.senderFirstName}, ${candidate.senderBorough} parent';
      final docId    = _wisdomCol.doc().id;

      final article = CommunityWisdomArticle(
        id:                    docId,
        title:                 articleContent['title'] ?? 'Community Tip',
        summary:               articleContent['summary'] ?? '',
        body:                  articleContent['body'] ?? candidate.messageText,
        category:              category,
        tags:                  List<String>.from(articleContent['tags'] ?? []),
        groupId:               groupId,
        groupName:             groupName,
        originalMessageIds:    [candidate.messageId],
        contributorFirstName:  candidate.senderFirstName,
        contributorBorough:    candidate.senderBorough,
        contributorCredit:     credit,
        aiGeneratedSummary:    articleContent['summary'] ?? '',
        engagementScore:       candidate.engagementScore,
        status:                WisdomArticleStatus.pendingReview,
        extractedAt:           DateTime.now(),
        authorUid:             candidate.senderId,
        consentGranted:        false,
      );

      await _wisdomCol.doc(docId).set(article.toFirestore());
      if (kDebugMode) debugPrint('[Flywheel] Saved pending article: ${article.title}');
      return article;
    } catch (e) {
      if (kDebugMode) debugPrint('[Flywheel] generateAndSaveArticle error: $e');
      return null;
    }
  }

  /// Calls Gemini to expand a raw message into a structured article.
  Future<Map<String, dynamic>?> _generateArticleContent(String rawText) async {
    try {
      final prompt = '''
You are a helpful editor for Huddl Wisdom, a community knowledge base for UK parents.

A parent in a local parenting group shared the following helpful message. Your task is to expand it into a short, warm, practical knowledge article.

Original message:
"$rawText"

Return a JSON object with these exact keys:
{
  "title": "A short, practical title (max 10 words)",
  "summary": "One sentence summary (max 25 words)",
  "body": "A warm, practical 2–3 paragraph article in UK English. Preserve the parent's voice. Add context but do not invent facts.",
  "tags": ["tag1", "tag2", "tag3"]
}

Rules:
- Write in second person ("you", "your child")
- Keep it conversational and warm, not clinical
- Do NOT include the parent's name or any identifying information
- Tags should be 1–3 word phrases relevant to UK parents
- Respond with ONLY the JSON object, no other text
''';

      final requestBody = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 600,
          'topP': 0.95,
        },
      };

      final raw = await AiApiHelper.generateText(
        requestBody,
        timeout: const Duration(seconds: 20),
      );
      if (raw == null) return null;

      // Strip markdown fences if present
      final cleaned = raw
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) debugPrint('[Flywheel] _generateArticleContent error: $e');
      return null;
    }
  }

  // ── Moderator actions ──────────────────────────────────────────────────────

  /// Moderator approves an article (moves to `approved`, then publishes).
  Future<bool> approveArticle(String articleId) async {
    try {
      final uid = _auth.currentUser?.uid;
      await _wisdomCol.doc(articleId).update({
        'status':               WisdomArticleStatus.published.firestoreValue,
        'moderator_id':         uid,
        'moderator_reviewed_at': FieldValue.serverTimestamp(),
        'approved_at':           FieldValue.serverTimestamp(),
        'published_at':          FieldValue.serverTimestamp(),
        'consent_granted':       true,
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Flywheel] approveArticle error: $e');
      return false;
    }
  }

  /// Moderator rejects / dismisses an article.
  Future<bool> rejectArticle(String articleId) async {
    try {
      final uid = _auth.currentUser?.uid;
      await _wisdomCol.doc(articleId).update({
        'status':               WisdomArticleStatus.rejected.firestoreValue,
        'moderator_id':         uid,
        'moderator_reviewed_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Flywheel] rejectArticle error: $e');
      return false;
    }
  }

  // ── User engagement ────────────────────────────────────────────────────────

  /// Records an upvote.  Uses a sub-collection to prevent double-voting.
  Future<void> upvoteArticle(String articleId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final voteRef = _wisdomCol
          .doc(articleId)
          .collection('upvotes')
          .doc(uid);
      final existing = await voteRef.get();
      if (existing.exists) return; // already upvoted

      final batch = _firestore.batch();
      batch.set(voteRef, {'voted_at': FieldValue.serverTimestamp()});
      batch.update(_wisdomCol.doc(articleId), {
        'upvotes': FieldValue.increment(1),
      });
      await batch.commit();
    } catch (e) {
      if (kDebugMode) debugPrint('[Flywheel] upvoteArticle error: $e');
    }
  }

  /// Increments the view count (fire-and-forget).
  void recordView(String articleId) {
    _wisdomCol.doc(articleId).update({
      'view_count': FieldValue.increment(1),
    }).catchError((e) {
      if (kDebugMode) debugPrint('[Flywheel] recordView error: $e');
    });
  }

  // ── Parent-shared link submission ─────────────────────────────────────────

  /// Allows any logged-in parent to share an external URL as a published
  /// insight.  Written directly as `published` — no moderation step needed
  /// for URL-only shares (no AI-extracted content, no consent requirement).
  ///
  /// Returns the new article ID on success, null on failure.
  Future<String?> submitParentSharedLink({
    required String title,
    required String summary,
    required String externalUrl,
    required KnowledgeCategory category,
    required String contributorFirstName,
    required String contributorBorough,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    try {
      final now = DateTime.now();
      final docRef = _wisdomCol.doc();
      final article = CommunityWisdomArticle(
        id:                    docRef.id,
        title:                 title.trim(),
        summary:               summary.trim(),
        body:                  summary.trim(),
        category:              category,
        tags:                  [],
        groupId:               'parent_share',
        groupName:             'Parent Recommendation',
        originalMessageIds:    [],
        contributorFirstName:  contributorFirstName,
        contributorBorough:    contributorBorough,
        contributorCredit:     '$contributorFirstName, $contributorBorough parent',
        aiGeneratedSummary:    '',
        engagementScore:       0.0,
        status:                WisdomArticleStatus.published,
        extractedAt:           now,
        authorUid:             uid,
        consentGranted:        true,
        publishedAt:           now,
        isParentShared:        true,
        externalUrl:           externalUrl.trim(),
      );
      await docRef.set(article.toFirestore());
      if (kDebugMode) debugPrint('[Flywheel] parent-shared link submitted: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      if (kDebugMode) debugPrint('[Flywheel] submitParentSharedLink error: $e');
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Simple keyword-based category inference as a fallback before AI pass.
  KnowledgeCategory _inferCategory(String text) {
    final lower = text.toLowerCase();
    if (_anyOf(lower, ['sleep', 'nap', 'bedtime', 'night waking'])) {
      return KnowledgeCategory.sleep;
    }
    if (_anyOf(lower, ['feed', 'breastfeed', 'bottle', 'weaning', 'solids'])) {
      return KnowledgeCategory.feeding;
    }
    if (_anyOf(lower, ['nhs', 'gp', 'doctor', 'hospital', 'rash', 'fever', 'vaccine'])) {
      return KnowledgeCategory.health;
    }
    if (_anyOf(lower, ['school', 'reception', 'year 1', 'ofsted', 'sats', 'homework'])) {
      return KnowledgeCategory.education;
    }
    if (_anyOf(lower, ['toddler', '18 month', '2 year'])) {
      return KnowledgeCategory.toddler;
    }
    if (_anyOf(lower, ['baby', 'newborn', '4 month', '6 month'])) {
      return KnowledgeCategory.baby;
    }
    if (_anyOf(lower, ['pregnancy', 'pregnant', 'trimester', 'birth', 'labour'])) {
      return KnowledgeCategory.pregnancy;
    }
    if (_anyOf(lower, ['anxiety', 'postnatal', 'mental health', 'overwhelmed', 'burnout'])) {
      return KnowledgeCategory.mentalHealth;
    }
    if (_anyOf(lower, ['activity', 'class', 'park', 'soft play', 'swimming'])) {
      return KnowledgeCategory.activities;
    }
    if (_anyOf(lower, ['childcare', 'nursery', 'childminder', 'wrap around'])) {
      return KnowledgeCategory.finance;
    }
    return KnowledgeCategory.parentalWellbeing;
  }

  bool _anyOf(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));
}
