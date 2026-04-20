import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/onboarding_progress_bar.dart';

// ── Design tokens ────────────────────────────────────────────────────────────

// ── Default avatar illustrations (gender-matched) ────────────────────────────
// Used when the user skips uploading a profile photo.
const _kMumAvatar = 'assets/images/avatars/Emma.png';  // female illustration
const _kDadAvatar = 'assets/images/avatars/John.png';  // male illustration

class AddPhotoScreen extends StatefulWidget {
  const AddPhotoScreen({super.key});

  @override
  State<AddPhotoScreen> createState() => _AddPhotoScreenState();
}

class _AddPhotoScreenState extends State<AddPhotoScreen> {
  final _picker = ImagePicker();
  final _onboarding = OnboardingDataService();

  XFile? _pickedFile;        // selected image (mobile / web)
  bool   _isLoading = false;

  // ── Photo picker ─────────────────────────────────────────────────────────

  /// Entry point when user taps the avatar circle or "Add photo" button.
  ///
  /// • Web: goes straight to the gallery picker — no intermediate sheet needed
  ///   because (a) camera is unavailable on web and (b) showing a sheet with
  ///   only one option then triggering the browser's own file chooser creates
  ///   a confusing double-prompt for the user.
  ///
  /// • Mobile: shows a bottom sheet offering both Gallery and Camera options,
  ///   then calls _pickFrom() with the chosen source.
  Future<void> _showPickerOptions() async {
    if (!mounted) return;

    // ── Web: skip the sheet, open the file picker directly ──────────────────
    if (kIsWeb) {
      await _pickFrom(ImageSource.gallery);
      return;
    }

    // ── Mobile: show gallery / camera choice sheet ───────────────────────────
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: HuddlColors.inputBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Add a profile photo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: HuddlColors.onboardingOrange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_outlined, color: HuddlColors.onboardingOrange),
                ),
                title: const Text('Choose from photos',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFrom(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: HuddlColors.onboardingOrange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_outlined, color: HuddlColors.onboardingOrange),
                ),
                title: const Text('Take a photo',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFrom(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFrom(ImageSource source) async {
    try {
      setState(() => _isLoading = true);
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file != null && mounted) {
        setState(() => _pickedFile = file);
        _onboarding.setProfilePhotoPath(kIsWeb ? file.name : file.path);

        // Convert to base64 data URL so it persists across page reloads.
        // blob: URLs die when the page refreshes, data: URLs survive in localStorage.
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        final dataUrl = 'data:$mimeType;base64,$base64Str';
        _onboarding.setProfilePhotoObjectUrl(dataUrl);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access photos: $e'),
            backgroundColor: HuddlColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _continue() => Navigator.pushNamed(context, '/about_you');

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _pickedFile != null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            OnboardingProgressBar(step: OnboardingStep.addPhoto),
            // ── App bar row ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Row(
                children: [
                  // Back chevron
                  GestureDetector(
                    onTap: () => Navigator.maybePop(context),
                    child: const Icon(Icons.chevron_left,
                        size: 30, color: HuddlColors.onboardingOrange),
                  ),
                  const Spacer(),
                  // Huddl logo centred
                  Image.asset(
                    'assets/images/logo_huddl_splash.png',
                    height: 34,
                    fit: BoxFit.contain,
                  ),
                  const Spacer(),
                  // Spacer to keep logo centred
                  const SizedBox(width: 48),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Title ────────────────────────────────────────────────────
            Text(
              'Add a photo',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            // ── Subtitle ─────────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Don\'t be just a name – share your smile with us too.',
                style: TextStyle(
                  fontSize: 14,
                  color: HuddlColors.disabledText,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 40),

            // ── Photo circle ─────────────────────────────────────────────
            GestureDetector(
              onTap: _isLoading ? null : _showPickerOptions,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  // Avatar circle — no background fill needed; illustration fills it
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: HuddlColors.avatarBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hasPhoto ? HuddlColors.onboardingOrange : HuddlColors.onboardingOrange.withValues(alpha: 0.4),
                        width: hasPhoto ? 3 : 2,
                      ),
                    ),
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: HuddlColors.onboardingOrange,
                              strokeWidth: 2.5,
                            ),
                          )
                        : _buildAvatarContent(),
                  ),
                  // Camera badge — always visible so user knows they can tap to change
                  if (!_isLoading)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: HuddlColors.onboardingOrange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),

            const Spacer(),

            // ── Buttons ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                children: [
                  // "Add photo" / "Change photo" outlined button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _showPickerOptions,
                      icon: const Icon(Icons.camera_alt_outlined, size: 20),
                      label: Text(
                        hasPhoto ? 'Change photo' : 'Add photo',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HuddlColors.onboardingOrange,
                        side: const BorderSide(color: HuddlColors.onboardingOrange, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // "Continue" filled button (always enabled — user can skip)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.onboardingOrange,
                        disabledBackgroundColor:
                            HuddlColors.disabled,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the asset path of the gender-matched default avatar illustration.
  String get _defaultAvatarAsset {
    final parentType = _onboarding.parentType?.toLowerCase(); // 'mum' or 'dad'
    return (parentType == 'dad') ? _kDadAvatar : _kMumAvatar;
  }

  /// Builds the content inside the 160 px avatar circle.
  Widget _buildAvatarContent() {
    if (_pickedFile != null) {
      if (kIsWeb) {
        // Web: XFile.path is a blob: URL — use Image.network
        return ClipOval(
          child: Image.network(
            _pickedFile!.path,
            width: 160,
            height: 160,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _defaultAvatar(),
          ),
        );
      }
      // Mobile (iOS / Android): XFile.path is a real file-system path.
      // Image.network does NOT work for local paths on iOS — use Image.file.
      return ClipOval(
        child: Image.file(
          File(_pickedFile!.path),
          width: 160,
          height: 160,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultAvatar(),
        ),
      );
    }
    // ── Gender-matched illustration placeholder ──
    return _defaultAvatar();
  }

  /// Gender-matched illustration shown before a photo is selected.
  Widget _defaultAvatar() {
    return ClipOval(
      child: Image.asset(
        _defaultAvatarAsset,
        width: 160,
        height: 160,
        fit: BoxFit.cover,
        // If asset fails to load for any reason, fall back to icon
        errorBuilder: (_, __, ___) => Container(
          width: 160,
          height: 160,
          color: HuddlColors.avatarBg,
          child: const Icon(Icons.person, size: 64, color: HuddlColors.avatarIcon),
        ),
      ),
    );
  }
}
