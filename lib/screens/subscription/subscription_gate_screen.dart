import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/subscription.dart';

// =============================================================================
// SUBSCRIPTION GATE SCREEN
//
// Shown when a free user taps a locked feature. Full-screen, orange header,
// shows exactly what they tried to do and why it needs Plus.
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
    this.featureIcon = Icons.lock_outline_rounded,
  });

  /// Convenience static method — preferred over Navigator.pushNamed for
  /// call sites that already have a BuildContext.
  static Future<bool> show(
    BuildContext context, {
    required String featureTitle,
    required String featureDescription,
    String requiredPlan = 'Huddl Plus',
    IconData featureIcon = Icons.lock_outline_rounded,
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
    (Icons.people_outline,
        'Every parent conversation in Cambridge'),
    (Icons.auto_awesome_outlined,
        'AI finds local events before you search'),
    (Icons.sell_outlined,
        'AI writes your preloved listings'),
    (Icons.summarize_outlined,
        'Group summaries catch you up instantly'),
    (Icons.verified_outlined,
        'Your Huddl Plus badge'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [

          // ── Orange hero — matches plans screen ──────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.of(context).padding.top + 20,
              24,
              28,
            ),
            decoration: const BoxDecoration(
              color: HuddlColors.primary,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Feature icon badge
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child:
                      Icon(featureIcon, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 16),
                Text(
                  featureTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  featureDescription,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.85),
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
            padding:
                EdgeInsets.fromLTRB(24, 12, 24, bottomPad + 24),
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
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'Unlock with $requiredPlan \u2014 from \u00A34.99/mo',
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
