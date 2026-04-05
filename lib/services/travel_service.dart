import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import 'onboarding_data_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL TRIPS — TRAVEL SERVICE
// Community-powered AI travel intelligence for parents
// ═══════════════════════════════════════════════════════════════════════════════

class TravelDestination {
  final String id;
  final String name;
  final String country;
  final String region;
  final String imageUrl;
  final String description;
  final double rating;
  final int reviewCount;
  final int huddlParentsVisited;
  final int recommendPercent;
  final List<String> bestForAges;
  final List<String> highlights;
  final String flightTime;
  final String bestMonths;
  final String avgTemp;
  final bool visaRequired;
  final List<String> safetyAlerts;
  final List<String> tags;

  TravelDestination({
    required this.id,
    required this.name,
    required this.country,
    required this.region,
    required this.imageUrl,
    required this.description,
    required this.rating,
    required this.reviewCount,
    required this.huddlParentsVisited,
    required this.recommendPercent,
    required this.bestForAges,
    required this.highlights,
    required this.flightTime,
    required this.bestMonths,
    required this.avgTemp,
    required this.visaRequired,
    required this.safetyAlerts,
    required this.tags,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'country': country, 'region': region,
    'imageUrl': imageUrl, 'description': description, 'rating': rating,
    'reviewCount': reviewCount, 'huddlParentsVisited': huddlParentsVisited,
    'recommendPercent': recommendPercent, 'bestForAges': bestForAges,
    'highlights': highlights, 'flightTime': flightTime, 'bestMonths': bestMonths,
    'avgTemp': avgTemp, 'visaRequired': visaRequired,
    'safetyAlerts': safetyAlerts, 'tags': tags,
  };

  factory TravelDestination.fromJson(Map<String, dynamic> j) =>
      TravelDestination(
        id: j['id'] ?? '', name: j['name'] ?? '', country: j['country'] ?? '',
        region: j['region'] ?? '', imageUrl: j['imageUrl'] ?? '',
        description: j['description'] ?? '', rating: (j['rating'] ?? 0).toDouble(),
        reviewCount: j['reviewCount'] ?? 0,
        huddlParentsVisited: j['huddlParentsVisited'] ?? 0,
        recommendPercent: j['recommendPercent'] ?? 0,
        bestForAges: List<String>.from(j['bestForAges'] ?? []),
        highlights: List<String>.from(j['highlights'] ?? []),
        flightTime: j['flightTime'] ?? '', bestMonths: j['bestMonths'] ?? '',
        avgTemp: j['avgTemp'] ?? '', visaRequired: j['visaRequired'] ?? false,
        safetyAlerts: List<String>.from(j['safetyAlerts'] ?? []),
        tags: List<String>.from(j['tags'] ?? []),
      );
}

class ParentReview {
  final String id;
  final String parentName;
  final String avatarColor;
  final String destinationId;
  final String childAgesAtVisit;
  final String visitDate;
  final double rating;
  final String title;
  final String review;
  final List<String> topTips;
  final bool wouldRecommend;
  final String travelWith; // 'toddler', 'baby', 'school-age'

  ParentReview({
    required this.id, required this.parentName, required this.avatarColor,
    required this.destinationId, required this.childAgesAtVisit,
    required this.visitDate, required this.rating, required this.title,
    required this.review, required this.topTips, required this.wouldRecommend,
    required this.travelWith,
  });
}

class PackingItem {
  final String category;
  final String item;
  final int quantity;
  final bool essential;
  final String note;
  bool isPacked;

  PackingItem({
    required this.category, required this.item, required this.quantity,
    required this.essential, this.note = '', this.isPacked = false,
  });
}

class ItineraryDay {
  final int dayNumber;
  final String title;
  final List<ItineraryActivity> activities;

  ItineraryDay({required this.dayNumber, required this.title, required this.activities});
}

class ItineraryActivity {
  final String time;
  final String title;
  final String description;
  final String icon;
  final bool isNapTime;
  final String? ageNote;

  ItineraryActivity({
    required this.time, required this.title, required this.description,
    required this.icon, this.isNapTime = false, this.ageNote,
  });
}

class TravelConversation {
  final String role; // 'user' or 'assistant'
  final String message;
  final DateTime timestamp;
  final List<String>? destinationSuggestions;
  final String? actionType; // 'destination', 'packing', 'safety', null

  TravelConversation({
    required this.role, required this.message, DateTime? timestamp,
    this.destinationSuggestions, this.actionType,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ParentsAbroad {
  final String destinationId;
  final String destinationName;
  final int familiesHere;
  final List<AbroadFamily> families;
  final List<AbroadActivity> activities;

  ParentsAbroad({
    required this.destinationId, required this.destinationName,
    required this.familiesHere, required this.families, required this.activities,
  });
}

class AbroadFamily {
  final String parentName;
  final String avatarColor;
  final String childAges;
  final String stayDates;
  final String accommodation;

  AbroadFamily({
    required this.parentName, required this.avatarColor,
    required this.childAges, required this.stayDates, required this.accommodation,
  });
}

class AbroadActivity {
  final String title;
  final String organiser;
  final String dateTime;
  final String location;
  final int spotsLeft;

  AbroadActivity({
    required this.title, required this.organiser, required this.dateTime,
    required this.location, required this.spotsLeft,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRAVEL SERVICE — singleton
// ═══════════════════════════════════════════════════════════════════════════════

class TravelService extends ChangeNotifier {
  static final TravelService _instance = TravelService._internal();
  factory TravelService() => _instance;
  TravelService._internal();

  final List<TravelDestination> _destinations = [];
  final List<ParentReview> _reviews = [];
  final List<TravelConversation> _conversations = [];
  final Map<String, List<PackingItem>> _packingLists = {};
  bool _isInitialized = false;

  List<TravelDestination> get destinations => List.unmodifiable(_destinations);
  List<ParentReview> get reviews => List.unmodifiable(_reviews);
  List<TravelConversation> get conversations => List.unmodifiable(_conversations);

  List<TravelDestination> get popularDestinations =>
      _destinations.where((d) => d.huddlParentsVisited >= 3).toList()
        ..sort((a, b) => b.huddlParentsVisited.compareTo(a.huddlParentsVisited));

  List<TravelDestination> get trendingDestinations =>
      _destinations.where((d) => d.reviewCount > 5).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));

  List<ParentReview> getReviewsFor(String destinationId) =>
      _reviews.where((r) => r.destinationId == destinationId).toList();

  Future<void> initialize() async {
    if (_isInitialized) return;
    _loadSampleData();
    _isInitialized = true;
    notifyListeners();
  }

  // ── AI Concierge — real Gemini-powered travel assistant ─────────────

  // Gemini API configuration (centralised in GeminiConfig)

  final List<Map<String, dynamic>> _chatHistory = [];

  Future<TravelConversation> askConcierge(String question) async {
    // Add user message
    _conversations.add(TravelConversation(role: 'user', message: question));
    _chatHistory.add({
      'role': 'user',
      'parts': [{'text': question}],
    });
    notifyListeners();

    try {
      final response = await _callGeminiTravel(question);
      final actionType = _detectActionType(question);
      final suggestions = _detectDestinationSuggestions(question, response);

      final aiResponse = TravelConversation(
        role: 'assistant',
        message: response,
        destinationSuggestions: suggestions,
        actionType: actionType,
      );
      _conversations.add(aiResponse);
      _chatHistory.add({
        'role': 'model',
        'parts': [{'text': response}],
      });
      notifyListeners();
      return aiResponse;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Travel concierge Gemini error: $e');
      }
      // Fallback response
      final fallback = TravelConversation(
        role: 'assistant',
        message: 'I\'m having a moment \u2014 let me try again! In the meantime, '
            'I can help with:\n\n'
            '\u2022 **Destination advice** \u2014 ask about any place\n'
            '\u2022 **Packing lists** \u2014 tap "Pack My Bag" on any destination\n'
            '\u2022 **Safety info** \u2014 vaccines, insurance, visa requirements\n'
            '\u2022 **Best places for your kids\' ages**\n\n'
            'Please try asking again!',
      );
      _conversations.add(fallback);
      _chatHistory.add({
        'role': 'model',
        'parts': [{'text': fallback.message}],
      });
      notifyListeners();
      return fallback;
    }
  }

  Future<String> _callGeminiTravel(String query) async {
    final onboarding = OnboardingDataService();
    await onboarding.initialize();
    final userName = onboarding.name ?? 'there';
    final children = onboarding.children;

    final childContext = StringBuffer();
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final name = child['name'] ?? 'Child ${i + 1}';
      final birthday = child['birthday'];
      if (birthday != null) {
        childContext.writeln('- Child: $name, born $birthday');
      }
    }

    // Build destination context from loaded data
    final destNames = _destinations.map((d) => d.name).take(10).join(', ');

    final systemPrompt = '''You are the huddl AI Travel Concierge \u2014 a friendly, expert family travel assistant built into the huddl app for UK parents.

YOUR PERSONALITY:
- Warm, enthusiastic, and practical \u2014 like a well-travelled friend who also has kids
- British English (use "nappy" not "diaper", "pushchair" not "stroller")
- Give specific, actionable advice with real tips
- Use bullet points and **bold text** to structure key information
- Keep responses 3-5 paragraphs \u2014 detailed but not overwhelming

USER CONTEXT:
- Name: $userName
${childContext.isNotEmpty ? childContext.toString() : '- No children info available'}

HUDDL TRIPS FEATURES (mention naturally):
- "Pack My Bag" AI packing list generator on each destination page
- Community reviews from real huddl parents
- Parents Abroad \u2014 connect with huddl families at your destination
- Preloved marketplace for lending/borrowing travel gear

AVAILABLE DESTINATIONS IN APP: $destNames

GUIDELINES:
- Give real, practical travel advice for families with young children
- Mention specific places, restaurants, and activities when relevant
- Include flight times from UK airports when discussing destinations
- Always mention safety considerations for families
- Reference NHS Fit for Travel for health/vaccine advice
- If unsure about specific facts, say so honestly
- Suggest relevant huddl features naturally''';

    final requestBody = {
      'system_instruction': {
        'parts': [{'text': systemPrompt}]
      },
      'contents': _chatHistory,
      'generationConfig': {
        'temperature': 0.8,
        'topP': 0.95,
        'topK': 40,
        'maxOutputTokens': 1024,
      },
      'safetySettings': [
        {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'BLOCK_ONLY_HIGH'},
        {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_ONLY_HIGH'},
      ],
    };

    final url = Uri.parse(
        GeminiConfig.generateContentUrl);

    final httpResponse = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 20));

    if (httpResponse.statusCode == 200) {
      final data = jsonDecode(httpResponse.body);
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return (parts[0]['text'] as String? ?? '').trim();
        }
      }
      throw Exception('No content in Gemini response');
    } else {
      throw Exception('Gemini API error: ${httpResponse.statusCode}');
    }
  }

  String? _detectActionType(String query) {
    final q = query.toLowerCase();
    if (q.contains('pack') || q.contains('bag') || q.contains('luggage')) return 'packing';
    if (q.contains('safe') || q.contains('vaccine') || q.contains('insurance')) return 'safety';
    // Check if query mentions a specific destination
    for (final dest in _destinations) {
      if (q.contains(dest.name.toLowerCase()) || q.contains(dest.country.toLowerCase())) {
        return 'destination';
      }
    }
    return null;
  }

  List<String>? _detectDestinationSuggestions(String query, String response) {
    final suggestions = <String>[];
    final combined = '$query $response'.toLowerCase();
    for (final dest in _destinations) {
      if (combined.contains(dest.name.toLowerCase())) {
        suggestions.add(dest.id);
      }
    }
    return suggestions.isNotEmpty ? suggestions.take(5).toList() : null;
  }

  void clearConversations() {
    _conversations.clear();
    notifyListeners();
  }

  // ── AI-Enhanced Packing list generation ─────────────────────────────────

  /// Generate a packing list using Gemini AI with local fallback
  Future<List<PackingItem>> generatePackingList(String destinationId, int durationDays, List<int> childAgesMonths) async {
    final key = '$destinationId-$durationDays';
    if (_packingLists.containsKey(key)) return _packingLists[key]!;

    final dest = _destinations.firstWhere((d) => d.id == destinationId,
        orElse: () => _destinations.first);

    // Try AI-generated packing list
    try {
      final aiItems = await _callGeminiForPackingList(dest, durationDays, childAgesMonths);
      if (aiItems.isNotEmpty) {
        _packingLists[key] = aiItems;
        notifyListeners();
        return aiItems;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI packing list error: $e');
      }
    }

    // Fallback to local generation
    final items = _generateLocalPackingList(dest, durationDays, childAgesMonths);
    _packingLists[key] = items;
    return items;
  }

  /// Call Gemini to generate a personalised packing list
  Future<List<PackingItem>> _callGeminiForPackingList(
    TravelDestination dest,
    int durationDays,
    List<int> childAgesMonths,
  ) async {
    final childDesc = childAgesMonths
        .map((a) => a < 12 ? '$a-month-old' : '${(a / 12).floor()}-year-old')
        .join(', ');

    final systemPrompt = '''You are a family travel packing expert for a UK parents' app called huddl. Generate a personalised packing list.

RESPOND IN EXACT JSON FORMAT (no markdown, no backticks, just raw JSON):
{
  "items": [
    {
      "category": "Category Name",
      "item": "Item name",
      "quantity": 1,
      "essential": true,
      "note": "Helpful tip or null"
    }
  ]
}

RULES:
- Generate 25-35 items across categories: Essentials, Medicine, Sun & Beach, Clothing, Travel Gear, Food & Feeding, Entertainment, Documents
- Tailor to: destination climate, child ages, trip duration
- Use British English (nappies, pushchair, Calpol, etc.)
- Include specific tips from parent experience (e.g., "Lidl stocks Ella's Kitchen in Tenerife")
- Calculate quantities based on trip duration and number of children
- Flag essentials vs nice-to-haves
- Include destination-specific items (e.g., beach gear for beach holidays)
- Add community tips in notes (e.g., "3 parents on Marketplace lending travel cots")''';

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
                  'Generate a packing list for:\n- Destination: ${dest.name}, ${dest.country} (${dest.region})\n- Duration: $durationDays days\n- Children: $childDesc\n- Climate: ${dest.avgTemp}, ${dest.tags.join(", ")}\n- Flight time: ${dest.flightTime}\n- Highlights: ${dest.highlights.join(", ")}'
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'topP': 0.9,
        'maxOutputTokens': 2048,
      },
    };

    final url = Uri.parse(
        GeminiConfig.generateContentUrl);

    final httpResponse = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 20));

    if (httpResponse.statusCode == 200) {
      final data = jsonDecode(httpResponse.body);
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
          final itemsJson = json['items'] as List<dynamic>? ?? [];
          return itemsJson
              .map((item) => PackingItem(
                    category: (item['category'] ?? 'Other') as String,
                    item: (item['item'] ?? 'Item') as String,
                    quantity: (item['quantity'] as num?)?.toInt() ?? 1,
                    essential: (item['essential'] ?? false) as bool,
                    note: (item['note'] ?? '') as String,
                  ))
              .toList();
        }
      }
    }

    throw Exception('No AI packing list response');
  }

  /// Local fallback packing list generator
  List<PackingItem> _generateLocalPackingList(
    TravelDestination dest,
    int durationDays,
    List<int> childAgesMonths,
  ) {
    final hasInfant = childAgesMonths.any((a) => a < 12);
    final hasToddler = childAgesMonths.any((a) => a >= 12 && a < 36);
    final isWarm = dest.tags.contains('beach') || dest.tags.contains('summer');

    final items = <PackingItem>[];

    if (hasInfant || hasToddler) {
      final nappiesPerDay = hasInfant ? 8 : 5;
      items.add(PackingItem(category: 'Essentials', item: 'Nappies', quantity: nappiesPerDay * durationDays + 10, essential: true, note: 'Pack extras \u2014 may not find your brand locally'));
      items.add(PackingItem(category: 'Essentials', item: 'Nappy bags', quantity: nappiesPerDay * durationDays, essential: true));
      items.add(PackingItem(category: 'Essentials', item: 'Baby wipes (packs)', quantity: (durationDays / 2).ceil(), essential: true));
      items.add(PackingItem(category: 'Essentials', item: 'Nappy cream', quantity: 1, essential: true));
    }

    items.add(PackingItem(category: 'Medicine', item: 'Calpol sachets (hand luggage)', quantity: 4, essential: true, note: 'Liquid <100ml for cabin'));
    items.add(PackingItem(category: 'Medicine', item: 'Ibuprofen (children\'s)', quantity: 1, essential: true));
    items.add(PackingItem(category: 'Medicine', item: 'Plasters & antiseptic', quantity: 1, essential: true));
    items.add(PackingItem(category: 'Medicine', item: 'Thermometer', quantity: 1, essential: true));
    items.add(PackingItem(category: 'Medicine', item: 'Antihistamine (if allergies)', quantity: 1, essential: false));

    if (isWarm) {
      items.add(PackingItem(category: 'Sun & Beach', item: 'Sun cream SPF50+', quantity: 2, essential: true, note: 'UV index likely 8-10'));
      items.add(PackingItem(category: 'Sun & Beach', item: 'Sun hat (wide brim)', quantity: childAgesMonths.length, essential: true));
      items.add(PackingItem(category: 'Sun & Beach', item: 'UV swim suit', quantity: childAgesMonths.length, essential: true));
      items.add(PackingItem(category: 'Sun & Beach', item: 'Swim nappies', quantity: durationDays + 3, essential: hasInfant || hasToddler));
      items.add(PackingItem(category: 'Sun & Beach', item: 'Beach tent / pop-up shade', quantity: 1, essential: true, note: 'Essential for nap-time shade'));
      items.add(PackingItem(category: 'Sun & Beach', item: 'Beach toys (bucket/spade)', quantity: 1, essential: false, note: 'Can buy locally'));
    }

    items.add(PackingItem(category: 'Clothing', item: 'Outfit changes per child', quantity: durationDays + 3, essential: true, note: 'Pack 3 extra \u2014 toddler mess!'));
    items.add(PackingItem(category: 'Clothing', item: 'Pyjamas', quantity: 3, essential: true));
    items.add(PackingItem(category: 'Clothing', item: 'Socks & shoes', quantity: 3, essential: true));
    items.add(PackingItem(category: 'Clothing', item: 'Light jacket / cardigan', quantity: 2, essential: true));

    items.add(PackingItem(category: 'Travel Gear', item: 'Travel stroller / buggy', quantity: 1, essential: true, note: '3 parents in your area lending on Marketplace'));
    items.add(PackingItem(category: 'Travel Gear', item: 'Car seat (if driving)', quantity: 1, essential: false, note: 'Can hire at airport'));
    items.add(PackingItem(category: 'Travel Gear', item: 'Travel cot / sleeping solution', quantity: 1, essential: hasInfant, note: 'Check with hotel first'));

    if (hasInfant) {
      items.add(PackingItem(category: 'Food & Feeding', item: 'Formula (full trip + 2 extra)', quantity: durationDays + 2, essential: true, note: 'Your brand may not be available'));
      items.add(PackingItem(category: 'Food & Feeding', item: 'Bottles / sippy cups', quantity: 3, essential: true));
      items.add(PackingItem(category: 'Food & Feeding', item: 'Sterilising tablets', quantity: 1, essential: true));
    }
    items.add(PackingItem(category: 'Food & Feeding', item: 'Snack pouches / fruit bars', quantity: durationDays * 3, essential: true, note: 'Lifesaver on the plane'));
    items.add(PackingItem(category: 'Food & Feeding', item: 'Portable high chair / booster', quantity: 1, essential: false));

    items.add(PackingItem(category: 'Entertainment', item: 'Sticker books / colouring', quantity: 3, essential: true, note: 'Flight entertainment'));
    items.add(PackingItem(category: 'Entertainment', item: 'Small toys (new = bonus)', quantity: 3, essential: false));
    items.add(PackingItem(category: 'Entertainment', item: 'Tablet with downloaded shows', quantity: 1, essential: false));
    items.add(PackingItem(category: 'Entertainment', item: 'Headphones (child-size)', quantity: 1, essential: false));

    items.add(PackingItem(category: 'Documents', item: 'Passports (all family)', quantity: childAgesMonths.length + 2, essential: true));
    items.add(PackingItem(category: 'Documents', item: 'EHIC/GHIC cards', quantity: childAgesMonths.length + 2, essential: true));
    items.add(PackingItem(category: 'Documents', item: 'Travel insurance docs', quantity: 1, essential: true));
    items.add(PackingItem(category: 'Documents', item: 'Booking confirmations', quantity: 1, essential: true));

    return items;
  }

  // ── Itinerary generation ───────────────────────────────────────────────

  List<ItineraryDay> generateItinerary(String destinationId, int durationDays) {
    final dest = _destinations.firstWhere((d) => d.id == destinationId,
        orElse: () => _destinations.first);
    final days = <ItineraryDay>[];

    final morningActivities = [
      ItineraryActivity(time: '08:00', title: 'Breakfast at hotel', description: 'Most family hotels serve breakfast 7-10am. Go early to avoid queues.', icon: 'restaurant'),
      ItineraryActivity(time: '09:30', title: 'Beach / Pool time', description: 'Best to go early before the midday sun. Set up shade and apply SPF50+.', icon: 'beach'),
      ItineraryActivity(time: '09:30', title: 'Local market visit', description: 'Fresh fruit, local treats, and a chance for little ones to explore.', icon: 'shopping'),
      ItineraryActivity(time: '10:00', title: 'Toddler-friendly attraction', description: 'Aquarium, zoo, or soft play — huddl parents rate these 4.5+', icon: 'attraction'),
    ];

    final napActivity = ItineraryActivity(
      time: '13:00', title: 'Nap time', description: 'Back to accommodation for nap. Perfect time for parents to relax too!',
      icon: 'sleep', isNapTime: true, ageNote: 'Scheduled around your child\'s usual nap window',
    );

    final afternoonActivities = [
      ItineraryActivity(time: '15:30', title: 'Shaded walk / explore', description: 'Temperature drops. Explore the local area on foot with the buggy.', icon: 'walk'),
      ItineraryActivity(time: '15:30', title: 'Splash pool / water play', description: 'Many resorts have separate toddler pools. Reapply sun cream!', icon: 'pool'),
      ItineraryActivity(time: '16:00', title: 'Playground visit', description: 'Huddl parents recommend the one near the main promenade — shaded with soft ground.', icon: 'playground'),
    ];

    final eveningActivities = [
      ItineraryActivity(time: '17:30', title: 'Family dinner', description: 'Early dinner at a family-friendly restaurant. Ask for a highchair when booking.', icon: 'dinner'),
      ItineraryActivity(time: '19:00', title: 'Evening stroll', description: 'Walk along the promenade. Cooler temperatures, beautiful sunset.', icon: 'sunset'),
      ItineraryActivity(time: '19:30', title: 'Bath & bedtime routine', description: 'Keep to your home routine as much as possible for smooth sleep.', icon: 'bedtime'),
    ];

    final rng = Random(dest.id.hashCode);

    for (int i = 1; i <= min(durationDays, 7); i++) {
      final activities = <ItineraryActivity>[];
      activities.add(morningActivities[rng.nextInt(morningActivities.length)]);
      activities.add(ItineraryActivity(
        time: '12:00', title: 'Light lunch', description: 'Snacks and light lunch. Many cafes are toddler-friendly with colouring sheets.',
        icon: 'lunch',
      ));
      activities.add(napActivity);
      activities.add(afternoonActivities[rng.nextInt(afternoonActivities.length)]);
      activities.add(eveningActivities[i % eveningActivities.length]);

      days.add(ItineraryDay(
        dayNumber: i,
        title: i == 1 ? 'Arrival Day' : i == durationDays ? 'Departure Day' : 'Day $i — ${dest.highlights[i % dest.highlights.length]}',
        activities: activities,
      ));
    }

    return days;
  }

  // ── Parents Abroad ─────────────────────────────────────────────────────

  ParentsAbroad getParentsAbroad(String destinationId) {
    final dest = _destinations.firstWhere((d) => d.id == destinationId,
        orElse: () => _destinations.first);

    return ParentsAbroad(
      destinationId: destinationId,
      destinationName: dest.name,
      familiesHere: 4,
      families: [
        AbroadFamily(parentName: 'Sarah & Tom', avatarColor: '#FF975C', childAges: 'Lily (14mo)', stayDates: '12 Jul - 19 Jul', accommodation: 'Hotel Las Americas'),
        AbroadFamily(parentName: 'Emma', avatarColor: '#3580F0', childAges: 'Archie (2yr), Mia (4yr)', stayDates: '10 Jul - 20 Jul', accommodation: 'Airbnb, Los Cristianos'),
        AbroadFamily(parentName: 'Priya & Raj', avatarColor: '#199A85', childAges: 'Aarav (18mo)', stayDates: '13 Jul - 21 Jul', accommodation: 'Club La Costa'),
        AbroadFamily(parentName: 'Claire', avatarColor: '#F3C54F', childAges: 'Oscar (3yr)', stayDates: '11 Jul - 18 Jul', accommodation: 'Hotel Paradise Park'),
      ],
      activities: [
        AbroadActivity(title: 'Beach playdate - Playa de Las Vistas', organiser: 'Emma', dateTime: 'Tue 15 Jul, 10:00am', location: 'South end near lifeguard station', spotsLeft: 6),
        AbroadActivity(title: 'Siam Park baby area morning', organiser: 'Sarah', dateTime: 'Wed 16 Jul, 9:30am', location: 'Meet at entrance', spotsLeft: 3),
        AbroadActivity(title: 'Sundowner walk (buggy friendly)', organiser: 'Priya', dateTime: 'Thu 17 Jul, 6:00pm', location: 'Los Cristianos promenade', spotsLeft: 8),
      ],
    );
  }

  // ── Search ─────────────────────────────────────────────────────────────

  List<TravelDestination> search(String query) {
    if (query.isEmpty) return _destinations;
    final q = query.toLowerCase();
    return _destinations.where((d) =>
        d.name.toLowerCase().contains(q) ||
        d.country.toLowerCase().contains(q) ||
        d.region.toLowerCase().contains(q) ||
        d.tags.any((t) => t.toLowerCase().contains(q)) ||
        d.description.toLowerCase().contains(q)
    ).toList();
  }

  List<TravelDestination> filterByAge(String ageGroup) {
    return _destinations.where((d) => d.bestForAges.contains(ageGroup)).toList();
  }

  // ── Sample data ────────────────────────────────────────────────────────

  void _loadSampleData() {
    _destinations.addAll([
      TravelDestination(
        id: 'tenerife', name: 'Tenerife', country: 'Spain', region: 'Canary Islands',
        imageUrl: 'https://images.unsplash.com/photo-1548574505-5e239809ee19?w=600',
        description: 'Year-round sunshine, calm beaches, and family-friendly resorts make Tenerife the top choice for huddl parents.',
        rating: 4.7, reviewCount: 24, huddlParentsVisited: 8, recommendPercent: 87,
        bestForAges: ['0-12m', '1-3yr', '3-5yr'], highlights: ['Siam Park baby area', 'Los Cristianos beach', 'Loro Parque', 'Mount Teide views'],
        flightTime: '4h 30m', bestMonths: 'Year-round (best Mar-May, Sep-Nov)', avgTemp: '22-28°C',
        visaRequired: false, safetyAlerts: [], tags: ['beach', 'summer', 'family-resort', 'popular'],
      ),
      TravelDestination(
        id: 'mallorca', name: 'Mallorca', country: 'Spain', region: 'Balearic Islands',
        imageUrl: 'https://images.unsplash.com/photo-1558642084-fd07fae5282e?w=600',
        description: 'Crystal-clear waters, short flight from the UK, and excellent family infrastructure. A huddl community favourite.',
        rating: 4.8, reviewCount: 18, huddlParentsVisited: 6, recommendPercent: 100,
        bestForAges: ['0-12m', '1-3yr', '3-5yr', '5-10yr'], highlights: ['Alcudia Beach', 'Palma Aquarium', 'Katmandu Park', 'Es Trenc Beach'],
        flightTime: '2h 30m', bestMonths: 'May-Oct', avgTemp: '20-32°C',
        visaRequired: false, safetyAlerts: [], tags: ['beach', 'summer', 'short-flight', 'popular'],
      ),
      TravelDestination(
        id: 'algarve', name: 'Algarve', country: 'Portugal', region: 'Southern Portugal',
        imageUrl: 'https://images.unsplash.com/photo-1555881400-74d7acaacd8b?w=600',
        description: 'Gentle waves, stunning cliffs, and wonderful food. Portuguese hospitality makes families feel truly welcome.',
        rating: 4.5, reviewCount: 15, huddlParentsVisited: 5, recommendPercent: 80,
        bestForAges: ['1-3yr', '3-5yr', '5-10yr'], highlights: ['Praia da Marinha', 'Zoomarine', 'Albufeira Old Town', 'Benagil Cave boats'],
        flightTime: '2h 45m', bestMonths: 'May-Oct', avgTemp: '18-30°C',
        visaRequired: false, safetyAlerts: [], tags: ['beach', 'culture', 'food', 'gentle-waves'],
      ),
      TravelDestination(
        id: 'malaga', name: 'Costa del Sol', country: 'Spain', region: 'Andalusia',
        imageUrl: 'https://images.unsplash.com/photo-1509840841025-9088ba78a826?w=600',
        description: '300 days of sunshine, affordable family dining, and beaches with soft sand. The community\'s best-value destination.',
        rating: 4.6, reviewCount: 30, huddlParentsVisited: 12, recommendPercent: 92,
        bestForAges: ['0-12m', '1-3yr', '3-5yr', '5-10yr'], highlights: ['Fuengirola Beach', 'Bioparc Fuengirola', 'Tivoli World', 'Nerja Caves'],
        flightTime: '2h 45m', bestMonths: 'Apr-Oct', avgTemp: '18-32°C',
        visaRequired: false, safetyAlerts: [], tags: ['beach', 'summer', 'budget-friendly', 'popular'],
      ),
      TravelDestination(
        id: 'lakegarda', name: 'Lake Garda', country: 'Italy', region: 'Northern Italy',
        imageUrl: 'https://images.unsplash.com/photo-1534631169685-38e88ca96a58?w=600',
        description: 'Stunning Alpine scenery meets Italian cuisine. Perfect for families who want culture, nature, and great food.',
        rating: 4.9, reviewCount: 12, huddlParentsVisited: 4, recommendPercent: 100,
        bestForAges: ['1-3yr', '3-5yr', '5-10yr'], highlights: ['Gardaland', 'Sirmione thermal baths', 'Limone sul Garda', 'Lido beaches'],
        flightTime: '2h (to Verona)', bestMonths: 'May-Sep', avgTemp: '15-30°C',
        visaRequired: false, safetyAlerts: [], tags: ['lake', 'culture', 'food', 'scenic'],
      ),
      TravelDestination(
        id: 'cornwall', name: 'Cornwall', country: 'United Kingdom', region: 'South West England',
        imageUrl: 'https://images.unsplash.com/photo-1567899378494-47b22a2ae96a?w=600',
        description: 'No passport needed! Rock pools, cream teas, and the UK\'s best beaches. The staycation favourite for huddl families.',
        rating: 4.4, reviewCount: 35, huddlParentsVisited: 15, recommendPercent: 88,
        bestForAges: ['0-12m', '1-3yr', '3-5yr', '5-10yr'], highlights: ['Eden Project', 'St Ives beaches', 'Padstow', 'Rock pooling'],
        flightTime: '0h (drive: 4-6h)', bestMonths: 'Jun-Sep', avgTemp: '14-21°C',
        visaRequired: false, safetyAlerts: [], tags: ['staycation', 'beach', 'nature', 'popular'],
      ),
      TravelDestination(
        id: 'cotswolds', name: 'Cotswolds', country: 'United Kingdom', region: 'Central England',
        imageUrl: 'https://images.unsplash.com/photo-1590523277543-a94d2e4eb00b?w=600',
        description: 'Honey-stone villages, farm parks, and gentle countryside walks. Ideal for a relaxing family break close to home.',
        rating: 4.3, reviewCount: 20, huddlParentsVisited: 9, recommendPercent: 89,
        bestForAges: ['0-12m', '1-3yr', '3-5yr'], highlights: ['Cotswold Farm Park', 'Birdland', 'Bourton-on-the-Water', 'Bibury walks'],
        flightTime: '0h (drive: 1-3h)', bestMonths: 'Apr-Oct', avgTemp: '10-22°C',
        visaRequired: false, safetyAlerts: [], tags: ['staycation', 'countryside', 'nature', 'short-break'],
      ),
      TravelDestination(
        id: 'crete', name: 'Crete', country: 'Greece', region: 'Greek Islands',
        imageUrl: 'https://images.unsplash.com/photo-1570077188670-e3a8d69ac5ff?w=600',
        description: 'The largest Greek island offers stunning beaches, ancient ruins, and incredible family hospitality.',
        rating: 4.6, reviewCount: 10, huddlParentsVisited: 3, recommendPercent: 100,
        bestForAges: ['1-3yr', '3-5yr', '5-10yr'], highlights: ['Elafonissi Beach', 'CRETAquarium', 'Knossos Palace', 'Samaria Gorge (older kids)'],
        flightTime: '3h 45m', bestMonths: 'May-Oct', avgTemp: '20-32°C',
        visaRequired: false, safetyAlerts: [], tags: ['beach', 'culture', 'history', 'food'],
      ),
    ]);

    // Sample reviews
    _reviews.addAll([
      ParentReview(id: 'r1', parentName: 'Sarah M.', avatarColor: '#FF975C', destinationId: 'tenerife', childAgesAtVisit: '14 months', visitDate: 'March 2026', rating: 4.5, title: 'Perfect for our little one!', review: 'We were nervous about flying with a 14-month-old but Tenerife was brilliant. The hotel had a cot ready, Siam Park baby area was the highlight, and the food was so good. Lidl had all the baby supplies we needed. Only downside: Mount Teide tour isn\'t suitable for toddlers.', topTips: ['Book Siam Park early', 'Lidl stocks Ella\'s Kitchen', 'South coast for calmer waves'], wouldRecommend: true, travelWith: 'baby'),
      ParentReview(id: 'r2', parentName: 'Tom & Emma', avatarColor: '#3580F0', destinationId: 'tenerife', childAgesAtVisit: '2yr, 4yr', visitDate: 'July 2025', rating: 5.0, title: 'We go every year now!', review: 'Third year visiting and it just gets better. The kids love the beaches, we love the restaurants. Los Cristianos is our base — everything is walkable with a double buggy. Mercadona supermarket is a 2 min walk.', topTips: ['Stay in Los Cristianos', 'Hire car for North coast day trip', 'Restaurant early bird deals at 6pm'], wouldRecommend: true, travelWith: 'toddler'),
      ParentReview(id: 'r3', parentName: 'Priya K.', avatarColor: '#199A85', destinationId: 'mallorca', childAgesAtVisit: '18 months', visitDate: 'May 2026', rating: 5.0, title: 'Short flight, incredible beaches', review: 'The 2.5h flight was perfect for our 18-month-old — she slept most of it! Alcudia Beach is incredibly shallow for ages — our toddler could wade safely. Palma Aquarium was a hit too.', topTips: ['Alcudia Beach = shallowest ever', 'Flight time is perfect for nap', 'Palma Aquarium worth the trip'], wouldRecommend: true, travelWith: 'toddler'),
      ParentReview(id: 'r4', parentName: 'James & Lisa', avatarColor: '#F3C54F', destinationId: 'malaga', childAgesAtVisit: '3yr, 5yr', visitDate: 'August 2025', rating: 4.5, title: 'Best value family holiday', review: 'We couldn\'t believe how affordable it was. Eating out with kids was about £30 for the whole family. Fuengirola beach has a playground right on the promenade — kept the kids entertained for hours. Bioparc is a must-do.', topTips: ['Fuengirola > Malaga city with kids', 'Bioparc is THE best zoo', 'Eat at chiringuitos on the beach'], wouldRecommend: true, travelWith: 'toddler'),
      ParentReview(id: 'r5', parentName: 'Meg C.', avatarColor: '#FF975C', destinationId: 'cornwall', childAgesAtVisit: '8 months, 3yr', visitDate: 'July 2026', rating: 4.0, title: 'UK staycation winner', review: 'Drove down with the kids — took 5 hours with stops but worth it. St Ives is beautiful but parking with a buggy is tricky. Eden Project has brilliant under-5s activities. Take waterproofs even in July!', topTips: ['Pack waterproofs regardless of forecast', 'Eden Project is rainy-day gold', 'Padstow fish & chips are legendary'], wouldRecommend: true, travelWith: 'baby'),
      ParentReview(id: 'r6', parentName: 'Rachel W.', avatarColor: '#3580F0', destinationId: 'lakegarda', childAgesAtVisit: '2yr', visitDate: 'June 2025', rating: 5.0, title: 'Italy with a toddler = heaven', review: 'Italians adore children and it shows everywhere. Restaurants brought out colouring and bread the moment we sat down. Sirmione was magical — the thermal baths have a toddler-friendly section. Gelato every day was non-negotiable.', topTips: ['Sirmione thermal baths are toddler-friendly', 'Gardaland is perfect from age 2+', 'Every restaurant welcomes kids'], wouldRecommend: true, travelWith: 'toddler'),
    ]);
  }
}
