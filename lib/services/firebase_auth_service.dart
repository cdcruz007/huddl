import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'onboarding_data_service.dart';

/// Centralised Firebase Authentication service for Huddl Connect.
///
/// Supports:
///   - Phone (SMS OTP) sign-in (primary auth method)
///   - User profile creation in Firestore on first sign-up
///   - Session persistence across app restarts
///
/// Huddl Connect uses **phone-only** authentication. Users register and
/// log in exclusively via their UK mobile number (+44) and a 6-digit
/// SMS OTP code. There is NO email/password auth.
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

  // ── iOS: ConfirmationResult from signInWithPhoneNumber ───────────────────
  // On iOS we use signInWithPhoneNumber (same as web API) to avoid the
  // internal assertionFailure crash that verifyPhoneNumber triggers when
  // APNs / reCAPTCHA isn't fully initialised.
  ConfirmationResult? _iosConfirmationResult;

  // ── Getters ─────────────────────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ═════════════════════════════════════════════════════════════════════════
  // PHONE (SMS OTP) AUTH
  // ═════════════════════════════════════════════════════════════════════════

  /// Initiate phone number verification — Firebase sends SMS to the number.
  ///
  /// ### Platform strategy
  /// | Platform | Method used | Why |
  /// |----------|-------------|-----|
  /// | Web      | `signInWithPhoneNumber` | Only available API on web |
  /// | iOS      | `signInWithPhoneNumber` | Avoids internal assertionFailure crash in `verifyPhoneNumber` when APNs/reCAPTCHA isn't ready |
  /// | Android  | `verifyPhoneNumber` | Supports auto-retrieval (SMS listener) |
  ///
  /// Firebase test phone numbers (e.g. +44 7700 900000 with code 123456)
  /// work on all platforms without real SMS.
  Future<PhoneAuthResult> verifyPhoneNumber(String phoneNumber) async {
    try {
      // ── Web + iOS: use signInWithPhoneNumber ──────────────────────────
      // On iOS, verifyPhoneNumber internally calls assertionFailure() if
      // APNs / reCAPTCHA is not yet initialised. signInWithPhoneNumber
      // uses the web-style reCAPTCHA flow which is stable on iOS.
      if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final confirmationResult =
              await _auth.signInWithPhoneNumber(phoneNumber);
          _verificationId = confirmationResult.verificationId;
          _iosConfirmationResult = confirmationResult;
          return PhoneAuthResult(
            status: PhoneAuthStatus.codeSent,
            verificationId: confirmationResult.verificationId,
          );
        } catch (e) {
          final msg = e.toString();
          if (kDebugMode) debugPrint('FirebaseAuthService iOS/Web error: $e');
          return PhoneAuthResult(
            status: PhoneAuthStatus.error,
            errorMessage: _mapRawError(msg),
          );
        }
      }

      // ── Android: use verifyPhoneNumber (supports auto-retrieval) ──────
      final completer = Completer<PhoneAuthResult>();

      // Safety timeout — completes with error if Firebase never responds
      Future.delayed(const Duration(seconds: 45), () {
        if (!completer.isCompleted) {
          completer.complete(PhoneAuthResult(
            status: PhoneAuthStatus.error,
            errorMessage: 'Verification timed out. Please try again.',
          ));
        }
      });

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 30),
        forceResendingToken: _resendToken,

        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-retrieval (Android only) — sign in directly
          try {
            await _auth.signInWithCredential(credential);
            if (!completer.isCompleted) {
              completer.complete(PhoneAuthResult(
                status: PhoneAuthStatus.verified,
              ));
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.complete(PhoneAuthResult(
                status: PhoneAuthStatus.error,
                errorMessage: 'Auto-verification failed: $e',
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

      return completer.future;
    } catch (e) {
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Phone verification failed: $e',
      );
    }
  }

  /// Verify the 6-digit SMS code entered by the user.
  ///
  /// On iOS, uses the [ConfirmationResult] from [signInWithPhoneNumber].
  /// On Android/Web, uses [PhoneAuthProvider.credential].
  Future<AuthResult> verifySmsCode(String smsCode,
      {String? verificationId}) async {
    try {
      // ── iOS path: confirm via ConfirmationResult ──────────────────────
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        if (_iosConfirmationResult != null) {
          try {
            final userCredential =
                await _iosConfirmationResult!.confirm(smsCode);
            if (userCredential.additionalUserInfo?.isNewUser ?? false) {
              await _createUserProfile(userCredential.user!.uid);
            }
            return AuthResult.success(userCredential.user);
          } on FirebaseAuthException catch (e) {
            return AuthResult.failure(_mapAuthError(e.code));
          } catch (e) {
            return AuthResult.failure('Verification failed: $e');
          }
        }
        // Fallback: use verificationId if ConfirmationResult not available
      }

      // ── Android / Web / fallback path ─────────────────────────────────
      final vId = verificationId ?? _verificationId;

      if (vId == null || vId.isEmpty) {
        return AuthResult.failure(
            'Verification session expired. Please request a new code.');
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);

      // Create profile if first time
      if (userCredential.additionalUserInfo?.isNewUser ?? false) {
        await _createUserProfile(userCredential.user!.uid);
      }

      return AuthResult.success(userCredential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e.code));
    } catch (e) {
      return AuthResult.failure('Verification failed: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SESSION & SIGN OUT
  // ═════════════════════════════════════════════════════════════════════════

  /// Sign out and clear local state.
  Future<void> signOut() async {
    await _auth.signOut();
    _verificationId = null;
    _resendToken = null;
    _iosConfirmationResult = null;
  }

  /// Check if user has a Firestore profile already.
  Future<bool> hasUserProfile() async {
    if (uid == null) return false;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists;
  }

  /// Get the current user's Firestore profile.
  Future<Map<String, dynamic>?> getUserProfile() async {
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // FIRESTORE USER PROFILE
  // ═════════════════════════════════════════════════════════════════════════

  /// Create a Firestore user profile from the onboarding data.
  Future<void> _createUserProfile(String userId) async {
    final onboarding = OnboardingDataService();
    await onboarding.initialize();

    final Map<String, dynamic> profile = {
      'uid': userId,
      'name': onboarding.name ?? '',
      'firstName': onboarding.name?.split(' ').first ?? '',
      'lastName': onboarding.name?.split(' ').length != null &&
              (onboarding.name?.split(' ').length ?? 0) > 1
          ? onboarding.name!.split(' ').sublist(1).join(' ')
          : '',
      'phone': onboarding.fullPhoneNumber ?? _auth.currentUser?.phoneNumber ?? '',
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

    await _db.collection('users').doc(userId).set(profile, SetOptions(merge: true));

    await _db.collection('subscriptions').add({
      'userId': userId,
      'tier': 'explorer',
      'billingPeriod': 'monthly',
      'status': 'active',
      'platform': kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
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
      debugPrint('FirebaseAuthService: User profile created for $userId');
    }
  }

  /// Update the last active timestamp.
  Future<void> updateLastActive() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ERROR MAPPING
  // ═════════════════════════════════════════════════════════════════════════

  String _mapAuthError(String code) {
    switch (code) {
      case 'operation-not-allowed':
        return 'Phone sign-in is not enabled. Please contact support.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
        return 'No account found with this phone number.';
      case 'invalid-credential':
        return 'Invalid credentials. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'invalid-verification-code':
        return 'Incorrect code. Please check and try again.';
      case 'invalid-verification-id':
        return 'Verification session expired. Please request a new code.';
      case 'session-expired':
        return 'Verification session expired. Please request a new code.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'missing-phone-number':
        return 'Please enter a valid phone number.';
      case 'invalid-phone-number':
        return 'Invalid phone number format. Use +44 followed by your number.';
      case 'credential-already-in-use':
        return 'This phone number is already linked to another account.';
      case 'web-context-cancelled':
        return 'Verification was cancelled. Please try again.';
      case 'web-context-already-presented':
        return 'A verification is already in progress. Please wait.';
      default:
        return 'Authentication error ($code). Please try again.';
    }
  }

  String _mapRawError(String raw) {
    if (raw.contains('too-many-requests') || raw.contains('TOO_LONG')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (raw.contains('invalid-phone-number') || raw.contains('INVALID_PHONE_NUMBER')) {
      return 'Invalid phone number format. Use +44 followed by your number.';
    }
    if (raw.contains('quota-exceeded')) {
      return 'SMS quota exceeded. Please try again later.';
    }
    if (raw.contains('network-request-failed')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (raw.contains('web-context-cancelled')) {
      return 'Verification was cancelled. Please try again.';
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

  factory AuthResult.success(User? user, {String? message}) => AuthResult._(
        isSuccess: true,
        user: user,
        message: message,
      );

  factory AuthResult.failure(String error) => AuthResult._(
        isSuccess: false,
        errorMessage: error,
      );
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
