import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/huddl_colors.dart';

/// Reusable image editor widget for profile pictures, group images, meetup photos, and marketplace items
/// Provides:
/// - Image selection from gallery or camera
/// - Crop with preset aspect ratios (square, 16:9, 4:3, free)
/// - Rotate and flip
/// - Preview before saving
class ImageEditorWidget {
  static final ImagePicker _picker = ImagePicker();

  /// Pick and crop an image with specified aspect ratio
  /// 
  /// [context] - BuildContext for showing dialogs
  /// [aspectRatio] - Preset aspect ratio (square, wide, portrait, free)
  /// [title] - Title for the cropper screen
  /// Returns the cropped image file or null if cancelled
  static Future<File?> pickAndCropImage({
    required BuildContext context,
    ImageAspectRatio aspectRatio = ImageAspectRatio.square,
    String title = 'Edit Image',
  }) async {
    // Show source selection bottom sheet
    final ImageSource? source = await _showImageSourceBottomSheet(context);
    if (source == null) return null;

    // Pick image from selected source
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: 2048, // Reasonable max size for upload
      maxHeight: 2048,
      imageQuality: 90,
    );

    if (pickedFile == null) return null;

    // Try to crop — if user dismisses the cropper (returns null), fall back
    // to the raw picked file so the photo is never silently dropped.
    final croppedFile = await _cropImage(
      context: context,
      imagePath: pickedFile.path,
      aspectRatio: aspectRatio,
      title: title,
    );

    return croppedFile ?? File(pickedFile.path);
  }

  /// Show bottom sheet to select image source (gallery or camera)
  static Future<ImageSource?> _showImageSourceBottomSheet(BuildContext context) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  'Select Image Source',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 20),
                // Gallery option
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: HuddlColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.photo_library,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  title: const Text('Choose from Gallery'),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
                // Camera option
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: HuddlColors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: HuddlColors.teal,
                    ),
                  ),
                  title: const Text('Take a Photo'),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Crop image with image_cropper
  static Future<File?> _cropImage({
    required BuildContext context,
    required String imagePath,
    required ImageAspectRatio aspectRatio,
    required String title,
  }) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: imagePath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: title,
          toolbarColor: HuddlColors.primary,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: _getAndroidAspectRatio(aspectRatio),
          lockAspectRatio: aspectRatio != ImageAspectRatio.free,
          aspectRatioPresets: _getAspectRatioPresets(aspectRatio),
          showCropGrid: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: title,
          aspectRatioPresets: _getAspectRatioPresets(aspectRatio),
          aspectRatioLockEnabled: aspectRatio != ImageAspectRatio.free,
          resetAspectRatioEnabled: true,
          rotateButtonsHidden: false,
        ),
      ],
    );

    return croppedFile?.path != null ? File(croppedFile!.path) : null;
  }

  /// Get Android aspect ratio preset
  static CropAspectRatioPreset _getAndroidAspectRatio(ImageAspectRatio ratio) {
    switch (ratio) {
      case ImageAspectRatio.square:
        return CropAspectRatioPreset.square;
      case ImageAspectRatio.wide:
        return CropAspectRatioPreset.ratio16x9;
      case ImageAspectRatio.portrait:
        return CropAspectRatioPreset.ratio4x3;
      case ImageAspectRatio.free:
        return CropAspectRatioPreset.original;
    }
  }

  /// Get list of aspect ratio presets
  static List<CropAspectRatioPreset> _getAspectRatioPresets(ImageAspectRatio ratio) {
    if (ratio == ImageAspectRatio.free) {
      return [
        CropAspectRatioPreset.original,
        CropAspectRatioPreset.square,
        CropAspectRatioPreset.ratio16x9,
        CropAspectRatioPreset.ratio4x3,
        CropAspectRatioPreset.ratio3x2,
      ];
    }
    return [_getAndroidAspectRatio(ratio)];
  }

  /// Pick and crop with a *pre-selected* [source], skipping the internal
  /// "Select Image Source" bottom sheet.  Use this when the caller has already
  /// shown its own source-selection sheet so the user is not prompted twice.
  static Future<File?> pickAndCropImageWithSource({
    required BuildContext context,
    required ImageSource source,
    ImageAspectRatio aspectRatio = ImageAspectRatio.square,
    String title = 'Edit Image',
  }) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (pickedFile == null) return null;

    // Try to crop — if user dismisses the cropper (returns null), fall back
    // to the raw picked file so the photo is never silently dropped.
    final cropped = await _cropImage(
      context: context,
      imagePath: pickedFile.path,
      aspectRatio: aspectRatio,
      title: title,
    );
    return cropped ?? File(pickedFile.path);
  }

  /// Quick helper for profile pictures (always square)
  static Future<File?> pickProfilePicture(BuildContext context) {
    return pickAndCropImage(
      context: context,
      aspectRatio: ImageAspectRatio.square,
      title: 'Edit Profile Picture',
    );
  }

  /// Quick helper for profile pictures with a *pre-selected* source (no double prompt).
  static Future<File?> pickProfilePictureWithSource(
      BuildContext context, ImageSource source) {
    return pickAndCropImageWithSource(
      context: context,
      source: source,
      aspectRatio: ImageAspectRatio.square,
      title: 'Edit Profile Picture',
    );
  }

  /// Quick helper for group images (16:9 recommended)
  static Future<File?> pickGroupImage(BuildContext context) {
    return pickAndCropImage(
      context: context,
      aspectRatio: ImageAspectRatio.wide,
      title: 'Edit Group Image',
    );
  }

  /// Quick helper for group images with a *pre-selected* source (no double prompt).
  static Future<File?> pickGroupImageWithSource(
      BuildContext context, ImageSource source) {
    return pickAndCropImageWithSource(
      context: context,
      source: source,
      aspectRatio: ImageAspectRatio.wide,
      title: 'Edit Group Image',
    );
  }

  /// Quick helper for meetup images (16:9 recommended)
  static Future<File?> pickMeetupImage(BuildContext context) {
    return pickAndCropImage(
      context: context,
      aspectRatio: ImageAspectRatio.wide,
      title: 'Edit Meetup Image',
    );
  }

  /// Quick helper for meetup images with a *pre-selected* source (no double prompt).
  static Future<File?> pickMeetupImageWithSource(
      BuildContext context, ImageSource source) {
    return pickAndCropImageWithSource(
      context: context,
      source: source,
      aspectRatio: ImageAspectRatio.wide,
      title: 'Edit Meetup Image',
    );
  }

  /// Quick helper for marketplace item images (free aspect ratio for flexibility)
  static Future<File?> pickMarketplaceImage(BuildContext context) {
    return pickAndCropImage(
      context: context,
      aspectRatio: ImageAspectRatio.free,
      title: 'Edit Item Photo',
    );
  }

  /// Quick helper for marketplace images with a *pre-selected* source (no double prompt).
  static Future<File?> pickMarketplaceImageWithSource(
      BuildContext context, ImageSource source) {
    return pickAndCropImageWithSource(
      context: context,
      source: source,
      aspectRatio: ImageAspectRatio.free,
      title: 'Edit Item Photo',
    );
  }
}

/// Preset aspect ratios for different use cases
enum ImageAspectRatio {
  square,   // 1:1 - Profile pictures
  wide,     // 16:9 - Group/meetup banners
  portrait, // 4:3 - Portrait photos
  free,     // Free aspect - Marketplace items
}
