import 'package:flutter/foundation.dart';

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
    this.attendeeNames = const [],
    this.imageUrl = '',
  });

  Meetup copyWith({
    int? attendeeCount,
    bool? isGoing,
    List<String>? attendeeNames,
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
      attendeeNames: attendeeNames ?? this.attendeeNames,
      imageUrl: imageUrl,
    );
  }
}

/// Manages the list of meet-ups. Singleton with ChangeNotifier.
class MeetupService extends ChangeNotifier {
  static final MeetupService _instance = MeetupService._internal();
  factory MeetupService() => _instance;
  MeetupService._internal() {
    _loadSampleMeetups();
  }

  final List<Meetup> _meetups = [];

  List<Meetup> get meetups => List.unmodifiable(_meetups);

  /// Creates a new meet-up and adds it to the list.
  void createMeetup(Meetup meetup) {
    _meetups.insert(0, meetup);
    notifyListeners();
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
  }

  /// Delete a meetup (organiser only).
  void deleteMeetup(String meetupId) {
    _meetups.removeWhere((m) => m.id == meetupId);
    notifyListeners();
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
      ),
    ]);
  }
}
