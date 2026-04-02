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
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Meetup copyWith({
    int? attendeeCount,
    bool? isGoing,
    bool? isFree,
    double? price,
    List<String>? attendeeNames,
    List<MeetupAttendee>? invitees,
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
      createdAt: createdAt,
    );
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
    'imageUrl': imageUrl.startsWith('data:') ? '' : imageUrl, // Don't persist base64
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
    _meetups.addAll([
      Meetup(
        id: 'mu_1',
        title: 'Coffee & Chat — New Parents',
        description:
            'Grab a coffee and meet other new parents in the area. Bring your little ones — there\'s space for prams and a play area for crawlers. No agenda, just good company and caffeine! We usually grab a table at the back where it\'s quieter.',
        category: 'Coffee',
        dateDisplay: 'MON, MAR 17',
        timeDisplay: '9:30 - 11:00 AM',
        dateTime: DateTime(2025, 3, 17, 9, 30),
        location: 'Little Bean Cafe, Fitzroy',
        organiserName: 'Sophie M.',
        organiserId: 'mem_sophie',
        imageUrl: 'https://images.pexels.com/photos/302899/pexels-photo-302899.jpeg?auto=compress&cs=tinysrgb&w=600',
        attendeeCount: 8,
        maxAttendees: 12,
        isGoing: false,
        attendeeNames: ['Sophie M.', 'Emma W.', 'Anna K.', 'Lucy R.', 'Kate P.', 'Sarah T.', 'Olivia L.', 'James D.'],
        privacy: MeetupPrivacy.public,
        repeat: MeetupRepeat.weekly,
        repeatDisplay: 'Every Monday',
        isFree: true,
      ),
      Meetup(
        id: 'mu_2',
        title: 'Dad\'s Golf Day',
        description:
            'Calling all dads! Let\'s hit the range for a relaxed 9 holes. All skill levels welcome — it\'s about getting out of the house and having a laugh. We\'ll grab a beer at the clubhouse after. Kids welcome to tag along if needed.',
        category: 'Sport',
        dateDisplay: 'SAT, MAR 22',
        timeDisplay: '7:30 - 10:30 AM',
        dateTime: DateTime(2025, 3, 22, 7, 30),
        location: 'Northcote Golf Course',
        organiserName: 'James D.',
        organiserId: 'mem_james',
        imageUrl: 'https://images.pexels.com/photos/1325735/pexels-photo-1325735.jpeg?auto=compress&cs=tinysrgb&w=600',
        attendeeCount: 5,
        maxAttendees: 8,
        isGoing: false,
        attendeeNames: ['James D.', 'Mark T.', 'Luke W.', 'David S.', 'Tom R.'],
        privacy: MeetupPrivacy.group,
        groupName: 'Dads Connect',
        isFree: false,
        price: 15.0,
      ),
      Meetup(
        id: 'mu_3',
        title: 'Pram Walk & Picnic',
        description:
            'Join us for a gentle walk through the park with prams, followed by a BYO picnic on the grass. Great way to get some fresh air and meet other parents. Dogs welcome too! We\'ll meet at the main entrance near the playground.',
        category: 'Walk',
        dateDisplay: 'FRI, MAR 21',
        timeDisplay: '10:00 AM - 12:00 PM',
        dateTime: DateTime(2025, 3, 21, 10, 0),
        location: 'Edinburgh Gardens, North Fitzroy',
        organiserName: 'Emma W.',
        organiserId: 'mem_emma',
        imageUrl: 'https://images.pexels.com/photos/3933239/pexels-photo-3933239.jpeg?auto=compress&cs=tinysrgb&w=600',
        attendeeCount: 15,
        isGoing: false,
        attendeeNames: ['Emma W.', 'Sophie M.', 'Anna K.', 'Kate P.', 'Lucy R.'],
        privacy: MeetupPrivacy.public,
        isFree: true,
      ),
      Meetup(
        id: 'mu_4',
        title: 'Playdate at the Park',
        description:
            'Bringing the toddlers to the new playground for a playdate! There\'s a great fenced area for little ones with sandpit, swings and climbing frame. BYO snacks and water. See you there!',
        category: 'Playdate',
        dateDisplay: 'WED, MAR 19',
        timeDisplay: '3:00 - 4:30 PM',
        dateTime: DateTime(2025, 3, 19, 15, 0),
        location: 'Curtain Square Playground, Carlton',
        organiserName: 'Anna K.',
        organiserId: 'mem_anna',
        imageUrl: 'https://images.pexels.com/photos/296301/pexels-photo-296301.jpeg?auto=compress&cs=tinysrgb&w=600',
        attendeeCount: 10,
        isGoing: false,
        attendeeNames: ['Anna K.', 'Emma W.', 'Sophie M.', 'Olivia L.'],
        privacy: MeetupPrivacy.public,
        isFree: true,
      ),
      Meetup(
        id: 'mu_5',
        title: 'Friday Night Dinner — Parents Only!',
        description:
            'Leave the kids with the babysitter and join us for an adults-only dinner. We\'re trying the new Italian place on Smith St. RSVP so we can book a table. Let\'s be honest, we all need a night out!',
        category: 'Social',
        dateDisplay: 'FRI, MAR 28',
        timeDisplay: '7:00 - 10:00 PM',
        dateTime: DateTime(2025, 3, 28, 19, 0),
        location: 'Trattoria Roma, Smith St, Collingwood',
        organiserName: 'Luke W.',
        organiserId: 'mem_luke',
        imageUrl: 'https://images.pexels.com/photos/260922/pexels-photo-260922.jpeg?auto=compress&cs=tinysrgb&w=600',
        attendeeCount: 6,
        maxAttendees: 10,
        isGoing: false,
        attendeeNames: ['Luke W.', 'Kate P.', 'Mark T.', 'Sarah T.', 'David S.', 'Tom R.'],
        privacy: MeetupPrivacy.private_,
        isFree: false,
        price: 35.0,
      ),
    ]);
  }
}
