import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'subscription_service.dart';

enum BusinessEntityType { limitedCompany, vatRegistered, soleTrader }

/// Result returned by all three verification paths.
///
/// [success]      — whether the operation completed without error.
/// [verifiedName] — server-derived business name (CH / HMRC) or declared
///                  trading name (sole trader).
/// [error]        — user-facing error message when success == false.
/// [selfDeclared] — true ONLY for the sole_trader_declaration path.
///                  The UI MUST render this as a distinct "self-declared"
///                  badge, NEVER as the verified badge.
class VerificationResult {
  final bool success;
  final String? verifiedName;
  final String? error;
  final bool selfDeclared;

  const VerificationResult({
    required this.success,
    this.verifiedName,
    this.error,
    this.selfDeclared = false, // CH and HMRC VAT paths leave this false
  });
}

/// Singleton service handling UK business verification via the verifyBusiness
/// Cloud Function (region: europe-west2).
///
/// SECURITY: The client sends ONLY the raw identifier (companyNumber /
/// vatNumber / utrNumber + names) + method. All trust fields
/// (businessVerified, businessSelfDeclared, verifiedBusinessName,
/// verificationData, verificationMethod) are written server-side by the CF
/// via Admin SDK — the F-09 Firestore rule blocks any direct client writes of
/// those fields. verifiedBusinessName is always API-sourced (CH / HMRC) or
/// declaration-sourced (sole trader) on the server.
///
/// SOLE TRADER NOTE: businessVerified is explicitly written FALSE by the CF
/// for the sole_trader_declaration path — a self-declaration must never
/// masquerade as a verified entity. The UI must use VerificationResult
/// .selfDeclared to choose the correct badge.
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

  /// Record a sole trader statutory declaration via the verifyBusiness CF
  /// (method: sole_trader_declaration).
  ///
  /// IMPORTANT: This path does NOT grant businessVerified. The CF explicitly
  /// writes businessVerified: false and businessSelfDeclared: true. The
  /// returned VerificationResult has selfDeclared: true so the UI can render
  /// the correct "self-declared" badge — NEVER the verified badge.
  ///
  /// The raw [utrNumber] is sent to the CF as-is. The CF validates format
  /// (10 digits) and stores only a sha256 hash — the client must NOT hash or
  /// pre-process the UTR before sending.
  Future<VerificationResult> submitSoleTraderDeclaration({
    required String legalName,
    required String tradingName,
    required String utrNumber,
  }) async {
    try {
      final result = await _callable.call(<String, dynamic>{
        'method': 'sole_trader_declaration',
        'legalName': legalName,
        'tradingName': tradingName,
        'utrNumber': utrNumber, // raw — CF hashes it; client must NOT hash
      });

      final data = result.data as Map<dynamic, dynamic>?;
      final selfDeclared = data?['selfDeclared'] as bool? ?? false;
      // businessName here is the declared tradingName, echoed back by the CF.
      final declaredName = data?['businessName'] as String?;

      if (!selfDeclared) {
        // CF returned an unexpected shape — treat as failure.
        return const VerificationResult(
          success: false,
          error: 'Declaration could not be recorded. Please try again.',
        );
      }

      // No loadBusinessVerificationStatus() here — businessVerified is false
      // on this path; the subscription service state does not change.
      return VerificationResult(
        success: true,
        verifiedName: declaredName ?? tradingName,
        selfDeclared: true, // UI must use distinct "self-declared" badge
      );
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('BusinessVerificationService [ST]: ${e.code} — ${e.message}');
      }
      return VerificationResult(success: false, error: _mapFunctionsError(e));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BusinessVerificationService [ST] unexpected: $e');
      }
      return const VerificationResult(
        success: false,
        error: 'Could not reach the verification service. Check your connection.',
      );
    }
  }
}
