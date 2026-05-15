import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'ai_api_helper.dart';
import 'browser_storage.dart';
import 'local_services_service.dart';

// =============================================================================
// AI DIRECTORY SERVICE — HUDDL INTELLIGENT CAMBRIDGE SERVICES DISCOVERY
//
// Uses Gemini AI to discover high-rated (≥4.5★) Cambridge local services
// across all 12 ServiceCategory values.  Runs automatically once per day;
// deduplicates against existing Firestore listings by name + category.
//
// Flow:
//   1. On Directory tab open → check last-run timestamp (BrowserStorage)
//   2. If >24 h ago (or never) → trigger _runDiscovery()
//   3. _runDiscovery() asks Gemini for N listings per category (rotating)
//   4. Each result is deduplicated by normalised name + category against
//      all existing Cambridge documents in Firestore
//   5. New listings are written to Firestore with listingSource='ai_discovered'
//   6. Last-run timestamp is updated
//
// Rate limiting: max 5 categories per daily run (rotates through all 12
// categories so every category is refreshed within 2–3 days).
//
// createdByUid: 'huddl_ai'  — sentinel UID for AI-sourced listings
// =============================================================================

class AiDirectoryService {
  // Singleton
  static final AiDirectoryService _instance = AiDirectoryService._internal();
  factory AiDirectoryService() => _instance;
  AiDirectoryService._internal();

  static const String _collection   = 'local_services';
  static const String _lastRunKey   = 'ai_directory_last_run_v1';
  static const String _nextCatKey   = 'ai_directory_next_category_v1';
  static const String _aiCreatorUid = 'huddl_ai';
  static const String _borough      = 'Cambridge';

  // How many categories to process per daily run (keeps API cost low)
  static const int _categoriesPerRun = 5;
  // How many listings to request per category per run
  static const int _listingsPerCategory = 6;
  // Minimum rating to accept
  static const double _minRating = 4.5;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Public entry point ────────────────────────────────────────────────────

  /// Returns true if a new discovery run was triggered and completed.
  /// Returns false if the daily cooldown hasn't expired yet.
  Future<bool> runIfDue() async {
    if (!await _isDue()) return false;
    await _runDiscovery();
    return true;
  }

  /// Force an immediate discovery run regardless of cooldown.
  /// Used for manual refresh button presses.
  Future<void> forceRun() async {
    await _runDiscovery();
  }

  /// Returns number of hours until the next scheduled run, or 0 if due now.
  Future<int> hoursUntilNextRun() async {
    final raw = await BrowserStorage.getString(_lastRunKey);
    if (raw == null) return 0;
    final last = DateTime.tryParse(raw);
    if (last == null) return 0;
    final next = last.add(const Duration(hours: 24));
    final diff = next.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inHours;
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<bool> _isDue() async {
    final raw = await BrowserStorage.getString(_lastRunKey);
    if (raw == null) return true;
    final last = DateTime.tryParse(raw);
    if (last == null) return true;
    return DateTime.now().difference(last).inHours >= 24;
  }

  Future<void> _runDiscovery() async {
    if (kDebugMode) debugPrint('[AiDirectory] 🤖 Starting daily discovery run…');

    // ── Select which categories to process this run ─────────────────────
    final allCats = ServiceCategory.values;
    final startIdx = await _nextCategoryIndex();
    final catsThisRun = <ServiceCategory>[];
    for (int i = 0; i < _categoriesPerRun; i++) {
      catsThisRun.add(allCats[(startIdx + i) % allCats.length]);
    }

    // ── Load existing names for dedup (Cambridge only) ───────────────────
    final existingNames = await _loadExistingNames();

    int totalAdded = 0;

    for (final cat in catsThisRun) {
      if (kDebugMode) {
        debugPrint('[AiDirectory]   → processing category: ${cat.displayName}');
      }
      try {
        final discovered = await _discoverForCategory(cat, existingNames);
        for (final item in discovered) {
          await _writeToFirestore(item);
          existingNames.add(_normaliseName(item['name'] as String));
          totalAdded++;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[AiDirectory]   ⚠️ category ${cat.name} error: $e');
        }
      }
    }

    // ── Advance category pointer for next run ────────────────────────────
    final nextIdx = (startIdx + _categoriesPerRun) % allCats.length;
    await BrowserStorage.setString(_nextCatKey, nextIdx.toString());

    // ── Update last-run timestamp ────────────────────────────────────────
    await BrowserStorage.setString(_lastRunKey, DateTime.now().toIso8601String());

    if (kDebugMode) {
      debugPrint('[AiDirectory] ✅ Run complete — $totalAdded new listings added');
    }
  }

  Future<int> _nextCategoryIndex() async {
    final raw = await BrowserStorage.getString(_nextCatKey);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  Future<Set<String>> _loadExistingNames() async {
    try {
      final snap = await _db
          .collection(_collection)
          .where('borough', isEqualTo: _borough)
          .get();
      return snap.docs
          .map((d) => _normaliseName(d.data()['name'] as String? ?? ''))
          .toSet();
    } catch (_) {
      return {};
    }
  }

  String _normaliseName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Ask Gemini for real, highly-rated Cambridge businesses in [cat].
  Future<List<Map<String, dynamic>>> _discoverForCategory(
    ServiceCategory cat,
    Set<String> existingNames,
  ) async {
    final prompt = _buildPrompt(cat);

    final response = await AiApiHelper.generateText(
      {
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'temperature':     0.3,
          'maxOutputTokens': 2048,
        },
      },
      timeout: const Duration(seconds: 45),
    );

    if (response == null || response.trim().isEmpty) return [];

    var json = response.trim();
    if (json.startsWith('```')) {
      json = json
          .replaceAll(RegExp(r'^```[a-z]*\n?'), '')
          .replaceAll(RegExp(r'\n?```$'), '')
          .trim();
    }

    List<dynamic> list;
    try {
      list = jsonDecode(json) as List<dynamic>;
    } catch (_) {
      return [];
    }

    final results = <Map<String, dynamic>>[];
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      final name = m['name'] as String? ?? '';
      if (name.isEmpty) continue;

      // Dedup check
      if (existingNames.contains(_normaliseName(name))) continue;

      // Rating gate — only accept ≥4.5
      final rating = (m['rating'] as num?)?.toDouble() ?? 0.0;
      if (rating < _minRating) continue;

      results.add({
        'name':        name,
        'tagline':     m['tagline']     as String? ?? '',
        'description': m['description'] as String? ?? '',
        'category':    cat.firestoreValue,
        'phone':       m['phone']       as String?,
        'website':     m['website']     as String?,
        'tags':        (m['tags'] as List<dynamic>?)
                           ?.map((e) => e as String)
                           .toList() ?? <String>[],
        'rating':      rating,
      });
    }

    return results;
  }

  String _buildPrompt(ServiceCategory cat) {
    final catLabel = cat.displayName;
    final today    = DateTime.now();
    final dateStr  = '${today.day}/${today.month}/${today.year}';

    return '''
You are a local services research assistant helping a UK parenting app populate a trusted directory.

Task: Find $_listingsPerCategory real, highly-rated local businesses or professionals in Cambridge, UK in the "$catLabel" category.

Requirements:
• Based in Cambridge (CB postcodes) or serving Cambridge families
• Minimum 4.5 out of 5 stars on Google, Yell, Bark, or similar UK review platforms
• Family-friendly, child-safe, and parent-recommended
• Real businesses that actually exist as of $dateStr

For each business provide:
- name: full business/professional name (e.g. "Little Stars Nursery", "David Brown CPR Training")
- tagline: one short phrase describing them (max 60 chars, e.g. "Ofsted Outstanding nursery, Cherry Hinton")
- description: 1-2 sentence endorsement-style description parents would trust (max 160 chars)
- category: "${cat.firestoreValue}"
- phone: UK phone number if known (or null)
- website: website URL if known (or null)
- tags: up to 4 short tags relevant to parents (e.g. ["Ofsted Outstanding", "DBS checked", "flexible hours"])
- rating: the numeric star rating (must be 4.5 or above)

Respond ONLY with a valid JSON array. No markdown, no explanation, no preamble.
Example format:
[{"name":"Little Stars Nursery","tagline":"Ofsted Outstanding nursery, Cherry Hinton","description":"Award-winning nursery with flexible sessions and a dedicated SEND support team.","category":"${cat.firestoreValue}","phone":"01223 000000","website":"https://example.com","tags":["Ofsted Outstanding","SEND support","flexible hours","DBS checked"],"rating":4.8}]

If you cannot find $_listingsPerCategory qualifying businesses, return as many as you can find that meet the criteria. Return [] if none.
''';
  }

  Future<void> _writeToFirestore(Map<String, dynamic> item) async {
    final now = DateTime.now();
    final cat = ServiceCategoryX.fromString(item['category'] as String);
    final rating = (item['rating'] as num?)?.toDouble();

    final data = <String, dynamic>{
      'name':             item['name'],
      'tagline':          item['tagline'],
      'description':      item['description'],
      'category':         cat.firestoreValue,
      'borough':          _borough,
      'tags':             item['tags'],
      'phone':            item['phone'],
      'website':          item['website'],
      'ownerUid':         null,
      'createdByUid':     _aiCreatorUid,
      'verificationTier': VerificationTier.none.firestoreValue,
      'isVerified':       false,
      'endorsementCount': 0,
      'viewCount':        0,
      'createdAt':        Timestamp.fromDate(now),
      'updatedAt':        Timestamp.fromDate(now),
      'listingSource':    'ai_discovered',
      'aiRating':         rating,
      'aiDiscoveredAt':   Timestamp.fromDate(now),
    };

    try {
      await _db.collection(_collection).add(data);
      if (kDebugMode) {
        debugPrint('[AiDirectory]     ✓ Added: ${item['name']} (${item['category']}, $rating★)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AiDirectory]     ✗ Failed to write ${item['name']}: $e');
      }
    }
  }
}
