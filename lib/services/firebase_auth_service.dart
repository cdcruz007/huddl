import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'onboarding_data_service.dart';

/// Centralised Firebase Authentication service for Huddl Connect.
///
/// Platform strategy:
///   iOS    → signInWithPhoneNumber  (reCAPTCHA web-view; NO APNs / verifyPhoneNumber)
///            FirebaseAuth 11.x has a hard assertionFailure() inside
///            verifyPhoneNumber when APNs is not set up, which causes a
///            SIGTRAP crash on iOS 18. signInWithPhoneNumber uses the
///            reCAPTCHA web-view path and never touches APNs, so it is
///            the only safe choice on iOS with firebase_auth 5.x.
///   Web    → signInWithPhoneNumber  (browser reCAPTCHA — same API, same path)
///   Android → verifyPhoneNumber     (SMS auto-retrieval via GMS)
class FirebaseAuthService {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();
  factory FirebaseAuthService() => _instance;
  FirebaseAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Phone auth state ─────────────────────────────────────────────────────
  // iOS + Web: signInWithPhoneNumber stores ConfirmationResult
  ConfirmationResult? _confirmationResult;
  // Android only: verifyPhoneNumber stores verificationId + resendToken
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
    _log('verifyPhoneNumber called: platform=${defaultTargetPlatform.name}, '
        'kIsWeb=$kIsWeb, number=$phoneNumber');

    try {
      if (kIsWeb) return await _signInWithPhoneVerify(phoneNumber);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _signInWithPhoneVerify(phoneNumber);
      }
      // Android only
      return await _androidVerify(phoneNumber);
    } catch (e, stack) {
      _logError(e, stack, 'verifyPhoneNumber outer catch');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Phone verification failed. Please try again.',
      );
    }
  }

  // ── iOS + Web: signInWithPhoneNumber (reCAPTCHA — NO APNs required) ─────
  //
  // On iOS this presents a Safari web-view for reCAPTCHA, then Firebase
  // sends the SMS. No APNs token is needed at any point.
  // On iOS with test numbers registered in the Firebase Console, Firebase
  // skips the reCAPTCHA web-view and immediately returns a ConfirmationResult;
  // no appVerificationDisabledForTesting flag is required.
  Future<PhoneAuthResult> _signInWithPhoneVerify(String phoneNumber) async {
    _log('iOS/Web: calling signInWithPhoneNumber for: $phoneNumber');
    try {
      final result = await _auth
          .signInWithPhoneNumber(phoneNumber)
          .timeout(const Duration(seconds: 60));
      _confirmationResult = result;
      _verificationId = result.verificationId;
      _log('iOS/Web: codeSent OK, verificationId=${result.verificationId}');
      return PhoneAuthResult(
        status: PhoneAuthStatus.codeSent,
        verificationId: result.verificationId,
      );
    } on FirebaseAuthException catch (e) {
      // Surface the RAW error code and message directly in the UI so we can
      // diagnose the exact Firebase rejection reason without another rebuild.
      final msg = 'Firebase error: [${e.code}] ${e.message ?? "no message"}';
      _logError(e, StackTrace.current, 'signInWithPhoneNumber failed: $msg');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: msg,
      );
    } on TimeoutException {
      _log('iOS/Web signInWithPhoneNumber timed out after 60s');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Firebase error: [timeout] Request timed out after 60s.',
      );
    } catch (e, stack) {
      final msg = 'Firebase error: [unknown] ${e.runtimeType}: $e';
      _logError(e, stack, 'signInWithPhoneNumber unknown: $msg');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: msg,
      );
    }
  }

  // ── Android: verifyPhoneNumber (native SMS / GMS auto-retrieval) ─────────
  Future<PhoneAuthResult> _androidVerify(String phoneNumber) async {
    _log('Android: calling verifyPhoneNumber');
    final completer = Completer<PhoneAuthResult>();

    // 45-second safety net in case no callback fires
    final timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (!completer.isCompleted) {
        _log('Android: timeout — completing with codeSent');
        completer.complete(PhoneAuthResult(
          status: PhoneAuthStatus.codeSent,
          verificationId: _verificationId ?? '',
          errorMessage: 'SMS may be delayed. Enter the code when it arrives.',
        ));
      }
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 30),
        forceResendingToken: _resendToken,

        // Auto sign-in when the device intercepts the SMS
        verificationCompleted: (PhoneAuthCredential credential) async {
          _log('Android: verificationCompleted (auto-retrieval)');
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
                errorMessage:
                    'Auto-verification failed. Please enter the code manually.',
              ));
            }
          }
        },

        verificationFailed: (FirebaseAuthException e) {
          _logError(e, StackTrace.current,
              'Android verifyPhoneNumber failed: ${e.code} — ${e.message}');
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
          _log('Android: codeSent, verificationId=$verificationId');
          if (!completer.isCompleted) {
            completer.complete(PhoneAuthResult(
              status: PhoneAuthStatus.codeSent,
              verificationId: verificationId,
            ));
          }
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          _log('Android: codeAutoRetrievalTimeout');
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
          errorMessage: 'Could not send verification code. Please try again.',
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
    _log('verifySmsCode: smsCode.length=${smsCode.length}, '
        'platform=${kIsWeb ? "web" : defaultTargetPlatform.name}');

    try {
      // iOS + Web: confirm via ConfirmationResult from signInWithPhoneNumber
      if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
        if (_confirmationResult == null) {
          _log('verifySmsCode: _confirmationResult is null — send step failed');
          return AuthResult.failure(
              'DEBUG: No confirmation result stored. The send-code step failed — check the error shown on the previous screen.');
        }
        _log('verifySmsCode: confirming with ConfirmationResult');
        final userCred = await _confirmationResult!.confirm(smsCode);
        if (userCred.additionalUserInfo?.isNewUser ?? false) {
          await _createUserProfile(userCred.user!.uid);
        }
        _log('verifySmsCode: success (iOS/Web), uid=${userCred.user?.uid}');
        return AuthResult.success(userCred.user);
      }

      // Android: build credential from verificationId + smsCode
      final vId = verificationId ?? _verificationId;
      if (vId == null || vId.isEmpty) {
        _log('verifySmsCode: no verificationId available on Android');
        return AuthResult.failure(
            'Verification session expired. Please go back and request a new code.');
      }

      _log('verifySmsCode: building PhoneAuthCredential, verificationId=$vId');
      final credential = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: smsCode,
      );
      final userCred = await _auth.signInWithCredential(credential);
      if (userCred.additionalUserInfo?.isNewUser ?? false) {
        await _createUserProfile(userCred.user!.uid);
      }
      _log('verifySmsCode: success (Android), uid=${userCred.user?.uid}');
      return AuthResult.success(userCred.user);
    } on FirebaseAuthException catch (e) {
      _log('verifySmsCode FirebaseAuthException: ${e.code}');
      return AuthResult.failure(_mapAuthError(e.code));
    } catch (e, stack) {
      _logError(e, stack, 'verifySmsCode catch');
      return AuthResult.failure('Verification failed. Please try again.');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SESSION
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> signOut() async {
    await _auth.signOut();
    _confirmationResult = null;
    _verificationId = null;
    _resendToken = null;
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
