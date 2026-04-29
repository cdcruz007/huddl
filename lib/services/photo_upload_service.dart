// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — PHOTO UPLOAD SERVICE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Uploads a picked image file to Firebase Storage and returns a permanent
// HTTPS download URL that can safely be stored in Firestore.
//
// On iOS/Android, image_picker returns a local temp file path such as
//   /private/var/mobile/Containers/Data/.../tmp/image_picker_xxx.jpg
// Storing that path directly in Firestore breaks for every other device and
// after the file is cleaned up by the OS.  This service uploads the bytes to
//   gs://<bucket>/profile_photos/<uid>/<timestamp>.<ext>
// and returns the public HTTPS download URL.
//
// Web: also works — reads bytes from XFile and uploads via putData.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class PhotoUploadService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final PhotoUploadService _instance = PhotoUploadService._internal();
  factory PhotoUploadService() => _instance;
  PhotoUploadService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Upload [file] to Firebase Storage under `profile_photos/<uid>/` and
  /// return the permanent HTTPS download URL.
  ///
  /// Returns `null` if:
  ///  - the user is not signed in
  ///  - the upload fails for any reason (caller should handle gracefully)
  ///
  /// [onProgress] is optional — called with a 0.0–1.0 fraction as bytes land.
  Future<String?> uploadProfilePhoto(
    XFile file, {
    void Function(double progress)? onProgress,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      _log('❌ No signed-in user — cannot upload profile photo');
      return null;
    }

    try {
      // Determine file extension
      final name = file.name.toLowerCase();
      final ext = name.endsWith('.png') ? 'png' : 'jpg';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'profile_photos/$uid/$timestamp.$ext';

      final ref = _storage.ref(storagePath);

      UploadTask task;

      if (kIsWeb) {
        // Web: use bytes
        final bytes = await file.readAsBytes();
        final metadata = SettableMetadata(
          contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
        );
        task = ref.putData(bytes, metadata);
      } else {
        // Mobile: use File
        final ioFile = File(file.path);
        final metadata = SettableMetadata(
          contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
        );
        task = ref.putFile(ioFile, metadata);
      }

      // Wire up progress callback if provided
      if (onProgress != null) {
        task.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes > 0) {
            onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
          }
        });
      }

      final snapshot = await task;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      _log('✅ Profile photo uploaded → $downloadUrl');
      return downloadUrl;
    } catch (e) {
      _log('❌ Upload failed: $e');
      return null;
    }
  }

  /// Upload an already-resolved [File] (returned by ImageEditorWidget / image_cropper)
  /// to Firebase Storage and return the permanent HTTPS download URL.
  ///
  /// This overload is the mobile-only path — on iOS/Android the cropper returns
  /// a dart:io File directly rather than an XFile.
  Future<String?> uploadProfilePhotoFromFile(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      _log('❌ No signed-in user — cannot upload profile photo');
      return null;
    }

    try {
      final filePath = file.path.toLowerCase();
      final ext = filePath.endsWith('.png') ? 'png' : 'jpg';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'profile_photos/$uid/$timestamp.$ext';

      final ref = _storage.ref(storagePath);
      final metadata = SettableMetadata(
        contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
      );
      final task = ref.putFile(file, metadata);

      if (onProgress != null) {
        task.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes > 0) {
            onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
          }
        });
      }

      final snapshot = await task;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      _log('✅ Profile photo uploaded → $downloadUrl');
      return downloadUrl;
    } catch (e) {
      _log('❌ Upload failed: $e');
      return null;
    }
  }

  /// Returns `true` when [url] is a valid remote URL that can be persisted
  /// in Firestore.  Local iOS/Android temp paths and blob: URLs are NOT valid.
  static bool isRemoteUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.startsWith('https://') || url.startsWith('http://');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _log(String msg) {
    if (kDebugMode) debugPrint('[PhotoUploadService] $msg');
  }
}
