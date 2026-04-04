import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import '../models/subscription.dart';
import '../services/subscription_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// UPGRADE PROMPT — reusable paywall dialog shown when a gated feature is hit
// ═══════════════════════════════════════════════════════════════════════════════

/// Shows a bottom sheet prompting the user to upgrade when they hit a tier limit.
/// Returns true if the user upgraded, false otherwise.
Future<bool> showUpgradePrompt(
  BuildContext context, {
  required String feature,
  required String message,
  SubscriptionTier? requiredTier,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _UpgradePromptSheet(
      feature: feature,
      message: message,
      requiredTier: requiredTier,
    ),
  );
  return result ?? false;
}

class _UpgradePromptSheet extends StatelessWidget {
  final String feature;
  final String message;
  final SubscriptionTier? requiredTier;

  const _UpgradePromptSheet({
    required this.feature,
    required this.message,
    this.requiredTier,
  });

  @override
  Widget build(BuildContext context) {
    final service = SubscriptionService();
    final currentTier = service.tier;

    return Container(
      decoration: const BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: HuddlColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Lock icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline,
                    color: HuddlColors.primary, size: 32),
              ),
              const SizedBox(height: 20),

              Text('Upgrade Required',
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.textDark)),
              const SizedBox(height: 8),

              Text(message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: HuddlColors.textSecondary)),
              const SizedBox(height: 24),

              // Quick tier previews
              if (currentTier == SubscriptionTier.free) ...[
                _QuickTierPreview(
                  name: 'Plus',
                  price: '\u00A34.99/mo',
                  color: HuddlColors.primary,
                  icon: Icons.star_outline,
                  benefits: const [
                    '20 groups, 15 meetups/mo',
                    'Private groups & events',
                    'Ad-free experience',
                  ],
                  onTap: () {
                    Navigator.pop(context, false);
                    Navigator.pushNamed(context, '/subscription_plans',
                        arguments: {
                          'highlightTier': 'plus',
                          'gateMessage': message,
                        });
                  },
                ),
                const SizedBox(height: 10),
              ],

              _QuickTierPreview(
                name: 'Pro',
                price: '\u00A39.99/mo',
                color: HuddlColors.teal,
                icon: Icons.workspace_premium,
                benefits: const [
                  'Unlimited everything',
                  'Priority support & analytics',
                  'Promoted listings',
                ],
                onTap: () {
                  Navigator.pop(context, false);
                  Navigator.pushNamed(context, '/subscription_plans',
                      arguments: {
                        'highlightTier': 'pro',
                        'gateMessage': message,
                      });
                },
              ),

              const SizedBox(height: 20),

              // View all plans
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, false);
                    Navigator.pushNamed(context, '/subscription_plans',
                        arguments: {'gateMessage': message});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    foregroundColor: HuddlColors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('View All Plans',
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Maybe Later',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.textHint)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTierPreview extends StatelessWidget {
  final String name;
  final String price;
  final Color color;
  final IconData icon;
  final List<String> benefits;
  final VoidCallback onTap;

  const _QuickTierPreview({
    required this.name,
    required this.price,
    required this.color,
    required this.icon,
    required this.benefits,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name,
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.textDark)),
                      const SizedBox(width: 6),
                      Text(price,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: color)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    benefits.join(' \u2022 '),
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: HuddlColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Small inline upgrade banner that can be placed anywhere in the app
class UpgradeBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onTap;

  const UpgradeBanner({
    super.key,
    this.message = 'Upgrade for more features',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ??
          () => Navigator.pushNamed(context, '/subscription_plans'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: HuddlColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.star, color: HuddlColors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.white)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: HuddlColors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Upgrade',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
