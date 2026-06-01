import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';
import 'postcode_service.dart';

// =============================================================================
// OnboardingPhotoResult — result of a photo resolution attempt
// =============================================================================
class OnboardingPhotoResult {
  /// True  → [path] is a local asset path (use Image.asset)
  /// False → [path] is a network URL (use CachedNetworkImage)
  final bool isAsset;

  /// The asset path or network URL for the hero image.
  final String path;

  /// The detected borough name for the dynamic badge, or null when fallback.
  final String? borough;

  /// True when using the default Cambridge fallback photo.
  final bool isDefault;

  const OnboardingPhotoResult({
    required this.isAsset,
    required this.path,
    this.borough,
    this.isDefault = false,
  });
}

// =============================================================================
// OnboardingPhotoService
// =============================================================================
//
// Resolves the best available hero photo for carousel slide 2 based on the
// user's GPS location — before they have entered a postcode.
//
// Resolution order (first match wins):
//   1. SharedPreferences cache (24-hour TTL) → instant, zero network
//   2. Local asset from _localAssets → instant, zero network
//   3. Pexels API with style-guide query → 1–2 seconds, cached after
//   4. Default Cambridge asset → always succeeds
//
// Photography style guide (Rules 1–3) applied to every Pexels query:
//   Rule 1: Warm natural light, no flash  → Pexels color=warm_tone
//   Rule 2: Real iconic borough locations → Query includes borough name + "park outdoor"
//   Rule 3: Diverse families, candid      → Query includes "families" not "portrait studio"
//
// =============================================================================
class OnboardingPhotoService {
  // ── Singleton ───────────────────────────────────────────────────────────────
  OnboardingPhotoService._();
  static final OnboardingPhotoService _i = OnboardingPhotoService._();
  factory OnboardingPhotoService() => _i;

  // ── Pexels API ──────────────────────────────────────────────────────────────
  // Free tier: 200 req/hour, 20,000/month. No per-image attribution required.
  // Supply via: flutter run --dart-define=PEXELS_API_KEY=YOUR_KEY
  // Get a key:  https://www.pexels.com/api/
  static const String _pexelsKey = String.fromEnvironment('PEXELS_API_KEY');
  static const String _pexelsBase = 'https://api.pexels.com/v1/search';

  // ── Local borough → first asset mapping ────────────────────────────────────
  // Mirrors the first entry from default_group_service._boroughImagePools.
  // When the user's borough is in this map, no network call is made.
  // Add entries here as huddl rolls out to new boroughs.
  static const Map<String, String> _localAssets = {
    'cambridge':              'assets/images/groups/cambridge_kings_college.jpg',
    'east cambridgeshire':    'assets/images/groups/east_cambs_ely_cathedral.jpg',
    'south cambridgeshire':   'assets/images/groups/south_cambs_village.jpg',
    'barnet':                 'assets/images/groups/boroughs/barnet_1.jpg',
    'birmingham':             'assets/images/groups/boroughs/birmingham_1.jpg',
    'brent':                  'assets/images/groups/boroughs/brent_1.jpg',
    'bristol':                'assets/images/groups/boroughs/bristol_1.jpg',
    'bromley':                'assets/images/groups/boroughs/bromley_1.jpg',
    'camden':                 'assets/images/groups/boroughs/camden_1.jpg',
    'city of london':         'assets/images/groups/boroughs/city_of_london_1.jpg',
    'croydon':                'assets/images/groups/boroughs/croydon_1.jpg',
    'ealing':                 'assets/images/groups/boroughs/ealing_1.jpg',
    'enfield':                'assets/images/groups/boroughs/enfield_1.jpg',
    'greenwich':              'assets/images/groups/boroughs/greenwich_1.jpg',
    'hackney':                'assets/images/groups/boroughs/hackney_1.jpg',
    'hammersmith and fulham': 'assets/images/groups/boroughs/hammersmith_1.jpg',
    'haringey':               'assets/images/groups/boroughs/haringey_1.jpg',
    'hounslow':               'assets/images/groups/boroughs/hounslow_1.jpg',
    'islington':              'assets/images/groups/boroughs/islington_1.jpg',
    'kensington and chelsea': 'assets/images/groups/boroughs/kensington_1.jpg',
    'lambeth':                'assets/images/groups/boroughs/lambeth_1.jpg',
    'leeds':                  'assets/images/groups/boroughs/leeds_1.jpg',
    'lewisham':               'assets/images/groups/boroughs/lewisham_1.jpg',
    'manchester':             'assets/images/groups/boroughs/manchester_1.jpg',
    'merton':                 'assets/images/groups/boroughs/merton_1.jpg',
    'newham':                 'assets/images/groups/boroughs/newham_1.jpg',
    'redbridge':              'assets/images/groups/boroughs/redbridge_1.jpg',
    'richmond upon thames':   'assets/images/groups/boroughs/richmond_1.jpg',
    'salford':                'assets/images/groups/boroughs/salford_1.jpg',
    'southwark':              'assets/images/groups/boroughs/southwark_1.jpg',
    'tower hamlets':          'assets/images/groups/boroughs/tower_hamlets_1.jpg',
    'trafford':               'assets/images/groups/boroughs/trafford_1.jpg',
    'waltham forest':         'assets/images/groups/boroughs/waltham_forest_1.jpg',
  };

  // ── Cache ────────────────────────────────────────────────────────────────────
  static const _kUrl     = 'onboarding_photo_v1_url';
  static const _kBorough = 'onboarding_photo_v1_borough';
  static const _kTime    = 'onboarding_photo_v1_time';
  static const _kTtl     = Duration(hours: 24);

  // ── Default fallback ─────────────────────────────────────────────────────────
  static const _kDefault = 'assets/images/onboarding_meetup.webp';

  // ── Public: resolve the best photo for this user ─────────────────────────────

  Future<OnboardingPhotoResult> resolve() async {
    // 1. Cache hit
    final cached = await _fromCache();
    if (cached != null) return cached;

    // 2. GPS
    final gps = await LocationService().getUserPosition();
    if (!gps.hasPosition) return _fallback();

    final pos = gps.position!;

    // 3. Reverse geocode → borough
    final borough = await PostcodeService().getBoroughFromCoords(
      pos.latitude, pos.longitude,
    );
    if (borough == null) return _fallback();

    final key = borough.toLowerCase().trim();

    // 4. Local asset (instant, no network)
    if (_localAssets.containsKey(key)) {
      final asset = _localAssets[key]!;
      await _toCache(url: asset, borough: borough, isAsset: true);
      return OnboardingPhotoResult(isAsset: true, path: asset, borough: borough);
    }

    // 5. Pexels API (borough not yet in local pool)
    if (_pexelsKey.isEmpty) {
      if (kDebugMode) debugPrint('[OnboardingPhotoService] No PEXELS_API_KEY — fallback');
      return _fallback();
    }
    final url = await _pexels(borough);
    if (url == null) return _fallback();

    await _toCache(url: url, borough: borough, isAsset: false);
    return OnboardingPhotoResult(isAsset: false, path: url, borough: borough);
  }

  /// Clears the cached photo. Call on logout or postcode change.
  static Future<void> clearCache() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kUrl);
    await p.remove(_kBorough);
    await p.remove(_kTime);
  }

  // ── Pexels fetch ──────────────────────────────────────────────────────────────

  Future<String?> _pexels(String borough) async {
    // Style guide rules baked into the query:
    //   Rule 1 (warm light):    color=warm_tone
    //   Rule 2 (local iconic):  borough name in query
    //   Rule 3 (candid family): "families outdoor park"
    final q = Uri.encodeComponent('$borough families outdoor park');
    final uri = Uri.parse(
      '$_pexelsBase?query=$q&orientation=portrait&color=warm_tone&per_page=15&page=1',
    );
    try {
      final res = await http.get(
        uri,
        headers: {'Authorization': _pexelsKey, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;
      final body = json.decode(res.body) as Map<String, dynamic>;
      final photos = body['photos'] as List<dynamic>?;
      if (photos == null || photos.isEmpty) return null;

      // Pick randomly from results for variety on each new install
      final idx = DateTime.now().millisecondsSinceEpoch % photos.length;
      final src = (photos[idx] as Map<String, dynamic>)['src'] as Map<String, dynamic>?;
      final url = src?['portrait'] as String?; // 630×950 — portrait, good quality
      if (kDebugMode) debugPrint('[OnboardingPhotoService] Pexels → $url');
      return url;
    } catch (e) {
      if (kDebugMode) debugPrint('[OnboardingPhotoService] Pexels error: $e');
      return null;
    }
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────────

  Future<OnboardingPhotoResult?> _fromCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final t = p.getString(_kTime);
      if (t == null) return null;
      final age = DateTime.now().difference(DateTime.parse(t));
      if (age > _kTtl) return null;
      final url = p.getString(_kUrl);
      if (url == null) return null;
      return OnboardingPhotoResult(
        isAsset: url.startsWith('assets/'),
        path: url,
        borough: p.getString(_kBorough),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _toCache({
    required String url,
    required String borough,
    required bool isAsset,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kUrl, url);
      await p.setString(_kBorough, borough);
      await p.setString(_kTime, DateTime.now().toIso8601String());
    } catch (e) {
      if (kDebugMode) debugPrint('[OnboardingPhotoService] Cache write error: $e');
    }
  }

  OnboardingPhotoResult _fallback() => const OnboardingPhotoResult(
    isAsset: true,
    path: _kDefault,
    isDefault: true,
  );
}
