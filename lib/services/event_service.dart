import 'dart:convert';
import '../theme/huddl_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/group.dart';
import 'ai_event_discovery_service.dart';
import 'browser_storage.dart';
import 'firestore_service.dart';
import 'onboarding_data_service.dart';
import 'saved_message_service.dart';

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
  final String price; // e.g. "£18" or "" if free
  final bool isOnline;
  final Color color;
  final IconData icon;
  final String organiser;
  final String organiserLogo;
  final String organiserUrl;   // External organiser website URL
  final String imageUrl;
  final bool isUserCreated;

  // ── UK-wide scope & sourcing ─────────────────────────────────
  final String scope;              // "uk_wide" | "borough" | "local"
  final bool isNew;                // true if within 20-day newUntil window
  final DateTime? newUntil;        // createdAt + 20 days; isNew hides after this
  final bool isExternallySourced;  // true for scraped/discovered events
  final String sourceName;         // e.g. "NHS Website", "Cambridge City Council"

  // ── Audience & content ───────────────────────────────────────
  final List<String> suitableFor;     // e.g. ["all_families", "mums", "babies"]
  final List<String> summaryBullets;  // bullet points for Summary section
  final List<String> whatToExpect;    // bullet points for What to Expect section
  final int attendeeCount;            // maintained via FieldValue.increment

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
    this.organiserUrl = '',
    this.imageUrl = '',
    this.isUserCreated = false,
    this.scope = 'uk_wide',
    this.isNew = false,
    this.newUntil,
    this.isExternallySourced = false,
    this.sourceName = '',
    this.suitableFor = const [],
    this.summaryBullets = const [],
    this.whatToExpect = const [],
    this.attendeeCount = 0,
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

  /// Returns true when this event should show the "New" amber badge.
  /// Evaluated at render time so it auto-hides once newUntil is exceeded.
  bool get showNewBadge {
    if (!isNew) return false;
    if (newUntil == null) return true;
    return DateTime.now().isBefore(newUntil!);
  }

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
      'attendeeCount': attendeeCount,
      'isFree': isFree,
      'price': price,
      'isOnline': isOnline,
      'color': color,
      'icon': icon,
      'organiser': organiser,
      'organiserLogo': organiserLogo,
      'organiserUrl': organiserUrl,
      'imageUrl': imageUrl,
      'borough': borough,
      'scope': scope,
      'isNew': showNewBadge,
      'isExternallySourced': isExternallySourced || isAiDiscovered,
      'sourceName': sourceName.isNotEmpty ? sourceName : (aiSource?.name ?? ''),
      'suitableFor': suitableFor,
      'summaryBullets': summaryBullets,
      'whatToExpect': whatToExpect,
      'isAiDiscovered': isAiDiscovered,
      'aiSourceName': aiSource?.name ?? '',
      'aiSourceIcon': aiSource?.icon ?? HuddlIcons.language,
      'sourceUrl': sourceUrl,
      // isDiscoverSomethingNew is set by Cloud Function after ingestion;
      // default false here — Firestore document overrides on read.
      'isDiscoverSomethingNew': false,
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
    // Demo sample events removed — app is production-only.
  }

  /// Global notifier that fires whenever an event group chat is created.
  /// The Messages tab listens to this so it can refresh immediately.
  static final ValueNotifier<int> groupChatCreated = ValueNotifier<int>(0);

  final List<Event> _events = [];
  final Set<String> _goingEventIds = {};
  // Bookmarks are now persisted via SavedMessageService — this set is kept
  // as a fast in-memory cache that mirrors the persisted state.
  final Set<String> _bookmarkedEventIds = {};

  final SavedMessageService _savedSvc = SavedMessageService();

  List<Event> get events => List.unmodifiable(_events);

  /// Events the user has marked as going.
  List<Event> get goingEvents =>
      _events.where((e) => _goingEventIds.contains(e.id)).toList();

  /// Whether the user is going to this event.
  bool isGoing(String eventId) => _goingEventIds.contains(eventId);

  /// Toggle going status for an event.
  /// Returns true if the user is now going (just registered).
  /// Also writes the RSVP to Firestore so it survives reinstall / shows on
  /// other devices (same pattern as MeetupService.toggleGoing).
  bool toggleGoing(String eventId) {
    final wasGoing = _goingEventIds.contains(eventId);
    if (wasGoing) {
      _goingEventIds.remove(eventId);
    } else {
      _goingEventIds.add(eventId);
    }
    notifyListeners();
    // Persist to Firestore so RSVP survives reinstall and shows cross-device.
    // Re-uses the same user_rsvps collection/format as MeetupService so a
    // single loadMyRsvpIds() call covers both.  Fire-and-forget — any error
    // is logged but never shown to the user.
    FirestoreService().saveRsvp(eventId, going: !wasGoing).catchError((e) {
      if (kDebugMode) debugPrint('[EventService] toggleGoing Firestore error: $e');
    });
    return !wasGoing;
  }

  /// Fetch this user's event RSVP state from Firestore and restore
  /// _goingEventIds.  Call once after the events list is loaded.
  Future<void> syncRsvpsFromFirestore() async {
    try {
      final goingIds = await FirestoreService().loadMyRsvpIds();
      if (goingIds.isEmpty) return;
      bool changed = false;
      for (final id in goingIds) {
        // loadMyRsvpIds returns ALL rsvp docs — meetup IDs and event IDs.
        // Only apply IDs that match an actual event in our list.
        final exists = _events.any((e) => e.id == id);
        if (exists && !_goingEventIds.contains(id)) {
          _goingEventIds.add(id);
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[EventService] syncRsvpsFromFirestore error: $e');
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

    // Signal the Messages tab to refresh immediately.
    groupChatCreated.value++;
  }

  /// Whether the user has bookmarked this event.
  /// Checks both the in-memory cache and the persisted SavedMessageService.
  bool isBookmarked(String eventId) =>
      _bookmarkedEventIds.contains(eventId) ||
      _savedSvc.isEventSaved(eventId);

  /// Toggle bookmark status for an event.
  /// Persists to SavedMessageService so the event appears in the Saved tab.
  Future<void> toggleBookmark(String eventId) async {
    // Ensure SavedMessageService is initialised before any read/write
    await _savedSvc.initialize();

    final alreadySaved = isBookmarked(eventId);
    if (alreadySaved) {
      _bookmarkedEventIds.remove(eventId);
      await _savedSvc.unsaveEvent(eventId);
    } else {
      _bookmarkedEventIds.add(eventId);
      // Find the event to snapshot its display data
      final ev = getEventById(eventId);
      if (ev != null) {
        await _savedSvc.saveEvent(
          eventId: eventId,
          title: ev.title,
          date: ev.dateDisplay,
          time: ev.timeDisplay,
          location: ev.location,
          organiser: ev.organiser,
          imageUrl: ev.imageUrl,
          isFree: ev.isFree,
          price: ev.price,
          category: ev.category,
          isOnline: ev.isOnline,
        );
      }
    }
    notifyListeners();
  }

  /// Remove an event from the in-memory bookmark cache (called when the user
  /// removes a bookmark from the Saved tab, which already updated
  /// SavedMessageService).
  void clearBookmarkCache(String eventId) {
    if (_bookmarkedEventIds.remove(eventId)) {
      notifyListeners();
    }
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

}
