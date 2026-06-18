import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'subscription_service.dart';

enum BusinessEntityType { limitedCompany, vatRegistered, soleTrader }

class VerificationResult {
  final bool success;
  final String? verifiedName;
  final String? error;
  const VerificationResult({required this.success, this.verifiedName, this.error});
}

/// Singleton service handling UK business verification via the verifyBusiness
/// Cloud Function (region: europe-west2).
///
/// SECURITY: The client sends ONLY the raw identifier (companyNumber / vatNumber)
/// + method. All trust fields (businessVerified, verifiedBusinessName,
/// verificationData, verificationMethod) are written server-side by the CF via
/// Admin SDK — the F-09 Firestore rule blocks any direct client writes of those
/// fields. verifiedBusinessName is always API-sourced on the server, preventing
/// business-name impersonation.
///
/// See: functions/src/index.ts  verifyBusiness (CF 11, Audit: SUB-3 / ANN-1)
class BusinessVerificationService {
  static final _i = BusinessVerificationService._();
  factory BusinessVerificationService() => _i;
  BusinessVerificationService._();

  /// Returns the europe-west2 callable for 'verifyBusiness'.
  HttpsCallable get _callable =>
      FirebaseFunctions.instanceFor(region: 'europe-west2')
          .httpsCallable('verifyBusiness');

  /// Maps FirebaseFunctionsException error codes to user-facing messages.
  String _mapFunctionsError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return "We couldn't find that company number.";
      case 'failed-precondition':
        return "That company isn't active / verification isn't available right now.";
      case 'unauthenticated':
        return "Please sign in again.";
      case 'unavailable':
        return "Verification service is temporarily unavailable. Please try later.";
      default:
        return "Verification failed. Please try again.";
    }
  }

  /// Verify a UK limited company via the verifyBusiness CF (Companies House).
  ///
  /// [companyNumber] is the raw 8-character Companies House number.
  /// [companyName]   is accepted for API compatibility but IGNORED — the
  ///                 server-verified name is always taken from the CF response.
  ///
  /// The client sends ONLY the raw companyNumber. The CF resolves the
  /// authoritative company_name from Companies House and writes all trust
  /// fields via Admin SDK.
  Future<VerificationResult> verifyLimitedCompany({
    required String companyNumber,
    required String companyName, // kept for caller compatibility; unused here
  }) async {
    try {
      final result = await _callable.call(<String, dynamic>{
        'method': 'companies_house',
        'companyNumber': companyNumber,
      });

      final data = result.data as Map<dynamic, dynamic>?;
      final verified = data?['verified'] as bool? ?? false;
      // businessName is always server-derived (API response), never client input.
      final serverName = data?['businessName'] as String?;

      if (!verified) {
        return const VerificationResult(
          success: false,
          error: 'Verification failed. Please try again.',
        );
      }

      // Refresh in-memory subscription / verification state.
      await SubscriptionService().loadBusinessVerificationStatus();
      return VerificationResult(success: true, verifiedName: serverName);
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('BusinessVerificationService [CH]: ${e.code} — ${e.message}');
      }
      return VerificationResult(success: false, error: _mapFunctionsError(e));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BusinessVerificationService [CH] unexpected: $e');
      }
      return const VerificationResult(
        success: false,
        error: 'Could not reach the verification service. Check your connection.',
      );
    }
  }

  /// Verify a UK VAT number via the verifyBusiness CF (HMRC).
  ///
  /// The client sends ONLY the raw vatNumber. The CF resolves the authoritative
  /// business name from HMRC and writes all trust fields via Admin SDK.
  Future<VerificationResult> verifyVatNumber(String vatNumber) async {
    try {
      final result = await _callable.call(<String, dynamic>{
        'method': 'hmrc_vat',
        'vatNumber': vatNumber,
      });

      final data = result.data as Map<dynamic, dynamic>?;
      final verified = data?['verified'] as bool? ?? false;
      final serverName = data?['businessName'] as String?;

      if (!verified) {
        return const VerificationResult(
          success: false,
          error: 'Verification failed. Please try again.',
        );
      }

      await SubscriptionService().loadBusinessVerificationStatus();
      return VerificationResult(success: true, verifiedName: serverName);
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('BusinessVerificationService [VAT]: ${e.code} — ${e.message}');
      }
      return VerificationResult(success: false, error: _mapFunctionsError(e));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BusinessVerificationService [VAT] unexpected: $e');
      }
      return const VerificationResult(
        success: false,
        error: 'Could not reach the verification service. Check your connection.',
      );
    }
  }

  /// Record a sole trader statutory declaration.
  ///
  /// No external API — legal liability transfers to the declarant.
  ///
  /// NOTE: The direct Firestore write of trust fields has been removed because
  /// the F-09 rule blocks client writes of businessVerified / verifiedBusinessName.
  /// A future `verifySoleTrader` CF (TODO: SUB-3 follow-on) will handle the
  /// Admin SDK write. For now the declaration is accepted client-side and
  /// the VerificationResult is returned; the CF write will be wired in when
  /// the sole-trader CF is deployed.
  Future<VerificationResult> submitSoleTraderDeclaration({
    required String legalName,
    required String tradingName,
    required String utrNumber,
  }) async {
    // TODO(SUB-3): call a verifySoleTrader CF here so the trust fields
    // (businessVerified, verifiedBusinessName, verificationData) are written
    // via Admin SDK. Until that CF exists, the declaration is accepted
    // client-side only — Firestore trust fields are NOT written (F-09 blocks
    // any direct client write).
    if (kDebugMode) {
      debugPrint(
        'BusinessVerificationService: sole trader declaration accepted '
        '(CF write pending — SUB-3 follow-on). '
        'legalName=$legalName tradingName=$tradingName',
      );
    }
    return VerificationResult(success: true, verifiedName: tradingName);
  }
}
