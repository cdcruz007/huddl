// ============================================================================
// HUDDL -- PAYMENT SERVICE
// ============================================================================
//
// Multi-platform payment integration:
//
//   MOBILE (iOS / Android)
//   ----------------------
//   Uses the official `in_app_purchase` plugin which wraps:
//     - Apple StoreKit  (iOS)  -> Apple Pay, cards in wallet, carrier billing
//     - Google Play Billing (Android) -> Google Pay, cards, carrier billing
//   These are the ONLY compliant channels for digital-goods subscriptions on
//   each respective store (Apple Guideline 3.1.1, Google Play Billing policy).
//
//   WEB
//   ---
//   The `in_app_purchase` plugin does not support web. On the web platform we
//   use a Stripe Checkout session redirect, which supports:
//     - Stripe-hosted checkout (PCI-DSS compliant)
//     - Apple Pay / Google Pay via Stripe Payment Request Button
//     - All major cards (Visa, Mastercard, Amex, etc.)
//     - Local payment methods (BACS, iDEAL, SEPA, etc.)
//
// PRODUCT IDS
// -----------
// Must match exactly what is configured in App Store Connect / Google Play
// Console / Stripe Product Catalog.
//
// ARCHITECTURE
// ------------
// PaymentService is a singleton that:
//   1. Initialises the IAP connection on mobile, or Stripe on web.
//   2. Queries available products from the store.
//   3. Initiates purchases and listens for purchase updates.
//   4. Verifies receipts (server-side in production; local in dev).
//   5. Exposes purchase state via ChangeNotifier.
//   6. Handles restore-purchases (required by Apple).
//
// ============================================================================

import 'dart:async' show StreamSubscription, TimeoutException;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/subscription.dart';
import 'backend_api_service.dart';

// ── Product ID constants ─────────────────────────────────────────────────────
// These MUST match the IDs configured in App Store Connect and Google Play
// Console. Use reverse-domain notation for clarity.

class HuddlProductIds {
  HuddlProductIds._();

  // Plus tier (formerly Neighbour)
  static const String plusMonthly  = 'huddl_plus_monthly';
  static const String plusAnnual   = 'huddl_plus_annual';

  // Partner tier (new business tier)
  static const String partnerMonthly = 'huddl_partner_monthly';
  static const String partnerAnnual  = 'huddl_partner_annual';

  /// All product IDs we expect to find in the store
  static const Set<String> all = {
    plusMonthly,
    plusAnnual,
    partnerMonthly,
    partnerAnnual,
  };

  /// Map product ID -> (SubscriptionTier, BillingPeriod)
  static (SubscriptionTier, BillingPeriod) tierForProduct(String id) {
    switch (id) {
      case plusMonthly:
        return (SubscriptionTier.plus, BillingPeriod.monthly);
      case plusAnnual:
        return (SubscriptionTier.plus, BillingPeriod.annual);
      case partnerMonthly:
        return (SubscriptionTier.partner, BillingPeriod.monthly);
      case partnerAnnual:
        return (SubscriptionTier.partner, BillingPeriod.annual);
      default:
        return (SubscriptionTier.welcome, BillingPeriod.monthly);
    }
  }

  /// Get the product ID for a given tier + billing period
  static String productIdFor(
    SubscriptionTier tier,
    BillingPeriod period,
  ) {
    if (tier == SubscriptionTier.plus) {
      return period == BillingPeriod.monthly ? plusMonthly : plusAnnual;
    }
    if (tier == SubscriptionTier.partner) {
      return period == BillingPeriod.monthly ? partnerMonthly : partnerAnnual;
    }
    return plusMonthly; // fallback
  }
}

// ── Stripe configuration (web only) ─────────────────────────────────────────
//
// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  STRIPE SETUP CHECKLIST — complete before going live                    ║
// ╠══════════════════════════════════════════════════════════════════════════╣
// ║  1. PUBLISHABLE KEY                                                      ║
// ║     Build with:  flutter build web --dart-define=STRIPE_PK=pk_live_xxx  ║
// ║     Test builds: flutter build web --dart-define=STRIPE_PK=pk_test_xxx  ║
// ║     Obtain from: https://dashboard.stripe.com/apikeys                   ║
// ║                                                                          ║
// ║  2. PRICE IDs  (replace placeholders in priceIds map below)             ║
// ║     Create products at: https://dashboard.stripe.com/products           ║
// ║     Then copy the Price ID (starts with price_) for each plan/period.   ║
// ║                                                                          ║
// ║  3. WEBHOOK                                                              ║
// ║     Endpoint: POST https://api.huddlapp.co.uk/api/stripe/webhook      ║
// ║     Events:   customer.subscription.created                             ║
// ║               customer.subscription.updated                             ║
// ║               invoice.paid                                              ║
// ║               invoice.payment_failed                                    ║
// ║               customer.subscription.deleted                             ║
// ║     Secret:   Set STRIPE_WEBHOOK_SECRET env var on the backend server.  ║
// ║     Obtain:   https://dashboard.stripe.com/webhooks                     ║
// ║                                                                          ║
// ║  4. BACKEND ENVIRONMENT VARIABLES (api.huddlapp.co.uk)                    ║
// ║     STRIPE_SECRET_KEY=sk_live_xxx                                       ║
// ║     STRIPE_WEBHOOK_SECRET=whsec_xxx                                     ║
// ║                                                                          ║
// ║  5. CUSTOMER PORTAL                                                     ║
// ║     Enable and configure at:                                             ║
// ║     https://dashboard.stripe.com/settings/billing/portal                ║
// ╚══════════════════════════════════════════════════════════════════════════╝

class StripeConfig {
  StripeConfig._();

  // Stripe publishable key — must be provided via --dart-define=STRIPE_PK=pk_live_xxx
  // In production, NEVER use a test key. Obtain your live key from Stripe Dashboard.
  static const String publishableKey =
      String.fromEnvironment('STRIPE_PK', defaultValue: '');

  // Backend endpoints (handled by BackendApiService — no hard-coded URLs needed)
  static String get checkoutSessionUrl =>
      '${BackendApiService().baseUrl}/api/stripe/create-checkout-session';

  static String get customerPortalUrl =>
      '${BackendApiService().baseUrl}/api/stripe/customer-portal';

  // ── Stripe Price IDs ────────────────────────────────────────────────────
  // Live Stripe Price IDs — configured Apr 2025
  //
  //  Product          Period   Stripe Price ID                      Amount
  //  ───────────────  ───────  ──────────────────────────────────── ──────
  //  Huddl Plus       Monthly  price_1TaagGGb8Lg9FVI5f2SrV5nv       £4.99
  //  Huddl Plus       Annual   price_1TaagHGb8Lg9FVI5k1BKNlqv      £39.99
  //  Huddl Partner    Monthly  price_1TaagHGb8Lg9FVI5bgzTWFLU      £24.99
  //  Huddl Partner    Annual   price_1TaagIGb8Lg9FVI54eBr0Qgo     £199.00
  //  (created via Stripe API — June 2025; old Neighbour/Circle prices archived)
  static const Map<String, String> priceIds = {
    HuddlProductIds.plusMonthly:     'price_1TaagGGb8Lg9FVI5f2SrV5nv',
    HuddlProductIds.plusAnnual:      'price_1TaagHGb8Lg9FVI5k1BKNlqv',
    HuddlProductIds.partnerMonthly:  'price_1TaagHGb8Lg9FVI5bgzTWFLU',
    HuddlProductIds.partnerAnnual:   'price_1TaagIGb8Lg9FVI54eBr0Qgo',
  };
}

// ── Purchase status enum ────────────────────────────────────────────────────

enum PaymentStatus {
  idle,
  loading,
  purchasing,
  verifying,
  success,
  error,
  restored,
}

// ── Store product wrapper ───────────────────────────────────────────────────

class StoreProduct {
  final String id;
  final String title;
  final String description;
  final String price; // formatted price string from the store
  final String rawPrice; // numeric price
  final String currencyCode;
  final ProductDetails? _iapDetails;

  StoreProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    ProductDetails? iapDetails,
  }) : _iapDetails = iapDetails;

  ProductDetails? get iapDetails => _iapDetails;

  /// Create from IAP ProductDetails
  factory StoreProduct.fromIAP(ProductDetails details) {
    return StoreProduct(
      id: details.id,
      title: details.title,
      description: details.description,
      price: details.price,
      rawPrice: details.price,
      currencyCode: details.currencyCode,
      iapDetails: details,
    );
  }

  /// Create a placeholder for web (Stripe) billing
  factory StoreProduct.fromStripe({
    required String id,
    required String title,
    required String price,
    required String currencyCode,
  }) {
    return StoreProduct(
      id: id,
      title: title,
      description: '',
      price: price,
      rawPrice: price,
      currencyCode: currencyCode,
    );
  }
}

// ── Payment Service ─────────────────────────────────────────────────────────

class PaymentService extends ChangeNotifier {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final PaymentService _instance = PaymentService._();
  factory PaymentService() => _instance;
  PaymentService._();

  // ── State ──────────────────────────────────────────────────────────────
  bool _initialized = false;
  bool _storeAvailable = false;
  PaymentStatus _status = PaymentStatus.idle;
  String? _errorMessage;
  final Map<String, StoreProduct> _products = {};
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  // ── Callbacks ──────────────────────────────────────────────────────────
  /// Called when a purchase is successfully completed and verified.
  /// The caller (SubscriptionService) should update its own state.
  void Function(String productId, PurchaseDetails? details)? onPurchaseSuccess;

  /// Called when a purchase fails
  void Function(String? errorMessage)? onPurchaseError;

  /// Called when purchases are restored
  void Function(List<String> restoredProductIds)? onPurchasesRestored;

  // ── Getters ────────────────────────────────────────────────────────────
  bool get isInitialized => _initialized;
  bool get isStoreAvailable => _storeAvailable;
  PaymentStatus get status => _status;
  String? get errorMessage => _errorMessage;
  Map<String, StoreProduct> get products => Map.unmodifiable(_products);
  bool get isWeb => kIsWeb;
  bool get isMobile => !kIsWeb;

  /// Whether the platform supports native IAP
  bool get supportsNativeIAP => !kIsWeb;

  /// Get the payment method display name for UI
  String get paymentMethodName {
    if (kIsWeb) return 'Stripe';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return 'Apple Pay / App Store';
    }
    return 'Google Pay / Google Play';
  }

  /// Get available payment methods for the current platform
  List<PaymentMethod> get availablePaymentMethods {
    if (kIsWeb) {
      return [
        PaymentMethod(
          type: PaymentMethodType.stripe,
          displayName: 'Card / Stripe',
          icon: 'credit_card',
          description: 'Visa, Mastercard, Amex & more',
        ),
        PaymentMethod(
          type: PaymentMethodType.applePay,
          displayName: 'Apple Pay',
          icon: 'apple',
          description: 'Pay with Apple Pay',
        ),
        PaymentMethod(
          type: PaymentMethodType.googlePay,
          displayName: 'Google Pay',
          icon: 'g_mobiledata',
          description: 'Pay with Google Pay',
        ),
      ];
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return [
        PaymentMethod(
          type: PaymentMethodType.appStore,
          displayName: 'Apple Pay / App Store',
          icon: 'apple',
          description:
              'Pay with Apple Pay, cards in your wallet, or App Store billing',
        ),
      ];
    }
    return [
      PaymentMethod(
        type: PaymentMethodType.googlePlay,
        displayName: 'Google Pay / Google Play',
        icon: 'g_mobiledata',
        description:
            'Pay with Google Pay, cards, or Google Play billing',
      ),
    ];
  }

  // ── Initialization ─────────────────────────────────────────────────────

  /// Initialise the payment service.
  ///
  /// Wrapped in an 8-second hard timeout so it can never block the UI
  /// regardless of what happens inside (Play Store unavailable, network
  /// timeout, device without Play Services, etc.).
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _doInitialize().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint(
              'PaymentService: initialize() timed out after 8 s '
              '— falling back to local pricing.',
            );
          }
          // Ensure the service is always left in a usable state
          if (!_initialized) {
            _storeAvailable = false;
            _populateWebProducts();
            _initialized = true;
            _setStatus(PaymentStatus.idle);
          }
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PaymentService: initialize() failed: $e — using local pricing.');
      }
      if (!_initialized) {
        _storeAvailable = false;
        _populateWebProducts();
        _initialized = true;
        _setStatus(PaymentStatus.idle);
      }
    }
  }

  Future<void> _doInitialize() async {
    _setStatus(PaymentStatus.loading);

    if (kIsWeb) {
      // Web: no IAP — pre-populate products from our local pricing
      _populateWebProducts();
      _storeAvailable = true;
    } else {
      // Mobile: initialise the IAP connection.
      //
      // IMPORTANT — "Checking service status..." hang explained:
      // The first call to InAppPurchase.instance triggers BillingClientManager
      // construction which immediately calls BillingClient.startConnection().
      // Google Play Billing shows its own OS-level "Checking service status..."
      // overlay while binding to the Play Store service. If the Play Store is
      // unreachable (no network, emulator without Play Services, slow device)
      // this binding can hang indefinitely, freezing the app at launch.
      //
      // Fix: isAvailable() has a 6 s timeout → falls back to local pricing.
      // The outer initialize() has an 8 s hard timeout as a belt-and-braces
      // safety net (covers isAvailable + _loadProducts combined).
      try {
        _storeAvailable = await InAppPurchase.instance
            .isAvailable()
            .timeout(
              const Duration(seconds: 6),
              onTimeout: () {
                if (kDebugMode) {
                  debugPrint(
                    'PaymentService: isAvailable() timed out after 6 s '
                    '— treating store as unavailable, using local pricing.',
                  );
                }
                return false;
              },
            );

        if (_storeAvailable) {
          // Listen for purchase updates
          _purchaseSubscription = InAppPurchase.instance.purchaseStream
              .listen(_handlePurchaseUpdate, onError: _handlePurchaseError);

          // Query products from the store
          await _loadProducts();
        } else {
          if (kDebugMode) {
            debugPrint('PaymentService: Store not available');
          }
          // Fallback to local pricing
          _populateWebProducts();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('PaymentService: Error initializing IAP: $e');
        }
        _storeAvailable = false;
        _populateWebProducts();
      }
    }

    _initialized = true;
    _setStatus(PaymentStatus.idle);
  }

  /// Load products from the native store
  Future<void> _loadProducts() async {
    try {
      // 15-second timeout prevents the initialization spinner hanging
      // indefinitely when the App Store / Play Store is unreachable.
      final response = await InAppPurchase.instance
          .queryProductDetails(HuddlProductIds.all)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
              'Product query timed out after 15 seconds',
            ),
          );

      if (response.error != null) {
        if (kDebugMode) {
          debugPrint(
              'PaymentService: Error querying products: ${response.error}');
        }
      }

      if (response.notFoundIDs.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
              'PaymentService: Products not found: ${response.notFoundIDs}');
        }
      }

      _products.clear();
      for (final details in response.productDetails) {
        _products[details.id] = StoreProduct.fromIAP(details);
      }

      // If no products found from store (e.g. sandbox), use fallback
      if (_products.isEmpty) {
        _populateWebProducts();
      }

      if (kDebugMode) {
        debugPrint(
            'PaymentService: Loaded ${_products.length} products from store');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PaymentService: Exception loading products: $e');
      }
      _populateWebProducts();
    }
  }

  /// Populate products using our local pricing (for web or when store
  /// is unavailable).
  void _populateWebProducts() {
    _products.clear();
    for (final plan in SubscriptionPlan.allPlans) {
      if (plan.tier == SubscriptionTier.welcome) continue;

      final monthlyId = HuddlProductIds.productIdFor(
          plan.tier, BillingPeriod.monthly);
      final annualId = HuddlProductIds.productIdFor(
          plan.tier, BillingPeriod.annual);

      _products[monthlyId] = StoreProduct.fromStripe(
        id: monthlyId,
        title: '${plan.name} Monthly',
        price: '\u00A3${plan.monthlyPrice.toStringAsFixed(2)}/month',
        currencyCode: 'GBP',
      );

      _products[annualId] = StoreProduct.fromStripe(
        id: annualId,
        title: '${plan.name} Annual',
        price: '\u00A3${plan.annualPrice.toStringAsFixed(2)}/year',
        currencyCode: 'GBP',
      );
    }
  }

  // ── Purchase Flow ──────────────────────────────────────────────────────

  /// Initiate a purchase for the given tier and period.
  ///
  /// On mobile: triggers the native store purchase sheet (Apple Pay / GPay /
  /// card selection is handled by the OS — the user sees the standard system
  /// payment sheet with all their saved payment methods).
  ///
  /// On web: initiates a Stripe Checkout redirect.
  Future<bool> purchaseSubscription({
    required SubscriptionTier tier,
    required BillingPeriod period,
  }) async {
    if (!_initialized) await initialize();

    final productId = HuddlProductIds.productIdFor(
      tier,
      period,
    );

    _setStatus(PaymentStatus.purchasing);

    if (kIsWeb) {
      return _purchaseViaStripe(productId);
    } else {
      return _purchaseViaNativeStore(productId);
    }
  }

  /// Purchase via native IAP (iOS/Android)
  Future<bool> _purchaseViaNativeStore(String productId) async {
    final product = _products[productId];
    if (product?.iapDetails == null) {
      _setError('Product not available. Please try again later.');
      return false;
    }

    try {
      final purchaseParam = PurchaseParam(
        productDetails: product!.iapDetails!,
      );

      // This triggers the native payment sheet:
      //   iOS:  Apple's payment sheet (Apple Pay, cards, carrier billing)
      //   Android: Google Play's payment sheet (Google Pay, cards, carrier)
      final success = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!success) {
        _setError('Purchase could not be initiated. Please try again.');
        return false;
      }

      // The actual result comes through the purchaseStream listener
      return true;
    } catch (e) {
      _setError('Purchase failed: ${e.toString()}');
      return false;
    }
  }

  /// Purchase via Stripe Checkout (web).
  ///
  /// Calls the Node.js backend to create a Stripe Checkout Session and opens
  /// the Stripe-hosted payment page in the browser via url_launcher.
  ///
  /// ─── HOW THE WEB FLOW WORKS ────────────────────────────────────────────
  ///  1. We POST to /api/stripe/create-checkout-session with:
  ///       productId   → tells the backend which Stripe Price to charge
  ///       successUrl  → Stripe redirects here after payment; include a
  ///                     ?session_id={CHECKOUT_SESSION_ID} query parameter so
  ///                     your backend can confirm the session on return.
  ///       cancelUrl   → Stripe redirects here if the user clicks "Back"
  ///  2. We receive a Stripe Checkout URL and open it in the browser.
  ///  3. Status is set to [PaymentStatus.verifying] while the user is on
  ///     the Stripe page.  We do NOT call onPurchaseSuccess here — payment
  ///     has not been collected yet.
  ///  4. After the user pays, Stripe fires a webhook to your backend
  ///     (invoice.paid / customer.subscription.created).  The backend
  ///     updates Firestore with the new subscription state.
  ///  5. On return to the app the SubscriptionService reads Firestore and
  ///     updates the user's tier.  The checkout screen should listen to
  ///     Firestore (or poll /api/subscription/{uid}) to detect the change
  ///     and show the success dialog.
  ///
  /// ─── STRIPE DASHBOARD SETUP REQUIRED ──────────────────────────────────
  ///  • Webhook endpoint:  POST https://api.huddlapp.co.uk/api/stripe/webhook
  ///  • Events to listen:  customer.subscription.created
  ///                        customer.subscription.updated
  ///                        invoice.paid
  ///                        invoice.payment_failed
  ///  • Webhook secret:    Set STRIPE_WEBHOOK_SECRET env var on backend.
  ///
  /// ─── PRODUCT / PRICE IDS IN STRIPE DASHBOARD ──────────────────────────
  /// Live Stripe Price IDs are configured in StripeConfig.priceIds.
  Future<bool> _purchaseViaStripe(String productId) async {
    try {
      final api = BackendApiService();

      // Build return URLs.  On web, window.location.origin is available via
      // Uri.base.  The backend embeds ?session_id={CHECKOUT_SESSION_ID} in
      // the successUrl so it can verify the session on return.
      final origin = kIsWeb ? Uri.base.origin : 'https://www.huddlapp.co.uk';
      final successUrl =
          '$origin/subscription/success?session_id={CHECKOUT_SESSION_ID}';
      final cancelUrl = '$origin/subscription/cancel';

      final result = await api.createCheckoutSession(
        productId: productId,
        successUrl: successUrl,
        cancelUrl: cancelUrl,
      );

      final checkoutUrl = result['url'] as String?;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        _setError('Could not create payment session. Please try again.');
        return false;
      }

      if (kDebugMode) {
        debugPrint('PaymentService: Opening Stripe Checkout: $checkoutUrl');
      }

      _lastCheckoutUrl = checkoutUrl;

      // Open the Stripe-hosted payment page in the browser.
      // On web this navigates the current tab; on mobile it opens a browser.
      final launched = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _setError(
            'Could not open payment page. Please try again or copy the link manually.');
        return false;
      }

      // Payment is IN PROGRESS — the user is now on the Stripe page.
      // We set status to verifying and return true to signal the UI to wait.
      // onPurchaseSuccess must NOT be called here — no money has been
      // collected yet.  The webhook (→ Firestore → SubscriptionService)
      // will confirm the payment asynchronously.
      _setStatus(PaymentStatus.verifying);
      return true;
    } on BackendApiException catch (e) {
      _setError(e.message);
      return false;
    } catch (e) {
      _setError('Payment failed: ${e.toString()}');
      return false;
    }
  }

  /// Notify the app that a Stripe payment completed (called from the
  /// success-return route or after a Firestore subscription-state change
  /// is detected).
  ///
  /// Call this from your router when the user lands on the successUrl path,
  /// e.g. in your GoRouter / Navigator redirect handler:
  ///
  ///   PaymentService().notifyStripeSuccess(productId: resolvedProductId);
  void notifyStripeSuccess(String productId) {
    _setStatus(PaymentStatus.success);
    onPurchaseSuccess?.call(productId, null);
  }

  /// The last Stripe Checkout URL (exposed so the UI can show a "Open
  /// payment page" button if the automatic launch failed).
  String? _lastCheckoutUrl;
  String? get lastCheckoutUrl => _lastCheckoutUrl;

  // ── Purchase Stream Handler ────────────────────────────────────────────

  void _handlePurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchase in purchaseDetailsList) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          // iOS "Ask to Buy" — purchase is pending parental approval.
          // completePurchase() MUST still be called so StoreKit doesn't
          // re-deliver the transaction on every subsequent app launch.
          // Without this, the user gets repeated purchase dialogs until
          // the parent approves or declines.
          if (purchase.pendingCompletePurchase) {
            InAppPurchase.instance.completePurchase(purchase);
          }
          _setStatus(PaymentStatus.purchasing);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _handleSuccessfulPurchase(purchase);
          break;

        case PurchaseStatus.error:
          _handlePurchaseFailure(purchase);
          break;

        case PurchaseStatus.canceled:
          // Canceled purchases on iOS also require completePurchase() to
          // remove the transaction from the StoreKit queue.
          if (purchase.pendingCompletePurchase) {
            InAppPurchase.instance.completePurchase(purchase);
          }
          _setStatus(PaymentStatus.idle);
          break;
      }
    }
  }

  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchase) async {
    _setStatus(PaymentStatus.verifying);

    // ── Receipt Verification ──────────────────────────────────────────
    // In production, send the receipt to your backend for server-side
    // verification:
    //
    //   iOS:  purchase.verificationData.serverVerificationData
    //         -> Send to Apple's verifyReceipt endpoint
    //   Android: purchase.verificationData.serverVerificationData
    //            -> Send to Google Play Developer API
    //
    // The backend should:
    //   1. Validate the receipt with the store.
    //   2. Check the product ID and expiry date.
    //   3. Update the user's subscription in your database.
    //   4. Return success/failure to the app.
    //
    // For now, we trust the local purchase status.

    final verified = await _verifyPurchase(purchase);

    if (verified) {
      // Complete the purchase (required — failure to do this on Android
      // causes the purchase to be refunded after 3 days)
      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }

      if (purchase.status == PurchaseStatus.restored) {
        _setStatus(PaymentStatus.restored);
        onPurchasesRestored?.call([purchase.productID]);
      } else {
        _setStatus(PaymentStatus.success);
        onPurchaseSuccess?.call(purchase.productID, purchase);
      }
    } else {
      _setError('Purchase verification failed. Please contact support.');
    }
  }

  Future<void> _handlePurchaseFailure(PurchaseDetails purchase) async {
    // completePurchase must be called for failed transactions too —
    // failure to do so leaves the transaction in StoreKit's queue and it
    // will be re-delivered on every app launch until acknowledged.
    if (purchase.pendingCompletePurchase) {
      await InAppPurchase.instance.completePurchase(purchase);
    }

    final errorMsg =
        purchase.error?.message ?? 'Purchase failed. Please try again.';
    _setError(errorMsg);
    onPurchaseError?.call(errorMsg);
  }

  void _handlePurchaseError(dynamic error) {
    if (kDebugMode) {
      debugPrint('PaymentService: Purchase stream error: $error');
    }
    _setError('An unexpected error occurred. Please try again.');
  }

  /// Verify the purchase receipt via the Huddl backend.
  ///
  /// Sends the receipt/token to the server which validates it with Apple or
  /// Google, updates Firestore, and returns the result.
  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    try {
      final api = BackendApiService();

      // Determine platform
      final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
      final serverData = purchase.verificationData.serverVerificationData;

      Map<String, dynamic> result;
      if (isIOS) {
        result = await api.verifyAppleReceipt(
          receiptData: serverData,
          productId: purchase.productID,
          transactionId: purchase.purchaseID,
        );
      } else {
        result = await api.verifyGoogleReceipt(
          purchaseToken: serverData,
          productId: purchase.productID,
        );
      }

      return result['valid'] == true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PaymentService: Receipt verification error: $e');
      }
      // Fallback to local verification in development
      if (!kReleaseMode) {
        return purchase.verificationData.localVerificationData.isNotEmpty;
      }
      return false;
    }
  }

  // ── Restore Purchases (Required by Apple Guideline 3.1.1) ─────────────

  Future<bool> restorePurchases() async {
    if (!_initialized) await initialize();

    if (kIsWeb) {
      // On web, restoration is handled by checking Stripe subscription status
      // via the backend API.
      try {
        final api = BackendApiService();
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return false;
        final status = await api.getSubscriptionStatus(uid);
        final isActive = status['isActive'] == true;
        final tier = status['tier'] as String? ?? 'welcome';
        if (isActive && tier != 'welcome') {
          _setStatus(PaymentStatus.restored);
          final productId = _productIdFromTierString(tier, status['billingPeriod'] as String?);
          onPurchasesRestored?.call([productId]);
          return true;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('PaymentService: Web restore error: $e');
        }
      }
      return false;
    }

    try {
      _setStatus(PaymentStatus.loading);
      await InAppPurchase.instance.restorePurchases();
      // Results come through the purchaseStream
      return true;
    } catch (e) {
      _setError('Could not restore purchases: ${e.toString()}');
      return false;
    }
  }

  // ── Manage Subscription ────────────────────────────────────────────────

  /// Opens the platform-specific subscription management page.
  ///   iOS: App Store subscription settings
  ///   Android: Google Play subscription settings
  ///   Web: Stripe Customer Portal
  Future<String?> openSubscriptionManagement() async {
    if (kIsWeb) {
      try {
        final api = BackendApiService();
        final result = await api.createCustomerPortal();
        final portalUrl = result['url'] as String?;
        if (kDebugMode) {
          debugPrint('PaymentService: Stripe Customer Portal URL: $portalUrl');
        }
        return portalUrl;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('PaymentService: Portal error: $e');
        }
      }
    }
    // On mobile, users manage subscriptions through their store settings.
    // The app should display instructions directing users there.
    return null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  /// Map a tier/billingPeriod string pair back to a product ID.
  String _productIdFromTierString(String tier, String? billingPeriod) {
    final isAnnual = billingPeriod == 'annual';
    switch (tier) {
      case 'plus':
        return isAnnual
            ? HuddlProductIds.plusAnnual
            : HuddlProductIds.plusMonthly;
      case 'partner':
        return isAnnual
            ? HuddlProductIds.partnerAnnual
            : HuddlProductIds.partnerMonthly;
      // backward-compat — old 'innerCircle' tier string maps to partner
      case 'innerCircle':
        return isAnnual
            ? HuddlProductIds.partnerAnnual
            : HuddlProductIds.partnerMonthly;
      default:
        return HuddlProductIds.plusMonthly;
    }
  }

  void _setStatus(PaymentStatus newStatus) {
    _status = newStatus;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _status = PaymentStatus.error;
    _errorMessage = message;
    notifyListeners();
    onPurchaseError?.call(message);
  }

  /// Get the store-localised price for a product, or a fallback
  String getPriceForProduct(String productId) {
    return _products[productId]?.price ?? '';
  }

  // ── Disposal ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}

// ── Payment Method types ────────────────────────────────────────────────────

enum PaymentMethodType {
  appStore, // Apple In-App Purchase (StoreKit)
  googlePlay, // Google Play Billing
  stripe, // Stripe Checkout (web)
  applePay, // Apple Pay (via Stripe on web)
  googlePay, // Google Pay (via Stripe on web)
}

class PaymentMethod {
  final PaymentMethodType type;
  final String displayName;
  final String icon;
  final String description;

  const PaymentMethod({
    required this.type,
    required this.displayName,
    required this.icon,
    required this.description,
  });
}
