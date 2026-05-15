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
    if (plan.tier == _service.tier && !_service.hasScheduledChange && !_service.isPendingCancellation) return;

    // ── Reactivate if currently pending cancellation and user taps current plan
    if (plan.tier == _service.tier && _service.isPendingCancellation) {
      final confirmed = await _showReactivateDialog();
      if (!confirmed) return;
      await _service.reactivateSubscription();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscription reactivated! Your plan will continue to renew.',
                style: GoogleFonts.poppins(color: HuddlColors.white)),
            backgroundColor: HuddlColors.teal,
          ),
        );
        setState(() {});
      }
      return;
    }

    // ── Revert scheduled change if user re-selects their current plan
    if (plan.tier == _service.tier && _service.hasScheduledChange) {
      final confirmed = await _showRevokeScheduledDialog();
      if (!confirmed) return;
      await _service.revokeScheduledChange();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scheduled change revoked. Your current plan continues.',
                style: GoogleFonts.poppins(color: HuddlColors.white)),
            backgroundColor: HuddlColors.teal,
          ),
        );
        setState(() {});
      }
      return;
    }

    // ── Downgrade to Explorer (cancel)
    if (plan.tier == SubscriptionTier.explorer) {
      if (_service.isPaid) {
        // Paid user cancelling — keep access until end of period
        final confirmed = await _showDowngradeDialog();
        if (!confirmed) return;
        await _service.cancelSubscription();
        if (mounted) {
          final summary = _service.scheduledChangeSummary ?? 'end of billing period';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Subscription cancelled. You keep full access until $summary.',
                  style: GoogleFonts.poppins(color: HuddlColors.white)),
              backgroundColor: HuddlColors.primary,
            ),
          );
          setState(() {});
        }
      } else {
        // Already free
        await _service.cancelSubscription();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Reverted to Welcome plan',
                  style: GoogleFonts.poppins(color: HuddlColors.white)),
              backgroundColor: HuddlColors.teal,
            ),
          );
          Navigator.pop(context, true);
        }
      }
      return;
    }

    // ── New purchase from Explorer (immediate) or tier change (scheduled)
    if (_service.isFree) {
      // Immediate purchase from free tier
      if (mounted) {
        final result = await Navigator.pushNamed(
          context,
          '/subscription_checkout',
          arguments: {
            'tier': plan.tier.name,
            'period': _period.name,
            'isScheduled': false,
          },
        );
        if (result == true && mounted) {
          Navigator.pop(context, true);
        }
      }
    } else {
      // Paid user switching tier — schedule for next billing cycle
      if (mounted) {
        final result = await Navigator.pushNamed(
          context,
          '/subscription_checkout',
          arguments: {
            'tier': plan.tier.name,
            'period': _period.name,
            'isScheduled': true,
          },
        );
        if (result == true && mounted) {
          setState(() {}); // Refresh plan cards
        }
      }
    }
  }

  Future<bool> _showDowngradeDialog() async {
    final renewalInfo = _service.renewalDate != null
        ? 'You\'ll keep full access to your current plan until '
          '${UserSubscription.formatDate(_service.renewalDate)}. '
          'After that, you\'ll be on the Welcome (free) plan.'
        : 'You\'ll lose access to premium features at the end of your billing period. '
          'Your groups, conversations, and data will be preserved, but you\'ll '
          'be limited to the Welcome plan features.';

    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Cancel Subscription?',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, color: context.hc.textPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  renewalInfo,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: context.hc.textSecondary),
                ),
                if (_service.daysUntilRenewal > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: HuddlColors.blueBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: HuddlColors.blue, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_service.daysUntilRenewal} days remaining in your current period.',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: HuddlColors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
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
                child: Text('Cancel Subscription',
                    style: GoogleFonts.poppins(color: HuddlColors.error)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showReactivateDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Reactivate Subscription?',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, color: context.hc.textPrimary)),
            content: Text(
              'Your cancellation will be reversed and your plan will '
              'continue to auto-renew at the end of the current billing period.',
              style: GoogleFonts.poppins(
                  fontSize: 14, color: context.hc.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Keep Cancelled',
                    style: GoogleFonts.poppins(color: context.hc.textTertiary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Reactivate',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.teal)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showRevokeScheduledDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Keep Current Plan?',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, color: context.hc.textPrimary)),
            content: Text(
              'This will cancel the scheduled plan change. '
              'Your current plan will continue to renew normally.',
              style: GoogleFonts.poppins(
                  fontSize: 14, color: context.hc.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Keep Scheduled Change',
                    style: GoogleFonts.poppins(color: context.hc.textTertiary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Keep Current Plan',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.primary)),
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
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Choose Your Plan',
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.hc.textPrimary)),
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

              // ── Pending cancellation / scheduled change banner ─────────
              if (_service.isPendingCancellation || _service.hasScheduledChange)
                _ScheduledChangeBanner(
                  summary: _service.scheduledChangeSummary ?? '',
                  isCancellation: _service.isPendingCancellation,
                  daysRemaining: _service.daysUntilRenewal,
                  onRevert: () async {
                    if (_service.isPendingCancellation) {
                      await _service.reactivateSubscription();
                    } else {
                      await _service.revokeScheduledChange();
                    }
                    if (mounted) setState(() {});
                  },
                ),
              if (_service.isPendingCancellation || _service.hasScheduledChange)
                const SizedBox(height: 16),


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
                      isScheduledTarget: plan.tier == _service.scheduledTier,
                      isPendingCancel: _service.isPendingCancellation &&
                          plan.tier == _service.tier,
                      scheduledSummary: _service.scheduledChangeSummary,
                      daysUntilRenewal: _service.daysUntilRenewal,
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
                        color: context.hc.textTertiary)),
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
                          color: context.hc.textSecondary),
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
                      'subscriptions in your App Store or Google Play account '
                      'settings. Prices shown are in GBP and may vary by region.',
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
                            Navigator.pushNamed(context, '/terms');
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
                            Navigator.pushNamed(context, '/privacy');
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

/// Banner displayed when there is a pending plan change or cancellation
class _ScheduledChangeBanner extends StatelessWidget {
  final String summary;
  final bool isCancellation;
  final int daysRemaining;
  final VoidCallback onRevert;

  const _ScheduledChangeBanner({
    required this.summary,
    required this.isCancellation,
    required this.daysRemaining,
    required this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isCancellation ? HuddlColors.error : HuddlColors.blue;
    final bgColor = isCancellation
        ? HuddlColors.error.withValues(alpha: 0.06)
        : HuddlColors.blue.withValues(alpha: 0.06);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCancellation ? Icons.cancel_outlined : Icons.schedule,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isCancellation
                      ? 'Subscription cancels at end of period'
                      : 'Plan change scheduled',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: GoogleFonts.poppins(
                fontSize: 12, color: context.hc.textSecondary),
          ),
          if (daysRemaining > 0) ...[
            const SizedBox(height: 2),
            Text(
              '$daysRemaining days remaining in current period',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.hc.textTertiary),
            ),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onRevert,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isCancellation
                    ? 'Undo Cancellation'
                    : 'Revert to Current Plan',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner shown when a gated feature redirects the user here
class _GateBanner extends StatelessWidget {
  final String message;
  const _GateBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.primary.withValues(alpha: 0.08),
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
                    color: context.hc.textPrimary)),
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
                    color: HuddlColors.accentAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Save 30%',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.accentAmber)),
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
  final bool isScheduledTarget;
  final bool isPendingCancel;
  final String? scheduledSummary;
  final int daysUntilRenewal;
  final VoidCallback onSelect;

  const _PlanCard({
    required this.plan,
    required this.period,
    required this.isCurrentPlan,
    required this.isHighlighted,
    this.isScheduledTarget = false,
    this.isPendingCancel = false,
    this.scheduledSummary,
    this.daysUntilRenewal = 0,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final price = plan.priceFor(period);
    final isFree = plan.tier == SubscriptionTier.explorer;
    Color borderColor = HuddlColors.gray200;
    Color bgColor = HuddlColors.white;
    if (isScheduledTarget) {
      borderColor = HuddlColors.blue;
      bgColor = HuddlColors.premiumPurpleBg;
    } else if (isHighlighted && !isCurrentPlan) {
      borderColor = HuddlColors.primary;
      bgColor = HuddlColors.primary.withValues(alpha: 0.06);
    }
    if (isCurrentPlan) {
      borderColor = isPendingCancel ? HuddlColors.error : HuddlColors.teal;
      bgColor = isPendingCancel
          ? HuddlColors.error.withValues(alpha: 0.05)
          : HuddlColors.successBg;
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isHighlighted || isCurrentPlan || isScheduledTarget ? 2 : 1),
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
                                  color: context.hc.textPrimary)),
                          if (isCurrentPlan) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isPendingCancel
                                    ? HuddlColors.error
                                    : HuddlColors.teal,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isPendingCancel ? 'Cancelling' : 'Current',
                                style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: HuddlColors.white)),
                            ),
                          ],
                          if (isScheduledTarget) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: HuddlColors.blue,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Scheduled',
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
                              color: context.hc.textSecondary)),
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
                      color: context.hc.textPrimary),
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
                          fontSize: 13, color: context.hc.textTertiary),
                    ),
                  ),
                  if (period == BillingPeriod.annual && plan.annualSavingsPercent > 0) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: HuddlColors.accentAmber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Save ${plan.annualSavingsPercent}%',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.accentAmber),
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
                      color: context.hc.textTertiary)),
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
                                      color: context.hc.textSecondary)),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),

          // Pending cancellation notice on card
          if (isPendingCancel && daysUntilRenewal > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: HuddlColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule,
                        color: HuddlColors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Access until end of period ($daysUntilRenewal days)',
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: HuddlColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Scheduled target notice on card
          if (isScheduledTarget)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: HuddlColors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule,
                        color: HuddlColors.blue, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        scheduledSummary ?? 'Scheduled for next billing cycle',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: HuddlColors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // CTA button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isCurrentPlan
                    ? (isPendingCancel || isScheduledTarget
                        ? onSelect
                        : null)
                    : (isScheduledTarget ? null : onSelect),
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
                      ? (isPendingCancel
                          ? 'Reactivate'
                          : (isScheduledTarget
                              ? 'Keep Current Plan'
                              : 'Current Plan'))
                      : (isScheduledTarget
                          ? 'Scheduled'
                          : (isFree ? 'Cancel Subscription' : 'Choose ${plan.name}')),
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
                color: context.hc.textPrimary)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: context.hc.surface,
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
                                color: context.hc.textTertiary))),
                    Expanded(
                        child: Text('Welcome',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: context.hc.textTertiary))),
                    Expanded(
                        child: Text('Neighbour',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.primary))),
                    Expanded(
                        child: Text('Circle',
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
              _rowBool('Profile badge', false, true, true),

              // ---- AI Features section ----
              _sectionHeader('AI Features'),
              _row('AI Copilot', '3/day', '25/day', '\u221E'),
              _row('AI Chat Summaries', '\u2014', '10/day', '\u221E'),
              _row('AI Event Discovery', '1/wk', 'Daily', '\u221E'),
              _rowBool('AI Recommendations', true, true, true),
              _rowBool('AI Smart Feed', true, true, true),
              _row('AI Listing Generator', '\u2014', '10/mo', '\u221E'),
              _rowBool('AI Matchmaker', false, false, true),

              // ---- Community Q&A section ----
              _sectionHeader('Community Q&A'),
              _row('Questions/week', '3', '15', '\u221E'),
              _row('Bookmarks/month', '10', '50', '\u221E'),
              _rowBool('Community badges', false, true, true),
              _rowBool('AI answer synthesis', false, true, true),

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
                      color: HuddlColors.textTertiary))),
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
