import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

/// A comment on an announcement.
class AnnouncementComment {
  final String id;
  final String authorName;
  final String? authorPhotoUrl;
  final String content;
  final DateTime createdAt;
  int likes;
  bool isLiked;

  AnnouncementComment({
    required this.id,
    required this.authorName,
    this.authorPhotoUrl,
    required this.content,
    required this.createdAt,
    this.likes = 0,
    this.isLiked = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorName': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'likes': likes,
        'isLiked': isLiked,
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
class AnnouncementService {
  static final AnnouncementService _instance = AnnouncementService._internal();
  factory AnnouncementService() => _instance;
  AnnouncementService._internal();

  static const String _storageKey = 'borough_announcements_v2';

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();

  List<Announcement> _announcements = [];
  bool _isInitialized = false;
  String? _userBorough;

  String? get userBorough => _userBorough;
  String get currentUserName => _onboarding.name ?? 'You';
  String? get currentUserPhoto => _onboarding.profilePhotoObjectUrl;
  List<Announcement> get announcements => List.unmodifiable(_announcements);

  /// Returns only announcements in the current user's borough, newest first.
  /// If no borough is resolved, returns all announcements (so posts still appear).
  List<Announcement> get boroughAnnouncements {
    List<Announcement> list;
    if (_userBorough == null || _userBorough!.isEmpty) {
      // No borough resolved — show all announcements so user posts are visible
      list = List<Announcement>.from(_announcements);
    } else {
      list = _announcements
          .where(
              (a) => a.borough.toLowerCase() == _userBorough!.toLowerCase())
          .toList();
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
    // Seed sample announcements if none exist for this borough
    if (_userBorough != null && boroughAnnouncements.isEmpty) {
      _seedSampleAnnouncements();
    }
    _isInitialized = true;
  }

  void _resolveBorough() {
    final pc = _onboarding.postcode;
    if (pc != null) {
      _userBorough = _postcode.getBoroughFromPostcode(pc);
    }
  }

  /// Post a new announcement from the current user.
  Future<Announcement> post(String content) async {
    await initialize();
    final a = Announcement(
      id: 'ann_${DateTime.now().millisecondsSinceEpoch}',
      authorName: _onboarding.name ?? 'You',
      authorPhotoUrl: _onboarding.profilePhotoObjectUrl,
      borough: _userBorough ?? 'Unknown',
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

  /// Seed realistic sample announcements for the user's borough.
  void _seedSampleAnnouncements() {
    final borough = _userBorough ?? 'Cambridge';
    final now = DateTime.now();
    final samples = <Announcement>[
      Announcement(
        id: 'seed_1',
        authorName: 'Sarah Mitchell',
        borough: borough,
        content:
            'Road closure on Mill Road this Saturday for the community fair! Great activities for kids planned - face painting, puppet show, and a bouncy castle. See you there!',
        createdAt: now.subtract(const Duration(hours: 1)),
        likes: 18,
        comments: 3,
        isPinned: true,
        commentsList: [
          AnnouncementComment(
            id: 'sc_1',
            authorName: 'Emma Collins',
            content: 'My kids are so excited for this! What time does the face painting start?',
            createdAt: now.subtract(const Duration(minutes: 45)),
            likes: 3,
          ),
          AnnouncementComment(
            id: 'sc_2',
            authorName: 'James Whitfield',
            content: 'Will there be parking available nearby?',
            createdAt: now.subtract(const Duration(minutes: 30)),
            likes: 1,
          ),
          AnnouncementComment(
            id: 'sc_3',
            authorName: 'Lucy Brennan',
            content: 'We went last year and it was brilliant. Highly recommend!',
            createdAt: now.subtract(const Duration(minutes: 15)),
            likes: 5,
          ),
        ],
      ),
      Announcement(
        id: 'seed_2',
        authorName: 'Emma Collins',
        borough: borough,
        content:
            'Lost: Grey tabby cat near Cherry Hinton Road. Answers to "Muffin". If you see her please message me - she\'s very friendly but might be scared.',
        createdAt: now.subtract(const Duration(hours: 3)),
        likes: 24,
        comments: 5,
        commentsList: [
          AnnouncementComment(
            id: 'sc_4',
            authorName: 'Kate Nguyen',
            content: 'I think I saw a grey cat near the park this morning! Will keep an eye out.',
            createdAt: now.subtract(const Duration(hours: 2)),
            likes: 4,
          ),
          AnnouncementComment(
            id: 'sc_5',
            authorName: 'Priya Sharma',
            content: 'Oh no! I hope Muffin comes home safe. Shared on my local WhatsApp group.',
            createdAt: now.subtract(const Duration(hours: 1, minutes: 30)),
            likes: 6,
          ),
          AnnouncementComment(
            id: 'sc_6',
            authorName: 'Oliver Chen',
            content: 'Try leaving some food outside your door overnight. Cats often come back when it\'s quiet.',
            createdAt: now.subtract(const Duration(hours: 1)),
            likes: 8,
          ),
          AnnouncementComment(
            id: 'sc_7',
            authorName: 'Sarah Mitchell',
            content: 'Have you tried the local vets? Sometimes people hand in found cats.',
            createdAt: now.subtract(const Duration(minutes: 45)),
            likes: 2,
          ),
          AnnouncementComment(
            id: 'sc_8',
            authorName: 'Liam O\'Brien',
            content: 'Will keep my eyes open on my evening walks!',
            createdAt: now.subtract(const Duration(minutes: 20)),
            likes: 1,
          ),
        ],
      ),
      Announcement(
        id: 'seed_3',
        authorName: 'James Whitfield',
        borough: borough,
        content:
            'The new playground at Coleridge Recreation Ground is now open! Took my little ones yesterday - the toddler section is brilliant. Highly recommend.',
        createdAt: now.subtract(const Duration(hours: 6)),
        likes: 31,
        comments: 4,
        commentsList: [
          AnnouncementComment(
            id: 'sc_9',
            authorName: 'Lucy Brennan',
            content: 'Finally! We\'ve been waiting for this. Is it suitable for 18-month-olds?',
            createdAt: now.subtract(const Duration(hours: 5)),
            likes: 2,
          ),
          AnnouncementComment(
            id: 'sc_10',
            authorName: 'James Whitfield',
            content: 'Yes! There\'s a whole fenced area for under 3s with soft ground. Perfect for toddlers.',
            createdAt: now.subtract(const Duration(hours: 4, minutes: 30)),
            likes: 7,
          ),
          AnnouncementComment(
            id: 'sc_11',
            authorName: 'Fatima Hassan',
            content: 'Just went today - the swings are amazing! My 2-year-old loved the little slide.',
            createdAt: now.subtract(const Duration(hours: 3)),
            likes: 4,
          ),
          AnnouncementComment(
            id: 'sc_12',
            authorName: 'Sophie Andrews',
            content: 'Is there a cafe nearby or should we bring snacks?',
            createdAt: now.subtract(const Duration(hours: 2)),
            likes: 1,
          ),
        ],
      ),
      Announcement(
        id: 'seed_4',
        authorName: 'Lucy Brennan',
        borough: borough,
        content:
            'Free buggy board (universal fit) available for collection from Romsey Town. Still in great condition - my toddler just outgrew it. First come first served!',
        createdAt: now.subtract(const Duration(hours: 12)),
        likes: 15,
        comments: 2,
        commentsList: [
          AnnouncementComment(
            id: 'sc_13',
            authorName: 'Priya Sharma',
            content: 'Is this still available? Would love to grab it!',
            createdAt: now.subtract(const Duration(hours: 10)),
            likes: 0,
          ),
          AnnouncementComment(
            id: 'sc_14',
            authorName: 'Lucy Brennan',
            content: 'Yes still here! Send me a DM and I\'ll give you the address.',
            createdAt: now.subtract(const Duration(hours: 9)),
            likes: 1,
          ),
        ],
      ),
      Announcement(
        id: 'seed_5',
        authorName: 'Kate Nguyen',
        borough: borough,
        content:
            'Anyone else noticed the potholes on Perne Road getting worse? I\'ve reported them to the council but more reports = faster action. Here\'s the link to report: fixmystreet.com',
        createdAt: now.subtract(const Duration(days: 1)),
        likes: 42,
        comments: 6,
        commentsList: [
          AnnouncementComment(
            id: 'sc_15',
            authorName: 'Oliver Chen',
            content: 'Reported! Nearly lost a wheel on my buggy last week going over one.',
            createdAt: now.subtract(const Duration(hours: 22)),
            likes: 9,
          ),
          AnnouncementComment(
            id: 'sc_16',
            authorName: 'James Whitfield',
            content: 'Done! The more of us that report it, the quicker they\'ll fix it.',
            createdAt: now.subtract(const Duration(hours: 20)),
            likes: 5,
          ),
          AnnouncementComment(
            id: 'sc_17',
            authorName: 'Sarah Mitchell',
            content: 'I reported them two weeks ago and got an acknowledgement but no action yet.',
            createdAt: now.subtract(const Duration(hours: 18)),
            likes: 3,
          ),
          AnnouncementComment(
            id: 'sc_18',
            authorName: 'Emma Collins',
            content: 'It\'s dangerous especially with pushchairs. Will report today.',
            createdAt: now.subtract(const Duration(hours: 15)),
            likes: 7,
          ),
          AnnouncementComment(
            id: 'sc_19',
            authorName: 'Fatima Hassan',
            content: 'The stretch near the junction is the worst. Nearly tripped over one yesterday.',
            createdAt: now.subtract(const Duration(hours: 12)),
            likes: 4,
          ),
          AnnouncementComment(
            id: 'sc_20',
            authorName: 'Liam O\'Brien',
            content: 'Great initiative Kate! Just submitted my report.',
            createdAt: now.subtract(const Duration(hours: 8)),
            likes: 2,
          ),
        ],
      ),
    ];
    _announcements.addAll(samples);
    _save();
  }
}
