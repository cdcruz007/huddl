// ============================================================================
// HUDDL -- BUSINESS VERIFICATION SERVICE
// ============================================================================
//
// Provides three verification paths for Huddl Partner applicants:
//
//   1. HMRC VAT Registration  — HMRC VAT Checker API (free, no key required)
//      Endpoint: https://api.service.hmrc.gov.uk/organisations/vat/check-vat-number/lookup/{vatNumber}
//      Valid for: VAT-registered businesses (turnover > £90k threshold)
//
//   2. Companies House lookup — Companies House REST API (free, no key required
//      for basic lookup via Accept: application/json header)
//      Endpoint: https://api.company-information.service.gov.uk/company/{companyNumber}
//      Valid for: Limited companies and LLPs registered in England & Wales
//
//   3. Sole Trader UTR declaration — self-attestation. The user declares their
//      UTR (Unique Taxpayer Reference) number and agrees to T&Cs. No API call
//      required. Sets a 'pendingReview' flag so Huddl admin can spot-check.
//
// All three paths write the verification result to Firestore via
// SubscriptionService.setBusinessVerified() on success.
// ============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Verification method chosen by the user.
enum BusinessVerificationMethod {
  vat,         // HMRC VAT number lookup
  companies,   // Companies House number lookup
  soleTrader,  // UTR self-declaration
}

/// Result returned by a verification attempt.
class VerificationResult {
  final bool success;
  final String? businessName;
  final String? registrationNumber;
  final String? errorMessage;
  final bool pendingReview; // sole-trader path sets this

  const VerificationResult({
    required this.success,
    this.businessName,
    this.registrationNumber,
    this.errorMessage,
    this.pendingReview = false,
  });

  factory VerificationResult.failure(String message) => VerificationResult(
        success: false,
        errorMessage: message,
      );
}

class BusinessVerificationService {
  BusinessVerificationService._();
  static final BusinessVerificationService instance =
      BusinessVerificationService._();

  // ── HMRC VAT number verification ──────────────────────────────────────────

  /// Validates a UK VAT number via the free HMRC API.
  /// VAT numbers should be 9 digits; leading 'GB' prefix is stripped.
  Future<VerificationResult> verifyVatNumber(String rawVat) async {
    final vatNumber = rawVat.trim().toUpperCase().replaceFirst('GB', '');
    if (vatNumber.isEmpty || vatNumber.length < 9) {
      return VerificationResult.failure(
          'Please enter a valid 9-digit VAT number.');
    }

    try {
      final uri = Uri.parse(
        'https://api.service.hmrc.gov.uk/organisations/vat/check-vat-number/lookup/$vatNumber',
      );
      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final target = data['target'] as Map<String, dynamic>?;
        final name = target?['name'] as String? ?? 'Your business';
        return VerificationResult(
          success: true,
          businessName: name,
          registrationNumber: 'GB$vatNumber',
        );
      } else if (response.statusCode == 404) {
        return VerificationResult.failure(
            'VAT number not found. Please check and try again.');
      } else {
        return VerificationResult.failure(
            'HMRC verification unavailable. Please try another method.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BusinessVerificationService.verifyVatNumber: $e');
      }
      return VerificationResult.failure(
          'Could not connect to HMRC. Please check your connection and try again.');
    }
  }

  // ── Companies House number verification ───────────────────────────────────

  /// Validates a Companies House number via the free public API.
  /// Company numbers are 8 characters (may start with 0).
  Future<VerificationResult> verifyCompanyNumber(String rawNumber) async {
    final number = rawNumber.trim().toUpperCase().padLeft(8, '0');
    if (number.isEmpty || number.length != 8) {
      return VerificationResult.failure(
          'Please enter a valid 8-character Companies House number.');
    }

    try {
      final uri = Uri.parse(
        'https://api.company-information.service.gov.uk/company/$number',
      );
      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final companyStatus = data['company_status'] as String? ?? '';
        final companyName = data['company_name'] as String? ?? 'Your company';

        // Only allow active companies
        if (companyStatus != 'active') {
          return VerificationResult.failure(
              'This company is listed as "$companyStatus". '
              'Only active companies are eligible for Partner verification.');
        }

        return VerificationResult(
          success: true,
          businessName: companyName,
          registrationNumber: number,
        );
      } else if (response.statusCode == 404) {
        return VerificationResult.failure(
            'Company number not found. Please check and try again.');
      } else {
        return VerificationResult.failure(
            'Companies House verification unavailable. Please try another method.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BusinessVerificationService.verifyCompanyNumber: $e');
      }
      return VerificationResult.failure(
          'Could not connect to Companies House. Please check your connection and try again.');
    }
  }

  // ── Sole Trader UTR self-declaration ──────────────────────────────────────

  /// Records a sole trader UTR self-declaration.
  /// No external API call — sets pendingReview = true for admin spot-check.
  VerificationResult declareSoleTrader({
    required String utr,
    required String tradingName,
    required bool agreedToTCs,
  }) {
    if (!agreedToTCs) {
      return VerificationResult.failure(
          'You must agree to the Terms & Conditions to proceed.');
    }

    final cleanUtr = utr.replaceAll(RegExp(r'\s+'), '');
    if (cleanUtr.length != 10 || int.tryParse(cleanUtr) == null) {
      return VerificationResult.failure(
          'Please enter a valid 10-digit Unique Taxpayer Reference (UTR).');
    }

    if (tradingName.trim().isEmpty) {
      return VerificationResult.failure(
          'Please enter your trading name or business name.');
    }

    return VerificationResult(
      success: true,
      businessName: tradingName.trim(),
      registrationNumber: 'UTR-${cleanUtr.substring(0, 4)}****',
      pendingReview: true, // Flagged for admin review
    );
  }
}
