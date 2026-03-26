import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

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
  });

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

  static const String _storageKey = 'borough_announcements_v1';

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();

  List<Announcement> _announcements = [];
  bool _isInitialized = false;
  String? _userBorough;

  String? get userBorough => _userBorough;
  List<Announcement> get announcements => List.unmodifiable(_announcements);

  /// Returns only announcements in the current user's borough, newest first.
  List<Announcement> get boroughAnnouncements {
    if (_userBorough == null) return [];
    final list = _announcements
        .where((a) => a.borough.toLowerCase() == _userBorough!.toLowerCase())
        .toList()
      ..sort((a, b) {
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

  // ── Persistence ──────────────────────────────────────────────────────────
  Future<void> _loadFromStorage() async {
    try {
      final raw = await BrowserStorage.getString(_storageKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _announcements =
            decoded.map((e) => Announcement.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AnnouncementService load error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final encoded = json.encode(_announcements.map((a) => a.toJson()).toList());
      await BrowserStorage.setString(_storageKey, encoded);
    } catch (e) {
      if (kDebugMode) debugPrint('AnnouncementService save error: $e');
    }
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
        comments: 7,
        isPinned: true,
      ),
      Announcement(
        id: 'seed_2',
        authorName: 'Emma Collins',
        borough: borough,
        content:
            'Lost: Grey tabby cat near Cherry Hinton Road. Answers to "Muffin". If you see her please message me - she\'s very friendly but might be scared.',
        createdAt: now.subtract(const Duration(hours: 3)),
        likes: 24,
        comments: 12,
      ),
      Announcement(
        id: 'seed_3',
        authorName: 'James Whitfield',
        borough: borough,
        content:
            'The new playground at Coleridge Recreation Ground is now open! Took my little ones yesterday - the toddler section is brilliant. Highly recommend.',
        createdAt: now.subtract(const Duration(hours: 6)),
        likes: 31,
        comments: 9,
      ),
      Announcement(
        id: 'seed_4',
        authorName: 'Lucy Brennan',
        borough: borough,
        content:
            'Free buggy board (universal fit) available for collection from Romsey Town. Still in great condition - my toddler just outgrew it. First come first served!',
        createdAt: now.subtract(const Duration(hours: 12)),
        likes: 15,
        comments: 4,
      ),
      Announcement(
        id: 'seed_5',
        authorName: 'Kate Nguyen',
        borough: borough,
        content:
            'Anyone else noticed the potholes on Perne Road getting worse? I\'ve reported them to the council but more reports = faster action. Here\'s the link to report: fixmystreet.com',
        createdAt: now.subtract(const Duration(days: 1)),
        likes: 42,
        comments: 16,
      ),
    ];
    _announcements.addAll(samples);
    _save();
  }
}
