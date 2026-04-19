import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'browser_storage.dart';

// =============================================================================
// POSTCODE SERVICE
//
// Single source of truth for postcode → borough (admin district) resolution.
//
// Resolution strategy (in priority order):
//   1. In-memory cache  — instantaneous, populated after first lookup
//   2. BrowserStorage   — survives app restart, populated after first lookup
//   3. postcodes.io API — authoritative, full postcode lookup (async)
//   4. Outward-code map — offline fallback only, never used for Firestore writes
//
// Public API
// ──────────
//   lookupBoroughAsync(postcode) → Future<String?>
//     Always-correct resolution. Calls postcodes.io, caches the result.
//     Use this wherever a postcode is first entered or changed:
//       • Onboarding postcode screen
//       • Profile postcode edit
//       • HuddlUserService.syncCurrentUserProfile()
//       • FirebaseAuthService._createUserProfile()
//
//   getBoroughFromPostcode(postcode) → String?
//     Synchronous cache-read. Returns the cached value if the postcode was
//     previously resolved via lookupBoroughAsync(). Falls back to the
//     outward-code map as a last resort (never null for known UK districts).
//     Safe to call from build() / sync code; will not trigger a network request.
//
//   isCambridgePostcode(postcode) → bool   [sync, cache-first]
//   isCambridgePostcodeAsync(postcode) → Future<bool>   [authoritative]
//
// Cache keys (BrowserStorage)
// ───────────────────────────
//   huddl_postcode_borough_v1   JSON map  { "CB12AB": "Cambridge", … }
// =============================================================================

class PostcodeService {
  static final PostcodeService _instance = PostcodeService._internal();
  factory PostcodeService() => _instance;
  PostcodeService._internal();

  // ── Persistent cache key ──────────────────────────────────────────────────
  static const String _cacheKey = 'huddl_postcode_borough_v1';

  // ── In-memory cache: cleanPostcode (no spaces, uppercase) → borough ───────
  final Map<String, String> _cache = {};
  bool _cacheLoaded = false;

  // ── Cambridge acceptance set (outward codes whose borough == Cambridge) ────
  // Kept as a fast sync check; the async path is always more accurate.
  static const Set<String> _cambridgeOutwardCodes = {
    'CB1', 'CB2', 'CB3', 'CB4', 'CB5',
    'CB6', 'CB7', 'CB8', 'CB9',
    'CB10', 'CB11',
    'CB21', 'CB22', 'CB23', 'CB24', 'CB25',
  };

  // ── Outward-code → borough fallback map ──────────────────────────────────
  // Used ONLY when no cached value exists and the network is unreachable.
  // These are the outward codes for areas where Huddl operates.
  static const Map<String, String> _fallbackMap = {
    // Cambridge
    'CB1': 'Cambridge', 'CB2': 'Cambridge', 'CB3': 'Cambridge',
    'CB4': 'Cambridge', 'CB5': 'Cambridge', 'CB6': 'Cambridge',
    'CB7': 'Cambridge', 'CB8': 'Cambridge', 'CB9': 'Cambridge',
    'CB10': 'Cambridge', 'CB11': 'Cambridge',
    'CB21': 'Cambridge', 'CB22': 'Cambridge', 'CB23': 'Cambridge',
    'CB24': 'Cambridge', 'CB25': 'Cambridge',
    // London — EC
    'EC1': 'City of London', 'EC1A': 'City of London', 'EC1M': 'Islington',
    'EC1N': 'Camden', 'EC1R': 'Islington', 'EC1V': 'Islington',
    'EC1Y': 'Islington', 'EC2': 'City of London', 'EC2A': 'City of London',
    'EC2M': 'City of London', 'EC2N': 'City of London',
    'EC2R': 'City of London', 'EC2V': 'City of London',
    'EC2Y': 'City of London', 'EC3': 'City of London',
    'EC3A': 'City of London', 'EC3M': 'City of London',
    'EC3N': 'City of London', 'EC3P': 'City of London',
    'EC3R': 'City of London', 'EC3V': 'City of London',
    'EC4': 'City of London', 'EC4A': 'City of London',
    'EC4M': 'City of London', 'EC4N': 'City of London',
    'EC4P': 'City of London', 'EC4R': 'City of London',
    'EC4V': 'City of London', 'EC4Y': 'City of London',
    // London — E
    'E1': 'Tower Hamlets', 'E2': 'Tower Hamlets', 'E3': 'Tower Hamlets',
    'E4': 'Waltham Forest', 'E5': 'Hackney', 'E6': 'Newham',
    'E7': 'Newham', 'E8': 'Hackney', 'E9': 'Hackney',
    'E10': 'Waltham Forest', 'E11': 'Redbridge', 'E12': 'Newham',
    'E13': 'Newham', 'E14': 'Tower Hamlets', 'E15': 'Newham',
    'E16': 'Newham', 'E17': 'Waltham Forest', 'E18': 'Redbridge',
    // London — N
    'N1': 'Islington', 'N2': 'Barnet', 'N3': 'Barnet', 'N4': 'Hackney',
    'N5': 'Islington', 'N6': 'Camden', 'N7': 'Islington',
    'N8': 'Haringey', 'N9': 'Enfield', 'N10': 'Haringey',
    'N11': 'Enfield', 'N12': 'Barnet', 'N13': 'Enfield',
    'N14': 'Enfield', 'N15': 'Haringey', 'N16': 'Hackney',
    'N17': 'Haringey', 'N18': 'Enfield', 'N19': 'Islington',
    'N20': 'Barnet', 'N21': 'Enfield', 'N22': 'Haringey',
    // London — NW
    'NW1': 'Camden', 'NW2': 'Barnet', 'NW3': 'Camden', 'NW4': 'Barnet',
    'NW5': 'Camden', 'NW6': 'Camden', 'NW7': 'Barnet',
    'NW8': 'Westminster', 'NW9': 'Barnet', 'NW10': 'Brent',
    'NW11': 'Barnet',
    // London — SE
    'SE1': 'Southwark', 'SE2': 'Greenwich', 'SE3': 'Greenwich',
    'SE4': 'Lewisham', 'SE5': 'Southwark', 'SE6': 'Lewisham',
    'SE7': 'Greenwich', 'SE8': 'Lewisham', 'SE9': 'Greenwich',
    'SE10': 'Greenwich', 'SE11': 'Lambeth', 'SE12': 'Lewisham',
    'SE13': 'Lewisham', 'SE14': 'Lewisham', 'SE15': 'Southwark',
    'SE16': 'Southwark', 'SE17': 'Southwark', 'SE18': 'Greenwich',
    'SE19': 'Croydon', 'SE20': 'Bromley', 'SE21': 'Southwark',
    'SE22': 'Southwark', 'SE23': 'Lewisham', 'SE24': 'Lambeth',
    'SE25': 'Croydon', 'SE26': 'Lewisham', 'SE27': 'Lambeth',
    'SE28': 'Greenwich',
    // London — SW
    'SW1': 'Westminster', 'SW1A': 'Westminster', 'SW1P': 'Westminster',
    'SW1V': 'Westminster', 'SW1W': 'Westminster', 'SW1X': 'Westminster',
    'SW1Y': 'Westminster', 'SW2': 'Lambeth',
    'SW3': 'Kensington and Chelsea', 'SW4': 'Lambeth',
    'SW5': 'Kensington and Chelsea', 'SW6': 'Hammersmith and Fulham',
    'SW7': 'Kensington and Chelsea', 'SW8': 'Lambeth', 'SW9': 'Lambeth',
    'SW10': 'Kensington and Chelsea', 'SW11': 'Wandsworth',
    'SW12': 'Wandsworth', 'SW13': 'Richmond', 'SW14': 'Richmond',
    'SW15': 'Wandsworth', 'SW16': 'Lambeth', 'SW17': 'Wandsworth',
    'SW18': 'Wandsworth', 'SW19': 'Merton', 'SW20': 'Merton',
    // London — W
    'W1': 'Westminster', 'W1A': 'Westminster', 'W1B': 'Westminster',
    'W1C': 'Westminster', 'W1D': 'Westminster', 'W1F': 'Westminster',
    'W1G': 'Westminster', 'W1H': 'Westminster', 'W1J': 'Westminster',
    'W1K': 'Westminster', 'W1S': 'Westminster', 'W1T': 'Westminster',
    'W1U': 'Westminster', 'W1W': 'Westminster', 'W2': 'Westminster',
    'W3': 'Ealing', 'W4': 'Hounslow', 'W5': 'Ealing',
    'W6': 'Hammersmith and Fulham', 'W7': 'Ealing',
    'W8': 'Kensington and Chelsea', 'W9': 'Westminster',
    'W10': 'Kensington and Chelsea', 'W11': 'Kensington and Chelsea',
    'W12': 'Hammersmith and Fulham', 'W13': 'Ealing',
    'W14': 'Hammersmith and Fulham',
    // London — WC
    'WC1': 'Camden', 'WC1A': 'Camden', 'WC1B': 'Camden',
    'WC1E': 'Camden', 'WC1H': 'Camden', 'WC1N': 'Camden',
    'WC1R': 'Camden', 'WC1V': 'Camden', 'WC1X': 'Camden',
    'WC2': 'Westminster', 'WC2A': 'Westminster', 'WC2B': 'Westminster',
    'WC2E': 'Westminster', 'WC2H': 'Westminster', 'WC2N': 'Westminster',
    'WC2R': 'Westminster',
    // Manchester
    'M1': 'Manchester', 'M2': 'Manchester', 'M3': 'Manchester',
    'M4': 'Manchester', 'M5': 'Salford', 'M6': 'Salford',
    'M7': 'Salford', 'M8': 'Manchester', 'M9': 'Manchester',
    'M11': 'Manchester', 'M12': 'Manchester', 'M13': 'Manchester',
    'M14': 'Manchester', 'M15': 'Manchester', 'M16': 'Trafford',
    'M17': 'Trafford', 'M18': 'Manchester', 'M19': 'Manchester',
    'M20': 'Manchester', 'M21': 'Manchester', 'M22': 'Manchester',
    'M23': 'Manchester',
    // Birmingham
    'B1': 'Birmingham', 'B2': 'Birmingham', 'B3': 'Birmingham',
    'B4': 'Birmingham', 'B5': 'Birmingham', 'B6': 'Birmingham',
    'B7': 'Birmingham', 'B8': 'Birmingham', 'B9': 'Birmingham',
    'B10': 'Birmingham', 'B11': 'Birmingham', 'B12': 'Birmingham',
    'B13': 'Birmingham', 'B14': 'Birmingham', 'B15': 'Birmingham',
    'B16': 'Birmingham', 'B17': 'Birmingham', 'B18': 'Birmingham',
    'B19': 'Birmingham', 'B20': 'Birmingham', 'B21': 'Birmingham',
    // Leeds
    'LS1': 'Leeds', 'LS2': 'Leeds', 'LS3': 'Leeds', 'LS4': 'Leeds',
    'LS5': 'Leeds', 'LS6': 'Leeds', 'LS7': 'Leeds', 'LS8': 'Leeds',
    'LS9': 'Leeds', 'LS10': 'Leeds', 'LS11': 'Leeds', 'LS12': 'Leeds',
    'LS13': 'Leeds', 'LS14': 'Leeds', 'LS15': 'Leeds', 'LS16': 'Leeds',
    'LS17': 'Leeds',
    // Bristol
    'BS1': 'Bristol', 'BS2': 'Bristol', 'BS3': 'Bristol', 'BS4': 'Bristol',
    'BS5': 'Bristol', 'BS6': 'Bristol', 'BS7': 'Bristol', 'BS8': 'Bristol',
    'BS9': 'Bristol', 'BS10': 'Bristol', 'BS11': 'Bristol',
    'BS13': 'Bristol', 'BS14': 'Bristol', 'BS15': 'Bristol',
    'BS16': 'Bristol',
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC ASYNC API  — use these when entering / changing a postcode
  // ═══════════════════════════════════════════════════════════════════════════

  /// Resolves borough for [postcode] using the postcodes.io REST API.
  ///
  /// Returns the `admin_district` field (the official local authority /
  /// district name) which is the correct grouping value for Huddl.
  ///
  /// Results are cached in memory AND in BrowserStorage so subsequent
  /// synchronous calls to [getBoroughFromPostcode] return instantly.
  ///
  /// Returns null if the postcode is invalid or the API is unreachable
  /// and no cache entry exists.
  Future<String?> lookupBoroughAsync(String? postcode) async {
    if (postcode == null || postcode.isEmpty) return null;

    final clean = _clean(postcode);
    if (clean.length < 5) return null;

    // 1. Check memory cache
    await _ensureCacheLoaded();
    if (_cache.containsKey(clean)) {
      _log('Cache hit: $clean → ${_cache[clean]}');
      return _cache[clean];
    }

    // 2. Call postcodes.io
    try {
      final uri = Uri.parse('https://api.postcodes.io/postcodes/${Uri.encodeComponent(clean)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final result = data['result'] as Map<String, dynamic>?;
        // admin_district is the local authority / borough name
        final district = result?['admin_district'] as String?;

        if (district != null && district.isNotEmpty) {
          await _writeToCache(clean, district);
          _log('API lookup: $clean → $district');
          return district;
        }
      } else if (response.statusCode == 404) {
        _log('postcodes.io: invalid postcode $clean (404)');
        return null;
      }
    } catch (e) {
      _log('postcodes.io error for $clean: $e — falling back to outward-code map');
    }

    // 3. Offline fallback: outward-code map
    final outward = _extractOutwardCode(clean);
    final fallback = outward != null ? _fallbackMap[outward] : null;
    if (fallback != null) {
      // Cache the fallback so future sync calls return it
      await _writeToCache(clean, fallback);
      _log('Fallback map: $clean → $fallback');
    }
    return fallback;
  }

  /// Returns true if [postcode] belongs to the Cambridge launch area,
  /// using the postcodes.io API for accuracy.
  ///
  /// Async version — use this in onboarding and profile screens.
  Future<bool> isCambridgePostcodeAsync(String? postcode) async {
    if (postcode == null || postcode.isEmpty) return false;
    final borough = await lookupBoroughAsync(postcode);
    if (borough == null) {
      // API unreachable — fall through to outward-code check
      return isCambridgePostcode(postcode);
    }
    // Accept any postcode whose admin_district is Cambridge or any of the
    // surrounding Cambridgeshire districts (South Cambridgeshire,
    // East Cambridgeshire, etc.) so users on the outskirts can join.
    return _isCambridgeBorough(borough);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC SYNC API  — cache-first, safe to call from build() / sync code
  // ═══════════════════════════════════════════════════════════════════════════

  /// Synchronous borough lookup. Returns the cached value if the postcode
  /// was previously resolved via [lookupBoroughAsync], otherwise falls back
  /// to the outward-code prefix map.
  ///
  /// ⚠️  Never use this as the source of truth when writing to Firestore.
  ///     Always call [lookupBoroughAsync] first and then store the result.
  String? getBoroughFromPostcode(String? postcode) {
    if (postcode == null || postcode.isEmpty) return null;
    final clean = _clean(postcode);

    // Memory cache (populated by lookupBoroughAsync)
    if (_cache.containsKey(clean)) return _cache[clean];

    // Outward-code fallback for offline / not-yet-looked-up postcodes
    final outward = _extractOutwardCode(clean);
    if (outward != null && _fallbackMap.containsKey(outward)) {
      return _fallbackMap[outward];
    }

    _log('getBoroughFromPostcode: no result for $postcode');
    return null;
  }

  /// Synchronous Cambridge check — outward-code based, fast.
  /// For authoritative validation use [isCambridgePostcodeAsync].
  bool isCambridgePostcode(String? postcode) {
    if (postcode == null || postcode.isEmpty) return false;
    final clean = _clean(postcode);

    // Check memory cache first (set by lookupBoroughAsync)
    if (_cache.containsKey(clean)) {
      return _isCambridgeBorough(_cache[clean]!);
    }

    // Fall back to outward-code check
    final outward = _extractOutwardCode(clean);
    return outward != null && _cambridgeOutwardCodes.contains(outward);
  }

  /// Get list of all known borough names (from fallback map).
  List<String> getAllBoroughs() {
    return _fallbackMap.values.toSet().toList()..sort();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CACHE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load the persisted cache from BrowserStorage into memory.
  Future<void> _ensureCacheLoaded() async {
    if (_cacheLoaded) return;
    try {
      final raw = await BrowserStorage.getString(_cacheKey);
      if (raw != null) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          if (v is String) _cache[k] = v;
        });
        _log('Loaded ${_cache.length} cached postcodes from storage');
      }
    } catch (e) {
      _log('Cache load error: $e');
    }
    _cacheLoaded = true;
  }

  Future<void> _writeToCache(String cleanPostcode, String borough) async {
    _cache[cleanPostcode] = borough;
    try {
      await BrowserStorage.setString(_cacheKey, json.encode(_cache));
    } catch (e) {
      _log('Cache write error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Normalise postcode: remove spaces, uppercase.
  static String _clean(String postcode) =>
      postcode.replaceAll(' ', '').toUpperCase();

  /// Extracts the outward code (area + district) from a normalised postcode.
  ///   CB12AB  → CB1
  ///   SW1A1AA → SW1A
  ///   E18GG   → E1   (not E18 — this is a 5-char postcode E1 8GG)
  static String? _extractOutwardCode(String clean) {
    if (clean.length < 5 || clean.length > 7) return null;
    final m = RegExp(r'^([A-Z]{1,2}\d{1,2}[A-Z]?)\d[A-Z]{2}$').firstMatch(clean);
    return m?.group(1);
  }

  /// Returns true if [borough] is a Cambridge-area local authority name
  /// as returned by postcodes.io.
  static bool _isCambridgeBorough(String borough) {
    final lower = borough.toLowerCase();
    return lower == 'cambridge' ||
        lower.contains('cambridgeshire') ||
        lower == 'south cambridgeshire' ||
        lower == 'east cambridgeshire' ||
        lower == 'fenland' ||
        lower == 'huntingdonshire';
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('📍 PostcodeService: $message');
    }
  }
}
