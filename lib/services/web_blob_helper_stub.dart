// Non-web stub: fetchBlobAsBytes should never be called on native platforms.
import 'dart:typed_data';

Future<Uint8List> fetchBlobAsBytes(String blobUrl) {
  throw UnsupportedError(
    'fetchBlobAsBytes is only available on web platforms. '
    'Got blob URL on native: $blobUrl',
  );
}
