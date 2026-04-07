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
///
/// UK-WIDE FEATURE \u2014 the ONLY feature that crosses borough boundaries.
///
/// Events are intentionally NOT borough-filtered. Parents can browse, RSVP,
/// and attend events in ANY borough across the UK. This supports the
/// real-world need for travelling parents to discover activities outside
/// their home area (e.g. holidays, day trips, visiting family).
///
/// The `borough` field on each Event is used for:
///   \u2022 Default sorting (local events ranked higher)
///   \u2022 AI event recommendation scoring (borough proximity = bonus points)
///   \u2022 Display labels (\"In your borough\" badge)
/// But it is NOT used as an access-control gate.
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
        title: 'Baby Sensory Storytelling',
        description:
            'This event is perfect for babies 5 months to 2 years and their parent. Enjoy colourful visuals, gentle sounds, and soft textures all woven into delightful tales. All materials provided by qualified early childhood educators.',
        dateDisplay: 'SAT, APR 18',
        timeDisplay: '10:00 - 11:30 AM',
        dateTime: DateTime(2026, 4, 18, 10, 0),
        location: 'Cherry Hinton Village Centre, Cambridge',
        attendees: 24,
        isFree: false,
        price: '\u00A318',
        isOnline: false,
        color: HuddlColors.primary,
        icon: Icons.child_care,
        organiser: 'Baby Sensory Cambridge',
        imageUrl:
            'https://images.pexels.com/photos/3661452/pexels-photo-3661452.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: 'Cambridge',
        suitableAgeRange: const AgeRange(5, 24),
        tags: ['sensory', 'baby', 'storytelling', 'educational'],
        targetStages: ['newborn'],
        category: 'play',
        isWeekend: true,
        capacityLeft: 6,
        partnerRating: 4.7,
        sourceUrl: 'https://www.eventbrite.com/e/baby-sensory-storytelling-tickets-1983528725814',
      ),
      Event(
        id: 'ev_2',
        title: 'NCT Antenatal Course \u2014 Cambridge',
        description:
            'A comprehensive NCT antenatal course covering labour, birth, feeding, and early parenthood. Meet other expecting parents in your area. Courses run over two sessions with expert NCT practitioners.',
        dateDisplay: 'SAT, APR 25',
        timeDisplay: '10:00 AM - 3:30 PM',
        dateTime: DateTime(2026, 4, 25, 10, 0),
        location: 'Cottenham Village Hall, Cambridge',
        attendees: 16,
        isFree: false,
        price: '\u00A3239',
        isOnline: false,
        color: HuddlColors.primary,
        icon: Icons.pregnant_woman,
        organiser: 'NCT',
        imageUrl:
            'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: 'Cambridge',
        suitableAgeRange: const AgeRange(0, 0),
        tags: ['antenatal', 'birth-prep', 'NCT', 'parenting'],
        targetStages: ['pregnant'],
        category: 'workshop',
        isWeekend: true,
        capacityLeft: 4,
        partnerRating: 4.8,
        sourceUrl: 'https://www.nct.org.uk/courses-workshops/nct-antenatal-course/C032129?ctype=NCT+Antenatal+course&r=5',
      ),
      Event(
        id: 'ev_3',
        title: 'Sleep Beyond Babyhood Workshop',
        description:
            'An in-person workshop with insights into tricky bedtimes and realistic strategies to support your toddler\'s sleep (18 months\u20144 years) and your well-being. Led by certified sleep consultant Luci.',
        dateDisplay: 'WED, APR 29',
        timeDisplay: '7:00 - 9:00 PM',
        dateTime: DateTime(2026, 4, 29, 19, 0),
        location: 'Cambridge Community Centre',
        attendees: 20,
        isFree: false,
        price: '\u00A335',
        isOnline: false,
        color: HuddlColors.primary,
        icon: Icons.nightlight_round,
        organiser: 'Gentle Sleep Solutions',
        imageUrl:
            'https://images.pexels.com/photos/3771519/pexels-photo-3771519.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: 'Cambridge',
        suitableAgeRange: const AgeRange(18, 48),
        tags: ['sleep', 'toddler', 'workshop', 'wellbeing'],
        targetStages: ['toddler'],
        category: 'workshop',
        isWeekend: false,
        capacityLeft: 8,
        partnerRating: 4.6,
        sourceUrl: 'https://www.eventbrite.com/e/sleep-beyond-babyhood-18-months4-years-tickets-1983764534123',
      ),
      Event(
        id: 'ev_4',
        title: 'BirthSense Antenatal Course \u2014 May',
        description:
            'Two-session antenatal course in Cambridge covering birth preparation, pain management, partner support, and postnatal planning. Small group setting with experienced midwife educators.',
        dateDisplay: 'MON, MAY 4',
        timeDisplay: '7:00 - 9:30 PM',
        dateTime: DateTime(2026, 5, 4, 19, 0),
        location: 'BirthSense Studio, Cambridge',
        attendees: 12,
        isFree: false,
        price: '\u00A3185',
        isOnline: false,
        color: HuddlColors.primary,
        icon: Icons.school,
        organiser: 'BirthSense Courses',
        imageUrl:
            'https://images.pexels.com/photos/3875089/pexels-photo-3875089.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: 'Cambridge',
        suitableAgeRange: const AgeRange(0, 0),
        tags: ['antenatal', 'birth-prep', 'midwife', 'education'],
        targetStages: ['pregnant'],
        category: 'workshop',
        isWeekend: false,
        capacityLeft: 4,
        partnerRating: 4.9,
        sourceUrl: 'https://birthsense.co.uk/all-courses/',
      ),
      Event(
        id: 'ev_5',
        title: 'Baby & Child First Aid Training',
        description:
            'Learn lifesaving first aid skills for babies and children. Covers CPR, choking response, burns, seizures, and common childhood injuries. Accredited certification included. Suitable for all parents and carers.',
        dateDisplay: 'SAT, MAY 16',
        timeDisplay: '9:30 AM - 1:30 PM',
        dateTime: DateTime(2026, 5, 16, 9, 30),
        location: 'Addenbrooke\'s Hospital, Cambridge',
        attendees: 30,
        isFree: false,
        price: '\u00A365',
        isOnline: false,
        color: HuddlColors.primary,
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
        sourceUrl: 'https://www.redcross.org.uk/first-aid/learn-first-aid-for-babies-and-children',
      ),
      Event(
        id: 'ev_6',
        title: 'Gentle Sleep Foundations \u2014 Online',
        description:
            'The science behind baby sleep (0\u201318 months) and realistic strategies to support your baby\'s sleep and your well-being. Live interactive webinar with Q&A session. Recording available for 30 days.',
        dateDisplay: 'THU, MAY 21',
        timeDisplay: '7:30 - 9:00 PM',
        dateTime: DateTime(2026, 5, 21, 19, 30),
        location: 'Online (Zoom)',
        attendees: 85,
        isFree: false,
        price: '\u00A325',
        isOnline: true,
        color: HuddlColors.primary,
        icon: Icons.nightlight_round,
        organiser: 'Gentle Sleep Solutions',
        imageUrl:
            'https://images.pexels.com/photos/3771519/pexels-photo-3771519.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: '',
        suitableAgeRange: const AgeRange(0, 18),
        tags: ['sleep', 'foundations', 'online', 'health'],
        targetStages: ['newborn', 'toddler'],
        category: 'health',
        isWeekend: false,
        capacityLeft: -1,
        partnerRating: 4.6,
        sourceUrl: 'https://www.eventbrite.com/e/gentle-sleep-foundations-0-18-months-tickets-1981699338066',
      ),
      Event(
        id: 'ev_7',
        title: 'Family Fun Day \u2014 Free Entry',
        description:
            'A free community event with face painting, balloon artists, petting zoo, food trucks and live music. Bring the whole family for a day of fun! Organised by the Cambridge Community Association.',
        dateDisplay: 'SUN, JUN 7',
        timeDisplay: '10:00 AM - 3:00 PM',
        dateTime: DateTime(2026, 6, 7, 10, 0),
        location: 'Parker\'s Piece, Cambridge',
        attendees: 150,
        isFree: true,
        price: '',
        isOnline: false,
        color: HuddlColors.primary,
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
        sourceUrl: 'https://www.eventbrite.co.uk/d/united-kingdom--cambridge/baby/',
      ),
      Event(
        id: 'ev_8',
        title: 'Rosie Hospital Antenatal Education',
        description:
            'Free NHS antenatal education sessions at The Rosie Hospital. Covers labour, birth, breastfeeding, and newborn care. Led by experienced midwives from Cambridge University Hospitals.',
        dateDisplay: 'TUE, JUN 16',
        timeDisplay: '6:00 - 8:30 PM',
        dateTime: DateTime(2026, 6, 16, 18, 0),
        location: 'The Rosie Hospital, Cambridge',
        attendees: 40,
        isFree: true,
        price: '',
        isOnline: false,
        color: HuddlColors.primary,
        icon: Icons.local_hospital,
        organiser: 'Cambridge University Hospitals',
        imageUrl:
            'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=600',
        borough: 'Cambridge',
        suitableAgeRange: const AgeRange(0, 0),
        tags: ['antenatal', 'NHS', 'free', 'midwife', 'birth-prep'],
        targetStages: ['pregnant'],
        category: 'health',
        isWeekend: false,
        capacityLeft: 12,
        partnerRating: 4.7,
        sourceUrl: 'https://www.cuh.nhs.uk/rosie-hospital/maternity/antenatal-education/',
      ),
    ]);
  }
}
