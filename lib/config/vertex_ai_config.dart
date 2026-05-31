import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// =============================================================================
// VERTEX AI CONFIG — huddl-uk-parenting-assistant (Gemini 2.5 fine-tuned)
//
// Project:   huddl-connect  (879152141283)
// Region:    europe-west4 (Netherlands)
// Model ID:  627673804901974016  (version @1)
// Auth:      Service account OAuth 2.0  (huddl-vertex-ai@huddl-connect.iam.gserviceaccount.com)
//
// The fine-tuned model is called via the Vertex AI generateContent endpoint —
// identical request/response shape to the Gemini AI Studio API, just a
// different base URL and Bearer-token auth instead of an API key.
// =============================================================================

class VertexAiConfig {
  VertexAiConfig._();

  // ── Project & model identifiers ───────────────────────────────────────
  static const String projectId     = 'huddl-connect';
  static const String projectNumber = '879152141283';
  static const String location      = 'europe-west4';
  static const String modelId       = '627673804901974016';
  static const String modelVersion  = '1';

  // ── Endpoint (Vertex AI generateContent — tuned Gemini model via project resource path) ──
  // Vertex AI Studio fine-tuned models are served under the project's model
  // resource path, NOT the publishers/google path used for base models.
  // Correct format: /v1/projects/{project}/locations/{region}/models/{modelId}@{version}:generateContent
  static String get generateContentUrl =>
      'https://$location-aiplatform.googleapis.com/v1/projects/$projectNumber'
      '/locations/$location/models/'
      '$modelId@$modelVersion:generateContent';

  // ── Service Account credentials (for OAuth 2.0 token exchange) ────────
  // These are the credentials for:
  //   huddl-vertex-ai@huddl-connect.iam.gserviceaccount.com
  // Role granted: Vertex AI User
  static const String _saEmail      = 'huddl-vertex-ai@huddl-connect.iam.gserviceaccount.com';
  static const String _saKeyId      = 'f1b8d8c2610e0cfcd9f5dc377d98ff8e06c283a5';
  static const String _saPrivateKey =
      '-----BEGIN PRIVATE KEY-----\n'
      'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDDkfCyyeGnGdWL\n'
      'YAOzjY0okD0FWuPt2xandscvetMDNgFIRWFAOhCZq3K008/s8NMh+01xWfzHDsFu\n'
      'uByrt/2kqbMyrlfxLSrzPsoKH89y2agrVZ5CIk7PMK0kLyw7Qt+FC40nNWdEeFiB\n'
      'LPLT+cMpQkOI4TSX842Ntl2Nk48NzN2sDDHdkvCQ/+KgioySLkpDXLgarLwgqQ9S\n'
      'LLQt3ezMLHq6U0e/rjRZIhMJNsnPnEW7P0LIZE6DOzkwqjAXQmmfVJwO5T358mn1\n'
      'tx44rTY5LCv1mRohzmsbo7Zb548S0sbakaDabmWlRgSF8c3y2mAR+z90Amk8hrAC\n'
      '0XLBQ2pNAgMBAAECggEAGbyMaPLhU7y2GfveMNRZdbOZnClMYoJY9lvOtaRbvYnv\n'
      'XEPpGuspQRfLZhmTvNIqbsfj9p1JgyahdQEcoMp7Qh6k+u/vmckAZHdoXjG2ep5D\n'
      'H8TKKVjbdy+oMWFV2EyiHp+ZCUZhWyTdPM6d/CBbuwPB4HMGmVKPV81efWGkS0Pm\n'
      'J3JwMQYtshccFgfmQNCS84r2Mu8gKlUw5sTT8VK4O5ooFZ4tz7K7L+tNJKe1lCRP\n'
      '8+OE7f3YHVFw4sMcDNIR+l4AzMbgTefG0nvvh+9YeYXBgBDjAl1GrTU2qT4K6mDs\n'
      'Z4RizKuMSbv2qTbZxYKhKMuHM2fbHAKx6VWUN8mNrwKBgQDjvbxaEAwTths6y4+F\n'
      'ODjmis53jVI94fUF1tzqu/hBUPDpw4gV4xutKahrUz6eb/JXhpWIBOa/aZ+HJAHo\n'
      '9A0dIe0til4+1ui7D6BnkHa0GZg2ZAgGIhITlNALmt/mIDXRArcBRYzw+BE3QTgg\n'
      '9V1inj2e+qLnQig6en6da3FvgwKBgQDb1kfmEQtcTiwkPlrwxW44e/2GrlnpT/QK\n'
      'jSyIPfKBi3UpDQxOZ8Tb2fWMs2Bk2Br1yKIMDMT1P7RbHfo5GX+SQuZOZHq8NV1W\n'
      'b6GsZ84DLHBLarNJEINOFoZgbe05AEWjxZNYakpP0SFCPlA+GV0ICUrX4RGLkc1P\n'
      '6JmrhBpF7wKBgFVN6JNDl4J6n9ByFxwrZwTT0WpugPO1A3ZgePdj2SV+D/8/wmWQ\n'
      'X/mItREeaUInZHrsam48h8IC6kJQdnavk4np/1EjlxGqphoLTGX+crgbLiyRY4AI\n'
      'mwTCpPrz1BH61q2neqz7REOuZ6RuxXty7LvX0fUOpJ5C5Zah83M7n43JAoGAZMT3\n'
      'li0v8PLgZwiyNPW7DWdAknDvQ/RjYEbQJ++Fbv5XCSczAemtIj3pwcIjqHYq/Ykn\n'
      'RrC/w8+cw7udDHl0sb26xipm3Ej17P4ktNusYmYHX3qcjhxko/HNTPx2pg9K3MRf\n'
      'Q0MNp0KspSndLGoB7AIebZB8s2Z1H3D2p9lZFb8CgYEAy/8Qjm7x7hq1QUt1e2pH\n'
      'j8/B2nnp4y8J6B6GvV3rHdy2212X8ZhGgtNv+oI+8pebRmKmVBElGKtz8bJ/cq/m\n'
      'lc8lF+8YeCKwby2T4d2hJyTq2lNdSnXDUDT2RZhGE0o5T4/NQdzmMrChGvVHA8zW\n'
      'gtg5nBjsEXi1z7vWxGTv//A=\n'
      '-----END PRIVATE KEY-----\n';

  static const String _tokenUri  = 'https://oauth2.googleapis.com/token';
  static const String _scope     = 'https://www.googleapis.com/auth/cloud-platform';

  // ── Token cache ───────────────────────────────────────────────────────
  static String? _cachedToken;
  static DateTime? _tokenExpiry;

  /// Returns a valid Bearer token, refreshing from Google OAuth if needed.
  /// Uses RS256 JWT signed with the service account private key.
  static Future<String> getBearerToken() async {
    // Return cached token if still valid (with 60s buffer)
    if (_cachedToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(seconds: 60)))) {
      return _cachedToken!;
    }

    // Build JWT header + payload
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final header = base64Url.encode(utf8.encode(jsonEncode({
      'alg': 'RS256',
      'typ': 'JWT',
      'kid': _saKeyId,
    }))).replaceAll('=', '');

    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'iss': _saEmail,
      'scope': _scope,
      'aud': _tokenUri,
      'iat': now,
      'exp': now + 3600,
    }))).replaceAll('=', '');

    final signingInput = '$header.$payload';

    // Sign with RSA-SHA256 using the private key
    final signature = await _rsaSign(signingInput, _saPrivateKey);
    final jwt = '$signingInput.$signature';

    // Exchange JWT for access token
    final response = await http.post(
      Uri.parse(_tokenUri),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': jwt,
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
          'VertexAiConfig: token exchange failed (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _cachedToken = data['access_token'] as String;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

    if (kDebugMode) {
      debugPrint('VertexAiConfig: OAuth token refreshed, expires in ${expiresIn}s');
    }

    return _cachedToken!;
  }

  /// Force-clear the cached token (e.g. on 401 response).
  static void invalidateToken() {
    _cachedToken = null;
    _tokenExpiry = null;
  }

  // ── RSA-SHA256 signing (pure Dart — no native plugin needed) ─────────
  // Uses dart:math BigInteger arithmetic for RSA PKCS#1 v1.5 signing.
  static Future<String> _rsaSign(String input, String pemKey) async {
    // Import pointycastle for RSA signing
    // We use the platform's crypto via a manual approach compatible with
    // Flutter Web (dart:html crypto) and mobile (dart:io).
    // For simplicity and web compatibility, we call a helper.
    return _signJwtRS256(input, pemKey);
  }

  static String _signJwtRS256(String signingInput, String pem) {
    // Extract the base64 DER content from PEM
    final pemLines = pem
        .split('\n')
        .where((l) => !l.startsWith('-----'))
        .join();
    final derBytes = base64.decode(pemLines);

    // Parse PKCS#8 DER to get RSA private key components
    final key = _parsePrivateKey(derBytes);

    // SHA-256 hash of the signing input
    final inputBytes = utf8.encode(signingInput);
    final hash = _sha256(inputBytes);

    // PKCS#1 v1.5 DigestInfo prefix for SHA-256
    final digestInfo = [
      0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86,
      0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05,
      0x00, 0x04, 0x20,
      ...hash,
    ];

    // PKCS#1 v1.5 padding
    final modLen = (key.n.bitLength + 7) ~/ 8;
    final padded = <int>[0x00, 0x01];
    final padLen = modLen - digestInfo.length - 3;
    padded.addAll(List.filled(padLen, 0xff));
    padded.add(0x00);
    padded.addAll(digestInfo);

    // RSA private key operation: sig = padded^d mod n
    final m = _bytesToBigInt(padded);
    final sigInt = _modPow(m, key.d, key.n);
    final sigBytes = _bigIntToBytes(sigInt, modLen);

    return base64Url.encode(sigBytes).replaceAll('=', '');
  }

  // ── Minimal SHA-256 (pure Dart) ───────────────────────────────────────
  static List<int> _sha256(List<int> data) {
    // Initial hash values (first 32 bits of fractional parts of sqrt of primes)
    var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

    // Round constants
    const k = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
      0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
      0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
      0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
      0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
      0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];

    // Pre-processing: adding padding bits
    final msgLen = data.length;
    final bitLen = msgLen * 8;
    final padded = [...data, 0x80];
    while (padded.length % 64 != 56) { padded.add(0); }
    // Append bit length as 64-bit big-endian
    for (var i = 7; i >= 0; i--) {
      padded.add((bitLen >> (i * 8)) & 0xff);
    }

    // Process each 512-bit (64-byte) chunk
    for (var chunk = 0; chunk < padded.length; chunk += 64) {
      final w = List<int>.filled(64, 0);
      for (var i = 0; i < 16; i++) {
        w[i] = (padded[chunk + i * 4] << 24) |
               (padded[chunk + i * 4 + 1] << 16) |
               (padded[chunk + i * 4 + 2] << 8) |
               padded[chunk + i * 4 + 3];
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (_add32(w[i - 16], s0) + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0, b = h1, c = h2, d = h3;
      var e = h4, f = h5, g = h6, h = h7;

      for (var i = 0; i < 64; i++) {
        final s1   = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch   = (e & f) ^ ((~e & 0xffffffff) & g);
        final temp1 = _add32(h, _add32(s1, _add32(ch, _add32(k[i], w[i]))));
        final s0   = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj  = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = _add32(s0, maj);

        h = g; g = f; f = e;
        e = _add32(d, temp1);
        d = c; c = b; b = a;
        a = _add32(temp1, temp2);
      }

      h0 = _add32(h0, a); h1 = _add32(h1, b);
      h2 = _add32(h2, c); h3 = _add32(h3, d);
      h4 = _add32(h4, e); h5 = _add32(h5, f);
      h6 = _add32(h6, g); h7 = _add32(h7, h);
    }

    final digest = <int>[];
    for (final v in [h0, h1, h2, h3, h4, h5, h6, h7]) {
      digest.addAll([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
    }
    return digest;
  }

  static int _rotr(int x, int n) =>
      ((x >>> n) | (x << (32 - n))) & 0xffffffff;

  static int _add32(int a, int b) => (a + b) & 0xffffffff;

  // ── BigInt RSA helpers ────────────────────────────────────────────────
  static BigInt _bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }

    return result;
  }

  static List<int> _bigIntToBytes(BigInt n, int length) {
    final bytes = <int>[];
    var v = n;
    while (v > BigInt.zero) {
      bytes.insert(0, (v & BigInt.from(0xff)).toInt());
      v >>= 8;
    }
    while (bytes.length < length) { bytes.insert(0, 0); }
    return bytes;
  }

  static BigInt _modPow(BigInt base, BigInt exp, BigInt mod) =>
      base.modPow(exp, mod);

  // ── Minimal PKCS#8 DER parser to extract RSA key components ──────────
  static ({BigInt n, BigInt d}) _parsePrivateKey(List<int> der) {
    // PKCS#8 wraps the RSA key in a PrivateKeyInfo structure.
    // We skip the outer SEQUENCE and AlgorithmIdentifier to get RSAPrivateKey.
    var pos = 0;

    // Helper: read a DER length
    int readLength() {
      if (der[pos] < 0x80) return der[pos++];
      final numBytes = der[pos++] & 0x7f;
      var len = 0;
      for (var i = 0; i < numBytes; i++) { len = (len << 8) | der[pos++]; }
      return len;
    }

    // Helper: skip a DER TLV
    void skipTlv() {
      pos++; // tag
      final len = readLength();
      pos += len;
    }

    // Helper: read a DER INTEGER as BigInt
    BigInt readInt() {
      if (der[pos++] != 0x02) throw Exception('Expected INTEGER tag');
      final len = readLength();
      var bytes = der.sublist(pos, pos + len);
      pos += len;
      // Strip leading zero byte used to indicate positive number
      if (bytes.isNotEmpty && bytes[0] == 0) bytes = bytes.sublist(1);
      return _bytesToBigInt(bytes);
    }

    // SEQUENCE (outer PrivateKeyInfo or RSAPrivateKey)
    if (der[pos] == 0x30) {
      pos++;
      readLength();
    }

    // If this is PKCS#8 (PrivateKeyInfo), skip version + AlgorithmIdentifier
    // PKCS#8 starts with INTEGER version=0, then AlgorithmIdentifier SEQUENCE
    if (der[pos] == 0x02) {
      // version INTEGER
      readInt(); // skip
      // AlgorithmIdentifier SEQUENCE
      if (der[pos] == 0x30) skipTlv();
      // OCTET STRING wrapping RSAPrivateKey
      if (der[pos] == 0x04) {
        pos++;
        readLength();
        // Inner SEQUENCE (RSAPrivateKey)
        if (der[pos] == 0x30) {
          pos++;
          readLength();
        }
      }
    }

    // Now parse RSAPrivateKey SEQUENCE: version, n, e, d, p, q, dp, dq, qInv
    readInt(); // version (skip)
    final n = readInt(); // modulus
    readInt(); // publicExponent (skip)
    final d = readInt(); // privateExponent

    return (n: n, d: d);
  }

  // ── Connectivity check ────────────────────────────────────────────────
  static bool _validated = false;
  static bool _isValid   = false;

  static bool get wasValidated => _validated;
  static bool get isKeyValid   => _isValid;

  /// Lightweight check that our service account can reach the Vertex AI API.
  static Future<bool> validateCredentials() async {
    if (_validated) return _isValid;
    try {
      await getBearerToken();
      _validated = true;
      _isValid   = true;
      if (kDebugMode) {
        if (kDebugMode) debugPrint('VertexAiConfig: credentials valid ✅');
      }
    } catch (e) {
      _validated = true;
      _isValid   = false;
      if (kDebugMode) debugPrint('VertexAiConfig: credential validation failed: $e');
    }
    return _isValid;
  }

  static void resetValidation() {
    _validated = false;
    _isValid   = false;
    invalidateToken();
  }
}
