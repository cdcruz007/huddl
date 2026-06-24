/// Client-side upload size limits — MUST mirror storage.rules maxSize() values.
/// Pre-checking here gives the user a clear message before wasting bandwidth on
/// an upload the Storage rule would reject. (LAYER-11-NO-SIZE-PRECHECK-1)
class UploadLimits {
  static const int imageMb = 10;  // profile_photos, marketplace_images, group_images
  static const int voiceMb = 25;  // voice_notes
  static const int mediaMb = 20;  // dm_images/documents, group_documents

  /// Returns an error string if [byteLength] exceeds [limitMb], else null.
  static String? checkSize(int byteLength, int limitMb, {String kind = 'file'}) {
    if (byteLength > limitMb * 1024 * 1024) {
      return 'That $kind is too large (max $limitMb MB). Please choose a smaller one.';
    }
    return null;
  }
}
