import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/browser_storage.dart';
import '../theme/huddl_colors.dart';

// =============================================================================
// CHAT SAFETY NOTICE
//
// Transparent disclosure to users that their chat messages are AI-filtered
// for safety and community standards compliance.
//
// Two components:
//
// 1. ChatSafetyNoticeDialog  — one-time modal, shown on first chat open ever.
//    Stored under BrowserStorage key 'chat_safety_notice_v1'.
//    Explains what is filtered, why, who processes it, and links to Privacy Policy.
//    Must be explicitly dismissed with "Got it".
//
// 2. ChatSafetyStrip  — compact 1-line strip rendered above every chat input bar.
//    Always visible. A shield icon + short text + tappable "Learn more" link
//    that re-opens the full notice on demand.
//
// Legal basis: UK GDPR Art. 13/14 transparency obligation — data subjects must
// be informed at the point of collection what processing their data undergoes.
// Burying this in a Privacy Policy alone is insufficient; it must be visible
// at the point where the data is actually submitted.
// =============================================================================

const String _kStorageKey  = 'chat_safety_notice_v1';
const String _kPrivacyUrl  = 'https://www.huddlapp.co.uk/privacy';

// ── One-time dialog ──────────────────────────────────────────────────────────

/// Call this from an initState `addPostFrameCallback`.
/// Shows the dialog only if the user hasn't dismissed it before.
Future<void> showChatSafetyNoticeIfNeeded(BuildContext context) async {
  final seen = await BrowserStorage.getString(_kStorageKey);
  if (seen == 'seen') return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ChatSafetyNoticeDialog(),
  );
}

class _ChatSafetyNoticeDialog extends StatelessWidget {
  const _ChatSafetyNoticeDialog();

  Future<void> _dismiss(BuildContext context) async {
    await BrowserStorage.setString(_kStorageKey, 'seen');
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _launchPrivacy() async {
    final uri = Uri.parse(_kPrivacyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? HuddlColors.darkSurface : HuddlColors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon ────────────────────────────────────────────────────────
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: HuddlColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_outlined, size: 28, color: HuddlColors.primary),
            ),
            const SizedBox(height: 16),

            // ── Title ────────────────────────────────────────────────────────
            Text(
              'Messages are safety-checked',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? HuddlColors.white : HuddlColors.textDark,
              ),
            ),
            const SizedBox(height: 12),

            // ── Body ─────────────────────────────────────────────────────────
            Text(
              'To keep Huddl safe for everyone — especially children — '
              'all chat messages are automatically checked before they\'re sent.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                height: 1.55,
                color: isDark ? HuddlColors.textSecondary : HuddlColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // ── What's checked list ───────────────────────────────────────
            _BulletRow(
              icon: Icons.check_circle_outline,
              text: 'A local word filter runs on-device — no data leaves your phone',
            ),
            const SizedBox(height: 8),
            _BulletRow(
              icon: Icons.cloud_outlined,
              text: 'An AI safety layer (Google Gemini) checks for threats, '
                  'grooming, and severe harassment',
            ),
            const SizedBox(height: 8),
            _BulletRow(
              icon: Icons.block_outlined,
              text: 'Messages that fail either check are blocked and never stored',
            ),
            const SizedBox(height: 8),
            _BulletRow(
              icon: Icons.person_outline,
              text: 'Huddl moderators can review flagged content via the Report button',
            ),
            const SizedBox(height: 20),

            // ── Privacy link ─────────────────────────────────────────────
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: isDark ? HuddlColors.textHint : HuddlColors.textHint,
                ),
                children: [
                  const TextSpan(text: 'Full details in our '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.primary,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()..onTap = _launchPrivacy,
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Dismiss button ────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _dismiss(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.primary,
                  foregroundColor: HuddlColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Got it',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BulletRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: HuddlColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 12,
              height: 1.5,
              color: isDark ? HuddlColors.textSecondary : HuddlColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Permanent compact strip ───────────────────────────────────────────────────

/// Thin strip rendered directly above the chat input bar on every chat screen.
/// Always visible — not dismissible. Tapping "Learn more" re-shows the full
/// notice dialog (without resetting the "seen" flag).
class ChatSafetyStrip extends StatelessWidget {
  const ChatSafetyStrip({super.key});

  void _showFullNotice(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _ChatSafetyNoticeDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: isDark
            ? HuddlColors.primary.withValues(alpha: 0.08)
            : HuddlColors.primary.withValues(alpha: 0.06),
        border: Border(
          top: BorderSide(
            color: isDark
                ? HuddlColors.primary.withValues(alpha: 0.15)
                : HuddlColors.primary.withValues(alpha: 0.12),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 12, color: HuddlColors.primary.withValues(alpha: 0.8)),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Messages are AI-checked for safety before sending.',
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                color: isDark ? HuddlColors.textHint : HuddlColors.textSecondary,
                height: 1.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => _showFullNotice(context),
            child: Text(
              'Learn more',
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                color: HuddlColors.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
