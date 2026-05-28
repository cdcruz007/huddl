import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/browser_storage.dart';
import '../theme/huddl_colors.dart';
import 'common/huddl_button.dart';
import '../constants/app_text_styles.dart';

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
    barrierDismissible: true,   // tapping outside dismisses (Figma spec)
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
                color: const Color(0xFFF7F7F7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_outlined, size: 28, color: HuddlColors.textDark),
            ),
            const SizedBox(height: 16),

            // ── Title ────────────────────────────────────────────────────────
            Text(
              'Huddl keeps chats safe',
              textAlign: TextAlign.center,
              style: HuddlText.heading(),
            ),
            const SizedBox(height: 12),

            // ── Body ─────────────────────────────────────────────────────────
            Text(
              'We want Huddl to feel like a trusted space for every parent. '
              'A few things happen in the background to help keep it that way.',
              textAlign: TextAlign.center,
              style: HuddlText.body().copyWith(height: 1.55),
            ),
            const SizedBox(height: 16),

            // ── What happens list ─────────────────────────────────────────
            _BulletRow(
              icon: Icons.check_circle_outline,
              text: 'Automated checks help catch harmful content before it reaches others',
            ),
            const SizedBox(height: 8),
            _BulletRow(
              icon: Icons.block_outlined,
              text: 'Anything that breaks our community guidelines is quietly blocked — not stored',
            ),
            const SizedBox(height: 8),
            _BulletRow(
              icon: Icons.flag_outlined,
              text: 'You can always report a message using the long-press menu',
            ),
            const SizedBox(height: 20),

            // ── Privacy link ─────────────────────────────────────────────
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: HuddlText.caption(),
                children: [
                  const TextSpan(text: 'Full details in our '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: HuddlText.caption(color: HuddlColors.textTertiary).copyWith(decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()..onTap = _launchPrivacy,
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Dismiss button ────────────────────────────────────────────
            HuddlButton(
              label: 'Got it, thanks',
              onPressed: () => _dismiss(context),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: HuddlColors.textDark),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: HuddlText.caption().copyWith(height: 1.5),
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
            ? const Color(0xFFF7F7F7)
            : const Color(0xFFF7F7F7),
        border: Border(
          top: BorderSide(
            color: isDark
                ? HuddlColors.divider
                : HuddlColors.divider,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 12, color: HuddlColors.textDark),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Huddl keeps this a safe space for families.',
              style: HuddlText.label(color: isDark ? HuddlColors.textHint : HuddlColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => _showFullNotice(context),
            child: Text(
              'About this',
              style: HuddlText.label(color: HuddlColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
