// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

/// AES-256-GCM field-level encryption for SEND-sensitive Firestore data.
///
/// ## Storage format
/// Every encrypted value is a single base64 string with the layout:
///
///   [ IV (12 bytes) | ciphertext + GCM auth-tag (16 bytes) ]
///
/// The base64 blob is safe to store in a Firestore `String` field.
///
/// ## Key derivation
/// The 256-bit AES key is derived with a single-round HMAC-SHA256:
///
///   key = HMAC-SHA256( secret=SEND_ENCRYPTION_SECRET, data=uid )
///
/// This binds the key to both the build-time secret (supplied via
/// `--dart-define=SEND_ENCRYPTION_SECRET=<hex64>`) and the user's UID,
/// so data from one user is unreadable by another even if the secret leaks.
///
/// ## Graceful degradation
/// If `SEND_ENCRYPTION_SECRET` is not injected at build time the service
/// operates in **passthrough mode**: encrypt returns the plaintext unchanged
/// (base64-encoded) and decrypt reverses that.  A warning is emitted once.
/// This prevents silent data loss during development; in production the secret
/// MUST be provided.
///
/// ## Thread safety
/// The service is a pure-function singleton — all state is derived at call
/// time from [uid].  No mutable instance state.
class SendEncryptionService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final SendEncryptionService _instance =
      SendEncryptionService._internal();
  factory SendEncryptionService() => _instance;
  SendEncryptionService._internal();

  // ── Build-time secret ──────────────────────────────────────────────────────
  /// Injected via `--dart-define=SEND_ENCRYPTION_SECRET=<64-hex-chars>`.
  /// Must be exactly 64 hex characters (= 32 bytes = 256 bits).
  static const String _rawSecret = String.fromEnvironment(
    'SEND_ENCRYPTION_SECRET',
    defaultValue: '',
  );

  static const int _ivLength  = 12; // bytes — GCM recommended IV size
  static const int _tagLength = 16; // bytes — GCM default auth tag

  // ── Warning gate ──────────────────────────────────────────────────────────
  static bool _passthroughWarned = false;

  // ── Key derivation ────────────────────────────────────────────────────────

  /// Derives a 32-byte AES key for [uid] using HMAC-SHA256 of the build-time
  /// secret.  The raw secret is decoded from hex before use.
  Uint8List _deriveKey(String uid) {
    final secretBytes = _hexToBytes(_rawSecret);
    final hmac = Hmac(sha256, secretBytes);
    final digest = hmac.convert(utf8.encode(uid));
    return Uint8List.fromList(digest.bytes);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Encrypts [plaintext] (a String) bound to [uid].
  ///
  /// Returns a base64-encoded blob: `IV || ciphertext+tag`.
  /// In passthrough mode returns `base64(plaintext)`.
  String encrypt(String plaintext, {required String uid}) {
    if (_rawSecret.isEmpty) {
      _warnPassthrough();
      return base64Encode(utf8.encode(plaintext));
    }
    final key    = enc.Key(_deriveKey(uid));
    final iv     = enc.IV(_randomIv());
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    // Layout: [IV (12 bytes)][ciphertext+tag]
    final output = Uint8List(_ivLength + encrypted.bytes.length);
    output.setRange(0, _ivLength, iv.bytes);
    output.setRange(_ivLength, output.length, encrypted.bytes);
    return base64Encode(output);
  }

  /// Decrypts a base64 blob produced by [encrypt].
  ///
  /// Returns the plaintext String, or `null` if:
  ///   - [cipherBlob] is null or empty (field absent from Firestore doc)
  ///   - GCM auth-tag verification fails (data tampered / wrong key)
  ///   - Any other decryption error (logs the error in debug mode)
  ///
  /// In passthrough mode decodes base64 directly.
  String? decrypt(String? cipherBlob, {required String uid}) {
    if (cipherBlob == null || cipherBlob.isEmpty) return null;
    if (_rawSecret.isEmpty) {
      _warnPassthrough();
      try {
        return utf8.decode(base64Decode(cipherBlob));
      } catch (_) {
        return cipherBlob; // already plaintext (pre-encryption legacy data)
      }
    }
    try {
      final bytes = base64Decode(cipherBlob);
      if (bytes.length <= _ivLength + _tagLength) {
        if (kDebugMode) {
          debugPrint('[SendEncryption] decrypt: blob too short — '
              '${bytes.length} bytes (expected > ${_ivLength + _tagLength})');
        }
        return null;
      }
      final iv         = enc.IV(bytes.sublist(0, _ivLength));
      final cipherBytes = bytes.sublist(_ivLength);
      final key        = enc.Key(_deriveKey(uid));
      final encrypter  = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      return encrypter.decrypt(enc.Encrypted(cipherBytes), iv: iv);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SendEncryption] decrypt error (wrong key / tampered data): $e');
      }
      return null;
    }
  }

  /// Encrypts a Map (e.g. a prefs document or deadline object) by converting
  /// it to JSON and then encrypting the resulting string.
  ///
  /// Returns a single-field map `{ '_enc': '<blob>' }` for Firestore storage.
  Map<String, dynamic> encryptMap(
    Map<String, dynamic> plainMap, {
    required String uid,
  }) {
    final json = jsonEncode(plainMap);
    return {'_enc': encrypt(json, uid: uid)};
  }

  /// Decrypts a map produced by [encryptMap].
  ///
  /// Accepts either:
  ///   - `{ '_enc': '<blob>' }` — normal encrypted form
  ///   - A plain map without `_enc` — legacy / pre-encryption data; returned as-is
  ///
  /// Returns `null` if decryption fails.
  Map<String, dynamic>? decryptMap(
    Map<String, dynamic> rawMap, {
    required String uid,
  }) {
    final blob = rawMap['_enc'] as String?;
    if (blob == null) {
      // Legacy plaintext document — return unchanged so callers keep working
      // until a re-encrypt migration runs.
      return rawMap;
    }
    final json = decrypt(blob, uid: uid);
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      if (kDebugMode) debugPrint('[SendEncryption] decryptMap: unexpected JSON type');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[SendEncryption] decryptMap JSON error: $e');
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Uint8List _randomIv() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_ivLength, (_) => rng.nextInt(256)),
    );
  }

  /// Decodes a lowercase/uppercase hex string to bytes.
  /// Pads with a leading zero if the string has odd length.
  static Uint8List _hexToBytes(String hex) {
    if (hex.isEmpty) return Uint8List(32); // zero key — passthrough guard
    final padded = hex.length.isOdd ? '0$hex' : hex;
    final result = Uint8List(padded.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  static void _warnPassthrough() {
    if (_passthroughWarned) return;
    _passthroughWarned = true;
    if (kDebugMode) {
      debugPrint(
        '[SendEncryption] WARNING: SEND_ENCRYPTION_SECRET not set. '
        'Running in passthrough mode — SEND data is NOT encrypted in Firestore. '
        'Provide --dart-define=SEND_ENCRYPTION_SECRET=<64-hex-chars> for production.',
      );
    }
  }
}
