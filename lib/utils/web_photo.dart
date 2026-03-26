// web_photo.dart
// Platform-safe web photo utility – creates an object URL from raw bytes.
// On web the URL is fed to <img> elements; on other platforms it's unused.

import 'dart:typed_data';

/// Creates an object URL from [bytes] suitable for displaying in a web img.
/// On non-web platforms this is a no-op stub that returns an empty string.
String createObjectUrlFromBytes(Uint8List bytes) {
  // Non-web stub – actual web implementation would call
  // html.Url.createObjectUrlFromBlob(html.Blob([bytes]))
  // but dart:html is unavailable on mobile/desktop.
  return '';
}

/// Revokes a previously-created object URL to free memory.
void revokeObjectUrl(String url) {
  // Stub – no-op on non-web platforms.
}
