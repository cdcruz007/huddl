import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'borough_scope_guard.dart';

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

/// A single borough-scoped announcement — like a notice on a town hall board.
class Announcement {
  final String id;
  final String authorName;
  final String? authorPhotoUrl; // blob: or asset path
  final String borough;
  final String content;
  final DateTime createdAt;
  int likes;
  int comments;
  bool isLiked;
  bool isPinned;
  bool isBookmarked;
  int shares;
  List<AnnouncementComment> commentsList;

  Announcement({
    required this.id,
    required this.authorName,
    this.authorPhotoUrl,
    required this.borough,
    required this.content,
    required this.createdAt,
    this.likes = 0,
    this.comments = 0,
    this.isLiked = false,
    this.isPinned = false,
    this.isBookmarked = false,
    this.shares = 0,
    List<AnnouncementComment>? commentsList,
  }) : commentsList = commentsList ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorName': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'borough': borough,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'likes': likes,
        'comments': comments,
        'isLiked': isLiked,
        'isPinned': isPinned,
        'isBookmarked': isBookmarked,
        'shares': shares,
        'commentsList': commentsList.map((c) => c.toJson()).toList(),
      };

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'] as String,
        authorName: j['authorName'] as String,
        authorPhotoUrl: j['authorPhotoUrl'] as String?,
        borough: j['borough'] as String,
        content: j['content'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        likes: j['likes'] as int? ?? 0,
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

/// Singleton that manages borough-scoped announcements persisted via
/// BrowserStorage.  Only announcements in the current user's borough are shown.
///
/// HYPERLOCAL RULE: Announcements are borough-only.
/// Parents can only see and post announcements within their home borough.
/// Uses BoroughScopeGuard for consistent borough resolution.
class AnnouncementService {
  static final AnnouncementService _instance = AnnouncementService._internal();
  factory AnnouncementService() => _instance;
  AnnouncementService._internal();

  // v3: bumped to purge any cached dummy/seed data from previous versions.
  static const String _storageKey = 'borough_announcements_v3';

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();
  final BoroughScopeGuard _guard = BoroughScopeGuard();

  List<Announcement> _announcements = [];
  bool _isInitialized = false;
  String? _userBorough;

  /// Current user's borough, resolved via BoroughScopeGuard (single source of truth).
  String? get userBorough => _guard.currentBorough ?? _userBorough;
  String get currentUserName => _onboarding.name ?? 'You';
  String? get currentUserPhoto => _onboarding.profilePhotoObjectUrl;
  List<Announcement> get announcements => List.unmodifiable(_announcements);

  /// Returns only announcements in the current user's borough, newest first.
  /// If no borough is resolved, returns all announcements (so posts still appear).
  ///
  /// HYPERLOCAL: Uses BoroughScopeGuard.filterByUserBorough for consistent
  /// borough matching across all services.
  List<Announcement> get boroughAnnouncements {
    final borough = _guard.currentBorough ?? _userBorough;
    List<Announcement> list;
    if (borough == null || borough.isEmpty) {
      // No borough resolved — show all announcements so user posts are visible
      list = List<Announcement>.from(_announcements);
    } else {
      list = _guard.filterByUserBorough<Announcement>(
        _announcements,
        (a) => a.borough,
      );
    }
    list.sort((a, b) {
      // Pinned first, then newest
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    _resolveBorough();
    await _loadFromStorage();
    // Production: never seed dummy announcements.
    // The board starts empty and fills with real user posts only.
    _isInitialized = true;
  }

  void _resolveBorough() {
    // Primary: use BoroughScopeGuard (single source of truth)
    _userBorough = _guard.currentBorough;
    // Fallback: resolve from postcode directly
    if (_userBorough == null || _userBorough!.isEmpty) {
      final pc = _onboarding.postcode;
      if (pc != null) {
        _userBorough = _postcode.getBoroughFromPostcode(pc);
      }
    }
  }

  /// Post a new announcement from the current user.
  ///
  /// HYPERLOCAL: The announcement is automatically tagged with the user's
  /// current borough. Parents can only post to their own borough.
  Future<Announcement> post(String content) async {
    await initialize();
    final borough = _guard.currentBorough ?? _userBorough ?? 'Unknown';
    final a = Announcement(
      id: 'ann_${DateTime.now().millisecondsSinceEpoch}',
      authorName: _onboarding.name ?? 'You',
      authorPhotoUrl: _onboarding.profilePhotoObjectUrl,
      borough: borough,
      content: content,
      createdAt: DateTime.now(),
    );
    _announcements.insert(0, a);
    await _save();
    return a;
  }

  /// Toggle like on an announcement.
  Future<void> toggleLike(String announcementId) async {
    final idx = _announcements.indexWhere((a) => a.id == announcementId);
    if (idx == -1) return;
    final a = _announcements[idx];
    a.isLiked = !a.isLiked;
    a.likes += a.isLiked ? 1 : -1;
    await _save();
  }

  /// Toggle bookmark on an announcement.
  Future<void> toggleBookmark(String announcementId) async {
    final idx = _announcements.indexWhere((a) => a.id == announcementId);
    if (idx == -1) return;
    _announcements[idx].isBookmarked = !_announcements[idx].isBookmarked;
    await _save();
  }

  /// Add a comment to an announcement.
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
    _announcements[idx].commentsList.add(comment);
    _announcements[idx].comments = _announcements[idx].commentsList.length;
    await _save();
    return comment;
  }

  /// Add a reply to a specific comment on an announcement.
  /// The reply appears in the flat comment list immediately after [replyToName]'s
  /// comment, tagged with [replyToName] so the UI can render the @mention.
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
    _announcements[idx].commentsList.add(reply);
    _announcements[idx].comments = _announcements[idx].commentsList.length;
    await _save();
    return reply;
  }

  /// Increment share count.
  Future<void> share(String announcementId) async {
    final idx = _announcements.indexWhere((a) => a.id == announcementId);
    if (idx == -1) return;
    _announcements[idx].shares++;
    await _save();
  }

  /// Delete an announcement.
  Future<void> delete(String announcementId) async {
    _announcements.removeWhere((a) => a.id == announcementId);
    await _save();
  }

  /// Report an announcement (just removes from local view).
  Future<void> report(String announcementId) async {
    _announcements.removeWhere((a) => a.id == announcementId);
    await _save();
  }

  /// Toggle pin on an announcement.
  Future<void> togglePin(String announcementId) async {
    final idx = _announcements.indexWhere((a) => a.id == announcementId);
    if (idx == -1) return;
    _announcements[idx].isPinned = !_announcements[idx].isPinned;
    await _save();
  }

  // ── Persistence ──────────────────────────────────────────────────────────
  Future<void> _loadFromStorage() async {
    try {
      final raw = await BrowserStorage.getString(_storageKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _announcements = decoded
            .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AnnouncementService load error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final encoded =
          json.encode(_announcements.map((a) => a.toJson()).toList());
      await BrowserStorage.setString(_storageKey, encoded);
    } catch (e) {
      if (kDebugMode) debugPrint('AnnouncementService save error: $e');
    }
  }

  /// Clear all announcement data — used for GDPR account deletion.
  Future<void> clearAll() async {
    _announcements.clear();
    await BrowserStorage.remove(_storageKey);
  }

  // _seedSampleAnnouncements() removed — production build shows real user posts only.
}
