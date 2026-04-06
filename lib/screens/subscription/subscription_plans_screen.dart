import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/subscription.dart';
import '../../services/subscription_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SUBSCRIPTION PLANS — tier comparison & purchase screen
// ═══════════════════════════════════════════════════════════════════════════════

class SubscriptionPlansScreen extends StatefulWidget {
  /// Optional: pre-select a tier (e.g. from an upgrade prompt)
  final SubscriptionTier? highlightTier;
  /// Optional: message shown when redirected from a gated feature
  final String? gateMessage;

  const SubscriptionPlansScreen({
    super.key,
    this.highlightTier,
    this.gateMessage,
  });

  @override
  State<SubscriptionPlansScreen> createState() =>
      _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState extends State<SubscriptionPlansScreen> {
  final SubscriptionService _service = SubscriptionService();
  BillingPeriod _period = BillingPeriod.annual; // Default to annual for LTV

  @override
  void initState() {
    super.initState();
    _service.initialize();
  }

  // ── Purchase flow ────────────────────────────────────────────────────
  Future<void> _onSelectPlan(SubscriptionPlan plan) async {
    if (plan.tier == _service.tier) return; // Already on this plan

    if (plan.tier == SubscriptionTier.explorer) {
      // Downgrade confirmation
      final confirmed = await _showDowngradeDialog();
      if (!confirmed) return;
      await _service.cancelSubscription();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reverted to Explorer plan',
                style: GoogleFonts.poppins(color: HuddlColors.white)),
            backgroundColor: HuddlColors.teal,
          ),
        );
        Navigator.pop(context, true);
      }
      return;
    }

    // Navigate to checkout
    if (mounted) {
      final result = await Navigator.pushNamed(
        context,
        '/subscription_checkout',
        arguments: {
          'tier': plan.tier.name,
          'period': _period.name,
        },
      );
      if (result == true && mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  Future<bool> _showDowngradeDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Downgrade to Explorer?',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            content: Text(
              'You\'ll lose access to premium features at the end of your billing period. '
              'Your groups, conversations, and data will be preserved, but you\'ll '
              'be limited to Explorer tier features.',
              style: GoogleFonts.poppins(
                  fontSize: 14, color: HuddlColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Keep Plan',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.primary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Downgrade',
                    style: GoogleFonts.poppins(color: HuddlColors.error)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close, color: HuddlColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Choose Your Plan',
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textDark)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            children: [
              // Gate message banner
              if (widget.gateMessage != null) _GateBanner(widget.gateMessage!),
              if (widget.gateMessage != null) const SizedBox(height: 16),

              // 7-day Neighbourhood trial CTA
              if (_service.isFree) ...[
                _TrialBanner(onTap: _startTrial),
                const SizedBox(height: 12),
              ],

              // Founding member banner
              if (_service.isFree && _service.foundingMemberAvailable) ...[
                _FoundingMemberBanner(
                  claimed: _service.foundingMembersClaimed,
                  cap: SubscriptionService.foundingMemberCap,
                ),
                const SizedBox(height: 20),
              ] else
                const SizedBox(height: 8),

              // Billing toggle
              _BillingToggle(
                period: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
              const SizedBox(height: 20),

              // Plan cards
              ...SubscriptionPlan.allPlans.map((plan) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _PlanCard(
                      plan: plan,
                      period: _period,
                      isCurrentPlan: plan.tier == _service.tier,
                      isHighlighted: plan.tier == widget.highlightTier ||
                          (widget.highlightTier == null &&
                              plan.tier == SubscriptionTier.neighbourhood),
                      isFoundingAvailable: _service.foundingMemberAvailable,
                      onSelect: () => _onSelectPlan(plan),
                    ),
                  )),

              const SizedBox(height: 16),

              // Feature comparison
              _FeatureComparisonTable(period: _period),

              const SizedBox(height: 24),

              // Restore purchases (Apple Guideline 3.1.1 — required)
              TextButton(
                onPressed: _restorePurchases,
                child: Text('Restore Purchases',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.textHint)),
              ),

              // ── Apple 3.1.2 / Google Play required subscription disclosures ──
              // Apple requires: subscription name, duration, price, renewal/
              // cancellation terms, and links to ToS & Privacy Policy.
              // Google Play requires: prominent disclosure of subscription
              // terms, auto-renewal, how to cancel, and billing information.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  children: [
                    Text(
                      'Subscription Terms',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Payment will be charged to your Apple ID or Google Play '
                      'account at confirmation of purchase. Subscriptions '
                      'automatically renew unless auto-renew is turned off at '
                      'least 24 hours before the end of the current period. '
                      'Your account will be charged for renewal within 24 hours '
                      'prior to the end of the current period at the rate of '
                      'your selected plan. You can manage and cancel your '
                      'subscriptions by going to your account settings on the '
                      'App Store or Google Play Store after purchase. Any '
                      'unused portion of a free trial period will be forfeited '
                      'when you purchase a subscription. Prices shown are in '
                      'GBP and may vary by region.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 10, color: HuddlColors.textLight),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            // TODO: Navigate to Terms of Service URL
                          },
                          child: Text('Terms of Service',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: HuddlColors.primary,
                                  decoration: TextDecoration.underline)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('\u2022',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: HuddlColors.textLight)),
                        ),
                        GestureDetector(
                          onTap: () {
                            // TODO: Navigate to Privacy Policy URL
                          },
                          child: Text('Privacy Policy',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: HuddlColors.primary,
                                  decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startTrial() async {
    final ok = await _service.startTrial();
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('7-day Neighbourhood trial activated! Enjoy unlimited access.',
              style: GoogleFonts.poppins(color: HuddlColors.white)),
          backgroundColor: HuddlColors.teal,
        ),
      );
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trial already used. Choose a plan to continue!',
              style: GoogleFonts.poppins(color: HuddlColors.white)),
          backgroundColor: HuddlColors.textHint,
        ),
      );
    }
  }

  Future<void> _restorePurchases() async {
    final restored = await _service.restorePurchases();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restored
                ? 'Subscription restored!'
                : 'No previous purchases found.',
            style: GoogleFonts.poppins(color: HuddlColors.white),
          ),
          backgroundColor: restored ? HuddlColors.teal : HuddlColors.textHint,
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUBWIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

/// Banner shown when a gated feature redirects the user here
class _GateBanner extends StatelessWidget {
  final String message;
  const _GateBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.peachLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: HuddlColors.primaryDark, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.textDark)),
          ),
        ],
      ),
    );
  }
}

/// 7-day Neighbourhood trial banner
class _TrialBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _TrialBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF0E6), Color(0xFFFFF8F0)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: HuddlColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: HuddlColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Try Neighbourhood free for 7 days',
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textDark)),
                const SizedBox(height: 2),
                Text(
                    'Unlimited groups, DMs, meetups & more. No card required.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: HuddlColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: HuddlColors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Start',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Founding member urgency banner
class _FoundingMemberBanner extends StatelessWidget {
  final int claimed;
  final int cap;
  const _FoundingMemberBanner({required this.claimed, required this.cap});

  @override
  Widget build(BuildContext context) {
    final remaining = cap - claimed;
    final progress = claimed / cap;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF5F0FF), Color(0xFFFAF5FF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3580F0).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3580F0).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_fire_department,
                    color: Color(0xFF3580F0), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Founding Member: \u00A33.99/mo locked for life',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3580F0)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF3580F0).withValues(alpha: 0.1),
              color: const Color(0xFF3580F0),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$claimed of $cap claimed',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: HuddlColors.textSecondary)),
              Text('Only $remaining spots left!',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3580F0))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Billing period toggle
class _BillingToggle extends StatelessWidget {
  final BillingPeriod period;
  final ValueChanged<BillingPeriod> onChanged;

  const _BillingToggle({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: HuddlColors.gray100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _toggleButton('Monthly', BillingPeriod.monthly),
          _toggleButton('Annual', BillingPeriod.annual, showSave: true),
        ],
      ),
    );
  }

  Widget _toggleButton(String label, BillingPeriod value,
      {bool showSave = false}) {
    final isActive = period == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? HuddlColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: HuddlColors.gray900.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive
                        ? HuddlColors.textDark
                        : HuddlColors.textHint,
                  )),
              if (showSave) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: HuddlColors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Save 30%',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.teal)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Individual plan card
class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final BillingPeriod period;
  final bool isCurrentPlan;
  final bool isHighlighted;
  final bool isFoundingAvailable;
  final VoidCallback onSelect;

  const _PlanCard({
    required this.plan,
    required this.period,
    required this.isCurrentPlan,
    required this.isHighlighted,
    required this.isFoundingAvailable,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final price = plan.priceFor(period);
    final isFree = plan.tier == SubscriptionTier.explorer;
    final isNeighbourhood = plan.tier == SubscriptionTier.neighbourhood;
    Color borderColor = HuddlColors.gray200;
    Color bgColor = HuddlColors.white;
    if (isHighlighted && !isCurrentPlan) {
      borderColor = HuddlColors.primary;
      bgColor = HuddlColors.peachVeryLight;
    }
    if (isCurrentPlan) {
      borderColor = HuddlColors.teal;
      bgColor = HuddlColors.successBg;
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isHighlighted || isCurrentPlan ? 2 : 1),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: HuddlColors.primary.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _tierColor(plan.tier).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_tierIcon(plan.tier),
                      color: _tierColor(plan.tier), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(plan.name,
                              style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: HuddlColors.textDark)),
                          if (isCurrentPlan) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: HuddlColors.teal,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Current',
                                  style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: HuddlColors.white)),
                            ),
                          ],
                          if (isHighlighted && !isCurrentPlan) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: HuddlColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Best Value',
                                  style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: HuddlColors.white)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(plan.tagline,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: HuddlColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Price
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isFree
                      ? 'Free'
                      : '\u00A3${price.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.textDark),
                ),
                if (!isFree) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      period == BillingPeriod.monthly
                          ? '/month'
                          : '/year',
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: HuddlColors.textHint),
                    ),
                  ),
                  if (period == BillingPeriod.annual && plan.annualSavingsPercent > 0) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: HuddlColors.teal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Save ${plan.annualSavingsPercent}%',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.teal),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          // Subtitle
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(plan.subtitle,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: HuddlColors.textHint)),
            ),
          ),

          // Founding member price callout
          if (isNeighbourhood && isFoundingAvailable && period == BillingPeriod.monthly) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF3580F0).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: Color(0xFF3580F0), size: 14),
                    const SizedBox(width: 4),
                    Text('Founding: \u00A33.99/mo locked for life',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF3580F0))),
                  ],
                ),
              ),
            ),
          ],

          // Highlights
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              children: plan.highlights
                  .map((h) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_circle,
                                  size: 16,
                                  color: _tierColor(plan.tier)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(h,
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: HuddlColors.textSecondary)),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),

          // CTA button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isCurrentPlan ? null : onSelect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCurrentPlan
                      ? HuddlColors.gray200
                      : (isHighlighted
                          ? HuddlColors.primary
                          : HuddlColors.textDark),
                  foregroundColor: HuddlColors.white,
                  disabledBackgroundColor: HuddlColors.successBg,
                  disabledForegroundColor: HuddlColors.teal,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  isCurrentPlan
                      ? 'Current Plan'
                      : (isFree ? 'Downgrade' : 'Choose ${plan.name}'),
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _tierColor(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.explorer:
        return HuddlColors.textHint;
      case SubscriptionTier.neighbourhood:
        return HuddlColors.primary;
      case SubscriptionTier.innerCircle:
        return HuddlColors.teal;
    }
  }

  static IconData _tierIcon(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.explorer:
        return Icons.explore_outlined;
      case SubscriptionTier.neighbourhood:
        return Icons.home_outlined;
      case SubscriptionTier.innerCircle:
        return Icons.workspace_premium;
    }
  }
}

/// Detailed feature comparison table
class _FeatureComparisonTable extends StatelessWidget {
  final BillingPeriod period;
  const _FeatureComparisonTable({required this.period});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Compare all features',
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textDark)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: HuddlColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: HuddlColors.gray200),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: const BoxDecoration(
                  color: HuddlColors.surfaceLight,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child: Text('Feature',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.textHint))),
                    Expanded(
                        child: Text('Explorer',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.textHint))),
                    Expanded(
                        child: Text('N’hood',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.primary))),
                    Expanded(
                        child: Text('Inner\nCircle',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.teal))),
                  ],
                ),
              ),
              // ---- Community section ----
              _sectionHeader('Community'),
              _row('Groups joined', '2', '\u221E', '\u221E'),
              _row('Groups created', '1', '25', '\u221E'),
              _row('Meetups/month', '2', '\u221E', '\u221E'),
              _row('DM conversations', '5', '\u221E', '\u221E'),
              _row('Messages/month', '30', '\u221E', '\u221E'),
              _row('Marketplace listings', '2', '15', '\u221E'),
              _row('Photo uploads', '3', '15', '50'),
              _rowBool('Private groups', false, true, true),
              _rowBool('Create meetups', false, true, true),
              _rowBool('Ad-free', false, true, true),
              _rowBool('Profile badge', false, true, true),
              _rowBool('Milestone tracker', false, true, true),

              // ---- AI Features section ----
              _sectionHeader('AI Features'),
              _row('AI Copilot', '3/day', '25/day', '\u221E'),
              _row('AI Chat Summaries', '1/day', '10/day', '\u221E'),
              _row('AI Event Discovery', '1/wk', 'Daily', '\u221E'),
              _rowBool('AI Recommendations', true, true, true),
              _rowBool('AI Smart Feed', true, true, true),
              _row('AI Listing Generator', '\u2014', '10/mo', '\u221E'),
              _row('AI Travel Concierge', '\u2014', '15/day', '\u221E'),
              _rowBool('AI Matchmaker', false, false, true),

              // ---- Travel section ----
              _sectionHeader('Travel'),
              _rowBool('Browse destinations', true, true, true),
              _row('Saved trips', '1', '10', '\u221E'),
              _rowBool('AI packing lists', false, true, true),


            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: HuddlColors.primary.withValues(alpha: 0.06),
        border: const Border(bottom: BorderSide(color: HuddlColors.gray100)),
      ),
      child: Text(title,
          style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: HuddlColors.primary)),
    );
  }

  Widget _row(String label, String explorer, String neighbourhood, String inner) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: HuddlColors.gray100)),
      ),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: HuddlColors.textSecondary))),
          Expanded(
              child: Text(explorer,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textHint))),
          Expanded(
              child: Text(neighbourhood,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.primary))),
          Expanded(
              child: Text(inner,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.teal))),
        ],
      ),
    );
  }

  Widget _rowBool(String label, bool explorer, bool neighbourhood, bool inner) {
    Widget checkIcon(bool val, Color color) => Icon(
          val ? Icons.check_circle : Icons.remove_circle_outline,
          size: 16,
          color: val ? color : HuddlColors.gray300,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: HuddlColors.gray100)),
      ),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: HuddlColors.textSecondary))),
          Expanded(child: Center(child: checkIcon(explorer, HuddlColors.textHint))),
          Expanded(child: Center(child: checkIcon(neighbourhood, HuddlColors.primary))),
          Expanded(child: Center(child: checkIcon(inner, HuddlColors.teal))),
        ],
      ),
    );
  }
}
