import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'subscription_service.dart';

enum BusinessEntityType { limitedCompany, vatRegistered, soleTrader }

class VerificationResult {
  final bool success;
  final String? verifiedName;
  final String? error;
  const VerificationResult({required this.success, this.verifiedName, this.error});
}

/// Singleton service handling HMRC + Companies House business verification.
/// Verification is a post-subscription unlock, not a pre-purchase gate.
class BusinessVerificationService {
  static final _i = BusinessVerificationService._();
  factory BusinessVerificationService() => _i;
  BusinessVerificationService._();

  /// Verify a UK limited company via the free Companies House public API.
  /// No API key required.
  Future<VerificationResult> verifyLimitedCompany({
    required String companyNumber,
    required String companyName,
  }) async {
    try {
      final cleaned = companyNumber.trim().toUpperCase().padLeft(8, '0');
      final uri = Uri.parse(
          'https://api.company-information.service.gov.uk/company/$cleaned');
      final res =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final status = data['company_status'] as String? ?? '';
        final name   = data['company_name']   as String? ?? '';
        if (status == 'active') {
          await _write(
            method: 'companies_house',
            entityType: 'limited_company',
            verifiedName: name,
            extra: {'companyNumber': cleaned},
          );
          return VerificationResult(success: true, verifiedName: name);
        }
        return const VerificationResult(
          success: false,
          error: 'Company is not listed as active on Companies House. '
              'Check the number and try again.',
        );
      }
      if (res.statusCode == 404) {
        return const VerificationResult(
          success: false,
          error: 'No company found with that number. '
              'Check Companies House and try again.',
        );
      }
      return const VerificationResult(
        success: false,
        error: 'Companies House is temporarily unavailable. Try again shortly.',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('BusinessVerificationService: $e');
      return const VerificationResult(
        success: false,
        error: 'Could not connect to Companies House. Check your connection.',
      );
    }
  }

  /// Verify a UK VAT number via the free HMRC VAT Validation public API.
  /// No API key required.
  Future<VerificationResult> verifyVatNumber(String vatNumber) async {
    try {
      final cleaned =
          vatNumber.trim().replaceAll(RegExp(r'[^0-9]'), '');
      final uri = Uri.parse(
          'https://api.service.hmrc.gov.uk/organisations/vat/check-vat-number/lookup/$cleaned');
      final res = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data   = jsonDecode(res.body) as Map<String, dynamic>;
        final target = data['target'] as Map<String, dynamic>?;
        final name   = target?['name'] as String? ?? '';
        await _write(
          method: 'hmrc_vat',
          entityType: 'vat_registered',
          verifiedName: name,
          extra: {'vatNumber': cleaned},
        );
        return VerificationResult(success: true, verifiedName: name);
      }
      if (res.statusCode == 404) {
        return const VerificationResult(
          success: false,
          error: 'VAT number not found. Check the number and try again.',
        );
      }
      return const VerificationResult(
        success: false,
        error: 'HMRC is temporarily unavailable. Try again shortly.',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('BusinessVerificationService: $e');
      return const VerificationResult(
        success: false,
        error: 'Could not connect to HMRC. Check your connection.',
      );
    }
  }

  /// Record a sole trader statutory declaration.
  /// No external API — legal liability transfers to the declarant.
  Future<VerificationResult> submitSoleTraderDeclaration({
    required String legalName,
    required String tradingName,
    required String utrNumber,
  }) async {
    try {
      await _write(
        method: 'sole_trader_declaration',
        entityType: 'sole_trader',
        verifiedName: tradingName,
        extra: {
          'legalName': legalName,
          'utrHash': utrNumber.hashCode.toString(), // never store raw UTR
          'declarationSignedAt': FieldValue.serverTimestamp(),
        },
      );
      return VerificationResult(success: true, verifiedName: tradingName);
    } catch (e) {
      if (kDebugMode) debugPrint('BusinessVerificationService: $e');
      return const VerificationResult(
        success: false,
        error: 'Could not save declaration. Please try again.',
      );
    }
  }

  Future<void> _write({
    required String method,
    required String entityType,
    required String verifiedName,
    required Map<String, dynamic> extra,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'businessVerified': true,
      'verificationMethod': method,
      'verifiedBusinessName': verifiedName,
      'verificationData': {
        'entityType': entityType,
        'verifiedAt': FieldValue.serverTimestamp(),
        ...extra,
      },
    }, SetOptions(merge: true));
    // Refresh in-memory state immediately
    await SubscriptionService().loadBusinessVerificationStatus();
  }
}
