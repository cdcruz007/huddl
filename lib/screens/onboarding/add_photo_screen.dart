import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/photo_upload_service.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';

// ── UX-09: Immersive dark profile photo setup ─────────────────────────────────
//
// DESIGN SPEC (from huddl_FINAL_complete_delivery.docx):
//   • scaffold backgroundColor: Colors.black
//   • Photo preview: ClipOval, 260px diameter, centred on screen
//   • Above preview: CustomPaint arc progress bar — thin arc in HuddlColors.primary, 20% filled
//   • Top bar: white 'Preview' title (centred) + white back arrow
//   • CTA buttons: white outlined + filled (primary colour)
//
// Cross-platform: iOS + Android + Web.

// ── Default avatar illustrations (gender-matched) ────────────────────────────
const _kMumAvatar = 'assets/images/avatars/Emma.png';
const _kDadAvatar = 'assets/images/avatars/John.png';

class AddPhotoScreen extends StatefulWidget {
  const AddPhotoScreen({super.key});

  @override
  State<AddPhotoScreen> createState() => _AddPhotoScreenState();
}

class _AddPhotoScreenState extends State<AddPhotoScreen>
    with SingleTickerProviderStateMixin {
  final _picker      = ImagePicker();
  final _onboarding  = OnboardingDataService();
  final _photoUpload = PhotoUploadService();

  XFile? _pickedFile;
  bool   _isLoading  = false;

  // Subtle pulse for the arc while loading
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.18, end: 0.28)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Photo picker ───────────────────────────────────────────────────────────

  Future<void> _showPickerOptions() async {
    if (!mounted) return;

    if (kIsWeb) {
      await _pickFrom(ImageSource.gallery);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E), // dark sheet
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Add a profile photo',
                style: HuddlText.body(weight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _darkSheetTile(
                ctx: ctx,
                icon: Icons.photo_library_outlined,
                label: 'Choose from photos',
                onTap: () { Navigator.pop(ctx); _pickFrom(ImageSource.gallery); },
              ),
              _darkSheetTile(
                ctx: ctx,
                icon: Icons.camera_alt_outlined,
                label: 'Take a photo',
                onTap: () { Navigator.pop(ctx); _pickFrom(ImageSource.camera); },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _darkSheetTile({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: HuddlColors.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: HuddlColors.primary),
      ),
      title: Text(
        label,
        style: HuddlText.body(),
      ),
      onTap: onTap,
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
      if (file == null || !mounted) return;
      setState(() => _pickedFile = file);

      final bytes     = await file.readAsBytes();
      final base64Str = base64Encode(bytes);
      final mimeType  = file.name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      final dataUrl   = 'data:$mimeType;base64,$base64Str';
      _onboarding.setProfilePhotoObjectUrl(dataUrl);

      final downloadUrl = await _photoUpload.uploadProfilePhoto(file);
      if (downloadUrl != null) {
        _onboarding.setProfilePhotoPath(downloadUrl);
      } else {
        _onboarding.setProfilePhotoPath(dataUrl);
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

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _continue() => Navigator.pushNamed(context, '/about_you');

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _pickedFile != null;

    return Scaffold(
      // UX-09: Immersive black scaffold
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: white back arrow + centred 'Preview' title ─────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.chevron_left,
                          size: 30, color: Colors.white),
                    ),
                  ),
                  Text(
                    'Preview',
                    style: HuddlText.heading(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Arc progress bar (CustomPaint, 20% filled) ──────────────────
            AnimatedBuilder(
              animation: _isLoading ? _pulseAnim : const AlwaysStoppedAnimation(0.2),
              builder: (_, __) {
                final progress = _isLoading
                    ? _pulseAnim.value
                    : (hasPhoto ? 0.6 : 0.2);
                return CustomPaint(
                  size: const Size(300, 14),
                  painter: _ArcProgressPainter(progress: progress),
                );
              },
            ),

            const SizedBox(height: 32),

            // ── 260px ClipOval photo preview ────────────────────────────────
            GestureDetector(
              onTap: _isLoading ? null : _showPickerOptions,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hasPhoto
                            ? HuddlColors.primary
                            : Colors.white.withValues(alpha: 0.15),
                        width: hasPhoto ? 3 : 1.5,
                      ),
                    ),
                    child: ClipOval(
                      child: _isLoading
                          ? Container(
                              color: const Color(0xFF1C1C1E),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: HuddlColors.primary,
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : _buildAvatarContent(),
                    ),
                  ),
                  // Camera badge
                  if (!_isLoading)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: HuddlColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2.5),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                ],
              ),
            ),

            const Spacer(),

            // ── Headline + subtitle ─────────────────────────────────────────
            Text(
              hasPhoto ? 'Looking good!' : 'Add a photo',
              style: HuddlText.display(),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                hasPhoto
                    ? 'Your neighbours will recognise you instantly.'
                    : 'Don\'t be just a name – share your smile with us too.',
                style: HuddlText.body(color: Colors.white.withValues(alpha: 0.55)),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 32),

            // ── CTA buttons ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  // Add / change photo — white outlined
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _showPickerOptions,
                      icon: const Icon(Icons.camera_alt_outlined, size: 20),
                      label: Text(
                        hasPhoto ? 'Change photo' : 'Add photo',
                        style: HuddlText.body(),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Continue — primary orange filled
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.primary,
                        disabledBackgroundColor:
                            HuddlColors.primary.withValues(alpha: 0.4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Continue',
                        style: HuddlText.body(weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String get _defaultAvatarAsset {
    final parentType = _onboarding.parentType?.toLowerCase();
    return (parentType == 'dad') ? _kDadAvatar : _kMumAvatar;
  }

  Widget _buildAvatarContent() {
    if (_pickedFile != null) {
      if (kIsWeb) {
        return Image.network(
          _pickedFile!.path,
          width: 260,
          height: 260,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultAvatar(),
        );
      }
      return Image.file(
        File(_pickedFile!.path),
        width: 260,
        height: 260,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _defaultAvatar(),
      );
    }
    return _defaultAvatar();
  }

  Widget _defaultAvatar() {
    return Image.asset(
      _defaultAvatarAsset,
      width: 260,
      height: 260,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: 260,
        height: 260,
        color: const Color(0xFF1C1C1E),
        child: const Icon(Icons.person, size: 80, color: HuddlColors.textHint),
      ),
    );
  }
}

// ── Arc progress bar painter ──────────────────────────────────────────────────
//
// Draws a thin track arc (270° sweep, bottom-centre start) with a filled
// foreground arc in HuddlColors.primary. Used above the 260px avatar circle.

class _ArcProgressPainter extends CustomPainter {
  const _ArcProgressPainter({required this.progress});

  final double progress; // 0.0 → 1.0

  @override
  void paint(Canvas canvas, Size size) {
    final cx    = size.width / 2;
    final cy    = size.height * 3.5; // arc centre below the painted rect
    final r     = size.width * 0.49;

    final trackPaint = Paint()
      ..color   = Colors.white.withValues(alpha: 0.12)
      ..style   = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap   = StrokeCap.round;

    final fillPaint = Paint()
      ..color   = HuddlColors.primary
      ..style   = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap   = StrokeCap.round;

    const startAngle  = math.pi + (math.pi * 0.15); // ~207°
    const sweepTotal  = math.pi * 0.7;              // ~126° total arc

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Track
    canvas.drawArc(rect, startAngle, sweepTotal, false, trackPaint);

    // Filled progress
    if (progress > 0) {
      canvas.drawArc(
        rect,
        startAngle,
        sweepTotal * progress.clamp(0.0, 1.0),
        false,
        fillPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcProgressPainter old) => old.progress != progress;
}
