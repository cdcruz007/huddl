import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';
import '../models/group.dart';
import 'ai_event_discovery_service.dart';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';

/// Represents a third-party or user-created event (may be free or paid).
/// Age range suitability for an event.
class AgeRange {
  final int minMonths;
  final int maxMonths; // -1 = no upper limit
  const AgeRange(this.minMonths, this.maxMonths);

  String get displayLabel {
    if (minMonths == 0 && maxMonths == -1) return 'All ages';
    final minStr = minMonths < 12
        ? '${minMonths}m'
        : '${(minMonths / 12).floor()}y';
    if (maxMonths == -1) return '$minStr+';
    final maxStr = maxMonths < 12
        ? '${maxMonths}m'
        : '${(maxMonths / 12).floor()}y';
    return '$minStr-$maxStr';
  }

  bool containsMonths(int months) {
    if (months < minMonths) return false;
    if (maxMonths != -1 && months > maxMonths) return false;
    return true;
  }
}

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

  // ── AI Recommendation metadata ──────────────────────────────────
  final String borough;             // Borough this event targets
  final AgeRange? suitableAgeRange; // Age suitability for children
  final List<String> tags;          // e.g. ['sensory', 'music', 'first-aid', 'outdoors']
  final List<String> targetStages;  // Onboarding stages: 'pregnant', 'newborn', 'toddler', 'school-age'
  final String category;            // 'class', 'workshop', 'community', 'health', 'play', 'sport'
  final bool isWeekend;
  final int capacityLeft;           // Remaining spots (-1 = unlimited)
  final double partnerRating;       // B2B partner quality score 0-5

  // ── AI Discovery metadata ──────────────────────────────────────
  final bool isAiDiscovered;        // true if found by AI daily crawl
  final EventSource? aiSource;      // Source where AI found this event

  // ── Source URL (external event page) ─────────────────────────
  final String sourceUrl;           // URL to the original event listing

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
    this.borough = '',
    this.suitableAgeRange,
    this.tags = const [],
    this.targetStages = const [],
    this.category = 'community',
    this.isWeekend = false,
    this.capacityLeft = -1,
    this.partnerRating = 4.0,
    this.isAiDiscovered = false,
    this.aiSource,
    this.sourceUrl = '',
  });

  /// Convert to the map expected by existing card widgets.
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
      'borough': borough,
      'isAiDiscovered': isAiDiscovered,
      'aiSourceName': aiSource?.name ?? '',
      'aiSourceIcon': aiSource?.icon ?? Icons.language,
      'sourceUrl': sourceUrl,
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
  final Set<String> _goingEventIds = {};
  final Set<String> _bookmarkedEventIds = {};

  List<Event> get events => List.unmodifiable(_events);

  /// Events the user has marked as going.
  List<Event> get goingEvents =>
      _events.where((e) => _goingEventIds.contains(e.id)).toList();

  /// Whether the user is going to this event.
  bool isGoing(String eventId) => _goingEventIds.contains(eventId);

  /// Toggle going status for an event.
  /// Returns true if the user is now going (just registered).
  bool toggleGoing(String eventId) {
    if (_goingEventIds.contains(eventId)) {
      _goingEventIds.remove(eventId);
      notifyListeners();
      return false;
    } else {
      _goingEventIds.add(eventId);
      notifyListeners();
      return true;
    }
  }

  /// Get the Event object by ID.
  Event? getEventById(String eventId) {
    final matches = _events.where((e) => e.id == eventId);
    return matches.isNotEmpty ? matches.first : null;
  }

  /// Create a group chat for event attendees under the Messages tab.
  /// Called when a user taps "Count Me In".
  Future<void> createEventGroupChat(String eventId) async {
    final event = getEventById(eventId);
    if (event == null) return;

    final groupKey = 'user_created_groups_v1';
    final eventGroupId = 'event_group_$eventId';

    // Check if group already exists
    final existing = await BrowserStorage.getString(groupKey);
    List<dynamic> groups = [];
    if (existing != null) {
      groups = json.decode(existing) as List<dynamic>;
      final alreadyExists =
          groups.any((g) => (g as Map<String, dynamic>)['id'] == eventGroupId);
      if (alreadyExists) return; // Don't create duplicate
    }

    final onboarding = OnboardingDataService();
    final userName = onboarding.name ?? 'You';

    final newGroup = Group(
      id: eventGroupId,
      name: event.title,
      description:
          'Attendees chat for "${event.title}" on ${event.dateDisplay} at ${event.location}',
      imageUrl: event.imageUrl,
      memberCount: event.attendees + 1,
      category: 'EVENT',
      isJoined: true,
      isImageLocked: true,
      targetAudience: const [],
      privacy: GroupPrivacy.private_,
      creatorId: 'system',
      creatorName: event.organiser,
      creatorBorough: event.borough,
      lastMessage: '$userName joined the event chat',
      lastSenderName: 'System',
      lastMessageTime: DateTime.now(),
    );

    groups.add(newGroup.toJson());
    await BrowserStorage.setString(groupKey, json.encode(groups));
  }

  /// Whether the user has bookmarked this event.
  bool isBookmarked(String eventId) => _bookmarkedEventIds.contains(eventId);

  /// Toggle bookmark status for an event.
  void toggleBookmark(String eventId) {
    if (_bookmarkedEventIds.contains(eventId)) {
      _bookmarkedEventIds.remove(eventId);
    } else {
      _bookmarkedEventIds.add(eventId);
    }
    notifyListeners();
  }

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
        location: 'Cherry Hinton Village Centre, Cambridge',
        attendees: 24,
        isFree: false,
        price: '\u00A318',
        isOnline: false,
        color: HuddlColors.primary,
        icon: Icons.child_care,
        organiser: 'Little Explorers Co.',
        imageUrl:
            'https://images.pexels.com/photos/3661452/pexels-photo-3661452.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: 'Cambridge',
        suitableAgeRange: const AgeRange(0, 12),
        tags: ['sensory', 'baby', 'play', 'educational'],
        targetStages: ['newborn'],
        category: 'play',
        isWeekend: true,
        capacityLeft: 6,
        partnerRating: 4.7,
        sourceUrl: 'https://littleexplorers.co.uk/sensory-play',
      ),
      Event(
        id: 'ev_2',
        title: 'Toddler Music & Movement',
        description:
            'Interactive music and movement class for toddlers aged 1-3 years. Singing, dancing and instrument play! Led by professional musicians who specialise in early childhood music education.',
        dateDisplay: 'WED, MAR 19',
        timeDisplay: '2:00 - 3:00 PM',
        dateTime: DateTime(2025, 3, 19, 14, 0),
        location: 'Cambridge Junction, Cambridge',
        attendees: 18,
        isFree: false,
        price: '\u00A315',
        isOnline: false,
        color: HuddlColors.blue,
        icon: Icons.music_note,
        organiser: 'Tiny Tunes Academy',
        imageUrl:
            'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: 'Cambridge',
        suitableAgeRange: const AgeRange(12, 36),
        tags: ['music', 'movement', 'toddler', 'creative'],
        targetStages: ['toddler'],
        category: 'class',
        isWeekend: false,
        capacityLeft: 4,
        partnerRating: 4.5,
        sourceUrl: 'https://tinytunes.academy/music-movement',
      ),
      Event(
        id: 'ev_3',
        title: 'New Parents Workshop',
        description:
            'A comprehensive workshop covering baby basics: feeding, sleeping, and settling techniques from certified professionals. Morning tea provided. Certificate of completion included.',
        dateDisplay: 'SAT, MAR 22',
        timeDisplay: '1:00 - 4:00 PM',
        dateTime: DateTime(2025, 3, 22, 13, 0),
        location: 'Brookfields Health Centre, Cambridge',
        attendees: 20,
        isFree: false,
        price: '\u00A345',
        isOnline: false,
        color: HuddlColors.primaryDark,
        icon: Icons.school,
        organiser: 'Parent Pro UK',
        imageUrl:
            'https://images.pexels.com/photos/3875089/pexels-photo-3875089.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: 'Cambridge',
        suitableAgeRange: const AgeRange(0, 12),
        tags: ['workshop', 'newborn', 'education', 'parenting-skills'],
        targetStages: ['pregnant', 'newborn'],
        category: 'workshop',
        isWeekend: true,
        capacityLeft: 10,
        partnerRating: 4.8,
        sourceUrl: 'https://parentpro.co.uk/new-parents-workshop',
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
        price: '\u00A325',
        isOnline: true,
        color: HuddlColors.blue,
        icon: Icons.nightlight_round,
        organiser: 'Sleep Well Babies',
        imageUrl:
            'https://images.pexels.com/photos/3771519/pexels-photo-3771519.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: '',
        suitableAgeRange: const AgeRange(4, 18),
        tags: ['sleep', 'masterclass', 'online', 'health'],
        targetStages: ['newborn', 'toddler'],
        category: 'health',
        isWeekend: false,
        capacityLeft: -1,
        partnerRating: 4.6,
        sourceUrl: 'https://sleepwellbabies.co.uk/masterclass',
      ),
      Event(
        id: 'ev_5',
        title: 'Family Fun Day \u2014 Free Entry',
        description:
            'A free community event with face painting, balloon artists, petting zoo, food trucks and live music. Bring the whole family for a day of fun! Organised by the Cambridge Community Association.',
        dateDisplay: 'SUN, MAR 30',
        timeDisplay: '10:00 AM - 3:00 PM',
        dateTime: DateTime(2025, 3, 30, 10, 0),
        location: 'Parker\'s Piece, Cambridge',
        attendees: 150,
        isFree: true,
        price: '',
        isOnline: false,
        color: HuddlColors.accentAmber,
        icon: Icons.celebration,
        organiser: 'Cambridge Community Assoc.',
        imageUrl:
            'https://images.pexels.com/photos/1684187/pexels-photo-1684187.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: 'Cambridge',
        suitableAgeRange: const AgeRange(0, -1),
        tags: ['family', 'free', 'outdoors', 'community', 'fun'],
        targetStages: ['pregnant', 'newborn', 'toddler', 'school-age'],
        category: 'community',
        isWeekend: true,
        capacityLeft: -1,
        partnerRating: 4.2,
        sourceUrl: 'https://cambridgecommunity.org.uk/family-fun-day',
      ),
      Event(
        id: 'ev_6',
        title: 'Baby First Aid & CPR',
        description:
            'Essential baby and child first aid course. Learn CPR, choking response, and how to handle common childhood injuries. Accredited certification included.',
        dateDisplay: 'SAT, APR 5',
        timeDisplay: '9:00 AM - 1:00 PM',
        dateTime: DateTime(2025, 4, 5, 9, 0),
        location: 'Addenbrooke\'s Hospital, Cambridge',
        attendees: 30,
        isFree: false,
        price: '\u00A365',
        isOnline: false,
        color: HuddlColors.error,
        icon: Icons.medical_services_outlined,
        organiser: 'British Red Cross',
        imageUrl:
            'https://images.pexels.com/photos/263337/pexels-photo-263337.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: 'Cambridge',
        suitableAgeRange: const AgeRange(0, -1),
        tags: ['first-aid', 'cpr', 'safety', 'health', 'certified'],
        targetStages: ['pregnant', 'newborn', 'toddler'],
        category: 'health',
        isWeekend: true,
        capacityLeft: 8,
        partnerRating: 4.9,
        sourceUrl: 'https://redcross.org.uk/first-aid-baby',
      ),
    ]);
  }
}
