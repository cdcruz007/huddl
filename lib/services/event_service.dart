import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';

/// Represents a third-party or user-created event (may be free or paid).
class Event {
  final String id;
  final String title;
  final String description;
  final String dateDisplay; // e.g. "SAT, MAR 15"
  final String timeDisplay; // e.g. "10:00 - 11:30 AM"
  final DateTime dateTime;
  final String location;
  final int attendees;
  final bool isFree;
  final String price; // e.g. "\$18" or "" if free
  final bool isOnline;
  final Color color;
  final IconData icon;
  final String organiser;
  final String organiserLogo;
  final String imageUrl;
  final bool isUserCreated;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.dateDisplay,
    required this.timeDisplay,
    required this.dateTime,
    required this.location,
    this.attendees = 0,
    this.isFree = true,
    this.price = '',
    this.isOnline = false,
    required this.color,
    required this.icon,
    this.organiser = '',
    this.organiserLogo = '',
    this.imageUrl = '',
    this.isUserCreated = false,
  });

  /// Convert to the Map<String, dynamic> expected by existing card widgets.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'date': dateDisplay,
      'time': timeDisplay,
      'location': location,
      'attendees': attendees,
      'isFree': isFree,
      'price': price,
      'isOnline': isOnline,
      'color': color,
      'icon': icon,
      'organiser': organiser,
      'organiserLogo': organiserLogo,
      'imageUrl': imageUrl,
    };
  }
}

/// Manages the list of events. Singleton with ChangeNotifier.
class EventService extends ChangeNotifier {
  static final EventService _instance = EventService._internal();
  factory EventService() => _instance;
  EventService._internal() {
    _loadSampleEvents();
  }

  final List<Event> _events = [];

  List<Event> get events => List.unmodifiable(_events);

  /// All events as Maps (for compatibility with existing _EventListCard).
  List<Map<String, dynamic>> get eventMaps =>
      _events.map((e) => e.toMap()).toList();

  /// Creates a new event and adds it to the top of the list.
  void createEvent(Event event) {
    _events.insert(0, event);
    notifyListeners();
  }

  /// Delete an event.
  void deleteEvent(String eventId) {
    _events.removeWhere((e) => e.id == eventId);
    notifyListeners();
  }

  // ── Sample data ─────────────────────────────────────────────────────────

  void _loadSampleEvents() {
    _events.addAll([
      Event(
        id: 'ev_1',
        title: 'Baby Sensory Play Session',
        description:
            'A fun sensory play session designed for babies aged 0-12 months. Come explore different textures, sounds and colours. Run by qualified early childhood educators with 10+ years experience. All materials provided.',
        dateDisplay: 'SAT, MAR 15',
        timeDisplay: '10:00 - 11:30 AM',
        dateTime: DateTime(2025, 3, 15, 10, 0),
        location: 'Community Centre, Carlton',
        attendees: 24,
        isFree: false,
        price: '\$18',
        isOnline: false,
        color: HuddlColors.primary,
        icon: Icons.child_care,
        organiser: 'Little Explorers Co.',
        imageUrl:
            'https://images.pexels.com/photos/3661452/pexels-photo-3661452.jpeg?auto=compress&cs=tinysrgb&w=600',
      ),
      Event(
        id: 'ev_2',
        title: 'Toddler Music & Movement',
        description:
            'Interactive music and movement class for toddlers aged 1-3 years. Singing, dancing and instrument play! Led by professional musicians who specialise in early childhood music education.',
        dateDisplay: 'WED, MAR 19',
        timeDisplay: '2:00 - 3:00 PM',
        dateTime: DateTime(2025, 3, 19, 14, 0),
        location: 'Music Room, Brunswick',
        attendees: 18,
        isFree: false,
        price: '\$15',
        isOnline: false,
        color: HuddlColors.teal,
        icon: Icons.music_note,
        organiser: 'Tiny Tunes Academy',
        imageUrl:
            'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=600',
      ),
      Event(
        id: 'ev_3',
        title: 'New Parents Workshop',
        description:
            'A comprehensive workshop covering baby basics: feeding, sleeping, and settling techniques from certified professionals. Morning tea provided. Certificate of completion included.',
        dateDisplay: 'SAT, MAR 22',
        timeDisplay: '1:00 - 4:00 PM',
        dateTime: DateTime(2025, 3, 22, 13, 0),
        location: 'Health Hub, Collingwood',
        attendees: 20,
        isFree: false,
        price: '\$45',
        isOnline: false,
        color: const Color(0xFFE8A838),
        icon: Icons.school,
        organiser: 'Parent Pro Australia',
        imageUrl:
            'https://images.pexels.com/photos/3875089/pexels-photo-3875089.jpeg?auto=compress&cs=tinysrgb&w=600',
      ),
      Event(
        id: 'ev_4',
        title: 'Online: Sleep Training Masterclass',
        description:
            'Join our expert paediatric sleep consultant for a live interactive webinar on establishing healthy sleep routines for babies 4-18 months. Q&A session included.',
        dateDisplay: 'THU, MAR 27',
        timeDisplay: '7:30 - 9:00 PM',
        dateTime: DateTime(2025, 3, 27, 19, 30),
        location: 'Online (Zoom)',
        attendees: 85,
        isFree: false,
        price: '\$25',
        isOnline: true,
        color: HuddlColors.blue,
        icon: Icons.nightlight_round,
        organiser: 'Sleep Well Babies',
        imageUrl:
            'https://images.pexels.com/photos/3771519/pexels-photo-3771519.jpeg?auto=compress&cs=tinysrgb&w=600',
      ),
      Event(
        id: 'ev_5',
        title: 'Family Fun Day \u2014 Free Entry',
        description:
            'A free community event with face painting, balloon artists, petting zoo, food trucks and live music. Bring the whole family for a day of fun! Organised by the Carlton Community Association.',
        dateDisplay: 'SUN, MAR 30',
        timeDisplay: '10:00 AM - 3:00 PM',
        dateTime: DateTime(2025, 3, 30, 10, 0),
        location: 'Princes Park, Carlton North',
        attendees: 150,
        isFree: true,
        price: '',
        isOnline: false,
        color: HuddlColors.purple,
        icon: Icons.celebration,
        organiser: 'Carlton Community Assoc.',
        imageUrl:
            'https://images.pexels.com/photos/1684187/pexels-photo-1684187.jpeg?auto=compress&cs=tinysrgb&w=600',
      ),
      Event(
        id: 'ev_6',
        title: 'Baby First Aid & CPR',
        description:
            'Essential baby and child first aid course. Learn CPR, choking response, and how to handle common childhood injuries. Accredited certification included.',
        dateDisplay: 'SAT, APR 5',
        timeDisplay: '9:00 AM - 1:00 PM',
        dateTime: DateTime(2025, 4, 5, 9, 0),
        location: 'St Vincent\'s Hospital, Fitzroy',
        attendees: 30,
        isFree: false,
        price: '\$65',
        isOnline: false,
        color: const Color(0xFFE53935),
        icon: Icons.medical_services_outlined,
        organiser: 'Red Cross Australia',
        imageUrl:
            'https://images.pexels.com/photos/263337/pexels-photo-263337.jpeg?auto=compress&cs=tinysrgb&w=600',
      ),
    ]);
  }
}
