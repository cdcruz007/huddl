import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';

/// Illustration asset paths — centralised so renaming is easy.
abstract class HuddlIllustration {
  /// Two people with speech bubbles — chat / messages / groups (messages tab)
  static const chat =
      'assets/images/illustrations/onboarding_chat_illustration.png';

  /// Four people celebrating with geometric shapes — community / discover groups
  static const community =
      'assets/images/illustrations/man__woman__female__male__person__shapes__shape__layout-1.png';

  /// Two people dancing with shapes — meetups / going / activity
  static const meetup =
      'assets/images/illustrations/man__woman__female__male__person__shapes__shape__layout.png';

  /// Two people greeting / dancing — events / social bonding
  static const events =
      'assets/images/illustrations/onboarding_two_people_illustration.png';

  /// Group of four dancing — home feed / announcements / welcome
  static const feed =
      'assets/images/illustrations/onboarding_welcome_illustration.png';

  /// Megaphone with social icons — marketplace / sell / saved items
  static const marketplace =
      'assets/images/illustrations/not_available_illustration.png';

  /// Person with orange handbag next to a storefront phone — marketplace empty/no items
  static const marketplaceEmpty =
      'assets/images/illustrations/marketplace_handbag_illustration.png';

  /// Four people high-fiving / greeting — groups empty / no groups in borough yet
  static const groupsEmpty =
      'assets/images/illustrations/groups_empty_illustration.png';

  /// Single dancing person — bookmarks / saved messages
  static const saved =
      'assets/images/illustrations/Group_3603.png';

  /// Man with oversized key at padlock — biometric lock / security / auth
  /// Source: Huddl uploaded illustration set #20
  static const auth =
      'https://www.genspark.ai/api/files/s/T21ihhOF';
}

/// A consistent, illustration-based empty state widget used across Huddl.
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
            Image.asset(
              illustration,
              height: illustrationHeight,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: HuddlColors.peachLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  size: 36,
                  color: HuddlColors.primary,
                ),
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
}
