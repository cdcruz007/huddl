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
  BillingPeriod _period = BillingPeriod.annual;

  @override
  void initState() {
    super.initState();
    _service.initialize();
  }

  // ── Purchase flow ────────────────────────────────────────────────────
  Future<void> _onSelectPlan(SubscriptionPlan plan) async {
    if (plan.tier == _service.tier) return; // Already on this plan

    if (plan.tier == SubscriptionTier.free) {
      // Downgrade confirmation
      final confirmed = await _showDowngradeDialog();
      if (!confirmed) return;
      await _service.cancelSubscription();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reverted to Free plan',
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
            title: Text('Downgrade to Free?',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            content: Text(
              'You\'ll lose access to premium features at the end of your billing period. Your data will be preserved.',
              style: GoogleFonts.poppins(
                  fontSize: 14, color: HuddlColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: GoogleFonts.poppins(color: HuddlColors.textHint)),
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

              // Trial CTA
              if (_service.isFree) ...[
                _TrialBanner(onTap: _startTrial),
                const SizedBox(height: 20),
              ],

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
                              plan.tier == SubscriptionTier.plus),
                      onSelect: () => _onSelectPlan(plan),
                    ),
                  )),

              const SizedBox(height: 16),

              // Feature comparison
              _FeatureComparisonTable(period: _period),

              const SizedBox(height: 24),

              // Restore purchases
              TextButton(
                onPressed: _restorePurchases,
                child: Text('Restore Purchases',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.textHint)),
              ),

              // Legal
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'Subscriptions are billed through your app store account. '
                  'Plans auto-renew unless cancelled 24 hours before the end of the current period.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: HuddlColors.textLight),
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
          content: Text('14-day Plus trial activated!',
              style: GoogleFonts.poppins(color: HuddlColors.white)),
          backgroundColor: HuddlColors.teal,
        ),
      );
      Navigator.pop(context, true);
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

/// 14-day trial banner
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
            child: const Icon(Icons.star, color: HuddlColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Try Plus free for 14 days',
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textDark)),
                const SizedBox(height: 2),
                Text(
                    'More groups, private groups, events & ad-free. Cancel anytime.',
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
                  child: Text('Save 33%',
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
  final VoidCallback onSelect;

  const _PlanCard({
    required this.plan,
    required this.period,
    required this.isCurrentPlan,
    required this.isHighlighted,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final price = plan.priceFor(period);
    final isFree = plan.tier == SubscriptionTier.free;
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
                              child: Text('Popular',
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

          // Highlights
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              children: plan.highlights
                  .map((h) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 16,
                                color: _tierColor(plan.tier)),
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
      case SubscriptionTier.free:
        return HuddlColors.textHint;
      case SubscriptionTier.plus:
        return HuddlColors.primary;
      case SubscriptionTier.pro:
        return HuddlColors.teal;
    }
  }

  static IconData _tierIcon(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.free:
        return Icons.person_outline;
      case SubscriptionTier.plus:
        return Icons.star_outline;
      case SubscriptionTier.pro:
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
                        child: Text('Free',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.textHint))),
                    Expanded(
                        child: Text('Plus',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.primary))),
                    Expanded(
                        child: Text('Pro',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.teal))),
                  ],
                ),
              ),
              _row('Groups joined', '5', '20', '\u221E'),
              _row('Groups created', '2', '10', '\u221E'),
              _row('Meetups/month', '3', '15', '\u221E'),
              _row('DM conversations', '10', '50', '\u221E'),
              _row('Marketplace listings', '5', '25', '\u221E'),
              _row('Photo uploads', '3', '10', '50'),
              _rowBool('Private groups', false, true, true),
              _rowBool('Create events', false, true, true),
              _rowBool('Ad-free', false, true, true),
              _rowBool('Profile badge', false, true, true),
              _rowBool('Priority support', false, false, true),
              _rowBool('Analytics', false, false, true),
              _rowBool('Promoted listings', false, false, true),
              _rowBool('Early access', false, false, true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String free, String plus, String pro) {
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
              child: Text(free,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textHint))),
          Expanded(
              child: Text(plus,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.primary))),
          Expanded(
              child: Text(pro,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.teal))),
        ],
      ),
    );
  }

  Widget _rowBool(String label, bool free, bool plus, bool pro) {
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
          Expanded(child: Center(child: checkIcon(free, HuddlColors.textHint))),
          Expanded(child: Center(child: checkIcon(plus, HuddlColors.primary))),
          Expanded(child: Center(child: checkIcon(pro, HuddlColors.teal))),
        ],
      ),
    );
  }
}
