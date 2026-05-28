import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import 'huddl_button.dart';

/// Illustration asset paths — mapped to new PNG library.
abstract class HuddlIllustration {
  static const chat        = 'assets/illustrations/chatting.png';
  static const community   = 'assets/illustrations/community_wave.png';
  static const meetup      = 'assets/illustrations/group_celebration.png';
  static const events      = 'assets/illustrations/calendar.png';
  static const feed        = 'assets/illustrations/waving_phone.png';
  static const marketplace = 'assets/illustrations/announcement.png';
  static const marketplaceEmpty = 'assets/illustrations/search_found.png';
  static const groupsEmpty = 'assets/illustrations/search_found.png';
  static const saved       = 'assets/illustrations/search_found.png';
  static const auth        = 'assets/illustrations/security.png';
  static const upgrade     = 'assets/illustrations/growth.png';
}

/// Maps illustration path to a representative fallback icon.
IconData _iconForIllustration(String illustration) {
  if (illustration.contains('chatting') || illustration.contains('chat')) {
    return Icons.chat_bubble_outline_rounded;
  }
  if (illustration.contains('community') || illustration.contains('wave')) {
    return Icons.people_outline_rounded;
  }
  if (illustration.contains('group') || illustration.contains('celebration')) {
    return Icons.groups_outlined;
  }
  if (illustration.contains('calendar') || illustration.contains('event')) {
    return Icons.event_outlined;
  }
  if (illustration.contains('waving') || illustration.contains('welcome')) {
    return Icons.waving_hand_outlined;
  }
  if (illustration.contains('announcement') || illustration.contains('marketplace')) {
    return Icons.campaign_outlined;
  }
  if (illustration.contains('search') || illustration.contains('found')) {
    return Icons.search_rounded;
  }
  if (illustration.contains('security') || illustration.contains('auth') || illustration.contains('locked')) {
    return Icons.lock_outline_rounded;
  }
  if (illustration.contains('growth') || illustration.contains('upgrade')) {
    return Icons.star_border_rounded;
  }
  return Icons.image_not_supported_outlined;
}

/// A consistent empty state widget used across Huddl.
/// Renders the PNG illustration asset if path ends with .png,
/// otherwise falls back to a Material icon in a circular container.
class HuddlEmptyState extends StatelessWidget {
  final String illustration;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double illustrationHeight;

  const HuddlEmptyState({
    super.key,
    required this.illustration,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.illustrationHeight = 160,
  });

  @override
  Widget build(BuildContext context) {
    final isPng = illustration.endsWith('.png');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Illustration or icon ─────────────────────────────────
            if (isPng)
              Image.asset(
                illustration,
                height: illustrationHeight,
                fit: BoxFit.contain,
              )
            else
              Container(
                width: illustrationHeight * 0.75,
                height: illustrationHeight * 0.75,
                decoration: const BoxDecoration(
                  color: HuddlColors.inputBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _iconForIllustration(illustration),
                  size: illustrationHeight * 0.45,
                  color: HuddlColors.textTertiary,
                ),
              ),

            const SizedBox(height: 24),

            // ── Title ────────────────────────────────────────────────
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: HuddlColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // ── Subtitle ─────────────────────────────────────────────
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: HuddlColors.textSecondary,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),

            // ── Optional CTA button ──────────────────────────────────
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 28),
              HuddlButton(
                label: actionLabel!,
                onPressed: onAction,
                fullWidth: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
