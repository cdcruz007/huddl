import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'onboarding_data_service.dart';

/// Centralised Firebase Authentication service for Huddl Connect.
///
/// Platform strategy:
///   iOS + Android → verifyPhoneNumber  (native SMS path via Firebase iOS SDK 10.x)
///                   Works correctly with firebase_auth 5.1.0 / Firebase iOS SDK 10.27.0.
///                   The assertionFailure crash only exists in FirebaseAuth 11.x
///                   (firebase_auth >=5.2.0). By pinning to 5.1.0 the crash is gone.
///   Web           → signInWithPhoneNumber (browser reCAPTCHA — the only web API)
class FirebaseAuthService {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();
  factory FirebaseAuthService() => _instance;
  FirebaseAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Phone auth state ─────────────────────────────────────────────────────
  // iOS + Android: verifyPhoneNumber stores verificationId + resendToken
  String? _verificationId;
  int? _resendToken;
  // Web only: signInWithPhoneNumber stores ConfirmationResult
  ConfirmationResult? _webConfirmationResult;

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
    _log('verifyPhoneNumber: platform=${kIsWeb ? "web" : defaultTargetPlatform.name}, '
        'number=$phoneNumber');
    try {
      if (kIsWeb) return await _webVerify(phoneNumber);
      return await _nativeVerify(phoneNumber);
    } catch (e, stack) {
      _logError(e, stack, 'verifyPhoneNumber outer catch');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Phone verification failed. Please try again.',
      );
    }
  }

  // ── iOS + Android: verifyPhoneNumber ─────────────────────────────────────
  //
  // Uses Firebase iOS SDK 10.27.0 (via firebase_auth 5.1.0 + firebase_core 3.1.0).
  // FirebaseAuth 10.x does NOT contain the assertionFailure that crashes on iOS 18.
  // appVerificationDisabledForTesting=true (set in main.dart after initializeApp)
  // makes Firebase skip APNs/reCAPTCHA for registered test numbers.
  Future<PhoneAuthResult> _nativeVerify(String phoneNumber) async {
    _log('Native: calling verifyPhoneNumber for $phoneNumber');
    final completer = Completer<PhoneAuthResult>();

    final timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (!completer.isCompleted) {
        _log('Native: timeout — completing with stored verificationId');
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

        verificationCompleted: (PhoneAuthCredential credential) async {
          _log('Native: verificationCompleted (Android auto-retrieval)');
          try {
            final userCred = await _auth.signInWithCredential(credential);
            if (userCred.additionalUserInfo?.isNewUser ?? false) {
              await _createUserProfile(userCred.user!.uid);
            }
            if (!completer.isCompleted) {
              completer.complete(
                  PhoneAuthResult(status: PhoneAuthStatus.verified));
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
              'Native verifyPhoneNumber failed: ${e.code} — ${e.message}');
          if (!completer.isCompleted) {
            // Pass BOTH the raw code and mapped message so UI can display
            // the exact Firebase error code for diagnosis
            completer.complete(PhoneAuthResult(
              status: PhoneAuthStatus.error,
              rawErrorCode: e.code,
              rawErrorMessage: e.message,
              errorMessage: _mapAuthError(e.code),
            ));
          }
        },

        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _log('Native: codeSent, verificationId=$verificationId');
          if (!completer.isCompleted) {
            completer.complete(PhoneAuthResult(
              status: PhoneAuthStatus.codeSent,
              verificationId: verificationId,
            ));
          }
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          _log('Native: codeAutoRetrievalTimeout');
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
      _logError(e, stack, 'Native verifyPhoneNumber outer catch');
      if (!completer.isCompleted) {
        completer.complete(PhoneAuthResult(
          status: PhoneAuthStatus.error,
          errorMessage: 'Could not send verification code. Please try again.',
        ));
      }
      return completer.future;
    }
  }

  // ── Web: signInWithPhoneNumber (browser reCAPTCHA) ───────────────────────
  Future<PhoneAuthResult> _webVerify(String phoneNumber) async {
    _log('Web: calling signInWithPhoneNumber');
    try {
      final result = await _auth.signInWithPhoneNumber(phoneNumber);
      _webConfirmationResult = result;
      _verificationId = result.verificationId;
      _log('Web: codeSent, verificationId stored');
      return PhoneAuthResult(
        status: PhoneAuthStatus.codeSent,
        verificationId: result.verificationId,
      );
    } on FirebaseAuthException catch (e) {
      _logError(e, StackTrace.current,
          'Web signInWithPhoneNumber failed: ${e.code}');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: _mapAuthError(e.code),
      );
    } catch (e, stack) {
      _logError(e, stack, 'Web signInWithPhoneNumber unknown error');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Could not send verification code. Please try again.',
      );
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PHONE AUTH — VERIFY OTP
  // ═════════════════════════════════════════════════════════════════════════

  Future<AuthResult> verifySmsCode(String smsCode,
      {String? verificationId}) async {
    _log('verifySmsCode: platform=${kIsWeb ? "web" : defaultTargetPlatform.name}');

    try {
      // Web: confirm via ConfirmationResult
      if (kIsWeb) {
        if (_webConfirmationResult == null) {
          return AuthResult.failure(
              'Verification session expired. Please go back and request a new code.');
        }
        final userCred = await _webConfirmationResult!.confirm(smsCode);
        if (userCred.additionalUserInfo?.isNewUser ?? false) {
          await _createUserProfile(userCred.user!.uid);
        }
        return AuthResult.success(userCred.user);
      }

      // iOS + Android: PhoneAuthCredential from verificationId + smsCode
      final vId = verificationId ?? _verificationId;
      if (vId == null || vId.isEmpty) {
        _log('verifySmsCode: no verificationId — send step may have failed');
        return AuthResult.failure(
            'Verification session expired. Please go back and request a new code.');
      }

      _log('verifySmsCode: signing in with credential, verificationId=$vId');
      final credential = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: smsCode,
      );
      final userCred = await _auth.signInWithCredential(credential);
      if (userCred.additionalUserInfo?.isNewUser ?? false) {
        await _createUserProfile(userCred.user!.uid);
      }
      _log('verifySmsCode: success, uid=${userCred.user?.uid}');
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
    _verificationId = null;
    _resendToken = null;
    _webConfirmationResult = null;
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
  // Raw Firebase error code and message — passed through for on-screen diagnosis
  final String? rawErrorCode;
  final String? rawErrorMessage;

  PhoneAuthResult({
    required this.status,
    this.verificationId,
    this.errorMessage,
    this.rawErrorCode,
    this.rawErrorMessage,
  });
}
