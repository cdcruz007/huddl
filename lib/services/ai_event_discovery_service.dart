import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'ai_api_helper.dart';
import '../theme/huddl_colors.dart';
import 'event_service.dart';
import 'gemini_system_prompt_builder.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'browser_storage.dart';

// =============================================================================
// AI EVENT DISCOVERY SERVICE  — HYPERLOCAL EDITION
//
// Uses Gemini AI to generate rich, borough-specific family event descriptions.
// Combines AI-generated content with structured event metadata to create
// realistic community events that populate the Events tab.
//
// The AI generates:
//   - Unique, natural-sounding event descriptions
//   - Borough-specific venue and organiser details
//   - Relevant tips and community-style language
//
// Structural data (dates, times, pricing, categories) use deterministic
// logic to ensure consistency, while descriptions are AI-generated.
// =============================================================================

/// Source where the AI discovered the event.
class EventSource {
  final String name;
  final String url;
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
  final String locationSuffix;
  final String descriptionHint; // Used as a prompt hint for AI generation

  const _EventTemplate({
    required this.titleTemplate,
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
    required this.locationSuffix,
    required this.descriptionHint,
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
  final Random _rng = Random(42);

  // Gemini API configuration (centralised in GeminiConfig)

  bool _isInitialised = false;
  bool _hasRunToday = false;
  DateTime? _lastDiscoveryRun;
  String _userBorough = '';

  bool get hasRunToday => _hasRunToday;
  DateTime? get lastDiscoveryRun => _lastDiscoveryRun;
  String get userBorough => _userBorough;
  int get discoveredEventCount =>
      _eventService.events.where((e) => e.isAiDiscovered).length;

  Future<void> initialize() async {
    if (_isInitialised) return;
    await _onboarding.initialize();
    // 3-tier borough resolution: persisted API result → sync cache → prefix map
    _userBorough = (_onboarding.borough?.isNotEmpty == true)
        ? _onboarding.borough!
        : (_postcodeService.getBoroughFromPostcode(_onboarding.postcode) ?? '');
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
  ///
  /// Guard logic:
  ///   • EventService is in-memory only — _events resets to [] on every cold
  ///     start.  If the list is empty we MUST regenerate regardless of whether
  ///     the "ran today" flag is stored, otherwise the Events tab always shows
  ///     an empty state after a page reload / app restart.
  ///   • If events are already loaded in this session AND we ran today AND
  ///     force==false, skip to avoid redundant API calls.
  Future<int> runDailyDiscovery({bool force = false}) async {
    await initialize();

    final existingDiscovered =
        _eventService.events.where((e) => e.isAiDiscovered).length;

    // Only skip when we already have events in memory AND the daily flag is set.
    // An empty in-memory list means it's a fresh load — always regenerate.
    if (_hasRunToday && !force && existingDiscovered > 0) return 0;

    // Secondary cap: don't add more if we already have ≥10 events loaded.
    if (existingDiscovered >= 10 && !force) {
      _hasRunToday = true;
      return 0;
    }

    // Generate AI-enhanced events
    final newEvents = await _generateDiscoveredEvents();

    final existingTitles = _eventService.events.map((e) => e.title).toSet();
    int added = 0;
    for (final event in newEvents) {
      if (!existingTitles.contains(event.title)) {
        _eventService.createEvent(event);
        added++;
      }
    }

    _lastDiscoveryRun = DateTime.now();
    _hasRunToday = true;
    await BrowserStorage.setString(
        'ai_discovery_last_run', _lastDiscoveryRun!.toIso8601String());

    return added;
  }

  // ── AI-Enhanced Event Generation ──────────────────────────────────────

  /// Generate descriptions for a batch of events using Gemini AI
  Future<Map<String, String>> _generateAiDescriptions(
    List<_EventTemplate> templates,
    String borough,
  ) async {
    final results = <String, String>{};

    // Build a batch prompt for all events at once (efficient single API call)
    final eventList = StringBuffer();
    for (var i = 0; i < templates.length; i++) {
      final t = templates[i];
      eventList.writeln(
          '${i + 1}. "${t.titleTemplate.replaceAll('{borough}', borough)}" - ${t.descriptionHint} (${t.category}, at ${t.locationSuffix})');
    }

    final basePrompt = GeminiSystemPromptBuilder().buildEventsPrompt(
      targetBorough: borough,
      isEventCreation: true,
    );
    final systemPrompt = '$basePrompt\n'
        'Generate engaging, natural descriptions for each event listed below. '
        'Each description should be 3-4 sentences, written in British English, '
        'and feel like it was written by a real local event organiser.\n\n'
        'RESPOND IN EXACT JSON FORMAT (no markdown, no backticks, just raw JSON):\n'
        '{\n  "descriptions": [\n    "Description for event 1...",\n'
        '    "Description for event 2...",\n    ...\n  ]\n}\n\n'
        'ADDITIONAL RULES:\n'
        '- Include practical details parents would want to know\n'
        '- Sound warm and community-focused, not corporate\n'
        '- Each description should be unique and specific to the event type\n'
        '- Mention age suitability naturally in the text\n'
        '- Include a welcoming line like "No booking required" or "Spaces limited" as appropriate';

    try {
      final requestBody = {
        'system_instruction': {
          'parts': [
            {'text': systemPrompt}
          ]
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text':
                    'Generate descriptions for these $borough family events:\n\n${eventList.toString()}'
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.85,
          'topP': 0.95,
          'maxOutputTokens': 2048,
        },
      };

      final data = await AiApiHelper.generateContent(
          requestBody, timeout: const Duration(seconds: 25));
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          var text = (parts[0]['text'] as String? ?? '').trim();
          text = text.replaceAll(RegExp(r'^```json\s*'), '');
          text = text.replaceAll(RegExp(r'\s*```$'), '');
          text = text.trim();

          final json = jsonDecode(text) as Map<String, dynamic>;
          final descriptions = json['descriptions'] as List<dynamic>? ?? [];
          for (var i = 0; i < min(templates.length, descriptions.length); i++) {
            results[templates[i].titleTemplate] =
                descriptions[i].toString();
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI event description generation error: $e');
      }
    }

    return results;
  }

  // Borough used for event discovery — resolved at runtime from _userBorough
  // (set during initialize()). Kept as a list so the loop index modulo
  // works unchanged; all entries are the user's actual borough.
  List<String> get _discoverBoroughs {
    final b = _userBorough.isNotEmpty ? _userBorough : 'Unknown';
    return List.filled(20, b);
  }

  Future<List<Event>> _generateDiscoveredEvents() async {
    final now = DateTime.now();
    final events = <Event>[];
    final templates = _allTemplates('{borough}');

    // Try to get AI-generated descriptions
    final aiDescriptions =
        await _generateAiDescriptions(templates, _userBorough);

    for (int i = 0; i < templates.length; i++) {
      final t = templates[i];
      final borough = _discoverBoroughs[i % _discoverBoroughs.length];

      final daysAhead = 3 + _rng.nextInt(25);
      final eventDate = now.add(Duration(days: daysAhead));
      final isWeekend = eventDate.weekday == DateTime.saturday ||
          eventDate.weekday == DateTime.sunday;

      final hour =
          t.isOnline ? (18 + _rng.nextInt(3)) : (9 + _rng.nextInt(6));
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
      const attendees = 0; // real RSVP count from Firestore — not fabricated

      final location = t.isOnline
          ? 'Online (${t.locationSuffix})'
          : '${t.locationSuffix}, $borough';

      // Use AI description if available, otherwise use the hint as fallback
      final description = aiDescriptions[t.titleTemplate] ??
          t.descriptionHint.replaceAll('{borough}', borough);

      events.add(Event(
        id: 'ai_disc_${i}_${eventDate.millisecondsSinceEpoch}',
        title: t.titleTemplate.replaceAll('{borough}', borough),
        description: description.replaceAll('{borough}', borough),
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
        sourceUrl: t.source.url.isNotEmpty
            ? t.source.url
            : 'https://${t.source.name.toLowerCase().replaceAll(' ', '').replaceAll('.', '')}.co.uk/events',
        isUserCreated: false,
        borough: borough,
        suitableAgeRange: t.ageRange,
        tags: t.tags,
        targetStages: t.targetStages,
        category: t.category,
        isWeekend: isWeekend,
        capacityLeft: -1, // capacity shown only when confirmed by organiser
        partnerRating: 0, // rating shown only when real reviews exist
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

  // ── Template library ──────────────────────────────────────────────────

  List<_EventTemplate> _allTemplates(String borough) {
    return [
      _EventTemplate(
        titleTemplate: 'Rhyme Time at {borough} Library',
        category: 'play',
        tags: ['storytime', 'library', 'free', 'baby', 'toddler', 'reading'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(0, 48),
        isFree: true,
        color: HuddlColors.teal,
        icon: Icons.menu_book,
        organiserTemplate: '{borough} Libraries',
        imageUrl: 'https://images.pexels.com/photos/1741230/pexels-photo-1741230.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Council Website', icon: Icons.account_balance),
        locationSuffix: 'Central Library',
        descriptionHint: 'Free weekly rhyme time session for babies and toddlers at {borough} Central Library. Join friendly librarians for 30 minutes of songs, nursery rhymes and stories. A lovely way to introduce your little one to reading and meet local parents. No booking required, just drop in! Suitable from birth to 4 years.',
      ),
      _EventTemplate(
        titleTemplate: 'Baby Splash \u2014 Water Confidence Classes',
        category: 'sport',
        tags: ['swimming', 'baby', 'water', 'exercise', 'confidence'],
        targetStages: ['newborn'],
        ageRange: const AgeRange(3, 18),
        isFree: false, price: '\u00A312',
        color: HuddlColors.lightBlue,
        icon: Icons.pool,
        organiserTemplate: 'Water Babies {borough}',
        imageUrl: 'https://images.pexels.com/photos/1556691/pexels-photo-1556691.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Eventbrite', icon: Icons.confirmation_number),
        locationSuffix: 'Leisure Centre',
        descriptionHint: 'Gentle water confidence sessions for babies aged 3-18 months with qualified swim instructors. Small class sizes, warm pool at 32\u00B0C. Changing facilities and parking available.',
      ),
      _EventTemplate(
        titleTemplate: 'Messy Play Adventure',
        category: 'play',
        tags: ['messy-play', 'sensory', 'creative', 'toddler', 'art'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(6, 48),
        isFree: false, price: '\u00A38',
        color: HuddlColors.primary,
        icon: Icons.brush,
        organiserTemplate: 'Little Messy Ones',
        imageUrl: 'https://images.pexels.com/photos/3662667/pexels-photo-3662667.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Facebook Events', icon: Icons.facebook),
        locationSuffix: 'Community Hall',
        descriptionHint: 'Let little ones explore textures, colours and sensory play. Paint, playdough, sand, water and more! All non-toxic materials. Parent supervision required. Tea and coffee for grown-ups.',
      ),
      _EventTemplate(
        titleTemplate: 'Mum & Baby Postnatal Yoga',
        category: 'health',
        tags: ['yoga', 'postnatal', 'mum', 'baby', 'fitness', 'wellbeing'],
        targetStages: ['newborn'],
        ageRange: const AgeRange(1, 10),
        isFree: false, price: '\u00A314',
        color: HuddlColors.teal,
        icon: Icons.self_improvement,
        organiserTemplate: 'Bloom Yoga {borough}',
        imageUrl: 'https://images.pexels.com/photos/3822864/pexels-photo-3822864.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'ClassPass', icon: Icons.fitness_center),
        locationSuffix: 'Wellness Studio',
        descriptionHint: 'Nurturing yoga class for new mums and babies (6 weeks to crawling). Rebuild core strength, ease tension, restore pelvic floor function. Suitable for complete beginners. Babies welcome to feed, sleep or play.',
      ),
      _EventTemplate(
        titleTemplate: 'Stay & Play at {borough} Children\'s Centre',
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
        locationSuffix: 'Children\'s Centre',
        descriptionHint: 'Free drop-in stay-and-play with qualified early years staff. Arts, crafts, imaginative play, construction, sensory exploration and outdoor play. Health visitors on selected dates. Refreshments provided.',
      ),
      _EventTemplate(
        titleTemplate: 'Buggy Bootcamp \u2014 Outdoor Fitness',
        category: 'sport',
        tags: ['fitness', 'buggy', 'outdoor', 'exercise', 'bootcamp'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(0, 36),
        isFree: false, price: '\u00A310',
        color: HuddlColors.successGreen,
        icon: Icons.directions_run,
        organiserTemplate: 'Buggy Fit {borough}',
        imageUrl: 'https://images.pexels.com/photos/3764011/pexels-photo-3764011.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Meetup.com', icon: Icons.groups),
        locationSuffix: 'Victoria Park',
        descriptionHint: 'Get fit with your baby! Certified personal trainer leads 45-minute outdoor workout with buggies. Cardio, strength and stretching for all fitness levels. Rain or shine!',
      ),
      _EventTemplate(
        titleTemplate: 'Infant Massage Workshop',
        category: 'health',
        tags: ['massage', 'baby', 'bonding', 'colic', 'wellbeing'],
        targetStages: ['newborn'],
        ageRange: const AgeRange(1, 9),
        isFree: false, price: '\u00A340',
        color: HuddlColors.primaryDark,
        icon: Icons.spa,
        organiserTemplate: 'Nurture & Grow',
        imageUrl: 'https://images.pexels.com/photos/3875089/pexels-photo-3875089.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Eventbrite', icon: Icons.confirmation_number),
        locationSuffix: 'Health Centre',
        descriptionHint: 'Learn gentle massage techniques to soothe your baby. 5-week course covering full body massage, colic relief, and bedtime relaxation strokes. Certified IAIM instructor. Organic massage oil provided. For babies 4 weeks to pre-crawling.',
      ),
      _EventTemplate(
        titleTemplate: 'NCT Nearly New Sale \u2014 {borough}',
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
        locationSuffix: 'Town Hall',
        descriptionHint: 'Huge selection of quality preloved baby and children\u2019s clothes, toys, equipment, buggies and maternity wear. Cash and card accepted. Early bird entry at 9:30am. All proceeds support local NCT activities.',
      ),
      _EventTemplate(
        titleTemplate: 'Dad\'s Saturday Breakfast Club',
        category: 'community',
        tags: ['dads', 'breakfast', 'weekend', 'social', 'free', 'support'],
        targetStages: ['newborn', 'toddler', 'school-age'],
        ageRange: const AgeRange(0, -1),
        isFree: true,
        color: HuddlColors.teal,
        icon: Icons.free_breakfast,
        organiserTemplate: 'DadPad {borough}',
        imageUrl: 'https://images.pexels.com/photos/3817495/pexels-photo-3817495.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Facebook Events', icon: Icons.facebook),
        locationSuffix: 'Community Cafe',
        descriptionHint: 'Relaxed Saturday morning meet-up exclusively for dads and their children. Free bacon rolls, coffee and chat while kids play in a safe environment. No agenda, no pressure \u2014 just dads supporting dads.',
      ),
      _EventTemplate(
        titleTemplate: 'Breastfeeding Support Drop-in',
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
        locationSuffix: 'Health Visitor Clinic',
        descriptionHint: 'Free, friendly breastfeeding support with trained counsellors and peer supporters. Weigh your baby, chat with other mums, and enjoy a hot drink. No appointment needed.',
      ),
      _EventTemplate(
        titleTemplate: 'Under 5s Soft Play Morning',
        category: 'play',
        tags: ['soft-play', 'indoor', 'toddler', 'active', 'rainy-day'],
        targetStages: ['toddler'],
        ageRange: const AgeRange(10, 60),
        isFree: false, price: '\u00A36',
        color: HuddlColors.primary,
        icon: Icons.sports_gymnastics,
        organiserTemplate: 'Jump & Tumble {borough}',
        imageUrl: 'https://images.pexels.com/photos/296301/pexels-photo-296301.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Google Maps', icon: Icons.map),
        locationSuffix: 'Play Zone',
        descriptionHint: 'Exclusive under-5s soft play session every weekday morning. Climb, slide, bounce and explore in a padded environment. Free drink for each child. Cafe serves coffee and snacks for parents. Socks required.',
      ),
      _EventTemplate(
        titleTemplate: 'Free NHS Antenatal Classes \u2014 {borough}',
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
        locationSuffix: 'Hospital Maternity Unit',
        descriptionHint: 'Comprehensive NHS antenatal education covering labour preparation, pain management, breathing techniques, birth partner support, breastfeeding basics and newborn care. Led by experienced midwives. Open to all from 28 weeks. Partners welcome.',
      ),
      _EventTemplate(
        titleTemplate: 'Jo Jingles \u2014 Music & Movement',
        category: 'class',
        tags: ['music', 'singing', 'movement', 'instruments', 'development'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(3, 48),
        isFree: false, price: '\u00A37',
        color: HuddlColors.accentAmber,
        icon: Icons.music_note,
        organiserTemplate: 'Jo Jingles {borough}',
        imageUrl: 'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Jo Jingles', icon: Icons.music_note),
        locationSuffix: 'Church Hall',
        descriptionHint: 'Award-winning music, singing and movement classes for babies and young children. Themed sessions with action songs, instruments, puppets and parachute games. Developed by music education specialists. Fun, energetic and interactive!',
      ),
      _EventTemplate(
        titleTemplate: 'Little Explorers Nature Walk',
        category: 'community',
        tags: ['nature', 'outdoors', 'walk', 'wildlife', 'family', 'free'],
        targetStages: ['newborn', 'toddler', 'school-age'],
        ageRange: const AgeRange(0, -1),
        isFree: true,
        color: HuddlColors.accentAmber,
        icon: Icons.forest,
        organiserTemplate: '{borough} Rangers',
        imageUrl: 'https://images.pexels.com/photos/1001914/pexels-photo-1001914.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Council Website', icon: Icons.account_balance),
        locationSuffix: 'Country Park',
        descriptionHint: 'Family nature walk through local park and woodland. Bug hunting, leaf collecting, bird spotting. Buggy-friendly main paths. Dogs on leads welcome. Free hot chocolate at the end!',
      ),
      _EventTemplate(
        titleTemplate: 'Online: Baby-Led Weaning Masterclass',
        category: 'workshop',
        tags: ['weaning', 'BLW', 'online', 'nutrition', 'baby', 'food'],
        targetStages: ['newborn'],
        ageRange: const AgeRange(4, 12),
        isFree: false, price: '\u00A315',
        isOnline: true,
        color: HuddlColors.teal,
        icon: Icons.restaurant,
        organiserTemplate: 'First Bites Nutrition',
        imageUrl: 'https://images.pexels.com/photos/3662846/pexels-photo-3662846.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Eventbrite', icon: Icons.confirmation_number),
        locationSuffix: 'Zoom',
        descriptionHint: 'Everything about introducing solid foods using baby-led weaning. Safe finger foods, choking vs gagging, allergies, nutrition and meal planning. Presented by a registered paediatric dietitian with Q&A. Recording included.',
      ),
      _EventTemplate(
        titleTemplate: 'Little Angel Puppet Show',
        category: 'class',
        tags: ['theatre', 'puppets', 'performance', 'arts', 'interactive'],
        targetStages: ['newborn', 'toddler'],
        ageRange: const AgeRange(6, 48),
        isFree: false, price: '\u00A39',
        color: HuddlColors.error,
        icon: Icons.theater_comedy,
        organiserTemplate: 'Little Angel Theatre',
        imageUrl: 'https://images.pexels.com/photos/3933250/pexels-photo-3933250.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Timeout', icon: Icons.newspaper),
        locationSuffix: 'Arts Centre',
        descriptionHint: 'Enchanting puppet theatre for little ones. 40-minute show with hand-crafted puppets, gentle music and interactive story. Relaxed seating \u2014 babies can wriggle, feed and make noise! Meet the puppets afterwards.',
      ),

      // ─── UK-WIDE CHARITY EVENTS (cross-borough) ──────────────────────────
      _EventTemplate(
        titleTemplate: 'Adoption UK Family Walk \u2014 {borough}',
        category: 'community',
        tags: ['adoption', 'fostering', 'walk', 'charity', 'uk-wide', 'support'],
        targetStages: ['pregnant', 'newborn', 'toddler', 'school-age'],
        ageRange: const AgeRange(0, -1),
        isFree: true,
        color: HuddlColors.teal,
        icon: Icons.directions_walk,
        organiserTemplate: 'Adoption UK',
        imageUrl: 'https://images.pexels.com/photos/1683975/pexels-photo-1683975.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Adoption UK', icon: Icons.favorite_border),
        locationSuffix: 'Country Park',
        descriptionHint: 'Join Adoption UK\u2019s family walk for adopted and care-experienced families. A friendly, inclusive event with refreshments. Chat with other adoptive parents while children play. All welcome \u2014 no registration needed.',
      ),
      _EventTemplate(
        titleTemplate: 'Gingerbread Single Parent Comedy Night',
        category: 'community',
        tags: ['single parent', 'comedy', 'charity', 'uk-wide', 'social', 'adults'],
        targetStages: ['pregnant', 'newborn', 'toddler', 'school-age'],
        ageRange: const AgeRange(0, -1),
        isFree: false, price: '\u00A312',
        color: HuddlColors.accentAmber,
        icon: Icons.emoji_emotions,
        organiserTemplate: 'Gingerbread',
        imageUrl: 'https://images.pexels.com/photos/7234213/pexels-photo-7234213.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Gingerbread', icon: Icons.volunteer_activism),
        locationSuffix: 'Arts Centre',
        descriptionHint: 'Laugh out loud with fellow single parents at Gingerbread\u2019s fundraiser comedy night. Local and national comedians. Proceeds support Gingerbread\u2019s helpline reaching ~800,000 single parents annually.',
      ),
      _EventTemplate(
        titleTemplate: 'Home for Good \u2014 Fostering Information Evening',
        category: 'community',
        tags: ['fostering', 'adoption', 'info evening', 'charity', 'uk-wide'],
        targetStages: ['pregnant', 'newborn', 'toddler', 'school-age'],
        ageRange: const AgeRange(0, -1),
        isFree: true,
        color: HuddlColors.primaryDark,
        icon: Icons.home,
        organiserTemplate: 'Home for Good',
        imageUrl: 'https://images.pexels.com/photos/3807517/pexels-photo-3807517.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Home for Good', icon: Icons.home_outlined),
        locationSuffix: 'Community Centre',
        descriptionHint: 'Considering fostering or adoption? Home for Good hosts this free information evening to answer your questions. Hear from experienced foster carers. Every 15 minutes a child enters care in the UK \u2014 you could make the difference.',
      ),
      _EventTemplate(
        titleTemplate: 'Care for the Family \u2014 Tweens & Teens Tour',
        category: 'community',
        tags: ['teens', 'family', 'charity', 'uk-wide', 'tour', 'parenting'],
        targetStages: ['school-age'],
        ageRange: const AgeRange(96, -1),
        isFree: false, price: '\u00A310',
        color: HuddlColors.teal,
        icon: Icons.family_restroom,
        organiserTemplate: 'Care for the Family',
        imageUrl: 'https://images.pexels.com/photos/5063096/pexels-photo-5063096.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Care for the Family', icon: Icons.groups),
        locationSuffix: 'Conference Venue',
        descriptionHint: 'Navigating the tween and teen years? Care for the Family\u2019s touring event offers practical wisdom, laughter, and encouragement. Keynote speakers, panel Q&A, and free resource pack. For parents of 8\u201318-year-olds.',
      ),
      _EventTemplate(
        titleTemplate: 'Family Fund \u2014 Face-to-Face Support Day',
        category: 'community',
        tags: ['disability', 'sen', 'support', 'charity', 'uk-wide', 'grants'],
        targetStages: ['pregnant', 'newborn', 'toddler', 'school-age'],
        ageRange: const AgeRange(0, -1),
        isFree: true,
        color: HuddlColors.teal,
        icon: Icons.accessibility_new,
        organiserTemplate: 'Family Fund',
        imageUrl: 'https://images.pexels.com/photos/8613312/pexels-photo-8613312.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Family Fund', icon: Icons.favorite),
        locationSuffix: 'Hotel Conference Room',
        descriptionHint: 'Free face-to-face support day for families raising disabled or seriously ill children. Meet Family Fund advisers, learn about grants, connect with other families. Accessible venue with sensory-friendly quiet room.',
      ),

      // ─── V4: NEW CHARITY & COMMUNITY EVENTS ────────────────────────────
      _EventTemplate(
        titleTemplate: 'Parentkind \u2014 Parent Engagement Workshop',
        category: 'workshop',
        tags: ['school', 'pta', 'parents', 'charity', 'uk-wide', 'education'],
        targetStages: ['toddler', 'school-age'],
        ageRange: const AgeRange(36, -1),
        isFree: true,
        color: HuddlColors.teal,
        icon: Icons.school,
        organiserTemplate: 'Parentkind',
        imageUrl: 'https://images.pexels.com/photos/8500365/pexels-photo-8500365.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Parentkind', icon: Icons.how_to_vote),
        locationSuffix: 'Primary School',
        descriptionHint: 'Free parent engagement workshop by Parentkind, backed by the National Parent Survey 2025 (5,866 parents, 134k+ insights). Learn how to support your child\u2019s learning and engage with school. Be School Ready guide included.',
      ),
      _EventTemplate(
        titleTemplate: 'Sibs \u2014 Young Siblings Activity Day',
        category: 'community',
        tags: ['siblings', 'sen', 'disability', 'charity', 'uk-wide', 'support', 'children'],
        targetStages: ['toddler', 'school-age'],
        ageRange: const AgeRange(84, 204),
        isFree: true,
        color: HuddlColors.accentAmber,
        icon: Icons.child_care,
        organiserTemplate: 'Sibs',
        imageUrl: 'https://images.pexels.com/photos/8612990/pexels-photo-8612990.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Sibs', icon: Icons.people_outline),
        locationSuffix: 'Youth Centre',
        descriptionHint: 'Activity day for young siblings (7\u201317) who have a brother or sister with a disability, SEN, or long-term condition. Arts, crafts, games \u2014 a chance to meet others who understand. Run by Sibs, the UK\u2019s only charity for siblings.',
      ),
      _EventTemplate(
        titleTemplate: 'Coram Family Lives \u2014 Free Parenting Course',
        category: 'workshop',
        tags: ['parenting', 'online', 'free', 'charity', 'uk-wide', 'course'],
        targetStages: ['pregnant', 'newborn', 'toddler', 'school-age'],
        ageRange: const AgeRange(0, -1),
        isFree: true,
        isOnline: true,
        color: HuddlColors.teal,
        icon: Icons.laptop_mac,
        organiserTemplate: 'Coram Family Lives',
        imageUrl: 'https://images.pexels.com/photos/4145354/pexels-photo-4145354.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Coram Family Lives', icon: Icons.support),
        locationSuffix: 'Online',
        descriptionHint: 'Free online parenting course from Coram Family Lives. Work at your own pace with techniques from experienced parenting professionals. Covers behaviour, communication, boundaries \u2014 from early years through teens. Certificate on completion.',
      ),
      _EventTemplate(
        titleTemplate: 'Barnardo\u2019s \u2014 Child Safety Workshop',
        category: 'workshop',
        tags: ['safety', 'children', 'charity', 'uk-wide', 'workshop', 'protection'],
        targetStages: ['newborn', 'toddler', 'school-age'],
        ageRange: const AgeRange(0, -1),
        isFree: true,
        color: HuddlColors.error,
        icon: Icons.shield,
        organiserTemplate: 'Barnardo\u2019s',
        imageUrl: 'https://images.pexels.com/photos/8613165/pexels-photo-8613165.jpeg?auto=compress&cs=tinysrgb&w=600',
        source: const EventSource(name: 'Barnardo\u2019s', icon: Icons.security),
        locationSuffix: 'Community Centre',
        descriptionHint: 'Free child safety workshop by Barnardo\u2019s. Practical advice on preventing home accidents, staying safe outdoors, online safety, addressing bullying and cyber-bullying. Interactive sessions with take-home resource pack.',
      ),
    ];
  }
}
