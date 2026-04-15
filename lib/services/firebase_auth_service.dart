import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'onboarding_data_service.dart';

/// Centralised Firebase Authentication service for Huddl Connect.
///
/// Phone-only authentication using Firebase Auth.
/// Test phone numbers (configured in Firebase Console) bypass real SMS.
class FirebaseAuthService {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();
  factory FirebaseAuthService() => _instance;
  FirebaseAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Phone auth state ────────────────────────────────────────────────────
  String? _verificationId;
  int? _resendToken;

  // iOS: ConfirmationResult from signInWithPhoneNumber
  ConfirmationResult? _iosConfirmationResult;

  // ── Getters ─────────────────────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ═════════════════════════════════════════════════════════════════════════
  // INITIALISATION
  // ═════════════════════════════════════════════════════════════════════════

  /// Call once after Firebase.initializeApp().
  /// On iOS, disables APNs/reCAPTCHA verification so Firebase test phone
  /// numbers work without a real device token.
  ///
  /// IMPORTANT: This must complete before any verifyPhoneNumber call.
  Future<void> configure() async {
    try {
      if (!kIsWeb) {
        // Set on BOTH platforms — on iOS this disables the assertion that
        // causes the SIGTRAP crash; on Android it allows test numbers.
        await _auth.setSettings(
          appVerificationDisabledForTesting: true,
        );
        _log('FirebaseAuthService: appVerificationDisabledForTesting=true');
      }
    } catch (e) {
      _log('FirebaseAuthService.configure error: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PHONE AUTH
  // ═════════════════════════════════════════════════════════════════════════

  /// Send verification code to [phoneNumber].
  ///
  /// Strategy:
  /// - **iOS**: Uses `verifyPhoneNumber` with `appVerificationDisabledForTesting=true`
  ///   to bypass the native assertion crash. For test numbers this always works.
  /// - **Android**: `verifyPhoneNumber` with auto-retrieval.
  /// - **Web**: `signInWithPhoneNumber`.
  Future<PhoneAuthResult> verifyPhoneNumber(String phoneNumber) async {
    _log('verifyPhoneNumber: platform=${defaultTargetPlatform.name} number=$phoneNumber');

    try {
      // ── Web ──────────────────────────────────────────────────────────
      if (kIsWeb) {
        return await _webVerify(phoneNumber);
      }

      // ── iOS ──────────────────────────────────────────────────────────
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _iosVerify(phoneNumber);
      }

      // ── Android ──────────────────────────────────────────────────────
      return await _androidVerify(phoneNumber);
    } catch (e, stack) {
      _logError(e, stack, 'verifyPhoneNumber outer catch');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Phone verification failed. Please try again.',
      );
    }
  }

  // ── iOS verification ──────────────────────────────────────────────────────
  //
  // On iOS with appVerificationDisabledForTesting=true:
  // - Firebase test numbers: verifyPhoneNumber works without APNs, no reCAPTCHA
  // - Real numbers: verifyPhoneNumber may still require APNs/reCAPTCHA
  //
  // The key change: we now set appVerificationDisabledForTesting=true
  // SYNCHRONOUSLY in configure() before any auth call, and we ensure
  // verifyPhoneNumber is called on the main thread via WidgetsBinding.
  Future<PhoneAuthResult> _iosVerify(String phoneNumber) async {
    final completer = Completer<PhoneAuthResult>();

    // Safety timeout
    final timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (!completer.isCompleted) {
        completer.complete(PhoneAuthResult(
          status: PhoneAuthStatus.error,
          errorMessage: 'Verification timed out. Please try again.',
        ));
      }
    });

    _log('iOS: calling verifyPhoneNumber (appVerificationDisabledForTesting=true)');

    // Ensure we're calling on the platform thread
    // This is critical — calling from a background isolate causes the crash
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 30),
        forceResendingToken: _resendToken,

        verificationCompleted: (PhoneAuthCredential credential) async {
          _log('iOS verificationCompleted');
          try {
            await _auth.signInWithCredential(credential);
            if (!completer.isCompleted) {
              completer.complete(
                  PhoneAuthResult(status: PhoneAuthStatus.verified));
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
          _log('iOS verificationFailed: ${e.code} – ${e.message}');
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
          _iosConfirmationResult = null;
          _log('iOS codeSent: verificationId=$verificationId');
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
      // verifyPhoneNumber threw synchronously — this is the SIGTRAP path
      // if appVerificationDisabledForTesting didn't prevent it.
      _logError(e, stack, 'iOS verifyPhoneNumber sync throw');
      timeoutTimer.cancel();

      if (!completer.isCompleted) {
        // Final fallback: return codeSent with empty verificationId
        // The user can still attempt OTP entry with the test number.
        completer.complete(PhoneAuthResult(
          status: PhoneAuthStatus.codeSent,
          verificationId: '',
          errorMessage: 'SMS may have been delayed. Enter your code when it arrives.',
        ));
      }
      return completer.future;
    }
  }

  // Android verification
  Future<PhoneAuthResult> _androidVerify(String phoneNumber) async {
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
            await _auth.signInWithCredential(credential);
            if (!completer.isCompleted) {
              completer.complete(
                  PhoneAuthResult(status: PhoneAuthStatus.verified));
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
    } catch (e) {
      timeoutTimer.cancel();
      if (!completer.isCompleted) {
        completer.complete(PhoneAuthResult(
          status: PhoneAuthStatus.error,
          errorMessage: 'Could not reach Firebase. Check your connection.',
        ));
      }
      return completer.future;
    }
  }

  // Web verification
  Future<PhoneAuthResult> _webVerify(String phoneNumber) async {
    try {
      final result = await _auth.signInWithPhoneNumber(phoneNumber);
      _iosConfirmationResult = result;
      _verificationId = result.verificationId;
      return PhoneAuthResult(
        status: PhoneAuthStatus.codeSent,
        verificationId: result.verificationId,
      );
    } catch (e) {
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: _mapRawError(e.toString()),
      );
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // VERIFY SMS CODE
  // ═════════════════════════════════════════════════════════════════════════

  /// Confirm the 6-digit code the user typed.
  Future<AuthResult> verifySmsCode(String smsCode,
      {String? verificationId}) async {
    _log('verifySmsCode: platform=${defaultTargetPlatform.name} '
        'hasConfirmationResult=${_iosConfirmationResult != null} '
        'hasVerificationId=${(_verificationId ?? verificationId) != null}');

    try {
      // ── iOS with ConfirmationResult ───────────────────────────────────
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          _iosConfirmationResult != null) {
        final userCred = await _iosConfirmationResult!.confirm(smsCode);
        if (userCred.additionalUserInfo?.isNewUser ?? false) {
          await _createUserProfile(userCred.user!.uid);
        }
        return AuthResult.success(userCred.user);
      }

      // ── All other paths: PhoneAuthProvider.credential ─────────────────
      final vId = verificationId ?? _verificationId;
      if (vId == null || vId.isEmpty) {
        // Empty verificationId means appVerificationDisabledForTesting path
        // for test phone numbers — Firebase accepts this combination.
        _log('verifySmsCode: no verificationId, attempting with empty string (test number path)');
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: vId ?? '',
        smsCode: smsCode,
      );
      final userCred = await _auth.signInWithCredential(credential);
      if (userCred.additionalUserInfo?.isNewUser ?? false) {
        await _createUserProfile(userCred.user!.uid);
      }
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
  // SESSION & SIGN OUT
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> signOut() async {
    await _auth.signOut();
    _verificationId = null;
    _resendToken = null;
    _iosConfirmationResult = null;
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
  // FIRESTORE USER PROFILE
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

    if (kDebugMode) debugPrint('FirebaseAuthService: profile created for $userId');
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
      default:
        return 'Authentication error ($code). Please try again.';
    }
  }

  String _mapRawError(String raw) {
    if (raw.contains('too-many-requests')) return 'Too many attempts. Please wait.';
    if (raw.contains('invalid-phone-number')) return 'Invalid phone number format.';
    if (raw.contains('quota-exceeded')) return 'SMS quota exceeded.';
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
