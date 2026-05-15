import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/huddl_colors.dart';
import '../../models/subscription.dart';
import '../../services/subscription_service.dart';
import '../../services/payment_service.dart';
import '../../services/firebase_auth_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SUBSCRIPTION CHECKOUT — multi-platform payment integration
//
// COMPLIANCE:
//   Apple 3.1.1:  Uses StoreKit via in_app_purchase for iOS.
//   Apple 3.1.2:  Subscription name, duration, price, auto-renewal terms,
//                 cancellation instructions, ToS & Privacy links all displayed.
//   Google Play:  Uses Google Play Billing via in_app_purchase for Android.
//                 Prominent disclosure of auto-renewal, cancellation, billing.
//   Web:          Stripe Checkout with Apple Pay / Google Pay / cards.
//
// PAYMENT METHODS (per platform):
//   iOS:     Apple Pay, credit/debit cards in wallet, carrier billing
//   Android: Google Pay, credit/debit cards, carrier billing, gift cards
//   Web:     Stripe — Visa, Mastercard, Amex, Apple Pay, Google Pay, BACS, etc.
// ═══════════════════════════════════════════════════════════════════════════════

class SubscriptionCheckoutScreen extends StatefulWidget {
  final SubscriptionTier tier;
  final BillingPeriod period;
  /// When true, the purchase is *scheduled* for the next billing cycle
  /// rather than taking effect immediately.
  final bool isScheduled;

  const SubscriptionCheckoutScreen({
    super.key,
    required this.tier,
    required this.period,
    this.isScheduled = false,
  });

  @override
  State<SubscriptionCheckoutScreen> createState() =>
      _SubscriptionCheckoutScreenState();
}

class _SubscriptionCheckoutScreenState
    extends State<SubscriptionCheckoutScreen> {
  final SubscriptionService _subService = SubscriptionService();
  final PaymentService _payService = PaymentService();
  late BillingPeriod _period;
  bool _isProcessing = false;
  bool _agreedToTerms = false;
  late bool _isScheduled;
  // Web-only: true while we're waiting for the Stripe webhook to confirm payment
  bool _awaitingStripeWebhook = false;

  late SubscriptionPlan _plan;

  @override
  void initState() {
    super.initState();
    _period = widget.period;
    _isScheduled = widget.isScheduled;
    _plan = SubscriptionPlan.allPlans.firstWhere(
      (p) => p.tier == widget.tier,
    );
    _initServices();
  }

  Future<void> _initServices() async {
    await _subService.initialize();
    await _payService.initialize();

    // Wire up PaymentService callbacks → SubscriptionService
    _payService.onPurchaseSuccess = _onPurchaseSuccess;
    _payService.onPurchaseError = _onPurchaseError;
    _payService.onPurchasesRestored = _onPurchasesRestored;

    // Listen for PaymentService status changes
    _payService.addListener(_onPaymentStatusChanged);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _payService.removeListener(_onPaymentStatusChanged);
    super.dispose();
  }

  void _onPaymentStatusChanged() {
    if (!mounted) return;
    setState(() {
      _isProcessing = _payService.status == PaymentStatus.purchasing;
      // On web, verifying means the user is on the Stripe page (not a spinner)
      if (kIsWeb && _payService.status == PaymentStatus.verifying) {
        _awaitingStripeWebhook = true;
        _isProcessing = false;
      }
      // If status flips to success via notifyStripeSuccess, hide waiting state
      if (_payService.status == PaymentStatus.success) {
        _awaitingStripeWebhook = false;
      }
    });
  }

  // ── Payment callbacks ──────────────────────────────────────────────────

  void _onPurchaseSuccess(String productId, dynamic details) {
    // Optimistically update local state immediately so the UI responds fast.
    final (tier, period) = HuddlProductIds.tierForProduct(productId);
    _subService.purchase(tier, period);

    // B6 fix: also sync authoritative subscription data from Firestore so that
    // the server-verified tier/expiry is used rather than the locally-generated
    // values.  This ensures multi-device consistency and picks up any trial
    // flags or grace periods set by the backend receipt-verification service.
    _syncSubscriptionFromFirestore();

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _SuccessDialog(
          plan: _plan,
        ),
      ).then((_) {
        if (mounted) Navigator.pop(context, true);
      });
    }
  }

  /// Pull the verified subscription record from Firestore and refresh the
  /// local SubscriptionService state.  Non-blocking — any failure is silent
  /// because the optimistic local update already went through.
  Future<void> _syncSubscriptionFromFirestore() async {
    try {
      await FirebaseAuthService().restoreProfileFromFirestore()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionCheckout: Firestore sync after purchase failed: $e');
      }
    }
  }

  void _onPurchaseError(String? errorMessage) {
    if (mounted) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage ?? 'Payment failed. Please try again.',
              style: GoogleFonts.poppins(color: HuddlColors.white)),
          backgroundColor: HuddlColors.error,
        ),
      );
    }
  }

  void _onPurchasesRestored(List<String> restoredProductIds) {
    if (mounted && restoredProductIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Subscription restored!',
              style: GoogleFonts.poppins(color: HuddlColors.white)),
          backgroundColor: HuddlColors.teal,
        ),
      );
    }
  }

  // ── Price calculation ──────────────────────────────────────────────────

  double get _displayPrice {
    return _plan.priceFor(_period);
  }

  /// Get store-localised price if available, else our default
  String get _displayPriceString {
    final productId = HuddlProductIds.productIdFor(
      _plan.tier,
      _period,
    );
    final storePrice = _payService.getPriceForProduct(productId);
    if (storePrice.isNotEmpty) return storePrice;
    final isAnnual = _period == BillingPeriod.annual;
    return '\u00A3${_displayPrice.toStringAsFixed(2)}${isAnnual ? '/year' : '/month'}';
  }

  // ── Purchase flow ─────────────────────────────────────────────────────

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

    if (_isScheduled) {
      // ── Scheduled change (upgrade/downgrade from a paid tier) ────────
      final ok = await _subService.schedulePlanChange(
        _plan.tier,
        _period,
      );

      if (mounted) {
        setState(() => _isProcessing = false);
        if (ok) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => _ScheduledSuccessDialog(
              plan: _plan,
              renewalDate: _subService.renewalDate,
            ),
          ).then((_) {
            if (mounted) Navigator.pop(context, true);
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not schedule plan change. Please try again.',
                  style: GoogleFonts.poppins(color: HuddlColors.white)),
              backgroundColor: HuddlColors.error,
            ),
          );
        }
      }
      return;
    }

    // ── Immediate purchase (from Welcome / new subscriber) ────────────
    final success = await _payService.purchaseSubscription(
      tier: _plan.tier,
      period: _period,
    );

    // On mobile: result comes via purchaseStream callback (_onPurchaseSuccess).
    // On web:    the user has been redirected to Stripe Checkout in the browser.
    //            Payment is NOT confirmed here — we wait for the Stripe webhook
    //            to update Firestore, or the user returns via successUrl and
    //            the router calls PaymentService().notifyStripeSuccess().
    //            _onPaymentStatusChanged() updates _awaitingStripeWebhook so
    //            the UI shows the "waiting for payment" banner.
    if (!success) {
      if (mounted) setState(() => _isProcessing = false);
    }
    // On mobile success=true means the native sheet was shown; wait for stream.
    // On web success=true means browser was opened; wait for webhook / return.
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isInnerCircle = _plan.tier == SubscriptionTier.innerCircle;
    final color = isInnerCircle ? HuddlColors.teal : HuddlColors.primary;

    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Checkout',
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.hc.textPrimary)),
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
                    // Scheduled change info banner
                    if (_isScheduled) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: HuddlColors.blue.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: HuddlColors.blue.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.schedule,
                                    color: HuddlColors.blue, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Scheduled Plan Change',
                                    style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.blue),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'This change will take effect at the start of '
                              'your next billing cycle. You\'ll keep full access '
                              'to your current plan until then.',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: context.hc.textSecondary),
                            ),
                            if (_subService.daysUntilRenewal > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${_subService.daysUntilRenewal} days remaining '
                                'in your current billing period.',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: HuddlColors.blue),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Plan summary card
                    _OrderSummaryCard(plan: _plan, period: _period),
                    const SizedBox(height: 20),

                    // Billing period selector
                    Text('Billing Period',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textPrimary)),
                    const SizedBox(height: 10),
                    _BillingOptionTile(
                      label: 'Monthly',
                      price:
                          '\u00A3${_plan.monthlyPrice.toStringAsFixed(2)}/month',
                      isSelected: _period == BillingPeriod.monthly,
                      onTap: () =>
                          setState(() => _period = BillingPeriod.monthly),
                    ),
                    const SizedBox(height: 8),
                    _BillingOptionTile(
                      label: 'Annual',
                      price:
                          '\u00A3${_plan.annualPrice.toStringAsFixed(2)}/year',
                      savingsText: 'Save ${_plan.annualSavingsPercent}%',
                      isSelected: _period == BillingPeriod.annual,
                      onTap: () => setState(() {
                        _period = BillingPeriod.annual;
                      }),
                    ),

                    const SizedBox(height: 24),

                    // ── Payment method section ──────────────────────────
                    Text('Payment Method',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textPrimary)),
                    const SizedBox(height: 10),
                    _PaymentMethodsSection(paymentService: _payService),

                    const SizedBox(height: 24),

                    // What you get
                    Text('What\'s Included',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textPrimary)),
                    const SizedBox(height: 10),
                    ..._plan.highlights.map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(Icons.check_circle_outline,
                                    size: 18, color: color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(h,
                                    style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: context.hc.textSecondary)),
                              ),
                            ],
                          ),
                        )),

                    const SizedBox(height: 20),

                    // ── Apple 3.1.2 / Google Play required terms ──────
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
                                    color: context.hc.textSecondary),
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
                                  const TextSpan(text: '. '),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Explicit auto-renewal disclosure
                    Padding(
                      padding: const EdgeInsets.only(left: 34),
                      child: Text(
                        'This subscription automatically renews unless '
                        'auto-renew is turned off at least 24 hours before '
                        'the end of the current period. Payment will be '
                        'charged to your ${_payService.paymentMethodName} account. '
                        'You can manage or cancel your subscription in your '
                        'device\u2019s account settings at any time.',
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: context.hc.textTertiary),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Web: Stripe payment pending banner ───────────────────────
            if (_awaitingStripeWebhook) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                color: HuddlColors.blue.withValues(alpha: 0.07),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: HuddlColors.blue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Waiting for payment confirmation…',
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.blue),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Complete your payment in the browser tab that just opened. '
                      'This screen will update automatically once your payment is confirmed.',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: context.hc.textSecondary),
                    ),
                    if (_payService.lastCheckoutUrl != null) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () async {
                          final url = _payService.lastCheckoutUrl!;
                          await launchUrl(Uri.parse(url),
                              mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.open_in_browser,
                            size: 16, color: HuddlColors.blue),
                        label: Text('Re-open payment page',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.blue)),
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // ── Purchase button bar ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: context.hc.surface,
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
                                color: context.hc.textPrimary)),
                        Text(
                          _displayPriceString,
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
                          backgroundColor: color,
                          foregroundColor: HuddlColors.white,
                          disabledBackgroundColor:
                              color.withValues(alpha: 0.5),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isProcessing
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: context.hc.surface,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _payService.status ==
                                            PaymentStatus.verifying
                                        ? 'Verifying...'
                                        : 'Processing...',
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.white),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isScheduled
                                        ? Icons.schedule
                                        : (_payService.isWeb
                                            ? Icons.lock_outline
                                            : Icons.payment),
                                    size: 18,
                                    color: context.hc.surface,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isScheduled
                                        ? 'Schedule ${_plan.name}'
                                        : 'Subscribe to ${_plan.name}',
                                    style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    // Restore purchases link (Apple 3.1.1 requirement)
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isProcessing ? null : _restorePurchases,
                      child: Text('Restore Purchases',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: context.hc.textTertiary)),
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

  Future<void> _restorePurchases() async {
    setState(() => _isProcessing = true);
    final restored = await _payService.restorePurchases();
    if (!restored && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No previous purchases found.',
              style: GoogleFonts.poppins(color: HuddlColors.white)),
          backgroundColor: HuddlColors.textHint,
        ),
      );
    }
    if (mounted) setState(() => _isProcessing = false);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUBWIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

/// Shows available payment methods for the current platform
class _PaymentMethodsSection extends StatelessWidget {
  final PaymentService paymentService;
  const _PaymentMethodsSection({required this.paymentService});

  @override
  Widget build(BuildContext context) {
    final methods = paymentService.availablePaymentMethods;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuddlColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Payment provider row with icons
          Row(
            children: [
              ...methods.map((m) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _PaymentBadge(method: m),
                  )),
            ],
          ),
          const SizedBox(height: 14),

          // Primary payment method card
          ...methods.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PaymentProviderRow(method: m),
              )),

          // Secure payment notice
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: HuddlColors.blueBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined,
                    color: HuddlColors.blue, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    paymentService.isWeb
                        ? 'Payments processed securely by Stripe (PCI-DSS Level 1). '
                          'Huddl never stores your card details.'
                        : 'Payment is processed securely by your app store. '
                          'Huddl never sees or stores your payment details.',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: HuddlColors.blue),
                  ),
                ),
              ],
            ),
          ),

          // Accepted payment methods visual row
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _cardBrandIcon(Icons.credit_card, 'Visa'),
              _cardBrandIcon(Icons.credit_card, 'Mastercard'),
              _cardBrandIcon(Icons.credit_card, 'Amex'),
              if (paymentService.isWeb || defaultTargetPlatform == TargetPlatform.iOS)
                _cardBrandIcon(Icons.apple, 'Apple Pay'),
              if (paymentService.isWeb || defaultTargetPlatform == TargetPlatform.android)
                _cardBrandIcon(Icons.g_mobiledata, 'Google Pay'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardBrandIcon(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: HuddlColors.gray100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: HuddlColors.textDark),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 9, color: HuddlColors.textTertiary)),
        ],
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  final PaymentMethod method;
  const _PaymentBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: HuddlColors.teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconForMethod(method), size: 14, color: HuddlColors.teal),
          const SizedBox(width: 4),
          Text(method.displayName,
              style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.teal)),
        ],
      ),
    );
  }

  static IconData _iconForMethod(PaymentMethod m) {
    switch (m.type) {
      case PaymentMethodType.appStore:
        return Icons.apple;
      case PaymentMethodType.googlePlay:
        return Icons.g_mobiledata;
      case PaymentMethodType.stripe:
        return Icons.credit_card;
      case PaymentMethodType.applePay:
        return Icons.apple;
      case PaymentMethodType.googlePay:
        return Icons.g_mobiledata;
    }
  }
}

class _PaymentProviderRow extends StatelessWidget {
  final PaymentMethod method;
  const _PaymentProviderRow({required this.method});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: HuddlColors.gray100,
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              Icon(_iconFor(method), color: context.hc.textPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(method.displayName,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary)),
              Text(method.description,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.hc.textSecondary)),
            ],
          ),
        ),
        const Icon(Icons.check_circle, color: HuddlColors.teal, size: 20),
      ],
    );
  }

  static IconData _iconFor(PaymentMethod m) {
    switch (m.type) {
      case PaymentMethodType.appStore:
        return Icons.phone_iphone;
      case PaymentMethodType.googlePlay:
        return Icons.phone_android;
      case PaymentMethodType.stripe:
        return Icons.credit_card;
      case PaymentMethodType.applePay:
        return Icons.apple;
      case PaymentMethodType.googlePay:
        return Icons.g_mobiledata;
    }
  }
}

class _OrderSummaryCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final BillingPeriod period;

  const _OrderSummaryCard({required this.plan, required this.period});

  @override
  Widget build(BuildContext context) {
    final isInnerCircle = plan.tier == SubscriptionTier.innerCircle;
    final color = isInnerCircle ? HuddlColors.teal : HuddlColors.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
              isInnerCircle ? Icons.workspace_premium : Icons.home_outlined,
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
                        color: context.hc.textPrimary)),
                const SizedBox(height: 2),
                Text(plan.tagline,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: context.hc.textSecondary)),
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
          color: isSelected ? HuddlColors.primary.withValues(alpha: 0.06) : HuddlColors.white,
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
              color: isSelected ? HuddlColors.primary : context.hc.textTertiary,
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
                          color: context.hc.textPrimary)),
                  Text(price,
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: context.hc.textSecondary)),
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

class _SuccessDialog extends StatelessWidget {
  final SubscriptionPlan plan;
  const _SuccessDialog({required this.plan});

  @override
  Widget build(BuildContext context) {
    final isInnerCircle = plan.tier == SubscriptionTier.innerCircle;
    final color = isInnerCircle ? HuddlColors.teal : HuddlColors.primary;

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
            Text(
              'Welcome to ${plan.name}!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Your subscription is now active. Enjoy all your new features!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: context.hc.textSecondary),
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

/// Dialog shown after a *scheduled* plan change is confirmed.
class _ScheduledSuccessDialog extends StatelessWidget {
  final SubscriptionPlan plan;
  final DateTime? renewalDate;
  const _ScheduledSuccessDialog({
    required this.plan,
    this.renewalDate,
  });

  @override
  Widget build(BuildContext context) {
    final isInnerCircle = plan.tier == SubscriptionTier.innerCircle;
    final color = isInnerCircle ? HuddlColors.teal : HuddlColors.primary;

    String dateStr = 'your next billing cycle';
    if (renewalDate != null) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      dateStr =
          '${renewalDate!.day} ${months[renewalDate!.month - 1]} ${renewalDate!.year}';
    }

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
              child: Icon(Icons.schedule, color: color, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              'Plan Change Scheduled!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ll switch to ${plan.name} on $dateStr. '
              'Until then, you keep full access to your current plan.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: context.hc.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, color: color, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'You can change or cancel this anytime before $dateStr.',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: color),
                    ),
                  ),
                ],
              ),
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
                child: Text('Got It',
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
