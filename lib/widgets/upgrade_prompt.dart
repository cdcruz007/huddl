import 'package:flutter/material.dart';
import 'common/huddl_button.dart';
import '../theme/huddl_colors.dart';
import '../models/subscription.dart';
import '../services/subscription_service.dart';
import '../constants/app_text_styles.dart';

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
      decoration: BoxDecoration(
        color: context.hc.surface,
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
                  color: const Color(0xFFF7F7F7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline,
                    color: HuddlColors.textDark, size: 32),
              ),
              const SizedBox(height: 20),

              Text('Upgrade to Unlock',
                  style: HuddlText.display(color: context.hc.textPrimary)),
              const SizedBox(height: 8),

              Text(message,
                  textAlign: TextAlign.center,
                  style: HuddlText.body(color: context.hc.textSecondary)),
              const SizedBox(height: 24),

              // Quick tier previews
              if (currentTier == SubscriptionTier.welcome) ...[
                _QuickTierPreview(
                  name: 'Huddl Plus',
                  price: '\u00A34.99/mo',
                  color: HuddlColors.primary,
                  icon: Icons.home_outlined,
                  benefits: const [
                    'Unlimited groups, DMs & meetups',
                    'Create private & invite-only groups',
                    'Full AI suite — Chat Helper, Summaries & more',
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
                name: 'Huddl Partner',
                price: '\u00A324.99/mo',
                color: HuddlColors.nearBlack,
                icon: Icons.verified_outlined,
                benefits: const [
                  'Everything in Huddl Plus, fully unlimited',
                  'HMRC-verified badge + dedicated business profile',
                  'Priority directory placement & reach analytics',
                ],
                onTap: () {
                  Navigator.pop(context, false);
                  Navigator.pushNamed(context, '/subscription_plans',
                      arguments: {
                        'highlightTier': 'partner',
                        'gateMessage': message,
                      });
                },
              ),

              const SizedBox(height: 16),

              // 7-day trial CTA (only if on Welcome and trial not used)
              if (currentTier == SubscriptionTier.welcome) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: HuddlColors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: HuddlColors.divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: HuddlColors.textDark, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Try Huddl Plus free for 7 days — no card required',
                          style: HuddlText.caption(color: context.hc.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // View all plans
              HuddlButton(
                label: 'View All Plans',
                onPressed: () {
                  Navigator.pop(context, false);
                  Navigator.pushNamed(context, '/subscription_plans',
                      arguments: {'gateMessage': message});
                },
              ),
              const SizedBox(height: 4),
              HuddlButton(
                label: 'Maybe Later',
                variant: HuddlButtonVariant.ghost,
                onPressed: () => Navigator.pop(context, false),
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
                          style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                      const SizedBox(width: 6),
                      Text(price,
                          style: HuddlText.caption(color: color)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    benefits.join(' \u2022 '),
                    style: HuddlText.caption(color: context.hc.textSecondary),
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
    this.message = 'Upgrade to Huddl Plus for unlimited access',
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HuddlColors.primary, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.star_rounded, color: HuddlColors.yellow, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: HuddlText.body(color: HuddlColors.nearBlack)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: HuddlColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Upgrade',
                  style: HuddlText.caption(weight: FontWeight.w600, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
