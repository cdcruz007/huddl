// ── GeocodingService ──────────────────────────────────────────────────────────
// Singleton that converts human-readable address strings → lat/lng coordinates
// using the Google Geocoding API (same key as Places Autocomplete).
//
// Features:
//  • In-memory LRU-style cache (max 200 entries) — avoids repeat API calls for
//    the same address string during a session.
//  • Returns null for "Online" meetups or addresses that cannot be resolved.
//  • Fails silently in the filter pipeline (unresolved = included in results).
//  • UK-biased results (region=gb) since Huddl is a UK-focused app.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Lat/lng pair returned by [GeocodingService].
class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
}

class GeocodingService {
  // ── Singleton ──────────────────────────────────────────────────
  GeocodingService._internal();
  static final GeocodingService _instance = GeocodingService._internal();
  factory GeocodingService() => _instance;

  // ── Google Places / Geocoding API key ─────────────────────────
  // Sourced from --dart-define=GOOGLE_PLACES_API_KEY=AIza... at build time.
  // SECURITY: Rotate the key via Google Cloud Console if previously exposed.
  static const String _apiKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
    defaultValue: '',
  );

  // ── In-memory cache: address string → LatLng? ─────────────────
  // null value means "already tried, could not resolve" — don't retry.
  static const int _maxCacheSize = 200;
  final Map<String, LatLng?> _cache = {};

  /// Resolves [address] to lat/lng.
  ///
  /// Returns null if:
  ///  • The address is "Online" / empty
  ///  • The API returns no results
  ///  • Any network or parsing error occurs
  ///
  /// Results are cached; a previous null result is also cached to avoid
  /// repeated API calls for unresolvable addresses.
  Future<LatLng?> geocode(String address) async {
    final cleaned = address.trim();

    // ── Skip well-known "non-place" values ─────────────────────
    if (cleaned.isEmpty ||
        cleaned.toLowerCase() == 'online' ||
        cleaned.toLowerCase().contains('online event') ||
        cleaned.toLowerCase() == 'tbc' ||
        cleaned.toLowerCase() == 'tbd') {
      return null;
    }

    // ── Return cached result (including cached misses) ──────────
    final cacheKey = cleaned.toLowerCase();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]; // may be null (cached miss)
    }

    // ── Evict oldest entry if cache is full ─────────────────────
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }

    // ── Call Google Geocoding API ───────────────────────────────
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'address': cleaned,
          'region': 'gb',     // UK-bias
          'key': _apiKey,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[GeocodingService] HTTP ${response.statusCode} for "$cleaned"');
        }
        _cache[cacheKey] = null; // cache the miss
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';

      if (status != 'OK') {
        if (kDebugMode) {
          debugPrint('[GeocodingService] status=$status for "$cleaned"');
        }
        _cache[cacheKey] = null;
        return null;
      }

      final results = data['results'] as List<dynamic>;
      if (results.isEmpty) {
        _cache[cacheKey] = null;
        return null;
      }

      final geometry = results[0]['geometry'] as Map<String, dynamic>;
      final location = geometry['location'] as Map<String, dynamic>;
      final lat = (location['lat'] as num).toDouble();
      final lng = (location['lng'] as num).toDouble();

      final latLng = LatLng(lat, lng);
      _cache[cacheKey] = latLng;

      if (kDebugMode) {
        debugPrint('[GeocodingService] "$cleaned" → (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})');
      }

      return latLng;
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[GeocodingService] Error for "$cleaned": $e');
      }
      _cache[cacheKey] = null; // cache the failure so we don't hammer the API
      return null;
    }
  }

  /// Pre-warms the cache for a list of addresses in parallel (fire-and-forget).
  /// Call this when the filter sheet is about to open.
  Future<void> prewarm(Iterable<String> addresses) async {
    final futures = addresses
        .where((a) => a.trim().isNotEmpty)
        .map(geocode)
        .toList();
    await Future.wait(futures, eagerError: false);
  }

  /// Clears the cache (useful when switching users or in tests).
  void clearCache() => _cache.clear();

  /// Returns the number of cached entries (for debugging).
  int get cacheSize => _cache.length;
}
