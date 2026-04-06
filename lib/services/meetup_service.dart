import 'dart:convert';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';

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
      createdAt: createdAt,
    );
  }

  /// Returns a Pexels URL that matches the meetup category.
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
    'imageUrl': imageUrl.startsWith('data:') ? _categoryFallbackUrl(category) : imageUrl, // Replace base64 with category image
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
    attendeeCount: j['attendeeCount'] ?? 1,
    maxAttendees: j['maxAttendees'],
    isGoing: j['isGoing'] ?? false,
    attendeeNames: List<String>.from(j['attendeeNames'] ?? []),
    imageUrl: j['imageUrl'] ?? '',
    isFree: j['isFree'] ?? true,
    price: j['price'] != null ? (j['price'] as num).toDouble() : null,
    privacy: MeetupPrivacy.values[j['privacy'] ?? 0],
    repeat: MeetupRepeat.values[j['repeat'] ?? 0],
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
    createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
  );
}

/// Manages the list of meet-ups. Singleton with ChangeNotifier.
class MeetupService extends ChangeNotifier {
  static final MeetupService _instance = MeetupService._internal();
  factory MeetupService() => _instance;
  MeetupService._internal() {
    _loadSampleMeetups();
    _loadPersistedMeetups();
  }

  static const String _storageKey = 'huddl_user_meetups';
  final List<Meetup> _meetups = [];

  List<Meetup> get meetups => List.unmodifiable(_meetups);

  /// Creates a new meet-up and adds it to the list.
  void createMeetup(Meetup meetup) {
    _meetups.insert(0, meetup);
    notifyListeners();
    _persistUserMeetups();
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
      attendeeNames: wasGoing
          ? (List<String>.from(m.attendeeNames)..remove('You'))
          : [...m.attendeeNames, 'You'],
    );
    notifyListeners();
    _persistUserMeetups();
  }

  /// Delete a meetup (organiser only).
  void deleteMeetup(String meetupId) {
    _meetups.removeWhere((m) => m.id == meetupId);
    notifyListeners();
    _persistUserMeetups();
  }

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

  Future<void> _persistUserMeetups() async {
    try {
      final userMeetups = _meetups.where((m) => m.organiserId == 'current_user').toList();
      final encoded = json.encode(userMeetups.map((m) => m.toJson()).toList());
      await BrowserStorage.setString(_storageKey, encoded);
    } catch (_) {}
  }

  Future<void> _loadPersistedMeetups() async {
    try {
      final raw = await BrowserStorage.getString(_storageKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        for (final j in decoded) {
          final meetup = Meetup.fromJson(j as Map<String, dynamic>);
          if (!_meetups.any((m) => m.id == meetup.id)) {
            _meetups.insert(0, meetup);
          }
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  // ── Sample data ─────────────────────────────────────────────────────────

  void _loadSampleMeetups() {
    final now = DateTime.now();
    _meetups.addAll([
      Meetup(
        id: 'mu_1',
        title: 'Coffee & Chat \u2014 New Parents',
        description:
            'Grab a coffee and meet other new parents in the area. Bring your little ones \u2014 there\'s space for prams and a play area for crawlers. No agenda, just good company and caffeine! We usually grab a table at the back where it\'s quieter.',
        category: 'Coffee',
        dateDisplay: _autoDateDisplay(now.add(const Duration(days: 3))),
        timeDisplay: '9:30 - 11:00 AM',
        dateTime: DateTime(now.year, now.month, now.day, 9, 30).add(const Duration(days: 3)),
        location: 'Little Bean Cafe, Cambridge',
        organiserName: 'Sophie Williams',
        organiserId: 'mem_sophie',
        imageUrl: 'https://images.pexels.com/photos/302899/pexels-photo-302899.jpeg?auto=compress&cs=tinysrgb&w=600',
        attendeeCount: 8,
        maxAttendees: 12,
        isGoing: false,
        attendeeNames: ['Sophie Williams', 'Emma Thompson', 'Anna Mitchell', 'Lucy Taylor', 'Kate Rogers', 'Sarah Clarke', 'Olivia Brown', 'James Carter'],
        privacy: MeetupPrivacy.public,
        repeat: MeetupRepeat.weekly,
        repeatDisplay: 'Every Monday',
        isFree: true,
        borough: 'Cambridge',
      ),
      Meetup(
        id: 'mu_2',
        title: 'Dad\'s Golf Day',
        description:
            'Calling all dads! Let\'s hit the range for a relaxed 9 holes. All skill levels welcome \u2014 it\'s about getting out of the house and having a laugh. We\'ll grab a beer at the clubhouse after. Kids welcome to tag along if needed.',
        category: 'Sport',
        dateDisplay: _autoDateDisplay(now.add(const Duration(days: 6))),
        timeDisplay: '7:30 - 10:30 AM',
        dateTime: DateTime(now.year, now.month, now.day, 7, 30).add(const Duration(days: 6)),
        location: 'Cambridge Golf Course',
        organiserName: 'James Carter',
        organiserId: 'mem_james',
        imageUrl: 'https://images.pexels.com/photos/1325735/pexels-photo-1325735.jpeg?auto=compress&cs=tinysrgb&w=600',
        attendeeCount: 5,
        maxAttendees: 8,
        isGoing: false,
        attendeeNames: ['James Carter', 'Mark Robinson', 'Luke Anderson', 'David Harris', 'Tom Evans'],
        privacy: MeetupPrivacy.group,
        groupId: 'disc_dads_connect',
        groupName: 'Dads Connect',
        isFree: false,
        price: 15.0,
        borough: 'Cambridge',
      ),
      Meetup(
        id: 'mu_3',
        title: 'Pram Walk & Picnic',
        description:
            'Join us for a gentle walk through the park with prams, followed by a BYO picnic on the grass. Great way to get some fresh air and meet other parents. Dogs welcome too! We\'ll meet at the main entrance near the playground.',
        category: 'Walk',
        dateDisplay: _autoDateDisplay(now.add(const Duration(days: 5))),
        timeDisplay: '10:00 AM - 12:00 PM',
        dateTime: DateTime(now.year, now.month, now.day, 10, 0).add(const Duration(days: 5)),
        location: 'Jesus Green, Cambridge',
        organiserName: 'Emma Thompson',
        organiserId: 'mem_emma',
        imageUrl: 'https://images.pexels.com/photos/3933239/pexels-photo-3933239.jpeg?auto=compress&cs=tinysrgb&w=600',
        attendeeCount: 15,
        isGoing: false,
        attendeeNames: ['Emma Thompson', 'Sophie Williams', 'Anna Mitchell', 'Kate Rogers', 'Lucy Taylor'],
        privacy: MeetupPrivacy.public,
        isFree: true,
        borough: 'Cambridge',
      ),
      Meetup(
        id: 'mu_4',
        title: 'Playdate at the Park',
        description:
            'Bringing the toddlers to the new playground for a playdate! There\'s a great fenced area for little ones with sandpit, swings and climbing frame. BYO snacks and water. See you there!',
        category: 'Playdate',
        dateDisplay: _autoDateDisplay(now.add(const Duration(days: 4))),
        timeDisplay: '3:00 - 4:30 PM',
        dateTime: DateTime(now.year, now.month, now.day, 15, 0).add(const Duration(days: 4)),
        location: 'Cherry Hinton Hall, Cambridge',
        organiserName: 'Anna Mitchell',
        organiserId: 'mem_anna',
        imageUrl: 'https://images.pexels.com/photos/296301/pexels-photo-296301.jpeg?auto=compress&cs=tinysrgb&w=600',
        attendeeCount: 10,
        isGoing: false,
        attendeeNames: ['Anna Mitchell', 'Emma Thompson', 'Sophie Williams', 'Olivia Brown'],
        privacy: MeetupPrivacy.public,
        isFree: true,
        borough: 'Cambridge',
      ),
      Meetup(
        id: 'mu_5',
        title: 'Friday Night Dinner \u2014 Parents Only!',
        description:
            'Leave the kids with the babysitter and join us for an adults-only dinner. We\'re trying the new Italian place on Mill Rd. RSVP so we can book a table. Let\'s be honest, we all need a night out!',
        category: 'Social',
        dateDisplay: _autoDateDisplay(now.add(const Duration(days: 10))),
        timeDisplay: '7:00 - 10:00 PM',
        dateTime: DateTime(now.year, now.month, now.day, 19, 0).add(const Duration(days: 10)),
        location: 'Trattoria Roma, Mill Road, Cambridge',
        organiserName: 'Luke Anderson',
        organiserId: 'mem_luke',
        imageUrl: 'https://images.pexels.com/photos/260922/pexels-photo-260922.jpeg?auto=compress&cs=tinysrgb&w=600',
        attendeeCount: 6,
        maxAttendees: 10,
        isGoing: false,
        attendeeNames: ['Luke Anderson', 'Kate Rogers', 'Mark Robinson', 'Sarah Clarke', 'David Harris', 'Tom Evans'],
        privacy: MeetupPrivacy.private_,
        invitedMemberIds: ['mem_kate', 'mem_mark', 'mem_sarah', 'mem_david', 'mem_tom'],
        isFree: false,
        price: 35.0,
        borough: 'Cambridge',
      ),
    ]);
  }

  /// Auto-format a date display string from a DateTime.
  static String _autoDateDisplay(DateTime d) {
    const dayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const monthAbbr = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return '${dayAbbr[d.weekday - 1]}, ${monthAbbr[d.month - 1]} ${d.day}';
  }
}
