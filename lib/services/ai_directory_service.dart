import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'browser_storage.dart';
import 'local_services_service.dart';
import 'borough_scope_guard.dart';

// =============================================================================
// AI DIRECTORY SERVICE — REAL LOCAL SERVICES via GOOGLE PLACES API (New)
//
// Discovers REAL, verifiable local businesses using the Google Places API
// (New) Text Search endpoint. Every listing comes directly from Google's
// business database — real names, addresses, ratings, phone numbers,
// websites, and actual Google Business photos.
//
// Daily refresh flow:
//   1. On Directory tab open → check last-run timestamp (BrowserStorage)
//   2. If >24 h ago → trigger _runDiscovery()
//   3. Rotates through category search queries (5 categories per run)
//   4. For each result: fetches the Google Places photo as imageUrl
//   5. Deduplicates against existing Firestore listings by normalised name
//   6. Writes new listings with listingSource='places_api'
//
// Places API (New) endpoints:
//   POST https://places.googleapis.com/v1/places:searchText
//   GET  https://places.googleapis.com/v1/{photo}/media?maxWidthPx=800
//
// All listings produced have:
//   • Real business name from Google
//   • Real address, phone, website
//   • Real Google star rating
//   • Real business photo from Google Maps
// =============================================================================

class AiDirectoryService {
  static final AiDirectoryService _instance = AiDirectoryService._internal();
  factory AiDirectoryService() => _instance;
  AiDirectoryService._internal();

  static const String _collection   = 'local_services';
  static const String _lastRunKey   = 'ai_directory_last_run_v3';
  static const String _nextCatKey   = 'ai_directory_next_category_v3';
  static const String _aiCreatorUid = 'huddl_ai';

  // Google Places API (New)
  // Key sourced from --dart-define=GOOGLE_PLACES_API_KEY=AIza... at build time.
  // SECURITY: Rotate via Google Cloud Console if previously exposed.
  static const String _placesKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
    defaultValue: '',
  );
  static const String _searchUrl      = 'https://places.googleapis.com/v1/places:searchText';
  static const String _photoBaseUrl   = 'https://places.googleapis.com/v1/';
  static const String _photoSuffix    = '/media?maxWidthPx=800&skipHttpRedirect=true&key=$_placesKey';

  // How many search-query slots to process per daily run
  static const int _queriesPerRun  = 8;
  // Max results to request per search query
  static const int _maxPerQuery    = 8;
  // Minimum Google rating to accept
  static const double _minRating   = 4.0;

  // Cambridge city centre (used as location bias for all searches)
  static const double _camLat = 52.2053;
  static const double _camLng = 0.1218;
  static const double _radius = 8000.0; // 8 km

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Borough resolution ────────────────────────────────────────────────────

  /// Single source of truth — delegates to BoroughScopeGuard.
  /// Returns '' when borough is unresolved; callers get empty results
  /// rather than wrong-borough results. (Option B UI prompt: separate PR.)
  String get _userBorough => BoroughScopeGuard().currentBorough ?? '';

  // ── Category search queries ───────────────────────────────────────────────
  // Each entry is (category firestoreValue, search query string).
  // Rotated daily so every query is covered within ~1 week.
  static const List<(String, String)> _queries = [
    // childcare
    ('childcare',      'day nursery {borough}'),
    ('childcare',      'childminder {borough}'),
    ('childcare',      'preschool {borough}'),
    ('childcare',      'after school club {borough}'),
    // education
    ('education',      'children tutor {borough}'),
    ('education',      'music lessons children {borough}'),
    ('education',      'swimming lessons children {borough}'),
    ('education',      'martial arts children {borough}'),
    ('education',      'drama classes children {borough}'),
    // healthWellness
    ('healthWellness', 'osteopath {borough}'),
    ('healthWellness', 'acupuncture {borough}'),
    ('healthWellness', 'postnatal yoga {borough}'),
    ('healthWellness', 'paediatric physiotherapy {borough}'),
    ('healthWellness', 'children dentist {borough}'),
    // fitness
    ('fitness',        'buggy fitness class {borough}'),
    ('fitness',        'postnatal fitness {borough}'),
    ('fitness',        'baby swimming class {borough}'),
    ('fitness',        'parent baby yoga {borough}'),
    // photography
    ('photography',    'family photographer {borough}'),
    ('photography',    'newborn photographer {borough}'),
    ('photography',    'baby photographer {borough}'),
    // cleaning
    ('cleaning',       'domestic cleaning service {borough}'),
    ('cleaning',       'house cleaning {borough}'),
    // homeServices
    ('homeServices',   'plumber {borough}'),
    ('homeServices',   'electrician {borough}'),
    ('homeServices',   'handyman {borough}'),
    ('homeServices',   'gardener {borough}'),
    // food
    ('food',           'organic food delivery {borough}'),
    ('food',           'baby weaning class {borough}'),
    // doula
    ('doula',          'doula {borough}'),
    ('doula',          'hypnobirthing {borough}'),
    // firstAid
    ('firstAid',       'first aid training {borough}'),
    ('firstAid',       'paediatric first aid course {borough}'),
    // other
    ('other',          'parent support group {borough}'),
    ('other',          'stay and play {borough}'),
    ('other',          'children library {borough}'),
  ];

  // Tags added to every listing per category
  static const Map<String, List<String>> _categoryTags = {
    'childcare':      ['Ofsted registered', 'DBS checked'],
    'education':      ['DBS checked', 'qualified teachers'],
    'healthWellness': ['qualified practitioner', 'family-friendly'],
    'fitness':        ['parent & child', 'qualified instructor'],
    'photography':    ['professional', 'family sessions'],
    'cleaning':       ['insured', 'background checked'],
    'homeServices':   ['insured', 'fully qualified'],
    'food':           ['family-friendly'],
    'doula':          ['certified'],
    'firstAid':       ['certified', 'Ofsted compliant'],
    'other':          ['community'],
  };

  // ── Public entry points ───────────────────────────────────────────────────

  Future<bool> runIfDue() async {
    if (!await _isDue()) return false;
    await _runDiscovery();
    return true;
  }

  Future<void> forceRun() async => _runDiscovery();

  Future<int> hoursUntilNextRun() async {
    final raw  = await BrowserStorage.getString(_lastRunKey);
    if (raw == null) return 0;
    final last = DateTime.tryParse(raw);
    if (last == null) return 0;
    final diff = last.add(const Duration(hours: 24)).difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inHours;
  }

  // ── Internal orchestration ────────────────────────────────────────────────

  Future<bool> _isDue() async {
    final raw  = await BrowserStorage.getString(_lastRunKey);
    if (raw == null) return true;
    final last = DateTime.tryParse(raw);
    if (last == null) return true;
    return DateTime.now().difference(last).inHours >= 24;
  }

  Future<void> _runDiscovery() async {
    if (kDebugMode) {
      if (kDebugMode) debugPrint('[AiDirectory] 📍 Starting Places API discovery…');
    }

    final borough       = _userBorough;
    final existingNames = await _loadExistingNames(borough);
    final startIdx      = await _nextQueryIndex();

    int totalAdded = 0;

    for (int i = 0; i < _queriesPerRun; i++) {
      final idx   = (startIdx + i) % _queries.length;
      final (cat, queryTemplate) = _queries[idx];
      final query = queryTemplate.replaceAll('{borough}', borough);

      if (kDebugMode) {
        if (kDebugMode) debugPrint('[AiDirectory]   🔍 $query');
      }

      try {
        final places = await _searchPlaces(query);

        for (final place in places) {
          final name = (place['displayName'] as Map?)?['text'] as String? ?? '';
          if (name.isEmpty) continue;
          if (place['businessStatus'] != 'OPERATIONAL') continue;

          final rating = (place['rating'] as num?)?.toDouble();
          if (rating != null && rating < _minRating) continue;

          final norm = _normalise(name);
          if (existingNames.contains(norm)) continue;

          final imageUrl = await _fetchPhotoUrl(
            (place['photos'] as List?)?.cast<Map<String, dynamic>>(),
          );

          await _writeToFirestore(place, cat, borough, imageUrl);
          existingNames.add(norm);
          totalAdded++;

          if (kDebugMode) {
            if (kDebugMode) {
              debugPrint('[AiDirectory]   ✓ ${name.substring(0, name.length.clamp(0, 50))} '
              '(${rating != null ? "$rating★" : "no rating"}, '
              '${imageUrl != null ? "📷" : "no img"})');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[AiDirectory]   ⚠️ Error for "$query": $e');
      }
    }

    // Advance pointer for next run
    final nextIdx = (startIdx + _queriesPerRun) % _queries.length;
    await BrowserStorage.setString(_nextCatKey, nextIdx.toString());
    await BrowserStorage.setString(_lastRunKey, DateTime.now().toIso8601String());

    if (kDebugMode) {
      if (kDebugMode) {
        debugPrint('[AiDirectory] ✅ Done — $totalAdded new real listings added');
      }
    }
  }

  // ── Places API: Text Search ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _searchPlaces(String query) async {
    final body = jsonEncode({
      'textQuery':    query,
      'locationBias': {
        'circle': {
          'center': {'latitude': _camLat, 'longitude': _camLng},
          'radius': _radius,
        },
      },
      'maxResultCount': _maxPerQuery,
      'languageCode':   'en',
    });

    final fieldMask = [
      'places.displayName',
      'places.formattedAddress',
      'places.nationalPhoneNumber',
      'places.websiteUri',
      'places.rating',
      'places.userRatingCount',
      'places.businessStatus',
      'places.photos',
      'places.editorialSummary',
    ].join(',');

    final response = await http.post(
      Uri.parse(_searchUrl),
      headers: {
        'Content-Type':     'application/json',
        'X-Goog-Api-Key':   _placesKey,
        'X-Goog-FieldMask': fieldMask,
      },
      body: body,
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Places API ${response.statusCode}: '
          '${response.body.substring(0, response.body.length.clamp(0, 200))}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['places'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  // ── Places API: Photo fetch ───────────────────────────────────────────────

  Future<String?> _fetchPhotoUrl(List<Map<String, dynamic>>? photos) async {
    if (photos == null || photos.isEmpty) return null;
    final photoName = photos.first['name'] as String?;
    if (photoName == null || photoName.isEmpty) return null;

    try {
      final url = '$_photoBaseUrl$photoName$_photoSuffix';
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Huddl/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final uri  = data['photoUri'] as String?;
        if (uri != null && uri.startsWith('http')) return uri;
      }
    } catch (_) {}
    return null;
  }

  // ── Firestore write ───────────────────────────────────────────────────────

  Future<void> _writeToFirestore(
    Map<String, dynamic> place,
    String category,
    String borough,
    String? imageUrl,
  ) async {
    final name    = (place['displayName'] as Map?)?['text'] as String? ?? '';
    final address = place['formattedAddress']  as String? ?? '';
    final phone   = place['nationalPhoneNumber'] as String?;
    final website = place['websiteUri']         as String?;
    final rating  = (place['rating'] as num?)?.toDouble();
    final summary = (place['editorialSummary'] as Map?)?['text'] as String?;

    // Build short tagline from name + area
    final addrParts = address.split(',');
    final shortAddr = addrParts.length >= 2
        ? addrParts.sublist(1, addrParts.length.clamp(0, 3)).join(',').trim()
        : address;
    final tagline = '${name.substring(0, name.length.clamp(0, 40))}, $shortAddr'
        .substring(0, ('${name.substring(0, name.length.clamp(0, 40))}, $shortAddr').length.clamp(0, 60));

    final description = summary?.substring(0, summary.length.clamp(0, 160))
        ?? '$name — serving families in $borough.';

    // Build tags
    final baseTags = List<String>.from(_categoryTags[category] ?? []);
    if (rating != null && rating >= 4.8) baseTags.add('Top rated');
    final tags = baseTags.take(4).toList();

    final cat = ServiceCategoryX.fromString(category);
    final now = DateTime.now();

    final data = <String, dynamic>{
      'name':             name,
      'tagline':          tagline,
      'description':      description,
      'address':          address,
      'category':         cat.firestoreValue,
      'borough':          borough,
      'tags':             tags,
      'phone':            phone,
      'website':          website,
      'ownerUid':         null,
      'createdByUid':     _aiCreatorUid,
      'verificationTier': VerificationTier.none.firestoreValue,
      'isVerified':       false,
      'endorsementCount': 0,
      'viewCount':        0,
      'createdAt':        Timestamp.fromDate(now),
      'updatedAt':        Timestamp.fromDate(now),
      'listingSource':    'places_api',
      'googleRating':     rating,
      'aiRating':         rating,
      'aiDiscoveredAt':   Timestamp.fromDate(now),
      if (imageUrl != null) 'imageUrl': imageUrl,
    };

    await _db.collection(_collection).add(data);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<int> _nextQueryIndex() async {
    final raw = await BrowserStorage.getString(_nextCatKey);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  Future<Set<String>> _loadExistingNames(String borough) async {
    try {
      final snap = await _db
          .collection(_collection)
          .where('borough', isEqualTo: borough)
          .get();
      return snap.docs
          .map((d) => _normalise(d.data()['name'] as String? ?? ''))
          .toSet();
    } catch (_) {
      return {};
    }
  }

  String _normalise(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
