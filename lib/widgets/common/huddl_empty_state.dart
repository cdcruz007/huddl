import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import 'huddl_button.dart';

/// Illustration asset paths — kept as constants for call-site compatibility.
/// Illustrations have been removed from the UI; these values are unused
/// by the rendering layer but retained so call sites don't need updating.
abstract class HuddlIllustration {
  static const chat = 'assets/illustrations/huddl_celebrating.svg';
  static const community = 'assets/illustrations/onboarding_02_community.svg';
  static const meetup = 'assets/illustrations/onboarding_03_neighbours.svg';
  static const events = 'assets/illustrations/huddl_waving.svg';
  static const feed = 'assets/illustrations/onboarding_01_welcome.svg';
  static const marketplace = 'assets/illustrations/huddl_noticeboard.svg';
  static const marketplaceEmpty = 'assets/illustrations/huddl_supportive.svg';
  static const groupsEmpty = 'assets/illustrations/huddl_neutral.svg';
  static const saved = 'assets/illustrations/huddl_curious.svg';
  static const auth = 'assets/illustrations/huddl_locked.svg';
  static const upgrade = 'assets/illustrations/huddl_upgrade.svg';
}

/// Maps legacy illustration paths to a representative icon.
IconData _iconForIllustration(String illustration) {
  if (illustration.contains('celebrating')) return Icons.celebration_outlined;
  if (illustration.contains('community')) return Icons.people_outline_rounded;
  if (illustration.contains('neighbours') || illustration.contains('meetup')) {
    return Icons.groups_outlined;
  }
  if (illustration.contains('waving') || illustration.contains('welcome')) {
    return Icons.waving_hand_outlined;
  }
  if (illustration.contains('noticeboard') || illustration.contains('marketplace')) {
    return Icons.campaign_outlined;
  }
  if (illustration.contains('supportive')) return Icons.favorite_border_rounded;
  if (illustration.contains('neutral')) return Icons.people_outline_rounded;
  if (illustration.contains('curious') || illustration.contains('search')) {
    return Icons.search_rounded;
  }
  if (illustration.contains('locked') || illustration.contains('auth')) {
    return Icons.lock_outline_rounded;
  }
  if (illustration.contains('upgrade')) return Icons.star_border_rounded;
  return Icons.image_not_supported_outlined;
}

/// A consistent empty state widget used across Huddl.
/// Illustrations removed — renders a Material icon + title + subtitle.
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
    final double iconSize = illustrationHeight * 0.45;
    final double containerSize = illustrationHeight * 0.75;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Icon container ───────────────────────────────────────
            Container(
              width: containerSize,
              height: containerSize,
              decoration: const BoxDecoration(
                color: HuddlColors.inputBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconForIllustration(illustration),
                size: iconSize,
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
