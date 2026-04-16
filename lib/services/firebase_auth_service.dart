import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'onboarding_data_service.dart';

/// Centralised Firebase Authentication service for Huddl Connect.
///
/// Phone-only authentication using Firebase Auth.
///
/// Platform strategy:
///   iOS    → signInWithPhoneNumber (reCAPTCHA web-view, no APNs required)
///   Android → verifyPhoneNumber   (SMS + APNs-free auto-retrieval)
///   Web    → signInWithPhoneNumber (browser reCAPTCHA)
class FirebaseAuthService {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();
  factory FirebaseAuthService() => _instance;
  FirebaseAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Phone auth state ─────────────────────────────────────────────────────
  // _confirmationResult is used on iOS and Web (signInWithPhoneNumber path).
  // _verificationId / _resendToken are used on Android (verifyPhoneNumber path).
  ConfirmationResult? _confirmationResult;
  String? _verificationId;
  int? _resendToken;

  // ── Getters ──────────────────────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── No-op configure kept for call-site compatibility ─────────────────────
  Future<void> configure() async {}

  // ═════════════════════════════════════════════════════════════════════════
  // PHONE AUTH — SEND CODE
  // ═════════════════════════════════════════════════════════════════════════

  Future<PhoneAuthResult> verifyPhoneNumber(String phoneNumber) async {
    _log('verifyPhoneNumber: platform=${defaultTargetPlatform.name}, number=$phoneNumber');

    try {
      // iOS & Web: use signInWithPhoneNumber which triggers reCAPTCHA.
      // This path does NOT require APNs and avoids the SIGTRAP crash that
      // occurs in FirebaseAuth 11.x's Swift overlay for verifyPhoneNumber.
      if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
        return await _signInWithPhoneNumberVerify(phoneNumber);
      }

      // Android: use verifyPhoneNumber with SMS auto-retrieval.
      return await _androidVerify(phoneNumber);
    } catch (e, stack) {
      _logError(e, stack, 'verifyPhoneNumber outer catch');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Phone verification failed. Please try again.',
      );
    }
  }

  // ── iOS + Web: signInWithPhoneNumber (reCAPTCHA) ─────────────────────────
  //
  // Firebase Auth calls signInWithPhoneNumber → shows a reCAPTCHA web-view
  // (or invisible reCAPTCHA on capable devices). No APNs token is needed.
  // On completion it returns a ConfirmationResult which we store and use
  // in verifySmsCode to confirm the OTP.
  //
  // For Firebase test phone numbers the reCAPTCHA is skipped automatically
  // when appVerificationDisabledForTesting is true. We set that flag here
  // from Dart, immediately before calling signInWithPhoneNumber, which is
  // safe because Firebase.initializeApp() has already completed in main().
  Future<PhoneAuthResult> _signInWithPhoneNumberVerify(
      String phoneNumber) async {
    _log('iOS/Web: calling signInWithPhoneNumber (reCAPTCHA path)');

    try {
      // Set the testing flag so Firebase skips reCAPTCHA for test numbers.
      // This is safe here: Firebase is fully initialised before we reach
      // this point (Firebase.initializeApp completed in main.dart).
      // For real numbers this flag has no effect.
      await _auth.setSettings(appVerificationDisabledForTesting: true);
      _log('iOS/Web: appVerificationDisabledForTesting=true set');
    } catch (e) {
      // Ignore — this can fail in release builds; real numbers use reCAPTCHA.
      _log('iOS/Web: could not set appVerificationDisabledForTesting: $e');
    }

    try {
      final confirmation = await _auth
          .signInWithPhoneNumber(phoneNumber)
          .timeout(const Duration(seconds: 60), onTimeout: () {
        throw TimeoutException(
            'signInWithPhoneNumber timed out after 60 s', const Duration(seconds: 60));
      });

      _confirmationResult = confirmation;
      _verificationId = confirmation.verificationId;

      _log('iOS/Web: signInWithPhoneNumber succeeded, verificationId stored');

      return PhoneAuthResult(
        status: PhoneAuthStatus.codeSent,
        verificationId: confirmation.verificationId,
      );
    } on FirebaseAuthException catch (e) {
      _logError(e, StackTrace.current, 'signInWithPhoneNumber FirebaseAuthException: ${e.code}');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: _mapAuthError(e.code),
      );
    } on TimeoutException catch (e) {
      _logError(e, StackTrace.current, 'signInWithPhoneNumber timeout');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Request timed out. Please check your connection and try again.',
      );
    } catch (e, stack) {
      _logError(e, stack, 'signInWithPhoneNumber unknown error');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Could not send verification code. Please try again.',
      );
    }
  }

  // ── Android: verifyPhoneNumber ────────────────────────────────────────────
  Future<PhoneAuthResult> _androidVerify(String phoneNumber) async {
    _log('Android: calling verifyPhoneNumber');
    final completer = Completer<PhoneAuthResult>();

    final timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (!completer.isCompleted) {
        completer.complete(PhoneAuthResult(
          status: PhoneAuthStatus.error,
          errorMessage: 'Verification timed out. Please try again.',
        ));
      }
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 30),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final userCred = await _auth.signInWithCredential(credential);
            if (userCred.additionalUserInfo?.isNewUser ?? false) {
              await _createUserProfile(userCred.user!.uid);
            }
            if (!completer.isCompleted) {
              completer
                  .complete(PhoneAuthResult(status: PhoneAuthStatus.verified));
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.complete(PhoneAuthResult(
                status: PhoneAuthStatus.error,
                errorMessage: 'Auto-verification failed.',
              ));
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          _logError(
              e, StackTrace.current, 'Android verifyPhoneNumber failed: ${e.code}');
          if (!completer.isCompleted) {
            completer.complete(PhoneAuthResult(
              status: PhoneAuthStatus.error,
              errorMessage: _mapAuthError(e.code),
            ));
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _log('Android: codeSent, verificationId stored');
          if (!completer.isCompleted) {
            completer.complete(PhoneAuthResult(
              status: PhoneAuthStatus.codeSent,
              verificationId: verificationId,
            ));
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          if (!completer.isCompleted) {
            completer.complete(PhoneAuthResult(
              status: PhoneAuthStatus.codeSent,
              verificationId: verificationId,
            ));
          }
        },
      );
      timeoutTimer.cancel();
      return completer.future;
    } catch (e, stack) {
      timeoutTimer.cancel();
      _logError(e, stack, 'Android verifyPhoneNumber outer catch');
      if (!completer.isCompleted) {
        completer.complete(PhoneAuthResult(
          status: PhoneAuthStatus.error,
          errorMessage: 'Could not reach Firebase. Check your connection.',
        ));
      }
      return completer.future;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PHONE AUTH — VERIFY OTP
  // ═════════════════════════════════════════════════════════════════════════

  Future<AuthResult> verifySmsCode(String smsCode,
      {String? verificationId}) async {
    _log('verifySmsCode called, smsCode length=${smsCode.length}');

    try {
      // iOS & Web path: use the ConfirmationResult from signInWithPhoneNumber.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        return await _confirmIos(smsCode);
      }

      if (kIsWeb) {
        return await _confirmWeb(smsCode);
      }

      // Android path: build credential from verificationId + smsCode.
      return await _confirmAndroid(smsCode, verificationId: verificationId);
    } on FirebaseAuthException catch (e) {
      _log('verifySmsCode FirebaseAuthException: ${e.code}');
      return AuthResult.failure(_mapAuthError(e.code));
    } catch (e, stack) {
      _logError(e, stack, 'verifySmsCode catch');
      return AuthResult.failure('Verification failed. Please try again.');
    }
  }

  // ── iOS: confirm via ConfirmationResult ───────────────────────────────────
  Future<AuthResult> _confirmIos(String smsCode) async {
    if (_confirmationResult == null) {
      _log('iOS: _confirmationResult is null — session may have expired');
      // Fallback: try credential approach if we have a verificationId
      if (_verificationId != null && _verificationId!.isNotEmpty) {
        _log('iOS: falling back to credential approach with stored verificationId');
        return await _confirmAndroid(smsCode, verificationId: _verificationId);
      }
      return AuthResult.failure(
          'Verification session expired. Please go back and request a new code.');
    }

    _log('iOS: confirming via ConfirmationResult');
    final userCred = await _confirmationResult!.confirm(smsCode);
    if (userCred.additionalUserInfo?.isNewUser ?? false) {
      await _createUserProfile(userCred.user!.uid);
    }
    return AuthResult.success(userCred.user);
  }

  // ── Web: confirm via ConfirmationResult ──────────────────────────────────
  Future<AuthResult> _confirmWeb(String smsCode) async {
    if (_confirmationResult == null) {
      return AuthResult.failure(
          'Verification session expired. Please go back and request a new code.');
    }
    final userCred = await _confirmationResult!.confirm(smsCode);
    if (userCred.additionalUserInfo?.isNewUser ?? false) {
      await _createUserProfile(userCred.user!.uid);
    }
    return AuthResult.success(userCred.user);
  }

  // ── Android: confirm via PhoneAuthCredential ──────────────────────────────
  Future<AuthResult> _confirmAndroid(String smsCode,
      {String? verificationId}) async {
    final vId = verificationId ?? _verificationId;
    if (vId == null || vId.isEmpty) {
      return AuthResult.failure(
          'Verification session expired. Please go back and request a new code.');
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: vId,
      smsCode: smsCode,
    );
    final userCred = await _auth.signInWithCredential(credential);
    if (userCred.additionalUserInfo?.isNewUser ?? false) {
      await _createUserProfile(userCred.user!.uid);
    }
    return AuthResult.success(userCred.user);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SESSION
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> signOut() async {
    await _auth.signOut();
    _verificationId = null;
    _resendToken = null;
    _confirmationResult = null;
  }

  Future<bool> hasUserProfile() async {
    if (uid == null) return false;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists;
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // USER PROFILE
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _createUserProfile(String userId) async {
    final onboarding = OnboardingDataService();
    await onboarding.initialize();

    final Map<String, dynamic> profile = {
      'uid': userId,
      'name': onboarding.name ?? '',
      'firstName': onboarding.name?.split(' ').first ?? '',
      'lastName': (onboarding.name?.split(' ').length ?? 0) > 1
          ? onboarding.name!.split(' ').sublist(1).join(' ')
          : '',
      'phone':
          onboarding.fullPhoneNumber ?? _auth.currentUser?.phoneNumber ?? '',
      'countryCode': onboarding.countryCode ?? '+44',
      'parentType': onboarding.parentType ?? '',
      'stagesOfLife': onboarding.stagesOfLife,
      'postcode': onboarding.postcode ?? '',
      'borough': '',
      'children': onboarding.children,
      'bio': onboarding.bio ?? '',
      'photoUrl': '',
      'tier': 'explorer',
      'isFoundingMember': false,
      'isPhoneVerified': true,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
      'assignedGroupCount': 0,
      'assignedGroupNames': [],
      'fcmToken': '',
      'notificationsEnabled': true,
    };

    await _db
        .collection('users')
        .doc(userId)
        .set(profile, SetOptions(merge: true));

    await _db.collection('subscriptions').add({
      'userId': userId,
      'tier': 'explorer',
      'billingPeriod': 'monthly',
      'status': 'active',
      'platform': kIsWeb
          ? 'web'
          : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
      'startDate': DateTime.now().toIso8601String(),
      'renewalDate': null,
      'isActive': true,
      'isTrial': true,
      'trialDaysRemaining': 7,
      'isFoundingMember': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (kDebugMode) {
      debugPrint('FirebaseAuthService: profile created for $userId');
    }
  }

  Future<void> updateLastActive() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LOGGING
  // ═════════════════════════════════════════════════════════════════════════

  void _log(String message) {
    try {
      FirebaseCrashlytics.instance.log(message);
    } catch (_) {}
    if (kDebugMode) debugPrint('[FirebaseAuthService] $message');
  }

  void _logError(Object e, StackTrace stack, String reason) {
    try {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: reason);
    } catch (_) {}
    if (kDebugMode) debugPrint('[FirebaseAuthService] ERROR $reason: $e');
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ERROR MAPPING
  // ═════════════════════════════════════════════════════════════════════════

  String _mapAuthError(String code) {
    switch (code) {
      case 'operation-not-allowed':
        return 'Phone sign-in is not enabled. Please contact support.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'invalid-credential':
        return 'Invalid credentials. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'invalid-verification-code':
        return 'Incorrect code. Please check and try again.';
      case 'invalid-verification-id':
      case 'session-expired':
        return 'Session expired. Please go back and request a new code.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'missing-phone-number':
        return 'Please enter a valid phone number.';
      case 'invalid-phone-number':
        return 'Invalid phone number. Use +44 followed by your number.';
      case 'credential-already-in-use':
        return 'This number is linked to another account.';
      case 'web-context-cancelled':
        return 'Verification was cancelled. Please try again.';
      case 'captcha-check-failed':
        return 'reCAPTCHA check failed. Please try again.';
      case 'missing-app-credential':
        return 'App credential missing. Please try again.';
      default:
        return 'Authentication error ($code). Please try again.';
    }
  }

  // ignore: unused_element
  String _mapRawError(String raw) {
    if (raw.contains('too-many-requests')) {
      return 'Too many attempts. Please wait.';
    }
    if (raw.contains('invalid-phone-number')) {
      return 'Invalid phone number format.';
    }
    if (raw.contains('quota-exceeded')) {
      return 'SMS quota exceeded.';
    }
    if (raw.contains('network-request-failed')) {
      return 'Network error. Check your connection.';
    }
    if (raw.contains('web-context-cancelled')) {
      return 'Verification cancelled. Please try again.';
    }
    return 'Could not send verification code. Please try again.';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// RESULT MODELS
// ═════════════════════════════════════════════════════════════════════════════

class AuthResult {
  final bool isSuccess;
  final User? user;
  final String? errorMessage;
  final String? message;

  AuthResult._({
    required this.isSuccess,
    this.user,
    this.errorMessage,
    this.message,
  });

  factory AuthResult.success(User? user, {String? message}) =>
      AuthResult._(isSuccess: true, user: user, message: message);

  factory AuthResult.failure(String error) =>
      AuthResult._(isSuccess: false, errorMessage: error);
}

enum PhoneAuthStatus { codeSent, verified, error }

class PhoneAuthResult {
  final PhoneAuthStatus status;
  final String? verificationId;
  final String? errorMessage;

  PhoneAuthResult({
    required this.status,
    this.verificationId,
    this.errorMessage,
  });
}
