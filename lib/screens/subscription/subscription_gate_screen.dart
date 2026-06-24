import 'package:flutter/material.dart';
import '../../theme/huddl_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/subscription.dart';
import '../../widgets/huddl_character.dart';

// =============================================================================
// SUBSCRIPTION GATE SCREEN
//
// Shown when a free user taps a locked feature. Full-screen, warm illustrated
// header, shows exactly what they tried to do and why it needs Plus.
// Single CTA: "Unlock with Huddl Plus" → pushes to subscription_plans.
//
// Usage:
//   SubscriptionGateScreen.show(context,
//     featureTitle: 'Private Groups',
//     featureDescription: 'Create a private group for your antenatal class.',
//   );
//
// Or via named route:
//   Navigator.pushNamed(context, '/subscription_gate', arguments: {
//     'featureTitle': 'Private Groups',
//     'featureDescription': 'Create a private group for your antenatal class.',
//     'requiredPlan': 'Huddl Plus',
//   });
// =============================================================================

/// Maps a feature icon codePoint → a warm illustration asset path.
/// Falls back to unlock_key if no specific match.
String _illustrationForFeature(int iconCodePoint) {
  // store / marketplace listing
  if (iconCodePoint == HuddlIcons.storefront.codePoint ||
      iconCodePoint == HuddlIcons.sellTag.codePoint) {
    return 'assets/illustrations/mobile_store_woman.webp';
  }
  // phone / contact / messages
  if (iconCodePoint == HuddlIcons.phone.codePoint ||
      iconCodePoint == HuddlIcons.chat.codePoint ||
      iconCodePoint == HuddlIcons.chat.codePoint) {
    return 'assets/illustrations/questions_two.webp';
  }
  // calendar / booking
  if (iconCodePoint == HuddlIcons.calendar.codePoint ||
      iconCodePoint == HuddlIcons.calendar.codePoint) {
    return 'assets/illustrations/calendar_event.webp';
  }
  // people / groups
  if (iconCodePoint == HuddlIcons.usersThree.codePoint ||
      iconCodePoint == HuddlIcons.usersThree.codePoint) {
    return 'assets/illustrations/community_wave.webp';
  }
  // handshake / services
  if (iconCodePoint == HuddlIcons.handshake.codePoint) {
    return 'assets/illustrations/handshake.webp';
  }
  // default
  return 'assets/illustrations/unlock_key.webp';
}

class SubscriptionGateScreen extends StatelessWidget {
  final String featureTitle;
  final String featureDescription;
  final String requiredPlan;
  final IconData featureIcon;

  const SubscriptionGateScreen({
    super.key,
    required this.featureTitle,
    required this.featureDescription,
    this.requiredPlan = 'Huddl Plus',
    this.featureIcon = HuddlIcons.lock,
  });

  /// Convenience static method — preferred over Navigator.pushNamed for
  /// call sites that already have a BuildContext.
  static Future<bool> show(
    BuildContext context, {
    required String featureTitle,
    required String featureDescription,
    String requiredPlan = 'Huddl Plus',
    IconData featureIcon = HuddlIcons.lock,
  }) async {
    final result = await Navigator.pushNamed(
      context,
      '/subscription_gate',
      arguments: {
        'featureTitle': featureTitle,
        'featureDescription': featureDescription,
        'requiredPlan': requiredPlan,
        'featureIcon': featureIcon.codePoint,
      },
    );
    return result == true;
  }

  // Plus benefit tiles shown below the hero
  static const List<(IconData, String)> _plusBenefits = [
    (HuddlIcons.usersThree,
        'Every parent conversation in Cambridge'),
    (HuddlIcons.ai,
        'AI finds local events before you search'),
    (HuddlIcons.sellTag,
        'AI writes your preloved listings'),
    (HuddlIcons.summarize,
        'Group summaries catch you up instantly'),
    (HuddlIcons.verified,
        'Your Huddl Plus badge'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final topPad    = MediaQuery.of(context).padding.top;
    final illustrationAsset = _illustrationForFeature(featureIcon.codePoint);

    return Scaffold(
      backgroundColor: isDark ? HuddlColors.darkBackground : Colors.white,
      body: Column(
        children: [

          // ── Warm illustrated hero — soft peach gradient replaces solid orange ──
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(24, topPad + 16, 24, 28),
            decoration: BoxDecoration(
              // Layered warm gradient: lightest peach at top → slightly richer at base
              gradient: isDark
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        HuddlColors.peachWarm, // warmest peach
                        HuddlColors.peachSurface, // soft apricot
                      ],
                    ),
              color: isDark ? HuddlColors.darkSurface : null,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Close button — dark text on light bg
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: HuddlColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(HuddlIcons.close,
                          size: 16, color: HuddlColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Illustration + text side-by-side
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Warm illustration circle
                    WarmCircleIllustration(
                      assetPath: illustrationAsset,
                      size: 72,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // "Huddl Plus" eyebrow
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: HuddlColors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              requiredPlan,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            featureTitle,
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.nearBlack,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Text(
                  featureDescription,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: HuddlColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // ── What you also get with Plus ─────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'With $requiredPlan you also get:',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.nearBlack,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._plusBenefits.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: HuddlColors.primary
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(item.$1,
                                  size: 18, color: HuddlColors.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.$2,
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  color: HuddlColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),

          // ── CTA ─────────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, bottomPad + 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await Navigator.pushNamed(
                        context,
                        '/subscription_plans',
                        arguments: {
                          'highlightTier': SubscriptionTier.plus.name,
                          'gateMessage': featureDescription,
                        },
                      );
                      if (result == true && context.mounted) {
                        Navigator.pop(context, true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HuddlColors.primary,
                      foregroundColor: HuddlColors.textPrimary, // WCAG AA: 6.67:1 ✔
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'Unlock with $requiredPlan — from £4.99/mo',
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    'Maybe later',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: HuddlColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
