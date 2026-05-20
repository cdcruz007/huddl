import 'dart:convert';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import 'borough_scope_guard.dart';
import 'firestore_service.dart';

/// Privacy level for a meetup
enum MeetupPrivacy { public, group, private_ }

/// Repeat frequency for a meetup
enum MeetupRepeat { none, daily, weekly, monthly, custom }

/// Represents an invitee / attendee
class MeetupAttendee {
  final String id;
  final String name;
  final String? avatarUrl;
  final Color? accentColor;
  final String status; // 'going', 'maybe', 'invited', 'declined'

  MeetupAttendee({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.accentColor,
    this.status = 'invited',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'status': status,
  };

  factory MeetupAttendee.fromJson(Map<String, dynamic> j) => MeetupAttendee(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    avatarUrl: j['avatarUrl'],
    status: j['status'] ?? 'invited',
  );
}

/// Represents a casual parent-organised meet-up (free, informal).
class Meetup {
  final String id;
  final String title;
  final String description;
  final String category; // Coffee, Playdate, Sport, Walk, Social, Other
  final String dateDisplay; // e.g. "SAT, MAR 15"
  final String timeDisplay; // e.g. "10:00 - 11:30 AM"
  final DateTime dateTime;
  final String location;
  final String organiserName;
  final String organiserId;
  final int attendeeCount;
  final int? maxAttendees;
  final bool isGoing;
  final List<String> attendeeNames;
  final String imageUrl;

  // New fields from wireframe
  final MeetupPrivacy privacy;
  final MeetupRepeat repeat;
  final String? repeatDisplay; // e.g. "Every Monday", "Monthly on the 15th"
  final List<int>? repeatDays; // For weekly: 0=Mon...6=Sun; for custom: specific dates
  final DateTime? repeatEndDate;
  final String? groupId; // When privacy=group, which group this belongs to
  final String? groupName;
  final bool isFree;
  final double? price;
  final List<MeetupAttendee> invitees;
  final List<String> invitedMemberIds; // For private meetups: IDs of invited members
  final String? borough; // Borough this meetup belongs to for visibility
  final List<String> targetAudience; // Participant types: Mums, Dads, Aspiring parents, Expecting parents, Kids
  final DateTime createdAt;

  Meetup({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.dateDisplay,
    required this.timeDisplay,
    required this.dateTime,
    required this.location,
    required this.organiserName,
    this.organiserId = 'current_user',
    this.attendeeCount = 1,
    this.maxAttendees,
    this.isGoing = false,
    this.isFree = true,
    this.price,
    this.attendeeNames = const [],
    this.imageUrl = '',
    this.privacy = MeetupPrivacy.public,
    this.repeat = MeetupRepeat.none,
    this.repeatDisplay,
    this.repeatDays,
    this.repeatEndDate,
    this.groupId,
    this.groupName,
    this.invitees = const [],
    this.invitedMemberIds = const [],
    this.borough,
    this.targetAudience = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Meetup copyWith({
    int? attendeeCount,
    bool? isGoing,
    bool? isFree,
    double? price,
    List<String>? attendeeNames,
    List<MeetupAttendee>? invitees,
    List<String>? invitedMemberIds,
    List<String>? targetAudience,
  }) {
    return Meetup(
      id: id,
      title: title,
      description: description,
      category: category,
      dateDisplay: dateDisplay,
      timeDisplay: timeDisplay,
      dateTime: dateTime,
      location: location,
      organiserName: organiserName,
      organiserId: organiserId,
      attendeeCount: attendeeCount ?? this.attendeeCount,
      maxAttendees: maxAttendees,
      isGoing: isGoing ?? this.isGoing,
      isFree: isFree ?? this.isFree,
      price: price ?? this.price,
      attendeeNames: attendeeNames ?? this.attendeeNames,
      imageUrl: imageUrl,
      privacy: privacy,
      repeat: repeat,
      repeatDisplay: repeatDisplay,
      repeatDays: repeatDays,
      repeatEndDate: repeatEndDate,
      groupId: groupId,
      groupName: groupName,
      invitees: invitees ?? this.invitees,
      invitedMemberIds: invitedMemberIds ?? this.invitedMemberIds,
      borough: borough,
      targetAudience: targetAudience ?? this.targetAudience,
      createdAt: createdAt,
    );
  }

  /// Returns a Pexels URL that matches the meetup category.
  /// Public so the create screen and detail screen can access it.
  static String categoryFallbackUrl(String category) => _categoryFallbackUrl(category);
  static String _categoryFallbackUrl(String category) {
    switch (category.toLowerCase()) {
      case 'coffee':
      case 'coffee & chat':
        return 'https://images.pexels.com/photos/302899/pexels-photo-302899.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'playdate':
      case 'play':
        return 'https://images.pexels.com/photos/3933239/pexels-photo-3933239.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'walk':
      case 'outdoor':
        return 'https://images.pexels.com/photos/1325735/pexels-photo-1325735.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'sport':
      case 'fitness':
      case 'exercise':
        return 'https://images.pexels.com/photos/3822864/pexels-photo-3822864.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'class':
      case 'workshop':
        return 'https://images.pexels.com/photos/3662667/pexels-photo-3662667.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'music':
        return 'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=300';
      case 'social':
        return 'https://images.pexels.com/photos/3184418/pexels-photo-3184418.jpeg?auto=compress&cs=tinysrgb&w=300';
      default:
        return 'https://images.pexels.com/photos/3933250/pexels-photo-3933250.jpeg?auto=compress&cs=tinysrgb&w=300';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category,
    'dateDisplay': dateDisplay,
    'timeDisplay': timeDisplay,
    'dateTime': dateTime.toIso8601String(),
    'location': location,
    'organiserName': organiserName,
    'organiserId': organiserId,
    'attendeeCount': attendeeCount,
    'maxAttendees': maxAttendees,
    'isGoing': isGoing,
    'attendeeNames': attendeeNames,
    'imageUrl': imageUrl, // Preserve original (base64 stored separately if needed)
    'isFree': isFree,
    'price': price,
    'privacy': privacy.index,
    'repeat': repeat.index,
    'repeatDisplay': repeatDisplay,
    'repeatDays': repeatDays,
    'repeatEndDate': repeatEndDate?.toIso8601String(),
    'groupId': groupId,
    'groupName': groupName,
    'invitees': invitees.map((i) => i.toJson()).toList(),
    'invitedMemberIds': invitedMemberIds,
    'borough': borough,
    'targetAudience': targetAudience,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Meetup.fromJson(Map<String, dynamic> j) => Meetup(
    id: j['id'] ?? '',
    title: j['title'] ?? '',
    description: j['description'] ?? '',
    category: j['category'] ?? 'Other',
    dateDisplay: j['dateDisplay'] ?? '',
    timeDisplay: j['timeDisplay'] ?? '',
    dateTime: DateTime.tryParse(j['dateTime'] ?? '') ?? DateTime.now(),
    location: j['location'] ?? '',
    organiserName: j['organiserName'] ?? '',
    organiserId: j['organiserId'] ?? 'current_user',
    attendeeCount: (j['attendeeCount'] as num?)?.toInt() ?? 1,
    maxAttendees: (j['maxAttendees'] as num?)?.toInt(),
    isGoing: j['isGoing'] ?? false,
    attendeeNames: List<String>.from(j['attendeeNames'] ?? []),
    imageUrl: j['imageUrl'] ?? '',
    isFree: j['isFree'] ?? true,
    price: j['price'] != null ? (j['price'] as num).toDouble() : null,
    privacy: () {
      final raw = j['privacy'];
      if (raw is int) return MeetupPrivacy.values[raw.clamp(0, MeetupPrivacy.values.length - 1)];
      if (raw is num) return MeetupPrivacy.values[raw.toInt().clamp(0, MeetupPrivacy.values.length - 1)];
      if (raw is String) {
        if (raw.contains('group')) return MeetupPrivacy.group;
        if (raw.contains('private')) return MeetupPrivacy.private_;
      }
      return MeetupPrivacy.public;
    }(),
    repeat: MeetupRepeat.values[((j['repeat'] as num?)?.toInt() ?? 0).clamp(0, MeetupRepeat.values.length - 1)],
    repeatDisplay: j['repeatDisplay'],
    repeatDays: j['repeatDays'] != null ? List<int>.from(j['repeatDays']) : null,
    repeatEndDate: j['repeatEndDate'] != null ? DateTime.tryParse(j['repeatEndDate']) : null,
    groupId: j['groupId'],
    groupName: j['groupName'],
    invitees: (j['invitees'] as List<dynamic>?)
        ?.map((i) => MeetupAttendee.fromJson(i as Map<String, dynamic>))
        .toList() ?? [],
    invitedMemberIds: List<String>.from(j['invitedMemberIds'] ?? []),
    borough: j['borough'],
    targetAudience: List<String>.from(j['targetAudience'] ?? []),
    createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
  );
}

/// Manages the list of meet-ups. Singleton with ChangeNotifier.
///
/// HYPERLOCAL RULE: Meetups are borough-only.
/// Only meetups tagged with the current user's borough are visible.
/// Users cannot create meetups outside their home borough.
class MeetupService extends ChangeNotifier {
  static final MeetupService _instance = MeetupService._internal();
  factory MeetupService() => _instance;
  MeetupService._internal() {
    _loadPersistedMeetups();
  }

  static const String _storageKey = 'huddl_user_meetups';
  final List<Meetup> _meetups = [];
  final BoroughScopeGuard _guard = BoroughScopeGuard();

  /// All meetups (unfiltered) — used internally.
  List<Meetup> get allMeetups => List.unmodifiable(_meetups);

  /// Meetups visible to the current user (borough-filtered).
  ///
  /// HYPERLOCAL: Only returns meetups in the user's home borough.
  /// If borough is not set, falls back to showing all (graceful degradation).
  List<Meetup> get meetups {
    final borough = _guard.currentBorough;
    if (borough == null || borough.isEmpty) return List.unmodifiable(_meetups);
    return List.unmodifiable(
      _guard.filterByUserBorough<Meetup>(
        _meetups,
        (m) => m.borough,
      ),
    );
  }

  /// Creates a new meet-up and adds it to the list.
  ///
  /// HYPERLOCAL: Auto-tags with user's borough if not already set,
  /// ensuring the meetup is visible in borough-filtered views.
  void createMeetup(Meetup meetup) {
    final toAdd = (meetup.borough == null || meetup.borough!.isEmpty)
        ? Meetup(
            id: meetup.id,
            title: meetup.title,
            description: meetup.description,
            category: meetup.category,
            dateDisplay: meetup.dateDisplay,
            timeDisplay: meetup.timeDisplay,
            dateTime: meetup.dateTime,
            location: meetup.location,
            organiserName: meetup.organiserName,
            organiserId: meetup.organiserId,
            attendeeCount: meetup.attendeeCount,
            maxAttendees: meetup.maxAttendees,
            isGoing: meetup.isGoing,
            isFree: meetup.isFree,
            price: meetup.price,
            attendeeNames: meetup.attendeeNames,
            imageUrl: meetup.imageUrl,
            privacy: meetup.privacy,
            repeat: meetup.repeat,
            repeatDisplay: meetup.repeatDisplay,
            repeatDays: meetup.repeatDays,
            repeatEndDate: meetup.repeatEndDate,
            groupId: meetup.groupId,
            groupName: meetup.groupName,
            invitees: meetup.invitees,
            invitedMemberIds: meetup.invitedMemberIds,
            borough: _guard.currentBorough,
            createdAt: meetup.createdAt,
          )
        : meetup;
    _meetups.insert(0, toAdd);
    notifyListeners();
    _persistUserMeetups();
    // Store base64 image separately (too large for main JSON list)
    if (toAdd.imageUrl.startsWith('data:')) {
      _persistMeetupImage(toAdd.id, toAdd.imageUrl);
    }
  }

  /// Toggle "going" status for a meetup.
  void toggleGoing(String meetupId) {
    final index = _meetups.indexWhere((m) => m.id == meetupId);
    if (index < 0) return;
    final m = _meetups[index];
    final wasGoing = m.isGoing;
    _meetups[index] = m.copyWith(
      isGoing: !wasGoing,
      attendeeCount: wasGoing ? m.attendeeCount - 1 : m.attendeeCount + 1,
      // attendeeNames is no longer used for fake/pre-filled names —
      // the real list comes from Firestore rsvpMeetup() writes.
      attendeeNames: const [],
    );
    notifyListeners();
    _persistUserMeetups();
    // Persist RSVP to Firestore so it survives reinstall / shows on other devices
    FirestoreService().saveRsvp(meetupId, going: !wasGoing);
  }

  /// Fetch this user's RSVP state from Firestore and apply it to the local
  /// meetup list. Call this once after loading meetups so that reinstalls
  /// and other devices see the correct "I'm Going" state.
  Future<void> syncRsvpsFromFirestore() async {
    try {
      final goingIds = await FirestoreService().loadMyRsvpIds();
      if (goingIds.isEmpty) return;
      bool changed = false;
      for (int i = 0; i < _meetups.length; i++) {
        final m = _meetups[i];
        if (goingIds.contains(m.id) && !m.isGoing) {
          _meetups[i] = m.copyWith(isGoing: true);
          changed = true;
        }
      }
      if (changed) {
        notifyListeners();
        _persistUserMeetups();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MeetupService] syncRsvpsFromFirestore error: $e');
    }
  }

  /// Delete / cancel a meetup (organiser only).
  /// Returns the meetup data before deletion (for cancellation messages).
  Meetup? cancelMeetup(String meetupId) {
    final index = _meetups.indexWhere((m) => m.id == meetupId);
    if (index < 0) return null;
    final cancelled = _meetups[index];
    _meetups.removeAt(index);
    notifyListeners();
    _persistUserMeetups();
    // Clean up stored image
    BrowserStorage.remove('meetup_image_$meetupId');
    return cancelled;
  }

  /// Legacy alias — kept for backward compatibility.
  void deleteMeetup(String meetupId) => cancelMeetup(meetupId);

  /// Update RSVP for an invitee
  void updateInviteeStatus(String meetupId, String inviteeId, String status) {
    final index = _meetups.indexWhere((m) => m.id == meetupId);
    if (index < 0) return;
    final m = _meetups[index];
    final updatedInvitees = m.invitees.map((inv) {
      if (inv.id == inviteeId) {
        return MeetupAttendee(
          id: inv.id,
          name: inv.name,
          avatarUrl: inv.avatarUrl,
          status: status,
        );
      }
      return inv;
    }).toList();
    _meetups[index] = m.copyWith(invitees: updatedInvitees);
    notifyListeners();
  }

  /// Clear all user-created meetups — used for GDPR account deletion.
  Future<void> clearAll() async {
    _meetups.removeWhere((m) => m.organiserId == 'current_user');
    await BrowserStorage.remove(_storageKey);
    notifyListeners();
  }

  // ── Persistence ──────────────────────────────────────────────────────

  /// Store a base64 image separately (keyed by meetup ID).
  Future<void> _persistMeetupImage(String meetupId, String dataUrl) async {
    try {
      await BrowserStorage.setString('meetup_image_$meetupId', dataUrl);
    } catch (_) {}
  }

  /// Load a stored base64 image for a meetup.
  Future<String?> getMeetupImage(String meetupId) async {
    return BrowserStorage.getString('meetup_image_$meetupId');
  }

  /// Synchronously check the in-memory cache for a stored image URL.
  /// Falls back to the meetup's own imageUrl if no override is cached.
  String resolvedImageUrl(Meetup meetup) {
    // If the meetup already holds a data: URI in memory, use it.
    if (meetup.imageUrl.startsWith('data:')) return meetup.imageUrl;
    // Otherwise use whatever URL is on the object (may be category fallback).
    return meetup.imageUrl;
  }

  /// Pre-load stored base64 images into the in-memory meetup list.
  /// Call once after app start so that card views have the data-URI available.
  Future<void> restoreCustomImages() async {
    bool changed = false;
    for (int i = 0; i < _meetups.length; i++) {
      final m = _meetups[i];
      // Only restore if the current URL is NOT a data: URI (i.e. was swapped)
      if (!m.imageUrl.startsWith('data:') && m.organiserId == 'current_user') {
        final stored = await BrowserStorage.getString('meetup_image_${m.id}');
        if (stored != null && stored.startsWith('data:')) {
          _meetups[i] = Meetup(
            id: m.id, title: m.title, description: m.description,
            category: m.category, dateDisplay: m.dateDisplay,
            timeDisplay: m.timeDisplay, dateTime: m.dateTime,
            location: m.location, organiserName: m.organiserName,
            organiserId: m.organiserId, attendeeCount: m.attendeeCount,
            maxAttendees: m.maxAttendees, isGoing: m.isGoing,
            isFree: m.isFree, price: m.price,
            attendeeNames: m.attendeeNames, imageUrl: stored,
            privacy: m.privacy, repeat: m.repeat,
            repeatDisplay: m.repeatDisplay, repeatDays: m.repeatDays,
            repeatEndDate: m.repeatEndDate, groupId: m.groupId,
            groupName: m.groupName, invitees: m.invitees,
            invitedMemberIds: m.invitedMemberIds, borough: m.borough,
            targetAudience: m.targetAudience,
            createdAt: m.createdAt,
          );
          changed = true;
        }
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> _persistUserMeetups() async {
    try {
      final userMeetups = _meetups.where((m) => m.organiserId == 'current_user').toList();
      // When serializing, swap out base64 for category fallback to keep JSON small
      final jsonList = userMeetups.map((m) {
        final j = m.toJson();
        if ((j['imageUrl'] as String).startsWith('data:')) {
          j['imageUrl'] = _categoryFallbackUrl(m.category);
          j['hasCustomImage'] = true; // Flag to reload from separate storage
        }
        return j;
      }).toList();
      final encoded = json.encode(jsonList);
      await BrowserStorage.setString(_storageKey, encoded);
    } catch (_) {}
  }

  static String _categoryFallbackUrl(String category) => Meetup._categoryFallbackUrl(category);

  Future<void> _loadPersistedMeetups() async {
    try {
      final raw = await BrowserStorage.getString(_storageKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        for (final j in decoded) {
          final map = j as Map<String, dynamic>;
          var meetup = Meetup.fromJson(map);
          // Restore base64 image from separate storage if flagged
          if (map['hasCustomImage'] == true) {
            final storedImage = await BrowserStorage.getString('meetup_image_${meetup.id}');
            if (storedImage != null && storedImage.startsWith('data:')) {
              meetup = Meetup(
                id: meetup.id, title: meetup.title, description: meetup.description,
                category: meetup.category, dateDisplay: meetup.dateDisplay,
                timeDisplay: meetup.timeDisplay, dateTime: meetup.dateTime,
                location: meetup.location, organiserName: meetup.organiserName,
                organiserId: meetup.organiserId, attendeeCount: meetup.attendeeCount,
                maxAttendees: meetup.maxAttendees, isGoing: meetup.isGoing,
                isFree: meetup.isFree, price: meetup.price,
                attendeeNames: meetup.attendeeNames, imageUrl: storedImage,
                privacy: meetup.privacy, repeat: meetup.repeat,
                repeatDisplay: meetup.repeatDisplay, repeatDays: meetup.repeatDays,
                repeatEndDate: meetup.repeatEndDate, groupId: meetup.groupId,
                groupName: meetup.groupName, invitees: meetup.invitees,
                invitedMemberIds: meetup.invitedMemberIds, borough: meetup.borough,
                targetAudience: meetup.targetAudience,
                createdAt: meetup.createdAt,
              );
            }
          }
          if (!_meetups.any((m) => m.id == meetup.id)) {
            _meetups.insert(0, meetup);
          }
        }
        // Guard notifyListeners so it never fires during a build frame.
        // This method is called from the constructor (_internal), which runs
        // during static singleton initialization. addPostFrameCallback can fire
        // DURING the first build frame. Future.delayed(Duration.zero) is
        // safer: it runs on the event queue after the build cycle completes.
        Future.delayed(Duration.zero, () {
          if (hasListeners) notifyListeners();
        });
      }
    } catch (_) {}
  }

  /// Loads meetups from Firestore and merges them into the local list.
  /// Safe to call multiple times — deduplicates by ID.
  Future<void> loadFromFirestore() async {
    try {
      final raw = await FirestoreService().getMeetups();
      bool changed = false;
      for (final map in raw) {
        // Normalise Firestore Timestamp fields that weren't converted
        if (map['dateTime'] is Map) {
          // Firestore Timestamp serialised as map — skip
          continue;
        }
        final meetup = Meetup.fromJson(map);
        if (!_meetups.any((m) => m.id == meetup.id)) {
          _meetups.add(meetup);
          changed = true;
        }
      }
      if (changed) {
        // Seed demo meetups only when Firestore is empty so filters are testable
        if (_meetups.where((m) => m.organiserId != 'current_user').isEmpty) {
          _seedDemoMeetups();
        }
        Future.delayed(Duration.zero, () {
          if (hasListeners) notifyListeners();
        });
      } else if (_meetups.isEmpty) {
        _seedDemoMeetups();
        Future.delayed(Duration.zero, () {
          if (hasListeners) notifyListeners();
        });
      }
    } catch (_) {
      // Firestore unavailable — seed demo data so UI is functional
      if (_meetups.isEmpty) {
        _seedDemoMeetups();
        Future.delayed(Duration.zero, () {
          if (hasListeners) notifyListeners();
        });
      }
    }
  }

  /// Seeds realistic demo meetups with varied categories, participants,
  /// price and date data so every filter in the sheet shows a visible result.
  void _seedDemoMeetups() {
    final now = DateTime.now();
    final demos = [
      Meetup(
        id: 'demo_1',
        title: 'Morning Coffee & Chat',
        description: 'Casual coffee morning for local parents.',
        category: 'Coffee',
        dateDisplay: 'SAT, ${now.add(const Duration(days: 3)).day} ${_monthName(now.add(const Duration(days: 3)).month)}',
        timeDisplay: '9:00 - 10:30 AM',
        dateTime: now.add(const Duration(days: 3, hours: 9)),
        location: 'The Bean Café, Hackney',
        organiserName: 'Sarah M.',
        organiserId: 'demo_user_1',
        attendeeCount: 14,
        isFree: true,
        targetAudience: ['Mums', 'Expecting parents'],
        imageUrl: Meetup.categoryFallbackUrl('Coffee'),
      ),
      Meetup(
        id: 'demo_2',
        title: 'Sunday Park Playdate',
        description: 'Kids play together while parents relax.',
        category: 'Playdate',
        dateDisplay: 'SUN, ${now.add(const Duration(days: 5)).day} ${_monthName(now.add(const Duration(days: 5)).month)}',
        timeDisplay: '11:00 AM - 1:00 PM',
        dateTime: now.add(const Duration(days: 5, hours: 11)),
        location: 'Victoria Park, London',
        organiserName: 'James T.',
        organiserId: 'demo_user_2',
        attendeeCount: 22,
        isFree: true,
        targetAudience: ['Dads', 'Mums', 'Kids'],
        imageUrl: Meetup.categoryFallbackUrl('Playdate'),
      ),
      Meetup(
        id: 'demo_3',
        title: 'Pregnancy Yoga Class',
        description: 'Gentle yoga for expecting parents.',
        category: 'Social',
        dateDisplay: 'WED, ${now.add(const Duration(days: 7)).day} ${_monthName(now.add(const Duration(days: 7)).month)}',
        timeDisplay: '6:00 - 7:00 PM',
        dateTime: now.add(const Duration(days: 7, hours: 18)),
        location: 'Bloom Studio, Islington',
        organiserName: 'Priya K.',
        organiserId: 'demo_user_3',
        attendeeCount: 8,
        isFree: false,
        price: 12.0,
        targetAudience: ['Expecting parents', 'Mums'],
        imageUrl: 'https://images.pexels.com/photos/3822622/pexels-photo-3822622.jpeg?auto=compress&cs=tinysrgb&w=800',
      ),
      Meetup(
        id: 'demo_4',
        title: 'Dads Weekend Football',
        description: 'Casual 5-a-side for dads. All abilities welcome!',
        category: 'Sport',
        dateDisplay: 'SAT, ${now.add(const Duration(days: 8)).day} ${_monthName(now.add(const Duration(days: 8)).month)}',
        timeDisplay: '8:00 - 9:30 AM',
        dateTime: now.add(const Duration(days: 8, hours: 8)),
        location: 'Hackney Marshes, London',
        organiserName: 'Marcus O.',
        organiserId: 'demo_user_4',
        attendeeCount: 18,
        isFree: true,
        targetAudience: ['Dads'],
        imageUrl: Meetup.categoryFallbackUrl('Sport'),
      ),
      Meetup(
        id: 'demo_5',
        title: 'Nature Walk for Families',
        description: 'Easy 3km walk through the forest.',
        category: 'Walk',
        dateDisplay: 'SUN, ${now.add(const Duration(days: 10)).day} ${_monthName(now.add(const Duration(days: 10)).month)}',
        timeDisplay: '10:00 - 11:30 AM',
        dateTime: now.add(const Duration(days: 10, hours: 10)),
        location: 'Epping Forest, Essex',
        organiserName: 'Yemi A.',
        organiserId: 'demo_user_5',
        attendeeCount: 31,
        isFree: true,
        targetAudience: ['Mums', 'Dads', 'Kids'],
        imageUrl: Meetup.categoryFallbackUrl('Walk'),
      ),
      Meetup(
        id: 'demo_6',
        title: 'Baby Sensory Workshop',
        description: 'Interactive sensory play for babies 0–18 months.',
        category: 'Social',
        dateDisplay: 'TUE, ${now.add(const Duration(days: 12)).day} ${_monthName(now.add(const Duration(days: 12)).month)}',
        timeDisplay: '10:00 - 11:00 AM',
        dateTime: now.add(const Duration(days: 12, hours: 10)),
        location: 'Little Stars Centre, Bethnal Green',
        organiserName: 'Aisha P.',
        organiserId: 'demo_user_6',
        attendeeCount: 6,
        isFree: false,
        price: 8.50,
        targetAudience: ['Mums', 'Aspiring parents'],
        imageUrl: 'https://images.pexels.com/photos/3662667/pexels-photo-3662667.jpeg?auto=compress&cs=tinysrgb&w=800',
      ),
      Meetup(
        id: 'demo_7',
        title: 'Aspiring Parents Support Group',
        description: 'Share experiences and support each other.',
        category: 'Social',
        dateDisplay: 'THU, ${now.add(const Duration(days: 14)).day} ${_monthName(now.add(const Duration(days: 14)).month)}',
        timeDisplay: '7:00 - 8:30 PM',
        dateTime: now.add(const Duration(days: 14, hours: 19)),
        location: 'Community Hall, Brixton',
        organiserName: 'Ruth S.',
        organiserId: 'demo_user_7',
        attendeeCount: 11,
        isFree: true,
        targetAudience: ['Aspiring parents'],
        imageUrl: 'https://images.pexels.com/photos/7551442/pexels-photo-7551442.jpeg?auto=compress&cs=tinysrgb&w=800',
      ),
      Meetup(
        id: 'demo_8',
        title: 'Theatre Show: Tales for Tots',
        description: 'Colourful puppet theatre for young children.',
        category: 'Social',
        dateDisplay: 'SAT, ${now.add(const Duration(days: 16)).day} ${_monthName(now.add(const Duration(days: 16)).month)}',
        timeDisplay: '2:00 - 3:00 PM',
        dateTime: now.add(const Duration(days: 16, hours: 14)),
        location: 'Unicorn Theatre, London Bridge',
        organiserName: 'Chloe D.',
        organiserId: 'demo_user_8',
        attendeeCount: 25,
        isFree: false,
        price: 15.0,
        targetAudience: ['Kids', 'Mums', 'Dads'],
        imageUrl: 'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=800',
      ),
    ];

    for (final d in demos) {
      if (!_meetups.any((m) => m.id == d.id)) {
        _meetups.add(d);
      }
    }
  }

  static String _monthName(int month) {
    const names = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return names[month.clamp(1, 12)];
  }

}
