import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/subscription.dart';
import '../../services/subscription_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SUBSCRIPTION CHECKOUT — payment confirmation screen
// ═══════════════════════════════════════════════════════════════════════════════

class SubscriptionCheckoutScreen extends StatefulWidget {
  final SubscriptionTier tier;
  final BillingPeriod period;

  const SubscriptionCheckoutScreen({
    super.key,
    required this.tier,
    required this.period,
  });

  @override
  State<SubscriptionCheckoutScreen> createState() =>
      _SubscriptionCheckoutScreenState();
}

class _SubscriptionCheckoutScreenState
    extends State<SubscriptionCheckoutScreen> {
  final SubscriptionService _service = SubscriptionService();
  late BillingPeriod _period;
  bool _isProcessing = false;
  bool _agreedToTerms = false;

  late SubscriptionPlan _plan;

  @override
  void initState() {
    super.initState();
    _period = widget.period;
    _plan = SubscriptionPlan.allPlans.firstWhere(
      (p) => p.tier == widget.tier,
    );
    _service.initialize();
  }

  Future<void> _completePurchase() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please agree to the terms to continue',
              style: GoogleFonts.poppins(color: HuddlColors.white)),
          backgroundColor: HuddlColors.error,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    // Simulate payment processing
    await Future.delayed(const Duration(seconds: 2));

    final success = await _service.purchase(widget.tier, _period);

    setState(() => _isProcessing = false);

    if (success && mounted) {
      // Show success dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _SuccessDialog(plan: _plan),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed. Please try again.',
              style: GoogleFonts.poppins(color: HuddlColors.white)),
          backgroundColor: HuddlColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = _plan.priceFor(_period);
    final isAnnual = _period == BillingPeriod.annual;

    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: HuddlColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Checkout',
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textDark)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Plan summary card
                    _OrderSummaryCard(plan: _plan, period: _period),
                    const SizedBox(height: 20),

                    // Billing period selector
                    Text('Billing Period',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark)),
                    const SizedBox(height: 10),
                    _BillingOptionTile(
                      label: 'Monthly',
                      price: '\u00A3${_plan.monthlyPrice.toStringAsFixed(2)}/month',
                      isSelected: _period == BillingPeriod.monthly,
                      onTap: () => setState(() => _period = BillingPeriod.monthly),
                    ),
                    const SizedBox(height: 8),
                    _BillingOptionTile(
                      label: 'Annual',
                      price: '\u00A3${_plan.annualPrice.toStringAsFixed(2)}/year',
                      savingsText: 'Save ${_plan.annualSavingsPercent}%',
                      isSelected: _period == BillingPeriod.annual,
                      onTap: () => setState(() => _period = BillingPeriod.annual),
                    ),

                    const SizedBox(height: 24),

                    // Payment method (simulated — in production, use Apple/Google Pay)
                    Text('Payment Method',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark)),
                    const SizedBox(height: 10),
                    _PaymentMethodCard(),

                    const SizedBox(height: 24),

                    // What you get
                    Text('What\'s Included',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark)),
                    const SizedBox(height: 10),
                    ..._plan.highlights.map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 18,
                                  color: _plan.tier == SubscriptionTier.pro
                                      ? HuddlColors.teal
                                      : HuddlColors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(h,
                                    style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: HuddlColors.textSecondary)),
                              ),
                            ],
                          ),
                        )),

                    const SizedBox(height: 20),

                    // Terms
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _agreedToTerms,
                            onChanged: (v) =>
                                setState(() => _agreedToTerms = v ?? false),
                            activeColor: HuddlColors.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(
                                () => _agreedToTerms = !_agreedToTerms),
                            child: Text.rich(
                              TextSpan(
                                text: 'I agree to the ',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: HuddlColors.textSecondary),
                                children: [
                                  TextSpan(
                                    text: 'Terms of Service',
                                    style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.primary,
                                        decoration: TextDecoration.underline),
                                  ),
                                  const TextSpan(text: ' and '),
                                  TextSpan(
                                    text: 'Privacy Policy',
                                    style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.primary,
                                        decoration: TextDecoration.underline),
                                  ),
                                  const TextSpan(
                                      text:
                                          '. Auto-renews unless cancelled 24h before period end.'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Purchase button
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: HuddlColors.white,
                boxShadow: [
                  BoxShadow(
                    color: HuddlColors.gray900.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total',
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.textDark)),
                        Text(
                          '\u00A3${price.toStringAsFixed(2)}${isAnnual ? '/year' : '/month'}',
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.textDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _completePurchase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.primary,
                          foregroundColor: HuddlColors.white,
                          disabledBackgroundColor:
                              HuddlColors.primary.withValues(alpha: 0.5),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: HuddlColors.white,
                                ),
                              )
                            : Text(
                                'Subscribe to ${_plan.name}',
                                style: GoogleFonts.poppins(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUBWIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _OrderSummaryCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final BillingPeriod period;

  const _OrderSummaryCard({required this.plan, required this.period});

  @override
  Widget build(BuildContext context) {
    final isPro = plan.tier == SubscriptionTier.pro;
    final color = isPro ? HuddlColors.teal : HuddlColors.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPro
              ? [const Color(0xFFE6F5F3), const Color(0xFFF0FAF8)]
              : [const Color(0xFFFFF0E6), const Color(0xFFFFF8F0)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isPro ? Icons.workspace_premium : Icons.star,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Huddl ${plan.name}',
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.textDark)),
                const SizedBox(height: 2),
                Text(plan.tagline,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: HuddlColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingOptionTile extends StatelessWidget {
  final String label;
  final String price;
  final String? savingsText;
  final bool isSelected;
  final VoidCallback onTap;

  const _BillingOptionTile({
    required this.label,
    required this.price,
    this.savingsText,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? HuddlColors.peachVeryLight : HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? HuddlColors.primary : HuddlColors.gray200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? HuddlColors.primary : HuddlColors.textHint,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textDark)),
                  Text(price,
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: HuddlColors.textSecondary)),
                ],
              ),
            ),
            if (savingsText != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: HuddlColors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(savingsText!,
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.teal)),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuddlColors.gray200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: HuddlColors.gray100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.phone_iphone,
                    color: HuddlColors.textDark, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('App Store / Google Play',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark)),
                    Text('Billed through your app store account',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: HuddlColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.check_circle,
                  color: HuddlColors.teal, size: 22),
            ],
          ),
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
                    color: HuddlColors.blue, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payment is processed securely by your app store. Huddl never stores your payment details.',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: HuddlColors.blue),
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

class _SuccessDialog extends StatelessWidget {
  final SubscriptionPlan plan;
  const _SuccessDialog({required this.plan});

  @override
  Widget build(BuildContext context) {
    final isPro = plan.tier == SubscriptionTier.pro;
    final color = isPro ? HuddlColors.teal : HuddlColors.primary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.celebration, color: color, size: 40),
            ),
            const SizedBox(height: 20),
            Text('Welcome to ${plan.name}!',
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.textDark)),
            const SizedBox(height: 8),
            Text(
              'Your subscription is now active. Enjoy all your new features!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: HuddlColors.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: HuddlColors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Start Exploring',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
