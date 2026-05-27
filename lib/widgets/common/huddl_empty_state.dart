import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/huddl_colors.dart';

/// Illustration asset paths — centralised so renaming is easy.
///
/// All illustrations now use the on-brand Huddl SVG set from
/// assets/illustrations/. The old stock PNGs in
/// assets/images/illustrations/ are no longer referenced here.
abstract class HuddlIllustration {
  /// Two people celebrating together — chat / messages / groups (messages tab)
  static const chat = 'assets/illustrations/huddl_celebrating.svg';

  /// Community gathering scene — discover groups / community feed
  static const community = 'assets/illustrations/onboarding_02_community.svg';

  /// Neighbours connecting — meetups / going / local activity
  static const meetup = 'assets/illustrations/onboarding_03_neighbours.svg';

  /// Character waving hello — events / social bonding / greetings
  static const events = 'assets/illustrations/huddl_waving.svg';

  /// Welcome screen illustration — home feed / announcements / welcome
  static const feed = 'assets/illustrations/onboarding_01_welcome.svg';

  /// Noticeboard with posts — marketplace / sell / announcements
  static const marketplace = 'assets/illustrations/huddl_noticeboard.svg';

  /// Supportive / caring character — marketplace empty / no items
  static const marketplaceEmpty = 'assets/illustrations/huddl_supportive.svg';

  /// Neutral waiting character — groups empty / no groups in borough yet
  static const groupsEmpty = 'assets/illustrations/huddl_neutral.svg';

  /// Curious character looking around — bookmarks / saved messages
  static const saved = 'assets/illustrations/huddl_curious.svg';

  /// Man with oversized key at padlock — biometric lock / security / auth
  static const auth = 'assets/illustrations/huddl_locked.svg';

  /// Upgrade / premium — subscription upsell screens
  static const upgrade = 'assets/illustrations/huddl_upgrade.svg';
}

/// A consistent, illustration-based empty state widget used across Huddl.
///
/// Renders SVG illustrations from the on-brand Huddl illustration set.
///
/// Usage:
/// ```dart
/// HuddlEmptyState(
///   illustration: HuddlIllustration.chat,
///   title: 'No groups yet',
///   subtitle: 'Join a group to start chatting with your community.',
/// )
/// ```
class HuddlEmptyState extends StatelessWidget {
  final String illustration;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// How tall the illustration image is rendered. Defaults to 160.
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Illustration ─────────────────────────────────────────
            _buildIllustration(),

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
              style: TextStyle(
                fontSize: 14,
                color: HuddlColors.textSecondary,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),

            // ── Optional CTA button ──────────────────────────────────
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  minimumSize: const Size(140, 48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  elevation: 0,
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIllustration() {
    // SVG paths (assets/illustrations/*.svg)
    if (illustration.endsWith('.svg')) {
      return SvgPicture.asset(
        illustration,
        height: illustrationHeight,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => SizedBox(
          width: illustrationHeight,
          height: illustrationHeight,
        ),
      );
    }

    // Fallback: PNG / network image (legacy paths kept working)
    if (illustration.startsWith('http')) {
      return Image.network(
        illustration,
        height: illustrationHeight,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fallbackIcon(),
      );
    }

    return Image.asset(
      illustration,
      height: illustrationHeight,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _fallbackIcon(),
    );
  }

  Widget _fallbackIcon() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 36,
        color: HuddlColors.textDark,
      ),
    );
  }
}
