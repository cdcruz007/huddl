import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

class OTPService {
  static final OTPService _instance = OTPService._internal();
  factory OTPService() => _instance;
  OTPService._internal();

  // Store OTP data temporarily (in production, this would be on backend)
  final Map<String, OTPData> _otpStorage = {};
  
  // Generate a 6-digit OTP
  String generateOTP() {
    final random = Random();
    final otp = (100000 + random.nextInt(900000)).toString();
    return otp;
  }
  
  // Send OTP to phone number
  Future<bool> sendOTP({
    required String phoneNumber,
    String? countryCode,
  }) async {
    try {
      final fullNumber = '${countryCode ?? '+44'}$phoneNumber';
      // TESTING: Always use 123456 for testing
      final otp = '123456';
      final expiryTime = DateTime.now().add(const Duration(minutes: 5));
      
      // Store OTP data
      _otpStorage[fullNumber] = OTPData(
        otp: otp,
        phoneNumber: fullNumber,
        expiryTime: expiryTime,
        attempts: 0,
      );
      
      // Simulate sending OTP (in production, call SMS API)
      if (kDebugMode) {
        debugPrint('📱 OTP Service: Sending OTP to $fullNumber');
        debugPrint('🔐 OTP Code: $otp (FIXED FOR TESTING)');
        debugPrint('⏰ Expires at: $expiryTime');
      }
      
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error sending OTP: $e');
      }
      return false;
    }
  }
  
  // Verify OTP
  Future<OTPVerificationResult> verifyOTP({
    required String phoneNumber,
    required String otp,
    String? countryCode,
  }) async {
    try {
      // ── Universal test bypass ─────────────────────────────────────────
      // Accept '123456' as a valid code in ALL build modes so testers can
      // always proceed through the verification screen without a real SMS.
      if (otp == '123456') {
        return OTPVerificationResult(
          success: true,
          message: 'Phone number verified successfully!',
        );
      }
      // ─────────────────────────────────────────────────────────────────

      final fullNumber = '${countryCode ?? '+44'}$phoneNumber';
      final otpData = _otpStorage[fullNumber];
      
      // Debug logging
      if (kDebugMode) {
        debugPrint('🔍 Verifying OTP for: $fullNumber');
        debugPrint('🔍 Entered OTP: $otp');
        debugPrint('🔍 Stored OTPs: ${_otpStorage.keys.toList()}');
        debugPrint('🔍 Found OTP data: ${otpData?.otp}');
      }
      
      // Check if OTP exists
      if (otpData == null) {
        if (kDebugMode) {
          debugPrint('❌ No OTP found for $fullNumber');
        }
        return OTPVerificationResult(
          success: false,
          message: 'No OTP found for this number. Please request a new code.',
        );
      }
      
      // Check if OTP expired
      if (DateTime.now().isAfter(otpData.expiryTime)) {
        _otpStorage.remove(fullNumber);
        return OTPVerificationResult(
          success: false,
          message: 'OTP has expired. Please request a new code.',
        );
      }
      
      // Check attempts limit (max 5 attempts)
      if (otpData.attempts >= 5) {
        _otpStorage.remove(fullNumber);
        return OTPVerificationResult(
          success: false,
          message: 'Too many failed attempts. Please request a new code.',
        );
      }
      
      // Increment attempts
      otpData.attempts++;
      
      // Verify OTP
      if (otpData.otp == otp) {
        _otpStorage.remove(fullNumber);
        if (kDebugMode) {
          debugPrint('✅ OTP Verified successfully for $fullNumber');
        }
        return OTPVerificationResult(
          success: true,
          message: 'Phone number verified successfully!',
        );
      } else {
        final remainingAttempts = 5 - otpData.attempts;
        return OTPVerificationResult(
          success: false,
          message: 'Invalid OTP. $remainingAttempts attempts remaining.',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error verifying OTP: $e');
      }
      return OTPVerificationResult(
        success: false,
        message: 'Verification failed. Please try again.',
      );
    }
  }
  
  // Resend OTP
  Future<bool> resendOTP({
    required String phoneNumber,
    String? countryCode,
  }) async {
    final fullNumber = '${countryCode ?? '+44'}$phoneNumber';
    _otpStorage.remove(fullNumber);
    return await sendOTP(phoneNumber: phoneNumber, countryCode: countryCode);
  }
  
  // Get remaining time for OTP
  Duration? getRemainingTime(String phoneNumber, {String? countryCode}) {
    final fullNumber = '${countryCode ?? '+44'}$phoneNumber';
    final otpData = _otpStorage[fullNumber];
    
    if (otpData == null) return null;
    
    final remaining = otpData.expiryTime.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }
  
  // Clear OTP for phone number
  void clearOTP(String phoneNumber, {String? countryCode}) {
    final fullNumber = '${countryCode ?? '+44'}$phoneNumber';
    _otpStorage.remove(fullNumber);
  }
  
  // Get OTP for testing/debugging (DO NOT USE IN PRODUCTION)
  String? getOTPForTesting(String phoneNumber, {String? countryCode}) {
    if (!kDebugMode) return null; // Only available in debug mode
    
    final fullNumber = phoneNumber.startsWith('+') ? phoneNumber : '${countryCode ?? '+44'}$phoneNumber';
    final otpData = _otpStorage[fullNumber];
    return otpData?.otp;
  }
}

// OTP Data Model
class OTPData {
  final String otp;
  final String phoneNumber;
  final DateTime expiryTime;
  int attempts;
  
  OTPData({
    required this.otp,
    required this.phoneNumber,
    required this.expiryTime,
    required this.attempts,
  });
}

// OTP Verification Result
class OTPVerificationResult {
  final bool success;
  final String message;
  
  OTPVerificationResult({
    required this.success,
    required this.message,
  });
}
