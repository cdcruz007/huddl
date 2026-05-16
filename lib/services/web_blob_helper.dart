// Web-only helper: fetches a blob: URL (from the record package) and returns
// its raw bytes so they can be uploaded to Firebase Storage via putData().
//
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';

Future<Uint8List> fetchBlobAsBytes(String blobUrl) {
  final completer = Completer<Uint8List>();
  final xhr = html.HttpRequest();
  xhr.open('GET', blobUrl);
  xhr.responseType = 'arraybuffer';
  xhr.onLoad.listen((_) {
    try {
      // xhr.response is a JS ArrayBuffer; dart:html maps it to ByteBuffer
      final byteBuffer = xhr.response as ByteBuffer;
      completer.complete(byteBuffer.asUint8List());
    } catch (e) {
      completer.completeError('Failed to decode blob bytes: $e');
    }
  });
  xhr.onError.listen((_) {
    completer.completeError(
      'XHR error fetching blob URL (status ${xhr.status}): $blobUrl',
    );
  });
  xhr.send();
  return completer.future;
}
