import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';
import 'event_service.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'browser_storage.dart';

// =============================================================================
// AI EVENT DISCOVERY SERVICE
//
// Simulates a daily AI-powered crawl of local community websites, council
// pages, Eventbrite, Meetup, Facebook Events and local business calendars to
// find family-friendly events in the user's borough and neighbouring areas.
//
// In production this would call a backend Cloud Function that uses:
//   • Google Custom Search API
//   • Eventbrite API
//   • Facebook Graph API (public events)
//   • Web scraping pipeline for council/library pages
//   • GPT-4o to extract structured event data from HTML
//   • Unsplash/Pexels API for high-quality cover images
//
// For now it generates realistic, borough-aware events with proper metadata
// and high-quality Pexels images so the Events tab is never empty.
// =============================================================================

/// Source where the AI discovered the event.
class EventSource {
  final String name;     // e.g. "Eventbrite", "Council Website"
  final String url;      // e.g. "https://eventbrite.co.uk/..."
  final IconData icon;

  const EventSource({
    required this.name,
    this.url = '',
    this.icon = Icons.language,
  });
}

/// A discovered-event template used by the generator.
class _EventTemplate {
  final String titleTemplate;
  final String descriptionTemplate;
  final String locationSuffix; // appended to borough venue
  final String category;
  final List<String> tags;
  final List<String> targetStages;
  final AgeRange? ageRange;
  final bool isFree;
  final String price;
  final bool isOnline;
  final Color color;
  final IconData icon;
  final String organiserTemplate;
  final String imageUrl;
  final EventSource source;
  final int attendeesMin;
  final int attendeesMax;

  const _EventTemplate({
    required this.titleTemplate,
    required this.descriptionTemplate,
    required this.locationSuffix,
    required this.category,
    required this.tags,
    required this.targetStages,
    this.ageRange,
    required this.isFree,
    this.price = '',
    this.isOnline = false,
    required this.color,
    required this.icon,
    required this.organiserTemplate,
    required this.imageUrl,
    required this.source,
    this.attendeesMin = 8,
    this.attendeesMax = 60,
  });
}

class AiEventDiscoveryService {
  static final AiEventDiscoveryService _instance =
      AiEventDiscoveryService._internal();
  factory AiEventDiscoveryService() => _instance;
  AiEventDiscoveryService._internal();

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcodeService = PostcodeService();
  final EventService _eventService = EventService();
  final Random _rng = Random(42); // deterministic seed for consistent demo

  bool _isInitialised = false;
  bool _hasRunToday = false;
  DateTime? _lastDiscoveryRun;
  String _userBorough = '';

  // ── Public getters ──────────────────────────────────────────────────

  bool get hasRunToday => _hasRunToday;
  DateTime? get lastDiscoveryRun => _lastDiscoveryRun;
  String get userBorough => _userBorough;
  int get discoveredEventCount =>
      _eventService.events.where((e) => e.isAiDiscovered).length;

  // ── Initialise & run ────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isInitialised) return;
    await _onboarding.initialize();
    _userBorough =
        _postcodeService.getBoroughFromPostcode(_onboarding.postcode) ??
            'Cambridge';
    // Check if we already ran today
    final lastRun = await BrowserStorage.getString('ai_discovery_last_run');
    if (lastRun != null) {
      _lastDiscoveryRun = DateTime.tryParse(lastRun);
      if (_lastDiscoveryRun != null) {
        final now = DateTime.now();
        _hasRunToday = _lastDiscoveryRun!.year == now.year &&
            _lastDiscoveryRun!.month == now.month &&
            _lastDiscoveryRun!.day == now.day;
      }
    }
    _isInitialised = true;
  }

  /// Run the daily discovery. Returns the number of new events found.
  /// Idempotent — calling multiple times on the same day is a no-op.
  Future<int> runDailyDiscovery({bool force = false}) async {
    await initialize();

    // Already ran today (unless forced)
    if (_hasRunToday && !force) return 0;

    // Check if discovered events already exist
    final existingDiscovered = _eventService.events
        .where((e) => e.isAiDiscovered)
        .length;
    if (existingDiscovered >= 10 && !force) {
      _hasRunToday = true;
      return 0;
    }

    // Generate borough-specific events
    final newEvents = _generateDiscoveredEvents();

    // Add to EventService (skip duplicates by title)
    final existingTitles = _eventService.events.map((e) => e.title).toSet();
    int added = 0;
    for (final event in newEvents) {
      if (!existingTitles.contains(event.title)) {
        _eventService.createEvent(event);
        added++;
      }
    }

    // Persist last run time
    _lastDiscoveryRun = DateTime.now();
    _hasRunToday = true;
    await BrowserStorage.setString(
        'ai_discovery_last_run', _lastDiscoveryRun!.toIso8601String());

    return added;
  }

  // ── Event generation engine ─────────────────────────────────────────

  /// Areas to scatter AI-discovered events across (Cambridge launch area).
  static const _discoverBoroughs = [
    'Cambridge', 'Cambridge', 'Cambridge', 'Cambridge', 'Cambridge',
    'Cambridge', 'Cambridge', 'Cambridge', 'Cambridge', 'Cambridge',
    'Cambridge', 'Cambridge', 'Cambridge', 'Cambridge', 'Cambridge',
    'Cambridge', 'Cambridge', 'Cambridge', 'Cambridge', 'Cambridge',
  ];

  List<Event> _generateDiscoveredEvents() {
    final now = DateTime.now();
    final events = <Event>[];

    // Generate events across many boroughs using all templates
    final templates = _allTemplates('{borough}'); // placeholder — replaced per event

    for (int i = 0; i < templates.length; i++) {
      final t = templates[i];
      // Assign borough round-robin so events span the city
      final borough = _discoverBoroughs[i % _discoverBoroughs.length];

      // Generate a date in the next 4 weeks
      final daysAhead = 3 + _rng.nextInt(25);
      final eventDate = now.add(Duration(days: daysAhead));
      final isWeekend =
          eventDate.weekday == DateTime.saturday ||
          eventDate.weekday == DateTime.sunday;

      // Pick a time
      final hour = t.isOnline
          ? (18 + _rng.nextInt(3))
          : (9 + _rng.nextInt(6));
      final minute = [0, 15, 30][_rng.nextInt(3)];

      final dateTime = DateTime(
          eventDate.year, eventDate.month, eventDate.day, hour, minute);

      final dayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      final monthAbbr = [
        'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
        'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
      ];

      final endHour = hour + 1 + _rng.nextInt(2);
      final startStr = _formatTime(hour, minute);
      final endStr = _formatTime(endHour, minute);
      final attendees =
          t.attendeesMin + _rng.nextInt(t.attendeesMax - t.attendeesMin + 1);

      // Build location with borough context
      final location = t.isOnline
          ? 'Online (${t.locationSuffix})'
          : '${t.locationSuffix}, $borough';

      events.add(Event(
        id: 'ai_disc_${i}_${eventDate.millisecondsSinceEpoch}',
        title: t.titleTemplate.replaceAll('{borough}', borough),
        description: t.descriptionTemplate.replaceAll('{borough}', borough),
        dateDisplay:
            '${dayAbbr[eventDate.weekday - 1]}, ${monthAbbr[eventDate.month - 1]} ${eventDate.day}',
        timeDisplay: '$startStr - $endStr',
        dateTime: dateTime,
        location: location,
        attendees: attendees,
        isFree: t.isFree,
        price: t.price,
        isOnline: t.isOnline,
        color: t.color,
        icon: t.icon,
        organiser: t.organiserTemplate.replaceAll('{borough}', borough),
        imageUrl: t.imageUrl,
        isUserCreated: false,
        borough: borough,
        suitableAgeRange: t.ageRange,
        tags: t.tags,
        targetStages: t.targetStages,
        category: t.category,
        isWeekend: isWeekend,
        capacityLeft: t.isFree ? -1 : (5 + _rng.nextInt(20)),
        partnerRating: 3.5 + (_rng.nextDouble() * 1.5),
        isAiDiscovered: true,
        aiSource: t.source,
      ));
    }

    return events;
  }

  String _formatTime(int hour, int minute) {
    final h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final m = minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }

  // ── Template library — 15+ realistic borough events ─────────────────

  List<_EventTemplate> _allTemplates(String borough) {
    return [
      // 1. Library storytime
      _EventTemplate(
        titleTemplate: 'Rhyme Time at {borough} Library',
        descriptionTemplate:
            'Free weekly rhyme time session for babies and toddlers at {borough} Central Library. Join our friendly librarians for 30 minutes of songs, nursery rhymes and stories. A wonderful way to introduce your little one to the joy of reading and meet other local parents. No booking required — just drop in! Suitable for babies from birth to 4 years old.',
        locationSuffix: 'Central Library',
        category: 'play',
        tags: ['storytime', 'library', 'free', 'baby', 'toddler', 'reading'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(0, 48),
        isFree: true,
        color: HuddlColors.blue,
        icon: Icons.menu_book,
        organiserTemplate: '{borough} Libraries',
        imageUrl: 'https://images.pexels.com/photos/1741230/pexels-photo-1741230.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Council Website', icon: Icons.account_balance),
        attendeesMin: 15,
        attendeesMax: 40,
      ),

      // 2. Baby swimming
      _EventTemplate(
        titleTemplate: 'Baby Splash — Water Confidence Classes',
        descriptionTemplate:
            'Gentle water confidence sessions for babies aged 3-18 months. Our qualified swim instructors guide parents and babies through fun water activities designed to build confidence and develop early swimming skills. Small class sizes ensure personal attention. Warm pool maintained at 32°C. Changing facilities and parking available.',
        locationSuffix: 'Leisure Centre',
        category: 'sport',
        tags: ['swimming', 'baby', 'water', 'exercise', 'confidence'],
        targetStages: ['newborn'],
        ageRange: const AgeRange(3, 18),
        isFree: false,
        price: '\u00A312',
        color: HuddlColors.lightBlue,
        icon: Icons.pool,
        organiserTemplate: 'Water Babies {borough}',
        imageUrl: 'https://images.pexels.com/photos/1556691/pexels-photo-1556691.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Eventbrite', icon: Icons.confirmation_number),
        attendeesMin: 8,
        attendeesMax: 16,
      ),

      // 3. Messy play
      _EventTemplate(
        titleTemplate: 'Messy Play Adventure',
        descriptionTemplate:
            'Let your little ones explore textures, colours and sensory play in our purpose-built messy play area. Paint, playdough, sand, water, pasta and more! Wear old clothes and prepare for fun. All materials are non-toxic and age appropriate. Parent supervision required. Tea and coffee available for grown-ups.',
        locationSuffix: 'Community Hall',
        category: 'play',
        tags: ['messy-play', 'sensory', 'creative', 'toddler', 'art'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(6, 48),
        isFree: false,
        price: '\u00A38',
        color: HuddlColors.primary,
        icon: Icons.brush,
        organiserTemplate: 'Little Messy Ones',
        imageUrl: 'https://images.pexels.com/photos/3662667/pexels-photo-3662667.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Facebook Events', icon: Icons.facebook),
        attendeesMin: 12,
        attendeesMax: 30,
      ),

      // 4. Postnatal yoga
      _EventTemplate(
        titleTemplate: 'Mum & Baby Postnatal Yoga',
        descriptionTemplate:
            'A nurturing yoga class designed specifically for new mums and their babies (6 weeks to crawling). Focus on rebuilding core strength, easing tension in the neck and shoulders, and restoring pelvic floor function. Gentle enough for complete beginners. Babies are welcome to feed, sleep or play during class. Bring your own mat or use ours.',
        locationSuffix: 'Wellness Studio',
        category: 'health',
        tags: ['yoga', 'postnatal', 'mum', 'baby', 'fitness', 'wellbeing'],
        targetStages: ['newborn'],
        ageRange: const AgeRange(1, 10),
        isFree: false,
        price: '\u00A314',
        color: HuddlColors.teal,
        icon: Icons.self_improvement,
        organiserTemplate: 'Bloom Yoga {borough}',
        imageUrl: 'https://images.pexels.com/photos/3822864/pexels-photo-3822864.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'ClassPass', icon: Icons.fitness_center),
        attendeesMin: 8,
        attendeesMax: 15,
      ),

      // 5. Stay-and-play
      _EventTemplate(
        titleTemplate: 'Stay & Play at {borough} Children\'s Centre',
        descriptionTemplate:
            'Free drop-in stay-and-play session run by qualified early years staff. Activities include arts and crafts, imaginative play, construction, sensory exploration and outdoor play (weather permitting). A great opportunity to meet other local families and access support services. Health visitors available on selected dates. Refreshments provided.',
        locationSuffix: 'Children\'s Centre',
        category: 'community',
        tags: ['stay-and-play', 'free', 'drop-in', 'crafts', 'community'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(0, 60),
        isFree: true,
        color: HuddlColors.accentAmber,
        icon: Icons.toys,
        organiserTemplate: '{borough} Children\'s Centre',
        imageUrl: 'https://images.pexels.com/photos/3661452/pexels-photo-3661452.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Council Website', icon: Icons.account_balance),
        attendeesMin: 20,
        attendeesMax: 50,
      ),

      // 6. Buggy fitness
      _EventTemplate(
        titleTemplate: 'Buggy Bootcamp — Outdoor Fitness',
        descriptionTemplate:
            'Get fit while bonding with your baby! Our certified personal trainer leads a 45-minute outdoor workout designed for parents with buggies. Combines cardio, strength and stretching exercises that you do alongside your pram. Suitable for all fitness levels. Meet at the park gates — rain or shine!',
        locationSuffix: 'Victoria Park',
        category: 'sport',
        tags: ['fitness', 'buggy', 'outdoor', 'exercise', 'bootcamp'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(0, 36),
        isFree: false,
        price: '\u00A310',
        color: HuddlColors.successGreen,
        icon: Icons.directions_run,
        organiserTemplate: 'Buggy Fit {borough}',
        imageUrl: 'https://images.pexels.com/photos/3764011/pexels-photo-3764011.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Meetup.com', icon: Icons.groups),
        attendeesMin: 10,
        attendeesMax: 25,
      ),

      // 7. Baby massage
      _EventTemplate(
        titleTemplate: 'Infant Massage Workshop',
        descriptionTemplate:
            'Learn gentle massage techniques to soothe your baby, aid digestion and promote bonding. This 5-week course covers full body massage routine, colic relief techniques, and relaxation strokes for bedtime. Taught by a certified infant massage instructor (IAIM). Organic massage oil provided. Suitable for babies 4 weeks to pre-crawling.',
        locationSuffix: 'Health Centre',
        category: 'health',
        tags: ['massage', 'baby', 'bonding', 'colic', 'wellbeing'],
        targetStages: ['newborn'],
        ageRange: const AgeRange(1, 9),
        isFree: false,
        price: '\u00A340',
        color: HuddlColors.primaryDark,
        icon: Icons.spa,
        organiserTemplate: 'Nurture & Grow',
        imageUrl: 'https://images.pexels.com/photos/3875089/pexels-photo-3875089.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Eventbrite', icon: Icons.confirmation_number),
        attendeesMin: 6,
        attendeesMax: 12,
      ),

      // 8. NCT Nearly New Sale
      _EventTemplate(
        titleTemplate: 'NCT Nearly New Sale — {borough}',
        descriptionTemplate:
            'Huge selection of quality preloved baby and children\'s clothes, toys, equipment, buggies and maternity wear at bargain prices. Organised by your local NCT branch. Cash and card accepted. Doors open at 10 AM — early bird tickets available for 9:30 AM entry. All proceeds support local NCT activities.',
        locationSuffix: 'Town Hall',
        category: 'community',
        tags: ['sale', 'preloved', 'NCT', 'bargains', 'shopping', 'sustainable'],
        targetStages: ['pregnant', 'newborn', 'toddler'],
        ageRange: const AgeRange(0, -1),
        isFree: true,
        color: HuddlColors.accentAmber,
        icon: Icons.shopping_bag,
        organiserTemplate: 'NCT {borough}',
        imageUrl: 'https://images.pexels.com/photos/6140676/pexels-photo-6140676.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'NCT Website', icon: Icons.child_friendly),
        attendeesMin: 50,
        attendeesMax: 200,
      ),

      // 9. Dad's Saturday Club
      _EventTemplate(
        titleTemplate: 'Dad\'s Saturday Breakfast Club',
        descriptionTemplate:
            'A relaxed Saturday morning meet-up exclusively for dads and their children. Enjoy free bacon rolls, coffee and a chat while the kids play in a safe, supervised environment. No agenda, no pressure — just dads supporting dads. A fantastic way to build friendships and share experiences of fatherhood.',
        locationSuffix: 'Community Cafe',
        category: 'community',
        tags: ['dads', 'breakfast', 'weekend', 'social', 'free', 'support'],
        targetStages: ['newborn', 'toddler', 'school-age'],
        ageRange: const AgeRange(0, -1),
        isFree: true,
        color: HuddlColors.blue,
        icon: Icons.free_breakfast,
        organiserTemplate: 'DadPad {borough}',
        imageUrl: 'https://images.pexels.com/photos/3817495/pexels-photo-3817495.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Facebook Events', icon: Icons.facebook),
        attendeesMin: 8,
        attendeesMax: 20,
      ),

      // 10. Breastfeeding support
      _EventTemplate(
        titleTemplate: 'Breastfeeding Support Drop-in',
        descriptionTemplate:
            'Free, friendly drop-in breastfeeding support group staffed by trained breastfeeding counsellors and peer supporters. Whether you\'re having difficulties or just want reassurance that things are going well, we\'re here to help. Weigh your baby, chat with other mums, and enjoy a hot drink. No appointment needed.',
        locationSuffix: 'Health Visitor Clinic',
        category: 'health',
        tags: ['breastfeeding', 'support', 'free', 'newborn', 'lactation'],
        targetStages: ['pregnant', 'newborn'],
        ageRange: const AgeRange(0, 12),
        isFree: true,
        color: HuddlColors.teal,
        icon: Icons.favorite,
        organiserTemplate: '{borough} Health Visiting Team',
        imageUrl: 'https://images.pexels.com/photos/3845456/pexels-photo-3845456.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'NHS Website', icon: Icons.local_hospital),
        attendeesMin: 6,
        attendeesMax: 18,
      ),

      // 11. Toddler soft play
      _EventTemplate(
        titleTemplate: 'Under 5s Soft Play Morning',
        descriptionTemplate:
            'Exclusive under-5s soft play session every weekday morning. Climb, slide, bounce and explore in a safe, padded environment designed for little adventurers. Includes a free squash or water for the child. Adjacent cafe serves excellent coffee and snacks for parents. Socks required for children.',
        locationSuffix: 'Play Zone',
        category: 'play',
        tags: ['soft-play', 'indoor', 'toddler', 'active', 'rainy-day'],
        targetStages: ['toddler'],
        ageRange: const AgeRange(10, 60),
        isFree: false,
        price: '\u00A36',
        color: HuddlColors.primary,
        icon: Icons.sports_gymnastics,
        organiserTemplate: 'Jump & Tumble {borough}',
        imageUrl: 'https://images.pexels.com/photos/296301/pexels-photo-296301.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Google Maps', icon: Icons.map),
        attendeesMin: 20,
        attendeesMax: 40,
      ),

      // 12. Antenatal class
      _EventTemplate(
        titleTemplate: 'Free NHS Antenatal Classes — {borough}',
        descriptionTemplate:
            'Comprehensive NHS antenatal education covering labour preparation, pain management options, breathing techniques, birth partner support, breastfeeding basics and newborn care. Led by experienced midwives. Open to all expectant parents from 28 weeks. Partners very welcome. Runs over two consecutive Saturday mornings.',
        locationSuffix: 'Hospital Maternity Unit',
        category: 'workshop',
        tags: ['antenatal', 'NHS', 'free', 'pregnancy', 'birth-preparation'],
        targetStages: ['pregnant'],
        ageRange: null,
        isFree: true,
        color: HuddlColors.primaryDark,
        icon: Icons.pregnant_woman,
        organiserTemplate: '{borough} Maternity Services',
        imageUrl: 'https://images.pexels.com/photos/3985170/pexels-photo-3985170.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'NHS Website', icon: Icons.local_hospital),
        attendeesMin: 12,
        attendeesMax: 24,
      ),

      // 13. Music class
      _EventTemplate(
        titleTemplate: 'Jo Jingles — Music & Movement',
        descriptionTemplate:
            'Award-winning music, singing and movement classes for babies and young children. Each themed session includes action songs, instrument play, props, puppets and parachute games. Developed by music education specialists to stimulate your child\'s development. Classes are fun, energetic and truly interactive — not just watching!',
        locationSuffix: 'Church Hall',
        category: 'class',
        tags: ['music', 'singing', 'movement', 'instruments', 'development'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(3, 48),
        isFree: false,
        price: '\u00A37',
        color: HuddlColors.accentAmber,
        icon: Icons.music_note,
        organiserTemplate: 'Jo Jingles {borough}',
        imageUrl: 'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Jo Jingles', icon: Icons.music_note),
        attendeesMin: 10,
        attendeesMax: 20,
      ),

      // 14. Outdoor nature walk
      _EventTemplate(
        titleTemplate: 'Little Explorers Nature Walk',
        descriptionTemplate:
            'Join our family nature walk through the local park and woodland. Learn about wildlife, seasonal changes and the natural world through fun activities like bug hunting, leaf collecting and bird spotting. Suitable for buggies on main paths. Dogs on leads welcome. Bring wellies and weather-appropriate clothing. Free hot chocolate at the end!',
        locationSuffix: 'Country Park',
        category: 'community',
        tags: ['nature', 'outdoors', 'walk', 'wildlife', 'family', 'free'],
        targetStages: ['newborn', 'toddler', 'school-age'],
        ageRange: const AgeRange(0, -1),
        isFree: true,
        color: HuddlColors.yellowDark,
        icon: Icons.forest,
        organiserTemplate: '{borough} Rangers',
        imageUrl: 'https://images.pexels.com/photos/1001914/pexels-photo-1001914.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Council Website', icon: Icons.account_balance),
        attendeesMin: 12,
        attendeesMax: 35,
      ),

      // 15. Online weaning webinar
      _EventTemplate(
        titleTemplate: 'Online: Baby-Led Weaning Masterclass',
        descriptionTemplate:
            'Everything you need to know about introducing solid foods using baby-led weaning. Covers when to start, safe finger foods, choking vs gagging, allergies, nutrition and meal planning. Presented by a registered paediatric dietitian with Q&A. Recording sent to all ticket holders so you can watch at your own pace.',
        locationSuffix: 'Zoom',
        category: 'workshop',
        tags: ['weaning', 'BLW', 'online', 'nutrition', 'baby', 'food'],
        targetStages: ['newborn'],
        ageRange: const AgeRange(4, 12),
        isFree: false,
        price: '\u00A315',
        isOnline: true,
        color: HuddlColors.blue,
        icon: Icons.restaurant,
        organiserTemplate: 'First Bites Nutrition',
        imageUrl: 'https://images.pexels.com/photos/3662846/pexels-photo-3662846.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Eventbrite', icon: Icons.confirmation_number),
        attendeesMin: 30,
        attendeesMax: 120,
      ),

      // 16. Puppet theatre
      _EventTemplate(
        titleTemplate: 'Little Angel Puppet Show',
        descriptionTemplate:
            'Enchanting puppet theatre performance especially for little ones. This 40-minute show features hand-crafted puppets, gentle music and an interactive story that will captivate children aged 6 months and up. Relaxed seating — babies can wriggle, feed and make noise! Followed by a chance to meet the puppets.',
        locationSuffix: 'Arts Centre',
        category: 'class',
        tags: ['theatre', 'puppets', 'performance', 'arts', 'interactive'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(6, 48),
        isFree: false,
        price: '\u00A39',
        color: HuddlColors.error,
        icon: Icons.theater_comedy,
        organiserTemplate: 'Little Angel Theatre',
        imageUrl: 'https://images.pexels.com/photos/3933250/pexels-photo-3933250.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Timeout', icon: Icons.newspaper),
        attendeesMin: 20,
        attendeesMax: 50,
      ),
    ];
  }
}
