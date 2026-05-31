import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'borough_scope_guard.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnnouncementComment
// ─────────────────────────────────────────────────────────────────────────────

/// A comment on an announcement.
class AnnouncementComment {
  final String id;
  final String authorName;
  final String? authorPhotoUrl;
  final String content;
  final DateTime createdAt;
  int likes;
  bool isLiked;

  /// When non-null this comment is a reply; value is the author being replied to.
  final String? replyToName;

  AnnouncementComment({
    required this.id,
    required this.authorName,
    this.authorPhotoUrl,
    required this.content,
    required this.createdAt,
    this.likes = 0,
    this.isLiked = false,
    this.replyToName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorName': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'likes': likes,
        'isLiked': isLiked,
        if (replyToName != null) 'replyToName': replyToName,
      };

  /// Firestore map — same as JSON but avoids redundant isLiked (device-local).
  Map<String, dynamic> toFirestoreMap() => {
        'id': id,
        'authorName': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'likes': likes,
        if (replyToName != null) 'replyToName': replyToName,
      };

  factory AnnouncementComment.fromJson(Map<String, dynamic> j) =>
      AnnouncementComment(
        id: j['id'] as String,
        authorName: j['authorName'] as String,
        authorPhotoUrl: j['authorPhotoUrl'] as String?,
        content: j['content'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        likes: j['likes'] as int? ?? 0,
        isLiked: j['isLiked'] as bool? ?? false,
        replyToName: j['replyToName'] as String?,
      );

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Announcement model
// ─────────────────────────────────────────────────────────────────────────────

/// A single borough-scoped announcement — like a notice on a town hall board.
class Announcement {
  final String id;
  final String authorId;       // UID of the post author (required for delete rule)
  final String authorName;
  final String? authorPhotoUrl;
  final String borough;        // legacy local field — kept for BrowserStorage compat
  final String boroughId;      // Firestore field name (== borough value)
  final String content;
  final DateTime createdAt;
  int likes;
  List<String> likedBy;        // concurrent-safe via arrayUnion/arrayRemove
  int comments;
  bool isLiked;                // device-local derived field (not stored in Firestore)
  bool isPinned;
  bool isBookmarked;           // device-local (not synced to Firestore)
  int shares;
  List<AnnouncementComment> commentsList;

  /// True when posted by a Huddl Partner business account.
  /// Drives the Partner badge display on the post card.
  final bool isPartnerPost;

  /// The verified business name — shown as author on Partner posts.
  /// Null on standard user posts.
  final String? businessName;

  /// The ID of the service listing this post is promoting.
  /// Null when no listing is attached.
  final String? linkedListingId;

  /// The display name of the linked service listing.
  /// Cached at post time so the card renders without a Firestore lookup.
  final String? linkedListingName;

  Announcement({
    required this.id,
    this.authorId = '',
    required this.authorName,
    this.authorPhotoUrl,
    required this.borough,
    String? boroughId,
    required this.content,
    required this.createdAt,
    this.likes = 0,
    List<String>? likedBy,
    this.comments = 0,
    this.isLiked = false,
    this.isPinned = false,
    this.isBookmarked = false,
    this.shares = 0,
    List<AnnouncementComment>? commentsList,
    this.isPartnerPost = false,
    this.businessName,
    this.linkedListingId,
    this.linkedListingName,
  })  : boroughId = boroughId ?? borough,
        likedBy = likedBy ?? [],
        commentsList = commentsList ?? [];

  // ── BrowserStorage serialisation ────────────────────────────────────────
  Map<String, dynamic> toJson() => {
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'borough': borough,
        'boroughId': boroughId,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'likes': likes,
        'likedBy': likedBy,
        'comments': comments,
        'isLiked': isLiked,
        'isPinned': isPinned,
        'isBookmarked': isBookmarked,
        'shares': shares,
        'commentsList': commentsList.map((c) => c.toJson()).toList(),
        'isPartnerPost': isPartnerPost,
        if (businessName != null) 'businessName': businessName,
        if (linkedListingId != null) 'linkedListingId': linkedListingId,
        if (linkedListingName != null) 'linkedListingName': linkedListingName,
      };

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'] as String,
        authorId: j['authorId'] as String? ?? '',
        authorName: j['authorName'] as String,
        authorPhotoUrl: j['authorPhotoUrl'] as String?,
        borough: (j['borough'] ?? j['boroughId'] ?? '') as String,
        boroughId: (j['boroughId'] ?? j['borough'] ?? '') as String,
        content: j['content'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        likes: j['likes'] as int? ?? 0,
        likedBy: (j['likedBy'] as List<dynamic>?)?.cast<String>() ?? [],
        comments: j['comments'] as int? ?? 0,
        isLiked: j['isLiked'] as bool? ?? false,
        isPinned: j['isPinned'] as bool? ?? false,
        isBookmarked: j['isBookmarked'] as bool? ?? false,
        shares: j['shares'] as int? ?? 0,
        commentsList: (j['commentsList'] as List<dynamic>?)
                ?.map((e) =>
                    AnnouncementComment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        isPartnerPost: j['isPartnerPost'] as bool? ?? false,
        businessName: j['businessName'] as String?,
        linkedListingId: j['linkedListingId'] as String?,
        linkedListingName: j['linkedListingName'] as String?,
      );

  // ── Firestore serialisation ─────────────────────────────────────────────
  /// Map written to Firestore on create.  Uses FieldValue.serverTimestamp()
  /// so all clients share the same canonical timestamp.
  Map<String, dynamic> toFirestore() => {
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'boroughId': boroughId,
        'content': content,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': likes,
        'likedBy': likedBy,
        'comments': comments,
        'isPinned': isPinned,
        'isBookmarked': isBookmarked,
        'shares': shares,
        'commentsList':
            commentsList.map((c) => c.toFirestoreMap()).toList(),
        'isPartnerPost': isPartnerPost,
        if (businessName != null) 'businessName': businessName,
        if (linkedListingId != null) 'linkedListingId': linkedListingId,
        if (linkedListingName != null) 'linkedListingName': linkedListingName,
      };

  /// Reconstruct from a Firestore document snapshot.
  /// Handles both Timestamp (live) and null (pending write) for createdAt.
  factory Announcement.fromFirestore(
      Map<String, dynamic> data, String docId, String? currentUid) {
    DateTime dt;
    final raw = data['createdAt'];
    if (raw is Timestamp) {
      dt = raw.toDate();
    } else {
      // Pending server timestamp — fall back to now
      dt = DateTime.now();
    }

    final likedByList =
        (data['likedBy'] as List<dynamic>?)?.cast<String>() ?? [];

    return Announcement(
      id: docId,
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'Unknown',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      borough: data['boroughId'] as String? ?? '',
      boroughId: data['boroughId'] as String? ?? '',
      content: data['content'] as String? ?? '',
      createdAt: dt,
      likes: data['likes'] as int? ?? 0,
      likedBy: likedByList,
      comments: data['comments'] as int? ?? 0,
      // isLiked is derived locally from likedBy + currentUid
      isLiked: currentUid != null && likedByList.contains(currentUid),
      isPinned: data['isPinned'] as bool? ?? false,
      isBookmarked: data['isBookmarked'] as bool? ?? false,
      shares: data['shares'] as int? ?? 0,
      commentsList: (data['commentsList'] as List<dynamic>?)
              ?.map((e) =>
                  AnnouncementComment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isPartnerPost: data['isPartnerPost'] as bool? ?? false,
      businessName: data['businessName'] as String?,
      linkedListingId: data['linkedListingId'] as String?,
      linkedListingName: data['linkedListingName'] as String?,
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AnnouncementService
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton that manages borough-scoped announcements.
///
/// DUAL-WRITE: every mutation writes to BOTH Firestore
/// (`borough_announcements` collection) AND BrowserStorage (as offline cache).
///
/// REAL-TIME: a Firestore `.snapshots()` stream replaces the old one-shot
/// `_loadFromStorage()`.  Each snapshot is cached to BrowserStorage so the
/// board is still visible when offline.
///
/// HYPERLOCAL RULE: Announcements are borough-only.
/// Parents can only see and post announcements within their home borough.
class AnnouncementService {
  static final AnnouncementService _instance = AnnouncementService._internal();
  factory AnnouncementService() => _instance;
  AnnouncementService._internal();

  // ── Storage key — v3 kept for cache compat ─────────────────────────────
  static const String _storageKey = 'borough_announcements_v3';

  // ── Firestore collection name ───────────────────────────────────────────
  static const String _collection = 'borough_announcements';

  // ── Dependencies ───────────────────────────────────────────────────────
  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();
  final BoroughScopeGuard _guard = BoroughScopeGuard();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── State ───────────────────────────────────────────────────────────────
  List<Announcement> _announcements = [];
  bool _isInitialized = false;
  String? _userBorough;

  // ── Firestore stream ────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  final StreamController<List<Announcement>> _streamController =
      StreamController<List<Announcement>>.broadcast();

  /// Public stream for StreamBuilder consumption.
  /// Emits the latest borough-filtered list every time Firestore updates.
  Stream<List<Announcement>> get boroughStream => _streamController.stream;

  // ── Accessors ───────────────────────────────────────────────────────────
  /// Current user's borough, resolved via BoroughScopeGuard.
  String? get userBorough => _guard.currentBorough ?? _userBorough;
  String get currentUserName => _onboarding.name ?? 'You';
  String? get currentUserPhoto => _onboarding.profilePhotoObjectUrl;
  List<Announcement> get announcements => List.unmodifiable(_announcements);

  /// Synchronous snapshot sorted pinned-first then newest.
  List<Announcement> get boroughAnnouncements {
    final list = List<Announcement>.from(_announcements);
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    _resolveBorough();
    // Seed from BrowserStorage immediately so UI shows cached data while
    // the Firestore stream connects.
    await _loadFromStorageCache();
    _startFirestoreStream();
    _isInitialized = true;
  }

  void _resolveBorough() {
    _userBorough = _guard.currentBorough;
    if (_userBorough == null || _userBorough!.isEmpty) {
      final pc = _onboarding.postcode;
      if (pc != null) {
        _userBorough = _postcode.getBoroughFromPostcode(pc);
      }
    }
  }

  /// Seed _announcements from BrowserStorage cache (fast, offline-safe).
  Future<void> _loadFromStorageCache() async {
    try {
      final raw = await BrowserStorage.getString(_storageKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _announcements = decoded
            .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
            .toList();
        // Push cached snapshot so any early StreamBuilders render immediately
        _streamController.add(boroughAnnouncements);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AnnouncementService cache load error: $e');
    }
  }

  /// Start (or restart) the Firestore real-time stream.
  ///
  /// Query: borough-filtered, pinned-first, newest-first, limit 50.
  /// Compound orderBy (isPinned + createdAt) requires a composite index —
  /// see Firestore console for the auto-generated index link on first use.
  void _startFirestoreStream() {
    final borough = _guard.currentBorough ?? _userBorough;
    if (borough == null || borough.isEmpty) {
      // Borough not resolved yet — nothing to stream; keep cached data.
      return;
    }

    _subscription?.cancel();

    try {
      _subscription = _firestore
          .collection(_collection)
          .where('boroughId', isEqualTo: borough)
          .orderBy('isPinned', descending: true)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .listen(
        (snapshot) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          _announcements = snapshot.docs
              .map((doc) =>
                  Announcement.fromFirestore(doc.data(), doc.id, uid))
              .toList();

          // Push live data to StreamBuilder
          _streamController.add(boroughAnnouncements);

          // Cache latest snapshot to BrowserStorage (offline resilience)
          _saveToStorageCache();
        },
        onError: (Object e) {
          if (kDebugMode) {
            debugPrint('AnnouncementService Firestore stream error: $e');
          }
          // On error keep the cached list visible; do not crash.
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AnnouncementService stream init error: $e');
      }
    }
  }

  /// Re-initialise after a borough change (e.g. onboarding update).
  void refreshBorough() {
    _resolveBorough();
    _startFirestoreStream();
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Post a new announcement.
  ///
  /// DUAL-WRITE: creates the Firestore document first (gets server timestamp),
  /// then optimistically inserts into the local list and caches.
  Future<Announcement> post(String content) async {
    await initialize();
    final borough = _guard.currentBorough ?? _userBorough ?? 'Unknown';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final localId = 'ann_${DateTime.now().millisecondsSinceEpoch}';

    final a = Announcement(
      id: localId,
      authorId: uid,
      authorName: _onboarding.name ?? 'You',
      authorPhotoUrl: _onboarding.profilePhotoObjectUrl,
      borough: borough,
      boroughId: borough,
      content: content,
      createdAt: DateTime.now(),
    );

    // 1. Optimistic local insert (stream will deduplicate on next snapshot)
    _announcements.insert(0, a);
    _streamController.add(boroughAnnouncements);
    await _saveToStorageCache();

    // 2. Firestore write (async — stream listener will confirm/update)
    try {
      await _firestore
          .collection(_collection)
          .doc(localId)
          .set(a.toFirestore());
    } catch (e) {
      if (kDebugMode) debugPrint('AnnouncementService post Firestore error: $e');
      // Keep the optimistic local entry so the user sees their own post.
    }

    return a;
  }

  /// Post a Partner business announcement.
  ///
  /// Called when a Partner subscriber posts from the business composer.
  /// Stores [businessName] as the visible author and optionally attaches
  /// a [linkedListingId] so the card can show a "See listing" button.
  Future<Announcement> postAsPartner({
    required String content,
    required String businessName,
    String? linkedListingId,
    String? linkedListingName,
  }) async {
    await initialize();
    final borough = _guard.currentBorough ?? _userBorough ?? 'Unknown';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final localId = 'ann_${DateTime.now().millisecondsSinceEpoch}';

    final a = Announcement(
      id: localId,
      authorId: uid,
      // Business name shown instead of personal name on the card
      authorName: businessName,
      authorPhotoUrl: null, // Partner posts use the Partner badge, not a photo
      borough: borough,
      boroughId: borough,
      content: content,
      createdAt: DateTime.now(),
      isPartnerPost: true,
      businessName: businessName,
      linkedListingId: linkedListingId,
      linkedListingName: linkedListingName,
    );

    // Optimistic local insert
    _announcements.insert(0, a);
    _streamController.add(boroughAnnouncements);
    await _saveToStorageCache();

    // Firestore write
    try {
      await _firestore
          .collection(_collection)
          .doc(localId)
          .set(a.toFirestore());
    } catch (e) {
      if (kDebugMode) debugPrint('AnnouncementService postAsPartner error: $e');
    }

    return a;
  }

  /// Toggle like using arrayUnion / arrayRemove for concurrent safety.
  Future<void> toggleLike(String announcementId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final idx = _announcements.indexWhere((a) => a.id == announcementId);
    if (idx == -1) return;
    final a = _announcements[idx];
    final nowLiked = !a.isLiked;

    // Optimistic local update
    a.isLiked = nowLiked;
    a.likes = (a.likes + (nowLiked ? 1 : -1)).clamp(0, 999999);
    if (nowLiked) {
      if (!a.likedBy.contains(uid)) a.likedBy.add(uid);
    } else {
      a.likedBy.remove(uid);
    }
    _streamController.add(boroughAnnouncements);
    await _saveToStorageCache();

    // Firestore update — concurrent-safe via arrayUnion / arrayRemove
    try {
      await _firestore.collection(_collection).doc(announcementId).update({
        'likedBy': nowLiked
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
        'likes': nowLiked ? FieldValue.increment(1) : FieldValue.increment(-1),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AnnouncementService toggleLike Firestore error: $e');
      }
    }
  }

  /// Toggle bookmark (device-local — not synced to Firestore).
  Future<void> toggleBookmark(String announcementId) async {
    final idx = _announcements.indexWhere((a) => a.id == announcementId);
    if (idx == -1) return;
    _announcements[idx].isBookmarked = !_announcements[idx].isBookmarked;
    _streamController.add(boroughAnnouncements);
    await _saveToStorageCache();

    // Best-effort Firestore sync
    try {
      await _firestore.collection(_collection).doc(announcementId).update({
        'isBookmarked': _announcements[idx].isBookmarked,
      });
    } catch (_) {}
  }

  /// Add a top-level comment to an announcement.
  Future<AnnouncementComment> addComment(
      String announcementId, String content) async {
    final idx = _announcements.indexWhere((a) => a.id == announcementId);
    if (idx == -1) throw Exception('Announcement not found');

    final comment = AnnouncementComment(
      id: 'cmt_${DateTime.now().millisecondsSinceEpoch}',
      authorName: _onboarding.name ?? 'You',
      authorPhotoUrl: _onboarding.profilePhotoObjectUrl,
      content: content,
      createdAt: DateTime.now(),
    );

    // Optimistic local update
    _announcements[idx].commentsList.add(comment);
    _announcements[idx].comments = _announcements[idx].commentsList.length;
    _streamController.add(boroughAnnouncements);
    await _saveToStorageCache();

    // Firestore: arrayUnion the new comment map onto the doc
    try {
      await _firestore.collection(_collection).doc(announcementId).update({
        'commentsList': FieldValue.arrayUnion([comment.toFirestoreMap()]),
        'comments': _announcements[idx].comments,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AnnouncementService addComment Firestore error: $e');
      }
    }

    return comment;
  }

  /// Add a reply to a comment, tagged with [replyToName].
  Future<AnnouncementComment> addReply({
    required String announcementId,
    required String replyToName,
    required String content,
  }) async {
    final idx = _announcements.indexWhere((a) => a.id == announcementId);
    if (idx == -1) throw Exception('Announcement not found');

    final reply = AnnouncementComment(
      id: 'rpl_${DateTime.now().millisecondsSinceEpoch}',
      authorName: _onboarding.name ?? 'You',
      authorPhotoUrl: _onboarding.profilePhotoObjectUrl,
      content: content,
      createdAt: DateTime.now(),
      replyToName: replyToName,
    );

    // Optimistic local update
    _announcements[idx].commentsList.add(reply);
    _announcements[idx].comments = _announcements[idx].commentsList.length;
    _streamController.add(boroughAnnouncements);
    await _saveToStorageCache();

    // Firestore: arrayUnion
    try {
      await _firestore.collection(_collection).doc(announcementId).update({
        'commentsList': FieldValue.arrayUnion([reply.toFirestoreMap()]),
        'comments': _announcements[idx].comments,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AnnouncementService addReply Firestore error: $e');
      }
    }

    return reply;
  }

  /// Increment share count.
  Future<void> share(String announcementId) async {
    final idx = _announcements.indexWhere((a) => a.id == announcementId);
    if (idx == -1) return;
    _announcements[idx].shares++;
    _streamController.add(boroughAnnouncements);
    await _saveToStorageCache();

    try {
      await _firestore.collection(_collection).doc(announcementId).update({
        'shares': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  /// Delete an announcement (only the author should call this — enforced by
  /// the Firestore security rule `allow delete: if request.auth.uid == resource.data.authorId`).
  Future<void> delete(String announcementId) async {
    _announcements.removeWhere((a) => a.id == announcementId);
    _streamController.add(boroughAnnouncements);
    await _saveToStorageCache();

    try {
      await _firestore.collection(_collection).doc(announcementId).delete();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AnnouncementService delete Firestore error: $e');
      }
    }
  }

  /// Report an announcement — removes from local view only.
  Future<void> report(String announcementId) async {
    _announcements.removeWhere((a) => a.id == announcementId);
    _streamController.add(boroughAnnouncements);
    await _saveToStorageCache();
  }

  /// Toggle pin status.
  Future<void> togglePin(String announcementId) async {
    final idx = _announcements.indexWhere((a) => a.id == announcementId);
    if (idx == -1) return;
    _announcements[idx].isPinned = !_announcements[idx].isPinned;
    _streamController.add(boroughAnnouncements);
    await _saveToStorageCache();

    try {
      await _firestore.collection(_collection).doc(announcementId).update({
        'isPinned': _announcements[idx].isPinned,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AnnouncementService togglePin Firestore error: $e');
      }
    }
  }

  // ── Persistence (BrowserStorage cache) ────────────────────────────────────

  /// Write the current in-memory list to BrowserStorage as the offline cache.
  Future<void> _saveToStorageCache() async {
    try {
      final encoded =
          json.encode(_announcements.map((a) => a.toJson()).toList());
      await BrowserStorage.setString(_storageKey, encoded);
    } catch (e) {
      if (kDebugMode) debugPrint('AnnouncementService cache save error: $e');
    }
  }

  // ── GDPR / account deletion ────────────────────────────────────────────────

  /// Clear all local announcement data — used for GDPR account deletion.
  Future<void> clearAll() async {
    _subscription?.cancel();
    _subscription = null;
    _announcements.clear();
    await BrowserStorage.remove(_storageKey);
  }
}
