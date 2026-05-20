// ── LocationService ──────────────────────────────────────────────────────────
// Singleton that wraps `geolocator` for the distance-filter feature.
//
// Responsibilities:
//  • Check / request location permission (Android + iOS)
//  • Acquire the user's current GPS position (cached for the session)
//  • Expose the permission status so the UI can show graceful-degradation copy
//  • Handle the "deniedForever" path by opening App Settings
//
// Platform notes:
//  • Android: ACCESS_FINE_LOCATION + ACCESS_COARSE_LOCATION already in manifest
//  • iOS: NSLocationWhenInUseUsageDescription already in Info.plist
//  • Web: geolocator uses browser Geolocation API — handled identically
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Outcome of a location-fetch attempt.
enum LocationStatus {
  /// Position acquired successfully.
  success,
  /// User denied the permission prompt (can ask again later).
  permissionDenied,
  /// User tapped "Never" / "Don't ask again" (must open Settings).
  permissionDeniedForever,
  /// Device has GPS disabled in system settings.
  serviceDisabled,
  /// Any other error (timeout, unexpected exception, etc.).
  error,
}

class LocationResult {
  final LocationStatus status;
  final Position? position;
  final String? errorMessage;

  const LocationResult._({
    required this.status,
    this.position,
    this.errorMessage,
  });

  factory LocationResult.success(Position pos) =>
      LocationResult._(status: LocationStatus.success, position: pos);

  factory LocationResult.denied() =>
      LocationResult._(status: LocationStatus.permissionDenied);

  factory LocationResult.deniedForever() =>
      LocationResult._(status: LocationStatus.permissionDeniedForever);

  factory LocationResult.serviceDisabled() =>
      LocationResult._(status: LocationStatus.serviceDisabled);

  factory LocationResult.error(String msg) =>
      LocationResult._(status: LocationStatus.error, errorMessage: msg);

  bool get hasPosition => position != null;
}

class LocationService {
  // ── Singleton ──────────────────────────────────────────────────
  LocationService._internal();
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;

  // ── Cached position (valid for the current app session) ────────
  Position? _cachedPosition;
  DateTime? _cacheTime;

  // Cache TTL: re-fetch if older than 5 minutes
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// Returns a cached position if still fresh, otherwise fetches a new one.
  Position? get cachedPosition {
    if (_cachedPosition == null || _cacheTime == null) return null;
    if (DateTime.now().difference(_cacheTime!) > _cacheTtl) return null;
    return _cachedPosition;
  }

  // ── Last known permission status ────────────────────────────────
  LocationStatus? _lastStatus;
  LocationStatus? get lastStatus => _lastStatus;

  /// True when the user's position is known and fresh.
  bool get hasPosition => cachedPosition != null;

  // ── Core method: get user position with full permission flow ────
  /// Requests permission if needed, fetches GPS position, caches it.
  /// Never throws — all errors are surfaced as [LocationResult].
  Future<LocationResult> getUserPosition({bool forceRefresh = false}) async {
    // Return cache if fresh and not forced
    if (!forceRefresh && cachedPosition != null) {
      return LocationResult.success(cachedPosition!);
    }

    try {
      // 1. Check if location services are enabled at OS level
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _lastStatus = LocationStatus.serviceDisabled;
        return LocationResult.serviceDisabled();
      }

      // 2. Check current permission state
      LocationPermission permission = await Geolocator.checkPermission();

      // 3. Request if not yet granted
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // 4. Handle denied outcomes
      if (permission == LocationPermission.denied) {
        _lastStatus = LocationStatus.permissionDenied;
        return LocationResult.denied();
      }
      if (permission == LocationPermission.deniedForever) {
        _lastStatus = LocationStatus.permissionDeniedForever;
        return LocationResult.deniedForever();
      }

      // 5. Fetch position (whileInUse / always both work here)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // medium accuracy is fine for km-scale filtering
        timeLimit: const Duration(seconds: 15),
      );

      // 6. Cache and return
      _cachedPosition = position;
      _cacheTime = DateTime.now();
      _lastStatus = LocationStatus.success;

      if (kDebugMode) {
        debugPrint('[LocationService] Got position: '
            '${position.latitude.toStringAsFixed(4)}, '
            '${position.longitude.toStringAsFixed(4)}');
      }

      return LocationResult.success(position);
    } on LocationServiceDisabledException {
      _lastStatus = LocationStatus.serviceDisabled;
      return LocationResult.serviceDisabled();
    } catch (e) {
      _lastStatus = LocationStatus.error;
      if (kDebugMode) debugPrint('[LocationService] Error: $e');
      return LocationResult.error(e.toString());
    }
  }

  /// Opens the device's app settings page so the user can re-enable location.
  /// Call this when [lastStatus] == [LocationStatus.permissionDeniedForever].
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Clears the cached position (useful when logging out or in tests).
  void clearCache() {
    _cachedPosition = null;
    _cacheTime = null;
    _lastStatus = null;
  }

  // ── Convenience: calculate straight-line distance in km ────────
  /// Returns km between [userPosition] and the given lat/lng.
  static double distanceInKm(
    Position userPosition,
    double targetLat,
    double targetLng,
  ) {
    final metres = Geolocator.distanceBetween(
      userPosition.latitude,
      userPosition.longitude,
      targetLat,
      targetLng,
    );
    return metres / 1000.0;
  }
}
