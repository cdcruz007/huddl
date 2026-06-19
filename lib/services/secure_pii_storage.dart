import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// =============================================================================
// SECURE PII STORAGE  —  ONBOARD-1
//
// Platform-aware wrapper for sensitive PII at rest.
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │  PLATFORM BEHAVIOUR                                                     │
// ├─────────────────────────────────────────────────────────────────────────┤
// │  MOBILE (iOS / Android)                                                 │
// │    Uses FlutterSecureStorage backed by iOS Keychain / Android Keystore. │
// │    Data is hardware-encrypted at rest and inaccessible without the OS   │
// │    key. On Android, the entry is further guarded by the secure enclave  │
// │    if available.                                                         │
// │                                                                         │
// │  WEB (kIsWeb == true)                                                   │
// │    Sensitive PII is NOT written to localStorage at all. There is no     │
// │    secure client-side storage on the web: any JS key stored in          │
// │    localStorage, sessionStorage, or IndexedDB is extractable from the   │
// │    browser's DevTools by the user or any XSS payload. Encoding/         │
// │    obfuscation is not encryption and provides no meaningful protection. │
// │                                                                         │
// │    On web the in-memory map (_webMemoryStore) is the sole store for     │
// │    the current session. It is lost on cold start — sensitive fields are │
// │    re-hydrated from Firestore by                                        │
// │    FirebaseAuthService.restoreProfileFromFirestore() which already runs │
// │    on every authenticated cold start (see firebase_auth_service.dart).  │
// └─────────────────────────────────────────────────────────────────────────┘
//
// API:
//   Future<void>               writePii(Map<String,dynamic> data)
//   Future<Map<String,dynamic>> readPii()
//   Future<void>               clearPii()
//
// Storage key: 'onboarding_pii_v1' (single JSON blob, one read/write cycle)
// =============================================================================

class SecurePiiStorage {
  SecurePiiStorage._();

  // ── Storage key ────────────────────────────────────────────────────────────
  static const String _key = 'onboarding_pii_v1';

  // ── Mobile: FlutterSecureStorage instance (lazy, shared) ──────────────────
  // aOptions: resetOnError → if the Keystore entry is corrupted (e.g. after
  // a factory reset or debug-build key rotation), clear and start fresh rather
  // than crashing. Data loss is acceptable here because Firestore is the SoT.
  static const FlutterSecureStorage _ss = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // ── Web: in-memory store only ──────────────────────────────────────────────
  // Static so the single instance survives for the lifetime of the JS isolate.
  // Lost on page reload — that is intentional (see header comment above).
  static Map<String, dynamic> _webMemoryStore = {};

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Persist [data] securely.
  ///
  /// On mobile: serialises to JSON and writes to Keychain/Keystore.
  /// On web:    stores in the in-memory map only — nothing touches localStorage.
  static Future<void> writePii(Map<String, dynamic> data) async {
    if (kIsWeb) {
      // Web: memory only — no localStorage write
      _webMemoryStore = Map<String, dynamic>.from(data);
      return;
    }
    // Mobile: Keychain / Keystore
    try {
      await _ss.write(key: _key, value: json.encode(data));
    } catch (e) {
      if (kDebugMode) debugPrint('[SecurePiiStorage] write error: $e');
      // Non-fatal — in-memory state in OnboardingDataService still holds data
    }
  }

  /// Read the stored PII map.
  ///
  /// On mobile: deserialises from Keychain/Keystore. Returns {} on any error.
  /// On web:    returns the current in-memory map (empty after page reload).
  static Future<Map<String, dynamic>> readPii() async {
    if (kIsWeb) {
      return Map<String, dynamic>.from(_webMemoryStore);
    }
    try {
      final raw = await _ss.read(key: _key);
      if (raw == null || raw.isEmpty) return {};
      return (json.decode(raw) as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) debugPrint('[SecurePiiStorage] read error: $e');
      return {};
    }
  }

  /// Delete the stored PII entry.
  ///
  /// On mobile: removes the Keychain/Keystore entry.
  /// On web:    clears the in-memory map.
  static Future<void> clearPii() async {
    if (kIsWeb) {
      _webMemoryStore = {};
      return;
    }
    try {
      await _ss.delete(key: _key);
    } catch (e) {
      if (kDebugMode) debugPrint('[SecurePiiStorage] clear error: $e');
    }
  }
}
