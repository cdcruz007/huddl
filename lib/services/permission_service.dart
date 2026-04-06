import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import 'browser_storage.dart';

/// Simple permission service that tracks first-time media access prompts.
/// On the web, actual file-system permissions aren't needed, but the UI/UX
/// experience of showing the "Allow Huddl to access photos…" dialog is
/// implemented here so it transfers seamlessly to native builds.
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  static const String _mediaPermKey = 'permission_media_access_v1';
  bool _isInitialized = false;
  bool _mediaPermissionGranted = false;

  bool get isMediaAccessGranted => _mediaPermissionGranted;

  Future<void> initialize() async {
    if (_isInitialized) return;
    final stored = await BrowserStorage.getString(_mediaPermKey);
    _mediaPermissionGranted = stored == 'granted';
    _isInitialized = true;
  }

  Future<void> _setGranted(bool granted) async {
    _mediaPermissionGranted = granted;
    await BrowserStorage.setString(
      _mediaPermKey,
      granted ? 'granted' : 'denied',
    );
  }

  /// Shows a native-style permission prompt. Returns `true` if allowed.
  /// If permission was already granted, returns `true` immediately.
  Future<bool> requestMediaAccess(BuildContext context) async {
    await initialize();
    if (_mediaPermissionGranted) return true;

    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => _PermissionDialog(),
    );

    final granted = result == true;
    await _setGranted(granted);
    return granted;
  }
}

class _PermissionDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Shield icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: HuddlColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                size: 34,
                color: HuddlColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Allow Huddl to access photos, media and files on your device?',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textDark,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'This will allow Huddl to share images, videos and documents in your chats.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: HuddlColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: HuddlColors.divider),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Deny',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HuddlColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: Text(
                      'Allow',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
