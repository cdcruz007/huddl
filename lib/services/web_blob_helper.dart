// Web-only helper: fetches a blob: URL (from the record package) and returns
// its raw bytes so they can be uploaded to Firebase Storage via putData().
//
// Uses dart:js_interop + package:web (replaces the deprecated dart:html XHR
// approach that was triggering linter warnings in Dart 3.x / Flutter 3.35+).
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<Uint8List> fetchBlobAsBytes(String blobUrl) {
  final completer = Completer<Uint8List>();
  final xhr = web.XMLHttpRequest();
  xhr.open('GET', blobUrl);
  xhr.responseType = 'arraybuffer';

  xhr.addEventListener(
    'load',
    (web.Event _) {
      try {
        // xhr.response is a JS ArrayBuffer; dartify() converts it to ByteBuffer
        final buffer = xhr.response.dartify() as ByteBuffer;
        completer.complete(buffer.asUint8List());
      } catch (e) {
        completer.completeError('Failed to decode blob bytes: $e');
      }
    }.toJS,
  );

  xhr.addEventListener(
    'error',
    (web.Event _) {
      completer.completeError(
        'XHR error fetching blob URL (status ${xhr.status}): $blobUrl',
      );
    }.toJS,
  );

  xhr.send();
  return completer.future;
}
