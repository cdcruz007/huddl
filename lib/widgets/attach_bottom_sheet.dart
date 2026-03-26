import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';

/// The type of attachment the user wants to send.
enum AttachAction { camera, gallery, document, location, contact }

/// A WhatsApp-style bottom sheet for selecting attachment type.
/// Shows a grid of icons: Camera, Gallery, Document, Location, Contact.
Future<AttachAction?> showAttachBottomSheet(BuildContext context) {
  return showModalBottomSheet<AttachAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const _AttachBottomSheet(),
  );
}

class _AttachBottomSheet extends StatelessWidget {
  const _AttachBottomSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // ── Drag handle ────────────────────────────────────
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: HuddlColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // ── Grid of attach options ─────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _AttachIcon(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    color: const Color(0xFFFF5C6A),
                    bgColor: const Color(0xFFFFE8EA),
                    onTap: () => Navigator.pop(context, AttachAction.camera),
                  ),
                  _AttachIcon(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: const Color(0xFF7C4DFF),
                    bgColor: const Color(0xFFF0EAFF),
                    onTap: () => Navigator.pop(context, AttachAction.gallery),
                  ),
                  _AttachIcon(
                    icon: Icons.insert_drive_file_rounded,
                    label: 'Document',
                    color: const Color(0xFF2979FF),
                    bgColor: const Color(0xFFE3F0FF),
                    onTap: () => Navigator.pop(context, AttachAction.document),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _AttachIcon(
                    icon: Icons.location_on_rounded,
                    label: 'Location',
                    color: const Color(0xFF00C853),
                    bgColor: const Color(0xFFE0F8EA),
                    onTap: () => Navigator.pop(context, AttachAction.location),
                  ),
                  _AttachIcon(
                    icon: Icons.person_rounded,
                    label: 'Contact',
                    color: const Color(0xFFFF9100),
                    bgColor: const Color(0xFFFFF3E0),
                    onTap: () => Navigator.pop(context, AttachAction.contact),
                  ),
                  // Invisible spacer to keep the grid even
                  const SizedBox(width: 76),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _AttachIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _AttachIcon({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: HuddlColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
