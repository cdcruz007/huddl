import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'onboarding_data_service.dart';

/// Centralised Firebase Authentication service for Huddl Connect.
///
/// Supports:
///   - Email/password sign-up & sign-in (primary for web)
///   - Phone (SMS OTP) sign-in (primary for mobile)
///   - User profile creation in Firestore on first sign-up
///   - Session persistence across app restarts
///   - Password reset via email
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
  // ── Getters ─────────────────────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ═════════════════════════════════════════════════════════════════════════
  // EMAIL / PASSWORD AUTH
  // ═════════════════════════════════════════════════════════════════════════

  /// Register a new user with email + password and create their Firestore
  /// profile from the onboarding data collected so far.
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return AuthResult.failure('Account creation failed. Please try again.');
      }

      // Create Firestore user profile
      await _createUserProfile(user.uid);

      return AuthResult.success(user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e.code));
    } catch (e) {
      return AuthResult.failure('An unexpected error occurred: $e');
    }
  }

  /// Sign in with email + password.
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return AuthResult.success(credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e.code));
    } catch (e) {
      return AuthResult.failure('An unexpected error occurred: $e');
    }
  }

  /// Send password-reset email.
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return AuthResult.success(null,
          message: 'Password reset email sent. Check your inbox.');
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e.code));
    } catch (e) {
      return AuthResult.failure('Failed to send reset email: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PHONE (SMS OTP) AUTH
  // ═════════════════════════════════════════════════════════════════════════

  /// Initiate phone number verification — Firebase sends SMS to the number.
  ///
  /// On **web**: returns immediately with a [ConfirmationResult] via
  /// `signInWithPhoneNumber`. The caller should prompt for the OTP and
  /// then call [verifySmsCode].
  ///
  /// On **Android/iOS**: Firebase may auto-retrieve the code. Callbacks
  /// handle verification completed / failed / code sent.
  Future<PhoneAuthResult> verifyPhoneNumber(String phoneNumber) async {
    try {
      // ── Web platform ─────────────────────────────────────────────────
      if (kIsWeb) {
        final confirmationResult =
            await _auth.signInWithPhoneNumber(phoneNumber);
        _verificationId = confirmationResult.verificationId;
        return PhoneAuthResult(
          status: PhoneAuthStatus.codeSent,
          verificationId: confirmationResult.verificationId,
        );
      }

      // ── Mobile platform ──────────────────────────────────────────────
      final completer = Completer<PhoneAuthResult>();

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
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
  Future<AuthResult> verifySmsCode(String smsCode,
      {String? verificationId}) async {
    try {
      final vId = verificationId ?? _verificationId;

      if (kIsWeb) {
        // On web, use stored verificationId with credential
        if (vId == null) {
          return AuthResult.failure(
              'Verification session expired. Please request a new code.');
        }
        final credential = PhoneAuthProvider.credential(
          verificationId: vId,
          smsCode: smsCode,
        );
        final userCredential =
            await _auth.signInWithCredential(credential);

        // Create profile if first time
        if (userCredential.additionalUserInfo?.isNewUser ?? false) {
          await _createUserProfile(userCredential.user!.uid);
        }

        return AuthResult.success(userCredential.user);
      }

      // Mobile path
      if (vId == null) {
        return AuthResult.failure(
            'Verification session expired. Please request a new code.');
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: smsCode,
      );
      final userCredential =
          await _auth.signInWithCredential(credential);

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
  // COMBINED: EMAIL + PHONE LINK
  // ═════════════════════════════════════════════════════════════════════════

  /// After email sign-up and phone verification, link the phone credential
  /// to the existing email account so the user has both auth methods.
  Future<AuthResult> linkPhoneToCurrentUser(String smsCode,
      {String? verificationId}) async {
    try {
      final vId = verificationId ?? _verificationId;
      if (vId == null || currentUser == null) {
        return AuthResult.failure('No active session to link phone to.');
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: smsCode,
      );
      await currentUser!.linkWithCredential(credential);
      return AuthResult.success(currentUser);
    } on FirebaseAuthException catch (e) {
      // If already linked, treat as success
      if (e.code == 'credential-already-in-use' ||
          e.code == 'provider-already-linked') {
        return AuthResult.success(currentUser);
      }
      return AuthResult.failure(_mapAuthError(e.code));
    } catch (e) {
      return AuthResult.failure('Phone linking failed: $e');
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
      'email': _auth.currentUser?.email ?? '',
      'phone': onboarding.fullPhoneNumber ?? _auth.currentUser?.phoneNumber ?? '',
      'countryCode': onboarding.countryCode ?? '+44',
      'parentType': onboarding.parentType ?? '',
      'stagesOfLife': onboarding.stagesOfLife,
      'postcode': onboarding.postcode ?? '',
      'borough': '', // Resolved later from postcode
      'children': onboarding.children,
      'bio': onboarding.bio ?? '',
      'photoUrl': '',
      'tier': 'explorer',
      'isFoundingMember': false,
      'isPhoneVerified': true,
      'isProvider': onboarding.isProvider,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
      'assignedGroupCount': 0,
      'assignedGroupNames': [],
      'fcmToken': '',
      'notificationsEnabled': true,
    };

    // Provider-specific fields
    if (onboarding.isProvider) {
      profile.addAll({
        'serviceTypes': onboarding.serviceTypes,
        'businessName': onboarding.businessName ?? '',
        'qualifications': onboarding.qualifications ?? '',
        'hasDBS': onboarding.hasDBS,
        'experience': onboarding.experience ?? '',
        'hourlyRate': onboarding.hourlyRate ?? '',
        'serviceAreas': onboarding.serviceAreas,
      });
    }

    await _db.collection('users').doc(userId).set(profile, SetOptions(merge: true));

    // Also create a default Explorer subscription
    await _db.collection('subscriptions').add({
      'userId': userId,
      'tier': 'explorer',
      'billingPeriod': 'monthly',
      'status': 'active',
      'platform': kIsWeb ? 'web' : 'android',
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
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled. Please contact support.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters with upper, lower and digit.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
        return 'No account found with these credentials.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Incorrect phone number or password. Please try again.';
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
