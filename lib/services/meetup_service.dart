import 'dart:convert';
import 'dart:ui' show Color;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import 'clearable_user_state.dart';
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
  // EVENT-COUNT-1 follow-up: attendeeIds is the authoritative source of truth.
  // attendeeCount is derived from attendeeIds.length and is no longer stored
  // as an independent field. This eliminates the forgeable denormalized mirror.
  final List<String> attendeeIds;
  int get attendeeCount => attendeeIds.length;
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
  final bool isOnline; // Whether this is a virtual/online meetup
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
    this.organiserId = '',  // set at call-site via FirebaseAuth.instance.currentUser?.uid
    this.attendeeIds = const [],
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
    this.isOnline = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Meetup copyWith({
    List<String>? attendeeIds,
    bool? isGoing,
    bool? isFree,
    double? price,
    bool? isOnline,
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
      attendeeIds: attendeeIds ?? this.attendeeIds,
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
      isOnline: isOnline ?? this.isOnline,
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
    // Firestore spec field names (spec-aligned) + legacy aliases for backward compat
    'name': title,          'title': title,         // spec: name
    'createdBy': organiserId, 'organiserId': organiserId, // spec: createdBy
    'photoUrl': imageUrl,   'imageUrl': imageUrl,   // spec: photoUrl (base64 stored separately)
    'participants': targetAudience, 'targetAudience': targetAudience, // spec: participants
    'scopedGroupId': groupId, 'groupId': groupId,   // spec: scopedGroupId
    'description': description,
    'category': category,
    'dateDisplay': dateDisplay,
    'timeDisplay': timeDisplay,
    'date': dateTime.toIso8601String(), 'dateTime': dateTime.toIso8601String(), // spec: date
    'startTime': timeDisplay.split(' - ').first,    // spec: startTime (parsed from timeDisplay)
    'endTime': timeDisplay.split(' - ').last,       // spec: endTime
    'location': location.isEmpty && isOnline ? null : location, // spec: nullable for online
    'organiserName': organiserName,
    // EVENT-COUNT-1: attendeeCount is derived from attendeeIds.length;
    // do not write a separate attendeeCount field — Firestore rules
    // no longer permit clients to write it via the RSVP branch.
    'attendeeIds': attendeeIds,
    'maxAttendees': maxAttendees,
    'isGoing': isGoing,
    'attendeeNames': attendeeNames,
    'isFree': isFree,
    'price': price,
    'privacy': privacy.index,
    'isRepeat': repeat != MeetupRepeat.none,  // spec: isRepeat Boolean
    'repeat': repeat.index,
    'repeatFrequency': repeatDisplay, 'repeatDisplay': repeatDisplay, // spec: repeatFrequency
    'repeatDays': repeatDays,
    'repeatEndDate': repeatEndDate?.toIso8601String(),
    'groupName': groupName,
    'invitees': invitees.map((i) => i.toJson()).toList(),
    'attendees': invitedMemberIds, 'invitedMemberIds': invitedMemberIds, // spec: attendees
    'borough': borough,
    'isOnline': isOnline,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Meetup.fromJson(Map<String, dynamic> j) => Meetup(
    id: j['id'] ?? '',
    // Read spec keys first, fall back to legacy keys for backward compat
    title: (j['name'] ?? j['title'] ?? '') as String,
    description: j['description'] ?? '',
    category: j['category'] ?? 'Other',
    dateDisplay: j['dateDisplay'] ?? '',
    timeDisplay: j['timeDisplay'] ?? '',
    dateTime: DateTime.tryParse(j['date'] ?? j['dateTime'] ?? '') ?? DateTime.now(),
    location: (j['location'] as String?) ?? '',
    organiserName: j['organiserName'] ?? '',
    organiserId: (j['createdBy'] ?? j['organiserId'] ?? '') as String,
    // EVENT-COUNT-1: derive attendeeIds from Firestore; fall back to 1-element
    // list with organiserId so that organiser-only meetups show count=1.
    attendeeIds: j['attendeeIds'] != null
        ? List<String>.from(j['attendeeIds'] as List)
        : (j['attendeeCount'] != null
            ? List.generate(
                ((j['attendeeCount'] as num?)?.toInt() ?? 1).clamp(0, 999),
                (i) => 'legacy_$i')
            : const []),
    maxAttendees: (j['maxAttendees'] as num?)?.toInt(),
    isGoing: j['isGoing'] ?? false,
    attendeeNames: List<String>.from(j['attendeeNames'] ?? []),
    imageUrl: (j['photoUrl'] ?? j['imageUrl'] ?? '') as String,
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
    groupId: (j['scopedGroupId'] ?? j['groupId']) as String?,
    groupName: j['groupName'] as String?,
    invitees: (j['invitees'] as List<dynamic>?)
        ?.map((i) => MeetupAttendee.fromJson(i as Map<String, dynamic>))
        .toList() ?? [],
    invitedMemberIds: List<String>.from(j['attendees'] ?? j['invitedMemberIds'] ?? []),
    borough: j['borough'],
    targetAudience: List<String>.from(j['participants'] ?? j['targetAudience'] ?? []),
    isOnline: j['isOnline'] as bool? ?? false,
    createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
  );
}

/// Manages the list of meet-ups. Singleton with ChangeNotifier.
///
/// HYPERLOCAL RULE: Meetups are borough-only.
/// Only meetups tagged with the current user's borough are visible.
/// Users cannot create meetups outside their home borough.
class MeetupService extends ChangeNotifier implements ClearableUserState {
  static final MeetupService _instance = MeetupService._internal();
  factory MeetupService() => _instance;
  MeetupService._internal() {
    UserStateRegistry.register(this);
    _loadPersistedMeetups();
  }

  static const String _storageKey = 'huddl_user_meetups';
  final List<Meetup> _meetups = [];
  final BoroughScopeGuard _guard = BoroughScopeGuard();

  /// Returns the current user's Firebase UID, falling back to the legacy
  /// sentinel 'current_user' for backwards-compat with persisted local data.
  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? 'current_user';

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
            attendeeIds: meetup.attendeeIds,
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
    // EVENT-COUNT-1 follow-up: derive count from attendeeIds list, not arithmetic.
    // Use the real Firebase UID where available so the list is authoritative.
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final updatedIds = wasGoing
        ? (List<String>.from(m.attendeeIds)..remove(myUid))
        : ([...m.attendeeIds, if (!m.attendeeIds.contains(myUid)) myUid]);
    _meetups[index] = m.copyWith(
      isGoing: !wasGoing,
      attendeeIds: updatedIds,
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

  /// Update an existing meetup (organiser only — edit flow).
  void updateMeetup(Meetup updated) {
    final index = _meetups.indexWhere((m) => m.id == updated.id);
    if (index < 0) return;
    _meetups[index] = updated;
    notifyListeners();
    _persistUserMeetups();
    // If image was updated and is a base64, persist separately
    if (updated.imageUrl.startsWith('data:')) {
      _persistMeetupImage(updated.id, updated.imageUrl);
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
    _meetups.removeWhere((m) => m.organiserId == _myUid || m.organiserId == 'current_user');
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
      if (!m.imageUrl.startsWith('data:') && (m.organiserId == _myUid || m.organiserId == 'current_user')) {
        final stored = await BrowserStorage.getString('meetup_image_${m.id}');
        if (stored != null && stored.startsWith('data:')) {
          _meetups[i] = Meetup(
            id: m.id, title: m.title, description: m.description,
            category: m.category, dateDisplay: m.dateDisplay,
            timeDisplay: m.timeDisplay, dateTime: m.dateTime,
            location: m.location, organiserName: m.organiserName,
            organiserId: m.organiserId, attendeeIds: m.attendeeIds,
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
      final userMeetups = _meetups.where((m) => m.organiserId == _myUid || m.organiserId == 'current_user').toList();
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
                organiserId: meetup.organiserId, attendeeIds: meetup.attendeeIds,
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

  // FETCH-SILENT-1: exposed so _MeetupsTabState can render HuddlErrorState.
  bool loadFailed = false;

  /// Loads meetups from Firestore and merges them into the local list.
  /// Safe to call multiple times — deduplicates by ID.
  Future<void> loadFromFirestore() async {
    loadFailed = false;
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
        Future.delayed(Duration.zero, () {
          if (hasListeners) notifyListeners();
        });
      } else if (_meetups.isEmpty) {
        // Firestore returned no meetups — notify so the UI shows its empty state
        // with a "Create your first meetup" CTA. No fake data injected.
        Future.delayed(Duration.zero, () {
          if (hasListeners) notifyListeners();
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MeetupService] loadFromFirestore error: $e');
      loadFailed = true; // FETCH-SILENT-1
      // Firestore unavailable — notify so UI can render error state.
      Future.delayed(Duration.zero, () {
        if (hasListeners) notifyListeners();
      });
    }
  }

  /// [ClearableUserState] — wipes meetup list + image cache on sign-out.
  @override
  Future<void> clearUserState() async {
    // Snapshot IDs before clearing so we can remove per-meetup image keys.
    final ids = _meetups.map((m) => m.id).toList();
    _meetups.clear();
    await BrowserStorage.remove(_storageKey);
    for (final id in ids) {
      await BrowserStorage.remove('meetup_image_$id');
    }
    notifyListeners();
  }

}
