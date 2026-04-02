import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

/// Represents a picked attachment from the device.
class PickedAttachment {
  final AttachmentType type;
  final String name;
  final String? path;
  final Uint8List? bytes; // for web — files don't have paths
  final String? mimeType;
  final int? sizeBytes;

  const PickedAttachment({
    required this.type,
    required this.name,
    this.path,
    this.bytes,
    this.mimeType,
    this.sizeBytes,
  });

  /// Friendly file size string
  String get formattedSize {
    if (sizeBytes == null) return '';
    if (sizeBytes! < 1024) return '$sizeBytes B';
    if (sizeBytes! < 1024 * 1024) return '${(sizeBytes! / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Returns a data URI for web display (images only)
  String? get dataUrl {
    if (bytes == null || type != AttachmentType.image) return null;
    final base64 = base64Encode(bytes!);
    return 'data:${mimeType ?? "image/jpeg"};base64,$base64';
  }
}

/// Supported attachment types
enum AttachmentType { image, video, document, location, contact }

/// Extension for file type icon
String iconForDocument(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'pdf':
      return 'PDF';
    case 'doc':
    case 'docx':
      return 'DOC';
    case 'xls':
    case 'xlsx':
      return 'XLS';
    case 'ppt':
    case 'pptx':
      return 'PPT';
    case 'txt':
      return 'TXT';
    case 'zip':
    case 'rar':
      return 'ZIP';
    default:
      return ext.toUpperCase();
  }
}

/// Centralized attachment picking service.
/// Uses native OS dialogs (camera, gallery, file browser) on all platforms.
class AttachmentService {
  static final AttachmentService _instance = AttachmentService._internal();
  factory AttachmentService() => _instance;
  AttachmentService._internal();

  final ImagePicker _imagePicker = ImagePicker();

  // ── Camera — take a photo ───────────────────────────────────────────────
  Future<PickedAttachment?> pickFromCamera() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (photo == null) return null;
      final bytes = await photo.readAsBytes();
      return PickedAttachment(
        type: AttachmentType.image,
        name: photo.name,
        path: photo.path,
        bytes: bytes,
        mimeType: photo.mimeType ?? 'image/jpeg',
        sizeBytes: bytes.length,
      );
    } catch (e) {
      _log('Camera error: $e');
      return null;
    }
  }

  // ── Gallery — pick one or more images ──────────────────────────────────
  Future<List<PickedAttachment>> pickFromGallery({bool multiple = true}) async {
    try {
      if (multiple) {
        final List<XFile> images = await _imagePicker.pickMultiImage(
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
        final results = <PickedAttachment>[];
        for (final img in images) {
          final bytes = await img.readAsBytes();
          results.add(PickedAttachment(
            type: AttachmentType.image,
            name: img.name,
            path: img.path,
            bytes: bytes,
            mimeType: img.mimeType ?? 'image/jpeg',
            sizeBytes: bytes.length,
          ));
        }
        return results;
      } else {
        final XFile? image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
        if (image == null) return [];
        final bytes = await image.readAsBytes();
        return [
          PickedAttachment(
            type: AttachmentType.image,
            name: image.name,
            path: image.path,
            bytes: bytes,
            mimeType: image.mimeType ?? 'image/jpeg',
            sizeBytes: bytes.length,
          ),
        ];
      }
    } catch (e) {
      _log('Gallery error: $e');
      return [];
    }
  }

  // ── Pick a video ──────────────────────────────────────────────────────
  Future<PickedAttachment?> pickVideo({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 5),
      );
      if (video == null) return null;
      final bytes = await video.readAsBytes();
      return PickedAttachment(
        type: AttachmentType.video,
        name: video.name,
        path: video.path,
        bytes: bytes,
        mimeType: video.mimeType ?? 'video/mp4',
        sizeBytes: bytes.length,
      );
    } catch (e) {
      _log('Video error: $e');
      return null;
    }
  }

  // ── Pick a document (PDF, DOC, etc.) ──────────────────────────────────
  Future<List<PickedAttachment>> pickDocuments({bool multiple = false}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: multiple,
        withData: true, // needed for web
      );
      if (result == null || result.files.isEmpty) return [];

      return result.files.map((file) {
        return PickedAttachment(
          type: AttachmentType.document,
          name: file.name,
          path: file.path,
          bytes: file.bytes,
          mimeType: _mimeFromExtension(file.extension ?? ''),
          sizeBytes: file.size,
        );
      }).toList();
    } catch (e) {
      _log('Document picker error: $e');
      return [];
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  String _mimeFromExtension(String ext) {
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
      case 'zip':
        return 'application/zip';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('AttachmentService: $message');
    }
  }
}

/// Base64 encoding helper
String base64Encode(Uint8List bytes) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final buffer = StringBuffer();
  for (var i = 0; i < bytes.length; i += 3) {
    final b0 = bytes[i];
    final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    buffer.write(chars[(b0 >> 2) & 0x3F]);
    buffer.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);
    buffer.write(i + 1 < bytes.length ? chars[((b1 << 2) | (b2 >> 6)) & 0x3F] : '=');
    buffer.write(i + 2 < bytes.length ? chars[b2 & 0x3F] : '=');
  }
  return buffer.toString();
}
