import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/subscription.dart';
import '../../services/subscription_service.dart';
import '../../services/payment_service.dart';
import '../../constants/app_text_styles.dart';

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
                style: HuddlText.body(color: HuddlColors.white)),
            backgroundColor: HuddlColors.textDark,
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
                style: HuddlText.body(color: HuddlColors.white)),
            backgroundColor: HuddlColors.textDark,
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
                  style: HuddlText.body(color: HuddlColors.white)),
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
                  style: HuddlText.body(color: HuddlColors.white)),
              backgroundColor: HuddlColors.textDark,
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
          await _celebrateUpgrade(plan);
          if (mounted) Navigator.pop(context, true);
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
                style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  renewalInfo,
                  style: HuddlText.body(color: context.hc.textSecondary),
                ),
                if (_service.daysUntilRenewal > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: HuddlColors.blueBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: HuddlColors.nearBlack, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_service.daysUntilRenewal} days remaining in your current period.',
                            style: HuddlText.caption(color: HuddlColors.nearBlack),
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
                    style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.primary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Cancel Subscription',
                    style: HuddlText.body(color: HuddlColors.error)),
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
                style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
            content: Text(
              'Your cancellation will be reversed and your plan will '
              'continue to auto-renew at the end of the current billing period.',
              style: HuddlText.body(color: context.hc.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Keep Cancelled',
                    style: HuddlText.body(color: context.hc.textTertiary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Reactivate',
                    style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.nearBlack)),
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
                style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
            content: Text(
              'This will cancel the scheduled plan change. '
              'Your current plan will continue to renew normally.',
              style: HuddlText.body(color: context.hc.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Keep Scheduled Change',
                    style: HuddlText.body(color: context.hc.textTertiary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Keep Current Plan',
                    style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.primary)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Upgrade celebration ──────────────────────────────────────────────
  Future<void> _celebrateUpgrade(SubscriptionPlan plan) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpgradeCelebration(planName: plan.name),
    );
  }

  // ── Hero header ──────────────────────────────────────────────────────
  Widget _buildHero(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      decoration: const BoxDecoration(
        color: HuddlColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(
            'assets/icons/huddl_logomark.svg',
            width: 36,
            height: 36 * (150 / 107),
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          const SizedBox(height: 16),
          Text(
            widget.gateMessage != null
                ? 'Unlock this feature'
                : 'Your village is waiting',
            style: GoogleFonts.poppins(
              fontSize: 28, fontWeight: FontWeight.w700,
              color: Colors.white, height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.gateMessage ??
                'Everything Cambridge parents need — groups, meetups, market, and AI. From £4.99/month.',
            style: GoogleFonts.poppins(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.people_outline,
                  size: 14, color: Colors.white.withValues(alpha: 0.75)),
              const SizedBox(width: 6),
              Text(
                'Joined by Cambridge parents this week',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Plus first for free users — primary conversion target
    final orderedPlans = _service.isFree
        ? [
            SubscriptionPlan.allPlans.firstWhere(
                (p) => p.tier == SubscriptionTier.neighbourhood),
            SubscriptionPlan.allPlans.firstWhere(
                (p) => p.tier == SubscriptionTier.explorer),
            SubscriptionPlan.allPlans.firstWhere(
                (p) => p.tier == SubscriptionTier.partner),
          ]
        : SubscriptionPlan.allPlans;

    return Scaffold(
      backgroundColor: context.hc.scaffold,
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Orange hero (replaces AppBar + _GateBanner)
                  _buildHero(context),
                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
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

                        // Billing toggle
                        _BillingToggle(
                          period: _period,
                          onChanged: (p) => setState(() => _period = p),
                        ),
                        const SizedBox(height: 20),

                        // Plan cards — ordered: Plus, Welcome, Partner for free users
                        ...orderedPlans.map((plan) {
                          final productId = HuddlProductIds.productIdFor(
                              plan.tier, _period);
                          final storePrice =
                              PaymentService().getPriceForProduct(productId);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _PlanCard(
                              plan: plan,
                              period: _period,
                              currentTier: _service.tier,
                              storePrice:
                                  storePrice.isNotEmpty ? storePrice : null,
                              isCurrentPlan: plan.tier == _service.tier,
                              isHighlighted: plan.tier ==
                                      widget.highlightTier ||
                                  (widget.highlightTier == null &&
                                      plan.tier ==
                                          SubscriptionTier.neighbourhood),
                              isScheduledTarget:
                                  plan.tier == _service.scheduledTier,
                              isPendingCancel:
                                  _service.isPendingCancellation &&
                                      plan.tier == _service.tier,
                              scheduledSummary:
                                  _service.scheduledChangeSummary,
                              daysUntilRenewal: _service.daysUntilRenewal,
                              onSelect: () => _onSelectPlan(plan),
                            ),
                          );
                        }),

                        const SizedBox(height: 16),

                        // Feature comparison
                        _FeatureComparisonTable(period: _period),

                        const SizedBox(height: 24),

                        // Restore purchases (Apple Guideline 3.1.1 — required)
                        TextButton(
                          onPressed: _restorePurchases,
                          child: Text('Restore Purchases',
                              style: HuddlText.body(
                                  color: context.hc.textTertiary)),
                        ),

                        // Apple 3.1.2 / Google Play required disclosures
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: Column(
                            children: [
                              Text(
                                'Subscription Terms',
                                style: HuddlText.caption(
                                    weight: FontWeight.w600,
                                    color: context.hc.textSecondary),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Payment will be charged to your Apple ID or '
                                'Google Play account at confirmation of purchase. '
                                'Subscriptions automatically renew unless '
                                'auto-renew is turned off at least 24 hours '
                                'before the end of the current period. Your '
                                'account will be charged for renewal within 24 '
                                'hours prior to the end of the current period at '
                                'the rate of your selected plan. You can manage '
                                'and cancel your subscriptions in your App Store '
                                'or Google Play account settings. Prices shown '
                                'are in GBP and may vary by region.',
                                textAlign: TextAlign.center,
                                style:
                                    HuddlText.label(color: HuddlColors.textLight),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: () => Navigator.pushNamed(
                                        context, '/terms'),
                                    child: Text(
                                      'Terms of Service',
                                      style: HuddlText.caption(
                                              color: HuddlColors.textTertiary)
                                          .copyWith(
                                              decoration:
                                                  TextDecoration.underline),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: Text('\u2022',
                                        style: HuddlText.caption(
                                            color: HuddlColors.textLight)),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.pushNamed(
                                        context, '/privacy'),
                                    child: Text(
                                      'Privacy Policy',
                                      style: HuddlText.caption(
                                              color: HuddlColors.textTertiary)
                                          .copyWith(
                                              decoration:
                                                  TextDecoration.underline),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Close button overlay ───────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
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
            style: HuddlText.body(color: HuddlColors.white),
          ),
          backgroundColor: restored ? HuddlColors.textDark : HuddlColors.textHint,
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
        isCancellation ? HuddlColors.error : HuddlColors.nearBlack;
    final bgColor = isCancellation
        ? HuddlColors.error.withValues(alpha: 0.06)
        : HuddlColors.nearBlack.withValues(alpha: 0.06);

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
                  style: HuddlText.body(weight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: HuddlText.caption(color: context.hc.textSecondary),
          ),
          if (daysRemaining > 0) ...[
            const SizedBox(height: 2),
            Text(
              '$daysRemaining days remaining in current period',
              style: HuddlText.caption(color: context.hc.textTertiary),
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
                style: HuddlText.caption(weight: FontWeight.w600, color: color),
              ),
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
                  style: HuddlText.body()),
              if (showSave) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Save 30%',
                      style: HuddlText.label(color: HuddlColors.primary)),
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
  final SubscriptionTier currentTier;
  /// Store-localised price string (e.g. "£4.99/month" from Apple/Google).
  /// When null, falls back to the hard-coded GBP price from the model.
  final String? storePrice;
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
    required this.currentTier,
    this.storePrice,
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
    final isPlus    = plan.tier == SubscriptionTier.neighbourhood;
    final isFreeUser = currentTier == SubscriptionTier.explorer;
    final tierColor  = _tierColor(plan.tier);

    // Plus card gets full orange treatment when the user is on free tier —
    // it's the primary conversion target.
    final bool isFeatured = isPlus && isFreeUser && !isCurrentPlan;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: isFeatured ? HuddlColors.primary : context.hc.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrentPlan && !isFeatured
              ? tierColor
              : isFeatured
                  ? Colors.transparent
                  : HuddlColors.divider,
          width: isCurrentPlan ? 2 : 0.5,
        ),
        boxShadow: isFeatured
            ? [
                BoxShadow(
                  color: HuddlColors.primary.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isFeatured
                        ? Colors.white.withValues(alpha: 0.20)
                        : tierColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _tierIcon(plan.tier),
                    color: isFeatured ? Colors.white : tierColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            plan.name,
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isFeatured
                                  ? Colors.white
                                  : context.hc.textPrimary,
                            ),
                          ),
                          if (isCurrentPlan) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isPendingCancel
                                    ? HuddlColors.error
                                    : (isFeatured
                                        ? Colors.white.withValues(alpha: 0.25)
                                        : HuddlColors.nearBlack),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isPendingCancel ? 'Cancelling' : 'Current',
                                style: HuddlText.label(color: Colors.white),
                              ),
                            ),
                          ],
                          if (isScheduledTarget) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: HuddlColors.nearBlack,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Scheduled',
                                  style:
                                      HuddlText.label(color: HuddlColors.white)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.tagline,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: isFeatured
                              ? Colors.white.withValues(alpha: 0.80)
                              : HuddlColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Price column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (plan.monthlyPrice > 0) ...[
                      Text(
                        storePrice ??
                            '\u00A3${plan.priceFor(period).toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isFeatured
                              ? Colors.white
                              : context.hc.textPrimary,
                        ),
                      ),
                      Text(
                        period == BillingPeriod.annual ? '/year' : '/month',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: isFeatured
                              ? Colors.white.withValues(alpha: 0.70)
                              : HuddlColors.textTertiary,
                        ),
                      ),
                      if (period == BillingPeriod.annual &&
                          plan.annualSavingsPercent > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isFeatured
                                ? Colors.white.withValues(alpha: 0.20)
                                : HuddlColors.yellowSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Save ${plan.annualSavingsPercent}%',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isFeatured
                                  ? Colors.white
                                  : HuddlColors.yellowDark,
                            ),
                          ),
                        ),
                    ] else
                      Text(
                        'Free',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: isFeatured
                ? Colors.white.withValues(alpha: 0.15)
                : HuddlColors.divider,
            indent: 20,
            endIndent: 20,
          ),
          const SizedBox(height: 14),

          // ── Benefit list ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: plan.highlights
                  .map((h) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: isFeatured ? Colors.white : tierColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                h,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: isFeatured
                                      ? Colors.white.withValues(alpha: 0.92)
                                      : context.hc.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),

          // Pending cancellation notice
          if (isPendingCancel && daysUntilRenewal > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
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
                        style: HuddlText.caption(color: HuddlColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Scheduled change notice
          if (isScheduledTarget)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: HuddlColors.nearBlack.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule,
                        color: HuddlColors.nearBlack, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        scheduledSummary ?? 'Scheduled for next billing cycle',
                        style:
                            HuddlText.caption(color: HuddlColors.nearBlack),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // ── CTA button ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isCurrentPlan
                    ? (isPendingCancel || isScheduledTarget ? onSelect : null)
                    : (isScheduledTarget ? null : onSelect),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFeatured
                      ? Colors.white
                      : isCurrentPlan
                          ? HuddlColors.gray100
                          : tierColor,
                  foregroundColor: isFeatured
                      ? HuddlColors.primary
                      : isCurrentPlan
                          ? HuddlColors.textTertiary
                          : Colors.white,
                  elevation: 0,
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
                      : isScheduledTarget
                          ? 'Scheduled'
                          : plan.monthlyPrice == 0
                              ? 'Continue Free'
                              : 'Get ${plan.name}',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w700),
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
        return HuddlColors.nearBlack;
      case SubscriptionTier.partner:
        return HuddlColors.primary;
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
      case SubscriptionTier.partner:
        return Icons.verified;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UPGRADE CELEBRATION — full-screen orange flash on successful purchase
// ─────────────────────────────────────────────────────────────────────────────

class _UpgradeCelebration extends StatefulWidget {
  final String planName;
  const _UpgradeCelebration({required this.planName});

  @override
  State<_UpgradeCelebration> createState() => _UpgradeCelebrationState();
}

class _UpgradeCelebrationState extends State<_UpgradeCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HuddlColors.primary,
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/icons/huddl_logomark.svg',
                  width: 80,
                  height: 80 * (150 / 107),
                  colorFilter: const ColorFilter.mode(
                      Colors.white, BlendMode.srcIn),
                ),
                const SizedBox(height: 24),
                Text(
                  "You're in! 🎉",
                  style: GoogleFonts.poppins(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Welcome to ${widget.planName}.\nYour community is fully unlocked.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
            style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
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
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child: Text('Feature',
                            style: HuddlText.caption(weight: FontWeight.w600, color: context.hc.textTertiary))),
                    Expanded(
                        child: Text('Welcome',
                            textAlign: TextAlign.center,
                            style: HuddlText.label(color: context.hc.textTertiary))),
                    Expanded(
                        child: Text('Plus',
                            textAlign: TextAlign.center,
                            style: HuddlText.label(color: HuddlColors.primary))),
                    Expanded(
                        child: Text('Partner',
                            textAlign: TextAlign.center,
                            style: HuddlText.label(color: HuddlColors.nearBlack))),
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
        color: const Color(0xFFF7F7F7),
        border: const Border(bottom: BorderSide(color: HuddlColors.gray100)),
      ),
      child: Text(title,
          style: HuddlText.caption(weight: FontWeight.w700, color: HuddlColors.textDark).copyWith(letterSpacing: 0.5)),
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
                  style: HuddlText.caption(color: HuddlColors.textSecondary))),
          Expanded(
              child: Text(explorer,
                  textAlign: TextAlign.center,
                  style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.textTertiary))),
          Expanded(
              child: Text(neighbourhood,
                  textAlign: TextAlign.center,
                  style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.textDark))),
          Expanded(
              child: Text(inner,
                  textAlign: TextAlign.center,
                  style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.nearBlack))),
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
                  style: HuddlText.caption(color: HuddlColors.textSecondary))),
          Expanded(child: Center(child: checkIcon(explorer, HuddlColors.textHint))),
          Expanded(child: Center(child: checkIcon(neighbourhood, HuddlColors.textDark))),
          Expanded(child: Center(child: checkIcon(inner, HuddlColors.nearBlack))),
        ],
      ),
    );
  }
}
