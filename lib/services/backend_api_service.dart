// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — BACKEND API SERVICE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Centralised HTTP client for communicating with the Huddl Node.js backend.
// Handles:
//   - Firebase ID token injection in every request
//   - Stripe Checkout session creation
//   - Stripe Customer Portal
//   - Apple & Google receipt verification
//   - Subscription status queries
//   - FCM token registration
//   - Error mapping
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class BackendApiService {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final BackendApiService _instance = BackendApiService._();
  factory BackendApiService() => _instance;
  BackendApiService._();

  // ── Configuration ──────────────────────────────────────────────────────
  // In production, point to your deployed backend URL.
  // In development, use the local backend or the sandbox URL.
  static const String _prodBaseUrl = 'https://api.huddlapp.co.uk';
  static const String _devBaseUrl = 'http://localhost:3000';

  String get baseUrl {
    if (kReleaseMode) return _prodBaseUrl;
    return _devBaseUrl;
  }

  // ── Auth helper ────────────────────────────────────────────────────────

  /// Get the current user's Firebase ID token for API authentication.
  Future<String?> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  /// Build authenticated headers.
  Future<Map<String, String>> _authHeaders() async {
    final token = await _getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ═════════════════════════════════════════════════════════════════════════
  // STRIPE ENDPOINTS
  // ═════════════════════════════════════════════════════════════════════════

  /// Create a Stripe Checkout session and return the redirect URL.
  ///
  /// Returns { 'sessionId': '...', 'url': 'https://checkout.stripe.com/...' }
  Future<Map<String, dynamic>> createCheckoutSession({
    required String productId,
    String? successUrl,
    String? cancelUrl,
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/stripe/create-checkout-session'),
      headers: headers,
      body: jsonEncode({
        'productId': productId,
        if (successUrl != null) 'successUrl': successUrl,
        if (cancelUrl != null) 'cancelUrl': cancelUrl,
      }),
    ).timeout(const Duration(seconds: 15)); // LAYER-10-RAILWAY-TIMEOUT-1
    return _handleResponse(response);
  }

  /// Create a Stripe Customer Portal session and return the redirect URL.
  ///
  /// Returns { 'url': 'https://billing.stripe.com/...' }
  Future<Map<String, dynamic>> createCustomerPortal() async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/stripe/customer-portal'),
      headers: headers,
    ).timeout(const Duration(seconds: 15)); // LAYER-10-RAILWAY-TIMEOUT-1
    return _handleResponse(response);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RECEIPT VERIFICATION
  // ═════════════════════════════════════════════════════════════════════════

  /// Verify an Apple App Store receipt.
  ///
  /// Returns { 'valid': true, 'subscription': { 'tier': '...', ... } }
  Future<Map<String, dynamic>> verifyAppleReceipt({
    required String receiptData,
    required String productId,
    String? transactionId,
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/verify/apple'),
      headers: headers,
      body: jsonEncode({
        'receiptData': receiptData,
        'productId': productId,
        if (transactionId != null) 'transactionId': transactionId,
      }),
    ).timeout(const Duration(seconds: 15)); // LAYER-10-RAILWAY-TIMEOUT-1
    return _handleResponse(response);
  }

  /// Verify a Google Play purchase token.
  ///
  /// Returns { 'valid': true, 'subscription': { 'tier': '...', ... } }
  Future<Map<String, dynamic>> verifyGoogleReceipt({
    required String purchaseToken,
    required String productId,
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/verify/google'),
      headers: headers,
      body: jsonEncode({
        'purchaseToken': purchaseToken,
        'productId': productId,
      }),
    ).timeout(const Duration(seconds: 15)); // LAYER-10-RAILWAY-TIMEOUT-1
    return _handleResponse(response);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SUBSCRIPTION
  // ═════════════════════════════════════════════════════════════════════════

  /// Get the current subscription status from the backend.
  Future<Map<String, dynamic>> getSubscriptionStatus(String userId) async {
    final headers = await _authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/subscription/$userId'),
      headers: headers,
    ).timeout(const Duration(seconds: 15)); // LAYER-10-RAILWAY-TIMEOUT-1
    return _handleResponse(response);
  }

  /// Cancel the current subscription.
  Future<Map<String, dynamic>> cancelSubscription({
    String? reason,
    int? pauseMonths,
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/subscription/cancel'),
      headers: headers,
      body: jsonEncode({
        if (reason != null) 'reason': reason,
        if (pauseMonths != null) 'pauseMonths': pauseMonths,
      }),
    ).timeout(const Duration(seconds: 15)); // LAYER-10-RAILWAY-TIMEOUT-1
    return _handleResponse(response);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // NOTIFICATIONS
  // ═════════════════════════════════════════════════════════════════════════

  /// Register the FCM token with the backend.
  Future<void> registerFcmToken({
    required String token,
    required String platform,
  }) async {
    final headers = await _authHeaders();
    await http.post(
      Uri.parse('$baseUrl/api/notifications/register-token'),
      headers: headers,
      body: jsonEncode({
        'token': token,
        'platform': platform,
      }),
    ).timeout(const Duration(seconds: 15)); // LAYER-10-RAILWAY-TIMEOUT-1
  }

  /// Send welcome email and push notification to a newly registered user.
  /// Called once immediately after profile creation in _createUserProfile.
  Future<void> sendWelcomeNotification({
    required String email,
    String? firstName,
    String? borough,
  }) async {
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$baseUrl/api/notifications/welcome'),
        headers: headers,
        body: jsonEncode({
          'email': email,
          'firstName': firstName ?? '',
          'borough': borough ?? '',
        }),
      ).timeout(const Duration(seconds: 15)); // LAYER-10-RAILWAY-TIMEOUT-1
    } catch (e) {
      // Non-fatal — log but don't block user flow
      if (kDebugMode) debugPrint('[BackendApiService] sendWelcomeNotification error: $e');
    }
  }

  /// Called when a user adds their email address to their profile for the
  /// first time. Triggers the welcome email if it hasn't been sent yet.
  Future<void> notifyEmailAdded(String email) async {
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$baseUrl/api/notifications/email-added'),
        headers: headers,
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 15)); // LAYER-10-RAILWAY-TIMEOUT-1
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendApiService] notifyEmailAdded error: $e');
    }
  }

  /// Polls whether the signed-in user has verified their email address.
  /// Returns a map with at least `{ emailVerified: bool, email: String }`.
  Future<Map<String, dynamic>> checkEmailVerified() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/notifications/check-verified'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'emailVerified': false};
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendApiService] checkEmailVerified error: $e');
      return {'emailVerified': false};
    }
  }

  /// Resends the verification email for the currently signed-in user.
  /// Throws a [BackendApiException] if the server returns an error (e.g. no
  /// email on file). Rate-limiting is enforced client-side (60 s cooldown).
  Future<void> resendVerificationEmail() async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/notifications/resend-verification'),
      headers: headers,
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw BackendApiException(
        statusCode: response.statusCode,
        message: body['error'] as String? ?? 'Failed to resend verification email',
      );
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MESSAGE PUSH NOTIFICATIONS
  // ═════════════════════════════════════════════════════════════════════════

  /// Fan-out a push notification to all group members except the sender.
  /// Called immediately after [FirestoreService.sendGroupMessage] writes to Firestore.
  /// Non-fatal — errors are logged but never bubble up to the UI.
  Future<void> notifyGroupMessage({
    required String groupId,
    required String groupName,
    required String senderName,
    required String messagePreview,
  }) async {
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$baseUrl/api/messages/notify-group'),
        headers: headers,
        body: jsonEncode({
          'groupId': groupId,
          'groupName': groupName,
          'senderName': senderName,
          'messagePreview': messagePreview,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendApiService] notifyGroupMessage error: $e');
    }
  }

  /// Fan-out a cancellation push to every confirmed attendee of a deleted meetup.
  ///
  /// Calls POST /api/meetups/notify-cancelled on the backend, which:
  ///   1. Looks up each attendeeUid's fcmToken in Firestore
  ///   2. Sends an FCM v1 notification to each token
  ///   3. Also writes a notifications_queue doc for Cloud Function fallback
  ///
  /// Non-fatal — errors are logged but never surface to the UI.
  Future<void> notifyMeetupCancelled({
    required String meetupId,
    required String meetupTitle,
    required String organiserName,
    required String dateDisplay,
    required List<String> attendeeUids,
  }) async {
    try {
      if (attendeeUids.isEmpty) return;
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$baseUrl/api/meetups/notify-cancelled'),
        headers: headers,
        body: jsonEncode({
          'meetupId': meetupId,
          'meetupTitle': meetupTitle,
          'organiserName': organiserName,
          'dateDisplay': dateDisplay,
          'attendeeUids': attendeeUids,
        }),
      ).timeout(const Duration(seconds: 12));
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendApiService] notifyMeetupCancelled error: $e');
    }
  }

  /// Push a notification to the DM recipient.
  /// Called immediately after [RealtimeDMService.sendMessage] writes to Firestore.
  /// Non-fatal — errors are logged but never bubble up to the UI.
  Future<void> notifyDmMessage({
    required String conversationId,
    required String recipientId,
    required String senderName,
    required String messagePreview,
  }) async {
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$baseUrl/api/messages/notify-dm'),
        headers: headers,
        body: jsonEncode({
          'conversationId': conversationId,
          'recipientId': recipientId,
          'senderName': senderName,
          'messagePreview': messagePreview,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendApiService] notifyDmMessage error: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MARKETPLACE NOTIFICATIONS
  // ═════════════════════════════════════════════════════════════════════════

  /// Notify a seller that they received a new offer on their listing.
  Future<void> notifyOfferReceived({
    required String sellerId,
    required String buyerName,
    required String itemTitle,
    required String itemId,
    required String offerId,
    required String offerAmount,
    String? notePreview,
    String? itemImageUrl,
  }) async {
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$baseUrl/api/messages/notify-offer'),
        headers: headers,
        body: jsonEncode({
          'sellerId': sellerId,
          'buyerName': buyerName,
          'itemTitle': itemTitle,
          'itemId': itemId,
          'offerId': offerId,
          'offerAmount': offerAmount,
          if (notePreview != null) 'notePreview': notePreview,
          if (itemImageUrl != null) 'itemImageUrl': itemImageUrl,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendApiService] notifyOfferReceived error: $e');
    }
  }

  /// Notify a buyer that the seller accepted or declined their offer.
  Future<void> notifyOfferResponse({
    required String buyerId,
    required String sellerName,
    required String itemTitle,
    required String itemId,
    required bool accepted,
    String? sellerId,
    String? responseMessage,
    String? itemImageUrl,
  }) async {
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$baseUrl/api/messages/notify-offer-response'),
        headers: headers,
        body: jsonEncode({
          'buyerId': buyerId,
          'sellerName': sellerName,
          'itemTitle': itemTitle,
          'itemId': itemId,
          'accepted': accepted,
          if (sellerId != null) 'sellerId': sellerId,
          if (responseMessage != null) 'responseMessage': responseMessage,
          if (itemImageUrl != null) 'itemImageUrl': itemImageUrl,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendApiService] notifyOfferResponse error: $e');
    }
  }

  /// Notify seller + other buyers when an item is marked as sold.
  Future<void> notifyItemSold({
    required String sellerId,
    required String itemTitle,
    required String itemId,
    String? buyerName,
    List<String>? otherBuyerIds,
    String? itemImageUrl,
  }) async {
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$baseUrl/api/messages/notify-item-sold'),
        headers: headers,
        body: jsonEncode({
          'sellerId': sellerId,
          'itemTitle': itemTitle,
          'itemId': itemId,
          if (buyerName != null) 'buyerName': buyerName,
          if (otherBuyerIds != null) 'otherBuyerIds': otherBuyerIds,
          if (itemImageUrl != null) 'itemImageUrl': itemImageUrl,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendApiService] notifyItemSold error: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MEETUP NOTIFICATIONS
  // ═════════════════════════════════════════════════════════════════════════

  /// Push an FCM notification to all borough members when a new public meetup
  /// is created. The backend looks up FCM tokens for users in [borough] and
  /// fires the notification, skipping the organiser.
  Future<void> notifyNewMeetupNearby({
    required String meetupId,
    required String meetupTitle,
    required String meetupDate,
    required String meetupLocation,
    required String borough,
    required String organiserId,
  }) async {
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$baseUrl/api/meetups/notify-new-nearby'),
        headers: headers,
        body: jsonEncode({
          'meetupId': meetupId,
          'meetupTitle': meetupTitle,
          'meetupDate': meetupDate,
          'meetupLocation': meetupLocation,
          'borough': borough,
          'organiserId': organiserId,
        }),
      ).timeout(const Duration(seconds: 12));
    } catch (e) {
      if (kDebugMode) debugPrint('[BackendApiService] notifyNewMeetupNearby error: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RESPONSE HANDLING
  // ═════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _handleResponse(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final errorMsg = body['error'] as String? ?? 'Unknown error';
    throw BackendApiException(
      statusCode: response.statusCode,
      message: errorMsg,
    );
  }
}

/// Exception thrown when a backend API call fails.
class BackendApiException implements Exception {
  final int statusCode;
  final String message;

  BackendApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'BackendApiException($statusCode): $message';
}
