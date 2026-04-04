// ============================================================================
// HUDDL CONNECT -- PAYMENT SERVICE
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

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../models/subscription.dart';

// ── Product ID constants ─────────────────────────────────────────────────────
// These MUST match the IDs configured in App Store Connect and Google Play
// Console. Use reverse-domain notation for clarity.

class HuddlProductIds {
  HuddlProductIds._();

  // Neighbourhood tier
  static const String neighbourhoodMonthly = 'huddl_neighbourhood_monthly';
  static const String neighbourhoodAnnual = 'huddl_neighbourhood_annual';
  static const String neighbourhoodFoundingMonthly =
      'huddl_neighbourhood_founding_monthly';

  // Inner Circle tier
  static const String innerCircleMonthly = 'huddl_inner_circle_monthly';
  static const String innerCircleAnnual = 'huddl_inner_circle_annual';

  /// All product IDs we expect to find in the store
  static const Set<String> all = {
    neighbourhoodMonthly,
    neighbourhoodAnnual,
    neighbourhoodFoundingMonthly,
    innerCircleMonthly,
    innerCircleAnnual,
  };

  /// Map product ID -> (SubscriptionTier, BillingPeriod)
  static (SubscriptionTier, BillingPeriod) tierForProduct(String id) {
    switch (id) {
      case neighbourhoodMonthly:
      case neighbourhoodFoundingMonthly:
        return (SubscriptionTier.neighbourhood, BillingPeriod.monthly);
      case neighbourhoodAnnual:
        return (SubscriptionTier.neighbourhood, BillingPeriod.annual);
      case innerCircleMonthly:
        return (SubscriptionTier.innerCircle, BillingPeriod.monthly);
      case innerCircleAnnual:
        return (SubscriptionTier.innerCircle, BillingPeriod.annual);
      default:
        return (SubscriptionTier.explorer, BillingPeriod.monthly);
    }
  }

  /// Get the product ID for a given tier + billing period
  static String productIdFor(
    SubscriptionTier tier,
    BillingPeriod period, {
    bool foundingMember = false,
  }) {
    if (tier == SubscriptionTier.neighbourhood) {
      if (foundingMember && period == BillingPeriod.monthly) {
        return neighbourhoodFoundingMonthly;
      }
      return period == BillingPeriod.monthly
          ? neighbourhoodMonthly
          : neighbourhoodAnnual;
    }
    if (tier == SubscriptionTier.innerCircle) {
      return period == BillingPeriod.monthly
          ? innerCircleMonthly
          : innerCircleAnnual;
    }
    return neighbourhoodMonthly; // fallback
  }
}

// ── Stripe configuration (web only) ─────────────────────────────────────────

class StripeConfig {
  StripeConfig._();

  // TODO: Replace with your actual Stripe publishable key
  static const String publishableKey = 'pk_test_YOUR_KEY_HERE';

  // TODO: Replace with your backend endpoint that creates Checkout Sessions
  static const String checkoutSessionUrl =
      'https://your-backend.com/api/create-checkout-session';

  // TODO: Replace with your backend endpoint for the customer portal
  static const String customerPortalUrl =
      'https://your-backend.com/api/customer-portal';

  // Stripe Price IDs (must match your Stripe Dashboard products)
  static const Map<String, String> priceIds = {
    HuddlProductIds.neighbourhoodMonthly: 'price_neighbourhood_monthly',
    HuddlProductIds.neighbourhoodAnnual: 'price_neighbourhood_annual',
    HuddlProductIds.neighbourhoodFoundingMonthly:
        'price_neighbourhood_founding',
    HuddlProductIds.innerCircleMonthly: 'price_inner_circle_monthly',
    HuddlProductIds.innerCircleAnnual: 'price_inner_circle_annual',
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

  Future<void> initialize() async {
    if (_initialized) return;

    _setStatus(PaymentStatus.loading);

    if (kIsWeb) {
      // Web: no IAP — pre-populate products from our local pricing
      _populateWebProducts();
      _storeAvailable = true;
    } else {
      // Mobile: initialise the IAP connection
      try {
        _storeAvailable = await InAppPurchase.instance.isAvailable();

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
      final response = await InAppPurchase.instance.queryProductDetails(
        HuddlProductIds.all,
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
      if (plan.tier == SubscriptionTier.explorer) continue;

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

    // Founding member product
    if (SubscriptionPlan.allPlans
        .any((p) => p.tier == SubscriptionTier.neighbourhood)) {
      final foundingPlan = SubscriptionPlan.allPlans
          .firstWhere((p) => p.tier == SubscriptionTier.neighbourhood);
      if (foundingPlan.foundingMonthlyPrice != null) {
        _products[HuddlProductIds.neighbourhoodFoundingMonthly] =
            StoreProduct.fromStripe(
          id: HuddlProductIds.neighbourhoodFoundingMonthly,
          title: 'Neighbourhood Founding Member',
          price:
              '\u00A3${foundingPlan.foundingMonthlyPrice!.toStringAsFixed(2)}/month',
          currencyCode: 'GBP',
        );
      }
    }
  }

  // ── Purchase Flow ──────────────────────────────────────────────────────

  /// Initiate a purchase for the given tier, period, and founding status.
  ///
  /// On mobile: triggers the native store purchase sheet (Apple Pay / GPay /
  /// card selection is handled by the OS — the user sees the standard system
  /// payment sheet with all their saved payment methods).
  ///
  /// On web: initiates a Stripe Checkout redirect.
  Future<bool> purchaseSubscription({
    required SubscriptionTier tier,
    required BillingPeriod period,
    bool foundingMember = false,
  }) async {
    if (!_initialized) await initialize();

    final productId = HuddlProductIds.productIdFor(
      tier,
      period,
      foundingMember: foundingMember,
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

  /// Purchase via Stripe Checkout (web)
  Future<bool> _purchaseViaStripe(String productId) async {
    try {
      // In production, this would call your backend to create a Stripe
      // Checkout session and redirect the user. The backend creates the
      // session with the appropriate price_id and returns the session URL.
      //
      // For now, we simulate the Stripe flow with a delay.
      // TODO: Implement actual Stripe Checkout session creation

      if (kDebugMode) {
        debugPrint(
            'PaymentService: Would initiate Stripe Checkout for $productId');
        debugPrint(
            'PaymentService: Stripe Price ID: ${StripeConfig.priceIds[productId]}');
      }

      // Simulate Stripe checkout
      await Future.delayed(const Duration(seconds: 2));

      _setStatus(PaymentStatus.verifying);
      await Future.delayed(const Duration(milliseconds: 500));

      // Simulate success
      _setStatus(PaymentStatus.success);
      onPurchaseSuccess?.call(productId, null);
      return true;
    } catch (e) {
      _setError('Payment failed: ${e.toString()}');
      return false;
    }
  }

  // ── Purchase Stream Handler ────────────────────────────────────────────

  void _handlePurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchase in purchaseDetailsList) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
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

  void _handlePurchaseFailure(PurchaseDetails purchase) {
    if (purchase.pendingCompletePurchase) {
      InAppPurchase.instance.completePurchase(purchase);
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

  /// Verify the purchase receipt.
  /// In production, this MUST be done server-side.
  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    // TODO: Implement server-side receipt verification
    //
    // Example backend call:
    // final response = await http.post(
    //   Uri.parse('https://your-backend.com/api/verify-receipt'),
    //   body: jsonEncode({
    //     'platform': Platform.isIOS ? 'ios' : 'android',
    //     'receipt': purchase.verificationData.serverVerificationData,
    //     'productId': purchase.productID,
    //     'transactionId': purchase.purchaseID,
    //   }),
    // );
    // return response.statusCode == 200;

    // For development, trust local verification
    return purchase.verificationData.localVerificationData.isNotEmpty;
  }

  // ── Restore Purchases (Required by Apple Guideline 3.1.1) ─────────────

  Future<bool> restorePurchases() async {
    if (!_initialized) await initialize();

    if (kIsWeb) {
      // On web, restoration is handled by checking Stripe subscription status
      // via the backend API.
      // TODO: Call backend to check current Stripe subscription status
      if (kDebugMode) {
        debugPrint(
            'PaymentService: Restore on web — check Stripe subscription status');
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
  Future<void> openSubscriptionManagement() async {
    if (kIsWeb) {
      // TODO: Open Stripe Customer Portal
      // final url = await _getStripePortalUrl();
      // launchUrl(Uri.parse(url));
      if (kDebugMode) {
        debugPrint(
            'PaymentService: Would open Stripe Customer Portal');
      }
    }
    // On mobile, users manage subscriptions through their store settings.
    // The app should display instructions directing users there.
  }

  // ── Helpers ────────────────────────────────────────────────────────────

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
