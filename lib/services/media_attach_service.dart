import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

/// Represents different types of media attachments.
enum AttachmentType { image, video, document, location, contact }

/// Holds the result of a media pick operation.
class MediaAttachment {
  final AttachmentType type;
  final String? filePath;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;
  final Uint8List? bytes; // For web platform

  const MediaAttachment({
    required this.type,
    this.filePath,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.bytes,
  });
}

/// Service that wraps image_picker and file_picker to provide native
/// camera, gallery, and file picking on Android/iOS, and HTML file
/// input on Web. Works identically to WhatsApp attach flow.
class MediaAttachService {
  static final MediaAttachService _instance = MediaAttachService._internal();
  factory MediaAttachService() => _instance;
  MediaAttachService._internal();

  final ImagePicker _imagePicker = ImagePicker();

  // ── Camera capture ─────────────────────────────────────────────────────

  /// Opens the device camera to take a photo.
  /// On web this triggers the browser camera dialog.
  Future<MediaAttachment?> takePhoto() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (photo == null) return null;
      final bytes = await photo.readAsBytes();
      return MediaAttachment(
        type: AttachmentType.image,
        filePath: photo.path,
        fileName: photo.name,
        mimeType: photo.mimeType ?? 'image/jpeg',
        fileSize: bytes.length,
        bytes: bytes,
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('[MediaAttachService] takePhoto error: $e');
      FirebaseCrashlytics.instance.recordError(
        e, stackTrace,
        reason: 'MediaAttachService.takePhoto',
      );
      rethrow;
    }
  }

  /// Opens the device camera to record a video.
  Future<MediaAttachment?> recordVideo({Duration? maxDuration}) async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: maxDuration ?? const Duration(minutes: 5),
      );
      if (video == null) return null;
      final bytes = await video.readAsBytes();
      return MediaAttachment(
        type: AttachmentType.video,
        filePath: video.path,
        fileName: video.name,
        mimeType: video.mimeType ?? 'video/mp4',
        fileSize: bytes.length,
        bytes: bytes,
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('[MediaAttachService] recordVideo error: $e');
      FirebaseCrashlytics.instance.recordError(
        e, stackTrace,
        reason: 'MediaAttachService.recordVideo',
      );
      rethrow;
    }
  }

  // ── Gallery pick ───────────────────────────────────────────────────────

  /// Opens the device photo gallery to pick one image.
  Future<MediaAttachment?> pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image == null) return null;
      final bytes = await image.readAsBytes();
      return MediaAttachment(
        type: AttachmentType.image,
        filePath: image.path,
        fileName: image.name,
        mimeType: image.mimeType ?? 'image/jpeg',
        fileSize: bytes.length,
        bytes: bytes,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[MediaAttachService] pickImage error: $e');
      return null;
    }
  }

  /// Opens the device gallery to pick multiple images.
  Future<List<MediaAttachment>> pickMultipleImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (images.isEmpty) return [];
      final results = <MediaAttachment>[];
      for (final img in images) {
        final bytes = await img.readAsBytes();
        results.add(MediaAttachment(
          type: AttachmentType.image,
          filePath: img.path,
          fileName: img.name,
          mimeType: img.mimeType ?? 'image/jpeg',
          fileSize: bytes.length,
          bytes: bytes,
        ));
      }
      return results;
    } catch (e) {
      if (kDebugMode) debugPrint('[MediaAttachService] pickMultiple error: $e');
      return [];
    }
  }

  /// Opens the device gallery to pick a video.
  Future<MediaAttachment?> pickVideoFromGallery() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      if (video == null) return null;
      final bytes = await video.readAsBytes();
      return MediaAttachment(
        type: AttachmentType.video,
        filePath: video.path,
        fileName: video.name,
        mimeType: video.mimeType ?? 'video/mp4',
        fileSize: bytes.length,
        bytes: bytes,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[MediaAttachService] pickVideo error: $e');
      return null;
    }
  }

  // ── Document pick ──────────────────────────────────────────────────────

  /// Opens the native file picker to select a document.
  /// Allows PDF, Word, Excel, PowerPoint, and other common document types.
  Future<MediaAttachment?> pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
          'txt', 'csv', 'zip', 'rar',
        ],
        withData: true, // needed for web
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      return MediaAttachment(
        type: AttachmentType.document,
        filePath: file.path,
        fileName: file.name,
        mimeType: _getMimeType(file.extension ?? ''),
        fileSize: file.size,
        bytes: file.bytes,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[MediaAttachService] pickDocument error: $e');
      return null;
    }
  }

  /// Opens the native file picker with any file type.
  Future<MediaAttachment?> pickAnyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      return MediaAttachment(
        type: AttachmentType.document,
        filePath: file.path,
        fileName: file.name,
        mimeType: _getMimeType(file.extension ?? ''),
        fileSize: file.size,
        bytes: file.bytes,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[MediaAttachService] pickAnyFile error: $e');
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  String _getMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'ppt':
      case 'pptx':
        return 'application/vnd.ms-powerpoint';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/x-rar-compressed';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  /// Human-readable file size string.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Returns an icon for a document extension.
  static String getDocumentIcon(String? fileName) {
    if (fileName == null) return '📄';
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return '📕';
      case 'doc':
      case 'docx':
        return '📘';
      case 'xls':
      case 'xlsx':
        return '📗';
      case 'ppt':
      case 'pptx':
        return '📙';
      case 'txt':
        return '📝';
      case 'csv':
        return '📊';
      case 'zip':
      case 'rar':
        return '📦';
      default:
        return '📄';
    }
  }
}
