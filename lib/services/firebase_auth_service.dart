import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'clearable_user_state.dart';
import 'onboarding_data_service.dart';
import 'huddl_user_service.dart';
import 'postcode_service.dart';
import 'subscription_service.dart';
import 'backend_api_service.dart';
import '../models/subscription.dart';

/// Centralised Firebase Authentication service for Huddl.
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

  // ── Session flag key ─────────────────────────────────────────────────────
  // Written on explicit logout. Splash screen checks this: if the user
  // deliberately logged out, they must go through /login again even though
  // the Firebase Auth Keychain token is still valid (iOS persists tokens
  // across reinstalls). Cleared on successful OTP verification.
  static const String _loggedOutKey = 'huddl_user_logged_out';

  // ── Getters ──────────────────────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;

  /// True if the user has explicitly logged out since the last sign-in.
  /// Checked by the splash screen to force /login even when a Keychain
  /// token is still present.
  static Future<bool> get hasExplicitlyLoggedOut async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_loggedOutKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Clear the explicit logout flag after a successful login.
  static Future<void> clearLoggedOutFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_loggedOutKey);
    } catch (_) {}
  }
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

  /// Direct sign-in for Firebase Console test phone numbers ONLY.
  ///
  /// For test numbers (e.g. +447575888453 / OTP 123456), Firebase's
  /// verifyPhoneNumber fires BOTH codeSent AND verificationCompleted.
  /// Whichever completes the Completer first wins — on many devices codeSent
  /// fires first, routing the app to the OTP screen instead of auto-verifying.
  ///
  /// This method completely bypasses verifyPhoneNumber by calling
  /// verifyPhoneNumber internally just to obtain a verificationId, then
  /// immediately signing in with the known test OTP — no race condition.
  ///
  /// MUST only be called for numbers in [_firebaseTestPhoneNumbers].
  Future<PhoneAuthResult> loginWithTestCredential(String phoneNumber) async {
    _log('loginWithTestCredential: $phoneNumber');
    try {
      // ── FAST PATH: Direct sign-in without verifyPhoneNumber callbacks ────
      //
      // The old approach called verifyPhoneNumber() and waited up to 35 s for
      // codeSent / verificationCompleted callbacks.  Firebase Test Lab's
      // UiAutomator has a 1-second "window update" watchdog: if the UI does
      // not change within 1 s after a tap it reports "Outside of app" and
      // aborts the Robo test — even though _isLoading=true is already set and
      // the screen rebuilds immediately.  The 30+ second wait for callbacks
      // reliably triggers that watchdog.
      //
      // Fix: use a two-stage approach that resolves in < 5 seconds:
      //   1. Call verifyPhoneNumber with a very short timeout (5 s) so
      //      codeSent fires quickly (it fires in < 1 s for test numbers).
      //   2. Once we have a verificationId, immediately sign in with the
      //      known OTP code — no further waiting needed.
      //
      // If we already have a cached verificationId from a previous call reuse
      // it directly, skipping verifyPhoneNumber entirely.

      String? effectiveVId = _verificationId;

      if (effectiveVId == null || effectiveVId.isEmpty) {
        // Step 1: get a verificationId as fast as possible.
        final idCompleter = Completer<String?>();

        // Fire-and-forget — we only need codeSent to resolve the completer.
        unawaited(_auth.verifyPhoneNumber(
          phoneNumber: phoneNumber,
          timeout: const Duration(seconds: 5), // short — test numbers respond fast
          verificationCompleted: (PhoneAuthCredential cred) async {
            // Auto-verified path: sign in directly and complete with null
            // so the caller knows it doesn't need the vId route.
            _log('loginWithTestCredential: verificationCompleted fired');
            try {
              await _auth.signInWithCredential(cred);
            } catch (_) {}
            if (!idCompleter.isCompleted) idCompleter.complete(null);
          },
          verificationFailed: (FirebaseAuthException e) {
            _log('loginWithTestCredential: verificationFailed ${e.code}');
            if (!idCompleter.isCompleted) idCompleter.complete(null);
          },
          codeSent: (String verificationId, int? resendToken) {
            _verificationId = verificationId;
            _log('loginWithTestCredential: codeSent vId=$verificationId');
            if (!idCompleter.isCompleted) idCompleter.complete(verificationId);
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            _verificationId = verificationId;
            if (!idCompleter.isCompleted) idCompleter.complete(verificationId);
          },
        ).catchError((_) {
          if (!idCompleter.isCompleted) idCompleter.complete(null);
        }));

        // Wait up to 10 s for the first callback.
        effectiveVId = await idCompleter.future
            .timeout(const Duration(seconds: 10), onTimeout: () => _verificationId);
      }

      // If verificationCompleted auto-signed us in, we're done.
      if (_auth.currentUser != null) {
        _log('loginWithTestCredential: already signed in, uid=${_auth.currentUser?.uid}');
        await clearLoggedOutFlag();
        return PhoneAuthResult(status: PhoneAuthStatus.verified);
      }

      if (effectiveVId == null || effectiveVId.isEmpty) {
        _log('loginWithTestCredential: no verificationId obtained');
        return PhoneAuthResult(
          status: PhoneAuthStatus.error,
          errorMessage: 'Could not obtain verification session. Please try again.',
        );
      }

      // Step 2: sign in immediately with the known test OTP.
      _log('loginWithTestCredential: signing in with vId + OTP 123456');
      final credential = PhoneAuthProvider.credential(
        verificationId: effectiveVId,
        smsCode: '123456',
      );
      await _auth.signInWithCredential(credential);
      _log('loginWithTestCredential: success, uid=${_auth.currentUser?.uid}');
      await clearLoggedOutFlag();
      return PhoneAuthResult(status: PhoneAuthStatus.verified);
    } catch (e, stack) {
      _logError(e, stack, 'loginWithTestCredential');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Test login failed: $e',
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
            final phone = userCred.user?.phoneNumber ?? '';
            final compactPhone = phone.replaceAll(' ', '');

            // ── Test-number fast path ─────────────────────────────────────
            // Firebase Console test numbers (e.g. +447575888453) are real
            // Firebase Auth entries but have NO Firestore `users` document.
            // Calling hasUserProfile() for them always returns false, which
            // causes an immediate sign-out and "account deleted" error —
            // blocking Firebase Test Lab Robo runs.
            //
            // For test numbers we skip the profile check entirely and return
            // verified. The OTP screen or the post-login handler will handle
            // any missing profile gracefully.
            if (_firebaseTestPhoneNumbers.contains(compactPhone)) {
              _log('verificationCompleted: test number $compactPhone — skipping profile check');
              if (!completer.isCompleted) {
                completer.complete(
                    PhoneAuthResult(status: PhoneAuthStatus.verified));
              }
              return;
            }
            // ─────────────────────────────────────────────────────────────

            if (userCred.additionalUserInfo?.isNewUser ?? false) {
              final profileCreated = await _createUserProfile(userCred.user!.uid);
              if (!profileCreated) {
                // PROFILE-COMMIT-1: Auth created but profile write failed.
                if (!completer.isCompleted) {
                  completer.complete(PhoneAuthResult(
                    status: PhoneAuthStatus.error,
                    errorMessage: 'We created your account but couldn\'t finish '
                        'setting up your profile. Please check your connection '
                        'and try again.',
                  ));
                }
                return;
              }
            } else {
              // Auto-retrieved returning user — check Firestore profile exists.
              final profileExists = await hasUserProfile();
              if (!profileExists) {
                await _auth.signOut();
                _log('verificationCompleted: phone re-used after deletion — no profile');
                if (!completer.isCompleted) {
                  completer.complete(PhoneAuthResult(
                    status: PhoneAuthStatus.error,
                    errorMessage:
                        'We couldn\'t find an account linked to this number. '
                        'Please sign up to create a new account.',
                    isAccountDeleted: true,
                  ));
                }
                return;
              }
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
            final isDeleted = e.code == 'user-not-found';
            completer.complete(PhoneAuthResult(
              status: PhoneAuthStatus.error,
              rawErrorCode: e.code,
              rawErrorMessage: e.message,
              errorMessage: isDeleted
                  ? 'We couldn\'t find an account linked to this number. '
                    'Please sign up to create a new account.'
                  : _mapAuthError(e.code),
              isAccountDeleted: isDeleted,
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

  /// Verify the SMS OTP code.
  ///
  /// [isOnboarding] — set to `true` when called from the onboarding
  /// verification screen (new user registration). In this context, if Firebase
  /// Auth still holds a stale entry for the phone number (e.g. from a
  /// previously deleted account) but no Firestore profile exists, we treat the
  /// user as new and create a fresh profile rather than blocking them.
  ///
  /// When `isOnboarding` is `false` (the default — login flow), a missing
  /// Firestore profile means the account was deleted and the user must
  /// re-register via the onboarding carousel.
  Future<AuthResult> verifySmsCode(String smsCode,
      {String? verificationId, bool isOnboarding = false}) async {
    _log('verifySmsCode: platform=${kIsWeb ? "web" : defaultTargetPlatform.name}, '
        'isOnboarding=$isOnboarding');

    try {
      // Web: confirm via ConfirmationResult
      if (kIsWeb) {
        if (_webConfirmationResult == null) {
          return AuthResult.failure(
              'Verification session expired. Please go back and request a new code.');
        }
        final userCred = await _webConfirmationResult!.confirm(smsCode);
        final isNewUser = userCred.additionalUserInfo?.isNewUser ?? false;
        if (isNewUser || (isOnboarding && !(await hasUserProfile()))) {
          // Create a fresh profile for new users OR for re-registering users
          // whose Auth entry persisted after Firestore deletion.
          final profileCreated = await _createUserProfile(userCred.user!.uid);
          _log('verifySmsCode(web): profile created (isNewUser=$isNewUser, isOnboarding=$isOnboarding)');
          if (!profileCreated) {
            // PROFILE-COMMIT-1: Auth created but profile write failed.
            return AuthResult.failure(
              'We created your account but couldn\'t finish setting up '
              'your profile. Please check your connection and try again.',
            );
          }
        } else {
          // Returning user on web — verify their Firestore profile still exists.
          final profileExists = await hasUserProfile();
          if (!profileExists) {
            await _auth.signOut();
            _log('verifySmsCode(web): phone re-used after account deletion — no profile found');
            return AuthResult.failure(
              'We couldn\'t find an account linked to this number. '
              'Please sign up to create a new account.',
              accountDeleted: true,
            );
          }
          await HuddlUserService().syncCurrentUserProfile();
        }
        // Clear the explicit logout flag — user has successfully authenticated
        await clearLoggedOutFlag();
        // Check if this account still needs onboarding.
        // AUTH-ONBOARD-1 / ONBOARD-RESUME-1: use != false semantics.
        // absent (null) OR true  → needsOnboarding = true  (still in flow)
        // explicit false         → needsOnboarding = false (positively complete)
        // Do NOT use ?? false: that collapses absent→false→"complete", wrong.
        bool needsOnboarding = true; // default: needs onboarding unless positively complete
        try {
          final doc = await _db.collection('users').doc(userCred.user!.uid).get()
              .timeout(const Duration(seconds: 3));
          final v = doc.data()?['isOnboarding'];
          needsOnboarding = (v != false); // only explicit false = done
        } catch (_) {} // leave needsOnboarding=true on error (fail safe)
        return AuthResult.success(userCred.user, requiresOnboarding: needsOnboarding);
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
      final isNewUser = userCred.additionalUserInfo?.isNewUser ?? false;

      // ── Test-number fast path ───────────────────────────────────────────
      // Firebase Console test numbers never have a Firestore `users` document.
      // Skip the profile check so Test Lab / manual QA flows complete normally.
      final compactPhone =
          (userCred.user?.phoneNumber ?? '').replaceAll(' ', '');
      if (_firebaseTestPhoneNumbers.contains(compactPhone)) {
        _log('verifySmsCode: test number $compactPhone — skipping profile check');
        await clearLoggedOutFlag();
        return AuthResult.success(userCred.user, requiresOnboarding: false);
      }
      // ───────────────────────────────────────────────────────────────────

      if (isNewUser) {
        // Genuinely new Firebase Auth user — create profile
        final profileCreated = await _createUserProfile(userCred.user!.uid);
        _log('verifySmsCode: new user — profile created');
        if (!profileCreated) {
          // PROFILE-COMMIT-1: Auth created but profile write failed.
          return AuthResult.failure(
            'We created your account but couldn\'t finish setting up '
            'your profile. Please check your connection and try again.',
          );
        }
      } else {
        // Firebase Auth already knows this phone number.
        final profileExists = await hasUserProfile();

        if (!profileExists && isOnboarding) {
          // Stale Auth entry from a previously deleted account, but the user
          // is going through onboarding again → create a fresh Firestore
          // profile so they can complete registration normally.
          final profileCreated483 = await _createUserProfile(userCred.user!.uid);
          _log('verifySmsCode: stale Auth entry re-used during onboarding — '
              'created fresh profile for uid=${userCred.user?.uid}');
          if (!profileCreated483) {
            // PROFILE-COMMIT-1: Auth exists but profile write failed.
            return AuthResult.failure(
              'We created your account but couldn\'t finish setting up '
              'your profile. Please check your connection and try again.',
            );
          }
        } else if (!profileExists) {
          // Login flow: missing profile means the account was deleted.
          // Sign out the stale auth session and tell the user to sign up.
          await _auth.signOut();
          _log('verifySmsCode: phone re-used after account deletion — no profile found');
          return AuthResult.failure(
            'We couldn\'t find an account linked to this number. '
            'Please sign up to create a new account.',
            accountDeleted: true,
          );
        } else {
          // Normal returning user with valid profile — sync and continue.
          await HuddlUserService().syncCurrentUserProfile();
        }
      }
      _log('verifySmsCode: success, uid=${userCred.user?.uid}');
      // Clear the explicit logout flag — user has successfully authenticated
      await clearLoggedOutFlag();
      // Check if this account still needs onboarding.
      // AUTH-ONBOARD-1 / ONBOARD-RESUME-1: use != false semantics.
      // absent (null) OR true  → needsOnboarding = true  (still in flow)
      // explicit false         → needsOnboarding = false (positively complete)
      // Do NOT use ?? false: that collapses absent→false→"complete", wrong.
      bool needsOnboarding = true; // default: needs onboarding unless positively complete
      try {
        final doc = await _db.collection('users').doc(userCred.user!.uid).get()
            .timeout(const Duration(seconds: 3));
        final v = doc.data()?['isOnboarding'];
        needsOnboarding = (v != false); // only explicit false = done
      } catch (_) {} // leave needsOnboarding=true on error (fail safe)
      return AuthResult.success(userCred.user, requiresOnboarding: needsOnboarding);
    } on FirebaseAuthException catch (e) {
      _log('verifySmsCode FirebaseAuthException: ${e.code}');
      if (e.code == 'user-not-found') {
        return AuthResult.failure(
          'We couldn\'t find an account linked to this number. '
          'Please sign up to create a new account.',
          accountDeleted: true,
        );
      }
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
    // Write the explicit logout flag BEFORE signing out so the splash screen
    // knows the user deliberately logged out (as opposed to just a fresh
    // install where the Keychain token persists but local data was cleared).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_loggedOutKey, true);
    } catch (_) {}
    // Wipe all per-user in-memory + BrowserStorage state before signing out.
    // One service failing must not prevent sign-out from completing.
    await UserStateRegistry.clearAll();
    await _auth.signOut();
    _verificationId = null;
    _resendToken = null;
    _webConfirmationResult = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UPDATE PHONE NUMBER (§3D)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Updates the signed-in user's phone number via a two-step SMS OTP flow.
  ///
  /// Step 1 — Call [sendPhoneUpdateOtp] with the new phone number.
  ///   → sends an SMS to the new number and returns codeSent / error.
  ///
  /// Step 2 — Call [confirmPhoneUpdate] with the OTP the user typed.
  ///   → re-links the credential on the Auth account and updates Firestore.
  ///   → returns null on success, or an error message string on failure.
  ///
  /// Platform notes:
  ///   iOS / Android → verifyPhoneNumber (no reCAPTCHA)
  ///   Web           → signInWithPhoneNumber (reCAPTCHA, stores ConfirmationResult)

  Future<PhoneAuthResult> sendPhoneUpdateOtp(String newPhoneNumber) async {
    _log('sendPhoneUpdateOtp: $newPhoneNumber');
    try {
      if (kIsWeb) {
        // Web: trigger reCAPTCHA + SMS to the new number
        _webConfirmationResult =
            await _auth.signInWithPhoneNumber(newPhoneNumber);
        return PhoneAuthResult(status: PhoneAuthStatus.codeSent);
      } else {
        // Mobile: verifyPhoneNumber → SMS to new number, store verificationId
        final completer = Completer<PhoneAuthResult>();
        await _auth.verifyPhoneNumber(
          phoneNumber: newPhoneNumber,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (_) {
            // Auto-verified (uncommon for number-change flow) — no-op here;
            // confirmPhoneUpdate with smsCode will handle it.
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
              completer.complete(
                PhoneAuthResult(status: PhoneAuthStatus.codeSent),
              );
            }
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            _verificationId = verificationId;
            if (!completer.isCompleted) {
              completer.complete(
                PhoneAuthResult(status: PhoneAuthStatus.codeSent),
              );
            }
          },
        );
        return completer.future
            .timeout(const Duration(seconds: 65), onTimeout: () {
          return PhoneAuthResult(
            status: PhoneAuthStatus.error,
            errorMessage: 'Timed out waiting for SMS. Please try again.',
          );
        });
      }
    } catch (e, stack) {
      _logError(e, stack, 'sendPhoneUpdateOtp');
      return PhoneAuthResult(
        status: PhoneAuthStatus.error,
        errorMessage: 'Could not send verification SMS. Please try again.',
      );
    }
  }

  /// Confirms the phone-number update using the OTP the user typed.
  ///
  /// On success:
  ///   1. The Firebase Auth account phone number is updated (re-link).
  ///   2. Firestore users/{uid}.phoneNumber is updated to [newPhoneNumber].
  ///
  /// Returns null on success, or a human-readable error string on failure.
  Future<String?> confirmPhoneUpdate({
    required String smsCode,
    required String newPhoneNumber,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 'No signed-in user. Please log in again.';
    try {
      PhoneAuthCredential credential;
      if (kIsWeb) {
        final result = await _webConfirmationResult?.confirm(smsCode);
        if (result == null) {
          return 'Verification session expired. Please request a new code.';
        }
        // On web the phone number was already updated via confirm(); just
        // update Firestore below.
        credential = PhoneAuthProvider.credential(
          verificationId: '',
          smsCode: smsCode,
        );
      } else {
        final vId = _verificationId;
        if (vId == null || vId.isEmpty) {
          return 'Verification session expired. Please go back and try again.';
        }
        credential = PhoneAuthProvider.credential(
          verificationId: vId,
          smsCode: smsCode,
        );
        // Re-link the new phone credential to the existing Auth account.
        // updatePhoneNumber replaces the old phone credential without sign-out.
        await user.updatePhoneNumber(credential);
      }

      // Update Firestore so other devices / backend sees the new number.
      await _safeDelete(() => _db
          .collection('users')
          .doc(user.uid)
          .set({'phoneNumber': newPhoneNumber}, SetOptions(merge: true)));

      _verificationId = null;
      _webConfirmationResult = null;
      _log('confirmPhoneUpdate: success — new number=$newPhoneNumber');
      return null; // success
    } on FirebaseAuthException catch (e) {
      _log('confirmPhoneUpdate: FirebaseAuthException ${e.code}');
      return _mapAuthError(e.code);
    } catch (e, stack) {
      _logError(e, stack, 'confirmPhoneUpdate');
      return 'Failed to update phone number. Please try again.';
    }
  }

  /// Permanently deletes the Firebase Auth account and ALL associated
  /// Firestore data for the currently signed-in user (GDPR Art. 17).
  ///
  /// Collections purged:
  // ═══════════════════════════════════════════════════════════════════════════
  // RE-AUTHENTICATION WITH OTP (§5D Change Password)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Verifies an OTP code against the stored verificationId from the most
  /// recent [verifyPhoneNumber] or [sendPhoneUpdateOtp] call.
  ///
  /// Used by the Change Password flow to confirm the user's identity before
  /// allowing a password change — without creating a new session or profile.
  ///
  /// Returns null on success (OTP accepted), or an error string on failure.
  Future<String?> reAuthWithOtp({required String smsCode}) async {
    _log('reAuthWithOtp: platform=${kIsWeb ? "web" : defaultTargetPlatform.name}');
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No signed-in user found.';

      if (kIsWeb) {
        // Web: confirm via the stored ConfirmationResult
        if (_webConfirmationResult == null) {
          return 'Verification session expired. Please request a new code.';
        }
        // Confirm returns a UserCredential — we only need it to not throw
        await _webConfirmationResult!.confirm(smsCode);
        _webConfirmationResult = null;
        return null;
      }

      // iOS + Android
      final vId = _verificationId;
      if (vId == null || vId.isEmpty) {
        return 'Verification session expired. Please request a new code.';
      }
      final credential = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: smsCode,
      );
      await user.reauthenticateWithCredential(credential);
      _verificationId = null;
      return null; // success
    } on FirebaseAuthException catch (e) {
      _log('reAuthWithOtp FirebaseAuthException: ${e.code}');
      if (e.code == 'invalid-verification-code') {
        return 'Incorrect code. Please check and try again.';
      } else if (e.code == 'session-expired') {
        return 'Code expired. Please request a new one.';
      }
      return e.message ?? 'Verification failed. Please try again.';
    } catch (e, stack) {
      _logError(e, stack, 'reAuthWithOtp');
      return 'Verification failed. Please try again.';
    }
  }

  ///   users, subscriptions, group_messages, direct_messages,
  ///   conversations, notifications, meetups, marketplace listings,
  ///   blocks, saved_items, endorsements, rsvps, user_rsvps,
  ///   deadlines sub-collection.
  ///
  /// Returns an error message on failure, or null on success.
  // ---------------------------------------------------------------------------
  // deleteAccount — GDPR spec F
  //
  // Replaces the old 16-step client-side sweep with a single CF call.
  // Sequence:
  //   1. Call deleteUserData CF (europe-west2); await structured result.
  //   2. Only on result.success == true: call user.delete().
  //   3. On CF failure or result.success == false: surface error, do NOT
  //      call user.delete(), leave the caller to offer retry.
  //
  // DECISION LOCKED: no belt-and-suspenders client sweep alongside the CF.
  // The CF is the single source of truth for GDPR data deletion.
  // ---------------------------------------------------------------------------
  Future<String?> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return 'No signed-in user found.';
    try {
      // ── 1. Call the GDPR deletion CF ──────────────────────────────────────
      final callable = FirebaseFunctions
          .instanceFor(region: 'europe-west2')
          .httpsCallable(
            'deleteUserData',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 570),
            ),
          );
      final response = await callable.call<Map<String, dynamic>>({});
      final resultData = response.data as Map<String, dynamic>? ?? {};
      final success = resultData['success'] as bool? ?? false;

      if (!success) {
        final stepErrors = (resultData['steps'] as Map<String, dynamic>?)
            ?.entries
            .where((e) => (e.value as Map<String, dynamic>?)?['status'] == 'error')
            .map((e) => e.key)
            .join(', ');
        return 'Account data deletion failed'
            '${stepErrors != null && stepErrors.isNotEmpty ? ' (steps: $stepErrors)' : ''}'
            '. Please try again or contact support.';
      }

      // ── 2. CF confirmed success: delete the Auth account ──────────────────
      await user.delete();
      // ACCT-LEAK-1 parity: clear in-memory singletons on account deletion,
      // same as signOut(). Prevents stale state if the user immediately
      // re-registers on the same device session.
      await UserStateRegistry.clearAll();
      _verificationId = null;
      _resendToken = null;
      _webConfirmationResult = null;
      return null; // success
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        return 'For security, please log out and log back in before deleting your account.';
      }
      return 'Account deletion failed: ${e.message ?? e.code}. Please try again.';
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return 'For security, please log out and log back in before deleting your account.';
      }
      return e.message ?? 'Failed to delete account.';
    } catch (e) {
      return 'Failed to delete account: $e';
    }
  }

  /// Safely deletes a Firestore document, ignoring errors (e.g. already
  /// deleted or permissions issues).
  Future<void> _safeDelete(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }



  Future<bool> hasUserProfile() async {
    if (uid == null) return false;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists;
  }

  /// ONBOARD-RESUME-1 + ONBOARD-COMPLETE-SIGNAL
  ///
  /// True ONLY when the user has a COMPLETE, usable profile.
  ///
  /// Completion semantics (CRITICAL — absence ≠ false):
  ///   - syncCurrentUserProfile() writes isOnboarding:false ONLY when a real
  ///     name is present. A profile created at phone-verification but abandoned
  ///     before about_you has the field ABSENT (not false).
  ///   - We treat ONLY an EXPLICIT `false` value as complete.
  ///   - Absent / true / null → NOT complete → route to /onboarding.
  ///
  /// Additional guard:
  ///   - borough must be non-empty (ONBOARD-BOROUGH-1: null-borough accounts
  ///     are broken and must re-complete onboarding to get a valid borough).
  ///
  /// Failure semantics — fail SAFE:
  ///   - !doc.exists  → false  (Auth entry but no Firestore doc — half-created)
  ///   - catch        → false  (network error — route to /onboarding, not /home)
  Future<bool> hasCompletedOnboarding() async {
    final u = uid;
    if (u == null) return false;
    try {
      final doc = await _db
          .collection('users')
          .doc(u)
          .get()
          .timeout(const Duration(seconds: 5));
      if (!doc.exists) return false; // half-created account (Auth yes, profile no)
      final data = doc.data()!;
      // ONLY explicit false means complete — absent/true = still in onboarding.
      // Do NOT use ?? false here: that collapses absent→false→"complete", wrong.
      if (data['isOnboarding'] != false) return false;
      // Borough must be non-empty — null/empty = broken account, recover via onboarding.
      final borough = (data['borough'] as String?) ?? '';
      if (borough.isEmpty) return false;
      return true;
    } catch (_) {
      return false; // fail safe → /onboarding (matches existing catch→/onboarding pattern)
    }
  }

  /// Pre-checks whether a phone number has a registered Huddl account in
  /// Firestore, BEFORE triggering SMS verification.
  ///
  /// This avoids sending an OTP (and confusing the user with an OTP screen)
  /// when the phone number was never registered or the account was deleted.
  ///
  /// Returns `true` if a matching Firestore user document exists.
  /// Returns `false` if no account found or on any error (fails open so the
  /// OTP path still runs if Firestore is unreachable).
  /// Phone numbers registered in Firebase Console → Authentication →
  /// "Sign-in method" → "Phone" → "Test phone numbers".
  ///
  /// These numbers exist only in Firebase Auth — they NEVER have a matching
  /// Firestore `users` document, so `checkPhoneHasAccount` would return false
  /// for them and show the "No account found" dialog, blocking Robo Test and
  /// manual QA flows that rely on test credentials.
  ///
  /// Add every test number you register in the Firebase Console here (compact
  /// E.164 form, no spaces). The pre-check is skipped for these numbers and
  /// the OTP flow proceeds directly.
  static const Set<String> _firebaseTestPhoneNumbers = {
    '+447575888453', // Firebase Console test number — code 123456
  };

  /// Pre-checks whether a phone number has a registered Huddl account in
  /// Firestore, BEFORE triggering SMS verification.
  ///
  /// This avoids sending an OTP (and confusing the user with an OTP screen)
  /// when the phone number was never registered or the account was deleted.
  ///
  /// Returns `true` if a matching Firestore user document exists.
  /// Returns `true` for Firebase Console test phone numbers (they have no
  /// Firestore document but must always proceed to OTP).
  /// Returns `false` if no account found.
  /// Falls through to `true` on any error (timeout / network / permissions)
  /// so real users are never incorrectly blocked.
  Future<bool> checkPhoneHasAccount(String fullPhoneNumber) async {
    // ── Fast-path: Firebase test numbers bypass Firestore lookup ───────────
    // Firebase Console test phone numbers (e.g. "+44 7575 888453") exist only
    // in Firebase Auth. They never have a Firestore users document, so the
    // query below would return false and block the OTP flow. Compact the
    // number and check the allowlist instead.
    final compact = fullPhoneNumber.replaceAll(RegExp(r'\s+'), '');
    if (_firebaseTestPhoneNumbers.contains(compact)) {
      _log('checkPhoneHasAccount: test number $compact — bypassing Firestore lookup');
      return true;
    }

    try {
      // Normalise the number the same way _createUserProfile stores it —
      // strip spaces so both "+44 7700 900123" and "+447700900123" match.

      // Query by the 'phone' field stored in the user document.
      // We try both spaced and compact forms for robustness.
      final query = await _db
          .collection('users')
          .where('phone', whereIn: [fullPhoneNumber, compact])
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 6), onTimeout: () {
            _log('checkPhoneHasAccount: Firestore timeout — allowing OTP');
            // Return an empty snapshot on timeout so we default to true
            // (allow the OTP flow rather than incorrectly blocking the user).
            throw TimeoutException('Firestore timeout');
          });

      return query.docs.isNotEmpty;
    } catch (e) {
      // On any error (network, permissions, timeout) default to true so
      // legitimate users are not incorrectly blocked.
      _log('checkPhoneHasAccount: error ($e) — defaulting to allow');
      return true;
    }
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  /// Restores the signed-in user's profile from Firestore into the local
  /// [OnboardingDataService] cache.
  ///
  /// Call this at app startup (splash screen) and after OTP verification for
  /// returning users to ensure the local cache always reflects Firestore —
  /// regardless of whether local storage was wiped (fresh install, reset, etc.)
  ///
  /// Returns `true` if the profile was successfully loaded from Firestore and
  /// at least the user's name was restored. Returns `false` on any error or
  /// if the profile document doesn't exist.
  Future<bool> restoreProfileFromFirestore() async {
    // Resolve uid asynchronously — on web, currentUser is null immediately
    // after Firebase.initializeApp() even for authenticated users.
    String? resolvedUid = uid;
    if (resolvedUid == null) {
      try {
        final user = await _auth
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 5));
        resolvedUid = user?.uid;
      } catch (_) {
        resolvedUid = uid; // last resort
      }
    }
    if (resolvedUid == null) return false;
    try {
      final doc = await _db
          .collection('users')
          .doc(resolvedUid)
          .get()
          .timeout(const Duration(seconds: 5));
      if (!doc.exists) return false;

      final data = doc.data()!;
      final onboarding = OnboardingDataService();
      await onboarding.initialize(forceReload: true);

      // Restore every field — only overwrite local value if local is empty/null
      String firestoreName = (data['name'] as String?) ?? '';

      // ── Self-repair: Firestore name was previously overwritten with "" ───
      // If both Firestore and local name are blank, try to recover a sensible
      // display name from other available sources so the user sees something
      // meaningful rather than "User". We also write the recovered name back
      // to Firestore so subsequent restores have real data.
      if (firestoreName.trim().isEmpty) {
        // Try firstName field
        final firstName = (data['firstName'] as String?) ?? '';
        if (firstName.trim().isNotEmpty) {
          firestoreName = firstName.trim();
        } else {
          // Fall back to the Firebase Auth phone number as a last resort —
          // at least the user can see their own number while they fix it.
          final authPhone = _auth.currentUser?.phoneNumber ?? '';
          if (authPhone.isNotEmpty) {
            firestoreName = authPhone;
          }
        }
        // Write the recovered name back to Firestore so it is fixed for future
        if (firestoreName.isNotEmpty) {
          try {
            final nameParts = firestoreName.trim().split(' ');
            await _db.collection('users').doc(resolvedUid).update({
              'name': firestoreName,
              'firstName': nameParts.first,
              if (nameParts.length > 1) 'lastName': nameParts.sublist(1).join(' '),
            });
          } catch (_) {} // non-fatal
        }
      }

      if (firestoreName.trim().isNotEmpty &&
          (onboarding.name == null || onboarding.name!.trim().isEmpty)) {
        onboarding.setName(firestoreName.trim());
      }

      final firestorePostcode = (data['postcode'] as String?) ?? '';
      if (firestorePostcode.isNotEmpty &&
          (onboarding.postcode == null || onboarding.postcode!.isEmpty)) {
        onboarding.setPostcode(firestorePostcode);
      }

      // ── Restore borough from Firestore and seed PostcodeService cache ──
      // The borough stored in Firestore was resolved from the full postcode
      // via postcodes.io at onboarding / profile-edit time.  Restore it to
      // OnboardingDataService and seed PostcodeService._cache so that every
      // sync getBoroughFromPostcode() call in the app sees the correct value
      // immediately on cold start, without a further network request.
      final firestoreBorough = (data['borough'] as String?) ?? '';
      if (firestoreBorough.isNotEmpty) {
        if (onboarding.borough == null || onboarding.borough!.isEmpty) {
          onboarding.setBorough(firestoreBorough);
        }
        // Seed PostcodeService in-memory cache regardless of whether we just
        // set it, so getBoroughFromPostcode() works for all sync callers.
        final postcodeToSeed = firestorePostcode.isNotEmpty
            ? firestorePostcode
            : (onboarding.postcode ?? '');
        PostcodeService().seedCache(postcodeToSeed, firestoreBorough);
      } else if (onboarding.borough != null && onboarding.borough!.isNotEmpty) {
        // Borough not in Firestore yet (existing account pre-dating this field)
        // but we have it locally — seed the cache at minimum.
        final postcodeToSeed = firestorePostcode.isNotEmpty
            ? firestorePostcode
            : (onboarding.postcode ?? '');
        PostcodeService().seedCache(postcodeToSeed, onboarding.borough!);
      }

      final firestoreParentType = (data['parentType'] as String?) ?? '';
      if (firestoreParentType.isNotEmpty && onboarding.parentType == null) {
        onboarding.setParentType(firestoreParentType);
      }

      final firestoreStages = data['stagesOfLife'];
      if (firestoreStages is List &&
          firestoreStages.isNotEmpty &&
          onboarding.stagesOfLife.isEmpty) {
        onboarding.setStagesOfLife(List<String>.from(firestoreStages));
      }

      final firestorePhone = (data['phone'] as String?) ?? '';
      final firestoreCountry = (data['countryCode'] as String?) ?? '+44';
      if (firestorePhone.isNotEmpty && onboarding.phoneNumber == null) {
        final subscriber = firestorePhone.startsWith(firestoreCountry)
            ? firestorePhone.substring(firestoreCountry.length)
            : firestorePhone;
        onboarding.setPhoneNumber(subscriber, countryCode: firestoreCountry);
        onboarding.setPhoneVerified(true);
      }

      // Children list
      final firestoreChildren = data['children'];
      if (firestoreChildren is List &&
          firestoreChildren.isNotEmpty &&
          onboarding.children.isEmpty) {
        // children is stored as List<Map<String, dynamic>> in Firestore
        // but OnboardingDataService uses List<Map<String, String>>
        final childList = firestoreChildren
            .whereType<Map>()
            .map((c) => c.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
            .toList()
            .cast<Map<String, String>>();
        if (childList.isNotEmpty) {
          onboarding.setChildren(childList);
        }
      }

      // ONBOARD-1-COLDSTART: due date — re-hydrate from Firestore if in-memory value is absent.
      // previous_postcode is intentionally NOT persisted here — it is a transient
      // "recently moved" signal and is session-lived by design.
      final firestoreDueDate = data['dueDate'];
      if (firestoreDueDate is String &&
          firestoreDueDate.isNotEmpty &&
          (onboarding.dueDate == null || onboarding.dueDate!.isEmpty)) {
        onboarding.setDueDate(firestoreDueDate);
      }

      // ONBOARD-1-COLDSTART: email — re-hydrate from FirebaseAuth if in-memory value is absent.
      // email is also written to Firestore (profile map above) but Firebase Auth is
      // the canonical source on cold start and is always available without an extra read.
      final fbEmail = FirebaseAuth.instance.currentUser?.email;
      if (fbEmail != null &&
          fbEmail.isNotEmpty &&
          (onboarding.email == null || onboarding.email!.isEmpty)) {
        onboarding.setEmail(fbEmail);
      }

      // Bio
      final firestoreBio = (data['bio'] as String?) ?? '';
      if (firestoreBio.isNotEmpty && (onboarding.bio == null || onboarding.bio!.isEmpty)) {
        onboarding.setBio(firestoreBio);
      }

      // Photo URL — restore both path and object URL from Firestore so the
      // profile screen can display the photo on fresh installs / after logout.
      final firestorePhoto = (data['photoUrl'] as String?) ?? '';
      if (firestorePhoto.isNotEmpty) {
        // Always update profilePhotoPath (permanent HTTPS download URL)
        if (onboarding.profilePhotoPath == null || onboarding.profilePhotoPath!.isEmpty) {
          onboarding.setProfilePhotoPath(firestorePhoto);
        }
        // Also set profilePhotoObjectUrl so the profile screen can read it
        // directly — it accepts both blob: URLs and https: Firebase Storage URLs.
        if (onboarding.profilePhotoObjectUrl == null || onboarding.profilePhotoObjectUrl!.isEmpty) {
          onboarding.setProfilePhotoObjectUrl(firestorePhoto);
        }
      }

      // ── Restore subscription tier from Firestore ─────────────────────────
      // On a fresh install BrowserStorage is empty so SubscriptionService
      // defaults to free tier. Fetch the subscriptions collection and
      // reinstate the correct tier so all paid features are immediately
      // accessible without requiring the user to go through a payment flow.
      try {
        final subDocs = await _db
            .collection('subscriptions')
            .where('userId', isEqualTo: resolvedUid)
            .get()
            .timeout(const Duration(seconds: 5));
        if (subDocs.docs.isNotEmpty) {
          final subData = subDocs.docs.first.data();
          final tierStr = (subData['tier'] as String?) ?? 'welcome';
          final isActive = (subData['isActive'] as bool?) ?? false;
          if (isActive && tierStr != 'welcome') {
            final tier = SubscriptionTier.values.firstWhere(
              (t) => t.name == tierStr,
              orElse: () => SubscriptionTier.welcome,
            );
            final periodStr = (subData['billingPeriod'] as String?) ?? 'monthly';
            final period = BillingPeriod.values.firstWhere(
              (p) => p.name == periodStr,
              orElse: () => BillingPeriod.monthly,
            );
            DateTime? renewalDate;
            final renewalStr = subData['renewalDate'] as String?;
            if (renewalStr != null) {
              try { renewalDate = DateTime.parse(renewalStr); } catch (_) {}
            }
            final subService = SubscriptionService();
            await subService.initialize();
            await subService.restoreFromFirestore(
              tier: tier,
              period: period,
              renewalDate: renewalDate,
              isFoundingMember: (subData['isFoundingMember'] as bool?) ?? false,
            );
            _log('restoreProfileFromFirestore: subscription restored → $tierStr');
          }
        }
      } catch (e) {
        _log('restoreProfileFromFirestore: subscription restore skipped ($e)');
      }

      _log('restoreProfileFromFirestore: restored name="${onboarding.name}" postcode="${onboarding.postcode}"');

      // ── CRITICAL: flush all set*() writes to SharedPreferences NOW ──────────
      // set*() methods fire-and-forget _saveToStorage(). Any subsequent call to
      // onboarding.initialize(forceReload:true) that happens before those futures
      // settle will re-read stale (empty) storage. flush() awaits the write so
      // storage is guaranteed up-to-date before callers re-read it.
      await onboarding.flush();

      return (onboarding.name ?? '').trim().isNotEmpty;
    } catch (e) {
      _log('restoreProfileFromFirestore: error $e');
      return false;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // USER PROFILE
  // ═════════════════════════════════════════════════════════════════════════

  Future<bool> _createUserProfile(String userId) async {
    final onboarding = OnboardingDataService();
    await onboarding.initialize(forceReload: true);

    // Resolve borough via postcodes.io so the exact admin district is used.
    // Prefer the borough already stored from onboarding (set in postcode_screen);
    // fall back to a fresh API call only if it's missing (e.g. legacy path).
    final postcode = onboarding.postcode ?? '';
    final borough = onboarding.borough?.isNotEmpty == true
        ? onboarding.borough!
        : await PostcodeService().lookupBoroughAsync(postcode) ?? '';
    // Persist the borough if it wasn't already stored
    if (borough.isNotEmpty && (onboarding.borough == null || onboarding.borough!.isEmpty)) {
      onboarding.setBorough(borough);
    }

    final name = onboarding.name ?? '';
    final parts = name.trim().split(' ');
    final firstName = parts.isNotEmpty ? parts.first : '';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final email = (onboarding.email ?? '').trim();

    final Map<String, dynamic> profile = {
      'uid': userId,
      'name': name,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,                       // captured at onboarding step 1
      'phone':
          onboarding.fullPhoneNumber ?? _auth.currentUser?.phoneNumber ?? '',
      'countryCode': onboarding.countryCode ?? '+44',
      'parentType': onboarding.parentType ?? '',
      'stagesOfLife': onboarding.stagesOfLife,
      'postcode': postcode,
      'borough': borough,
      'children': onboarding.children,
      'dueDate': onboarding.dueDate ?? '',   // ONBOARD-1-COLDSTART: empty string when not expecting
      'bio': onboarding.bio ?? '',
      'photoUrl': '',
      'tier': 'welcome',
      'isFoundingMember': false,
      'isPhoneVerified': true,
      'isOnline': true,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'assignedGroupCount': 0,
      'assignedGroupNames': [],
      'fcmToken': '',
      'notificationsEnabled': true,
      // AGE-1 / AGE-1-R1: full DOB components written to user doc.
      // Firestore rules enforce precise 18+ via year/month/day at create time.
      // dateOfBirth (ISO-8601 string) retained for audit / future assurance levels.
      'birthYear':  onboarding.birthYear,          // e.g. 1990  (int)
      'birthMonth': onboarding.birthMonth,         // e.g. 6     (int) — AGE-1-R1
      'birthDay':   onboarding.birthDay,           // e.g. 15    (int) — AGE-1-R1
      'dateOfBirth': onboarding.dateOfBirth ?? '', // e.g. '1990-06-15'
    };

    // PROFILE-COMMIT-1 + SUBSCRIPTION-DUP-1: atomic batch for the two critical
    // writes. users + subscriptions commit together or not at all.
    // subscriptions uses doc(userId).set(merge) — idempotent on retry,
    // aligned with the Stripe-webhook write shape, and keyed by uid
    // (the read path's primary lookup at firestore_service doc(uid)).
    try {
      final batch = _db.batch();
      batch.set(
        _db.collection('users').doc(userId),
        profile,
        SetOptions(merge: true),
      );
      batch.set(
        _db.collection('subscriptions').doc(userId),
        {
          'userId': userId,
          'tier': 'welcome',
          'billingPeriod': 'monthly',
          'status': 'active',
          'platform': kIsWeb
              ? 'web'
              : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
          'startDate': DateTime.now().toIso8601String(),
          'renewalDate': null,
          'isActive': true,
          'isTrial': false,         // Welcome is free forever — NOT a trial
          'trialDaysRemaining': 0,  // No time limit on Welcome tier
          'isFoundingMember': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      // LAYER-15: write consent record atomically with the account.
      // user_consents/{uid} is keyed by uid (one record per onboarding).
      // Firestore rules lock this doc immutable after creation (update/delete=false)
      // and it is intentionally excluded from the deleteUserData erasure sweep —
      // it is the lawful-basis proof that data processing was consented to.
      batch.set(
        _db.collection('user_consents').doc(userId),
        {
          'userId': userId,
          'dataProcessing': onboarding.consentDataProcessing ?? true,
          'marketing': onboarding.consentMarketing ?? false,
          'policyVersion': onboarding.consentPolicyVersion ?? 'v1',
          'consentedAt': onboarding.consentedAt != null
              ? Timestamp.fromDate(onboarding.consentedAt!)
              : FieldValue.serverTimestamp(),
          'recordedAt': FieldValue.serverTimestamp(),
        },
      );
      await batch.commit();
    } catch (e, st) {
      _logError(e, st, '_createUserProfile: critical profile write failed');
      return false; // PROFILE-COMMIT-1: signal failure to caller for targeted retry
    }

    // Post-commit best-effort: sync + welcome notification.
    // Profile is already committed; these failures must NOT fail profile-create.
    try {
      await HuddlUserService().syncCurrentUserProfile();
    } catch (_) {}

    // Send welcome push notification + email via backend.
    // Email address is captured at onboarding step 1 — available immediately.
    unawaited(
      BackendApiService().sendWelcomeNotification(
        email: email,
        firstName: firstName,
        borough: borough,
      ).catchError((_) {}),
    );

    if (kDebugMode) {
      debugPrint('FirebaseAuthService: profile created for $userId, borough=$borough');
    }
    return true; // PROFILE-COMMIT-1: critical writes committed successfully
  }

  Future<void> updateLastActive() async {
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).update({
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Silently ignore — document may not exist for test numbers or
      // freshly-deleted accounts. Non-critical operation.
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LOGGING
  // ═════════════════════════════════════════════════════════════════════════

  void _log(String message) {
    try {
      FirebaseCrashlytics.instance.log(message);
    } catch (_) {}
    if (kDebugMode) {
      if (kDebugMode) debugPrint('[FirebaseAuthService] $message');
    }
  }

  void _logError(Object e, StackTrace stack, String reason) {
    try {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: reason);
    } catch (_) {}
    if (kDebugMode) {
      if (kDebugMode) debugPrint('[FirebaseAuthService] ERROR $reason: $e');
    }
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
      // Returned when the phone number belonged to a deleted Firebase Auth account
      case 'user-not-found':
        return 'account-not-found'; // sentinel — caught by UI layer
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
  /// True when the OTP was technically valid but the Firebase Auth account
  /// no longer exists (i.e. it was deleted). The UI should direct the user
  /// to sign up / restart onboarding instead of showing a generic error.
  final bool isAccountDeleted;
  /// True when Firestore user document has isOnboarding=true — account exists
  /// but onboarding was never completed. Route to /onboarding, not /home.
  final bool requiresOnboarding;

  AuthResult._({
    required this.isSuccess,
    this.user,
    this.errorMessage,
    this.message,
    this.isAccountDeleted = false,
    this.requiresOnboarding = false,
  });

  factory AuthResult.success(User? user, {String? message, bool requiresOnboarding = false}) =>
      AuthResult._(isSuccess: true, user: user, message: message, requiresOnboarding: requiresOnboarding);

  factory AuthResult.failure(String error, {bool accountDeleted = false}) =>
      AuthResult._(
        isSuccess: false,
        errorMessage: error,
        isAccountDeleted: accountDeleted,
      );
}

enum PhoneAuthStatus { codeSent, verified, error }

class PhoneAuthResult {
  final PhoneAuthStatus status;
  final String? verificationId;
  final String? errorMessage;
  // Raw Firebase error code and message — passed through for on-screen diagnosis
  final String? rawErrorCode;
  final String? rawErrorMessage;
  /// True when Firebase explicitly reports the phone number has no associated
  /// account (user-not-found). The UI should direct the user to sign up.
  final bool isAccountDeleted;

  PhoneAuthResult({
    required this.status,
    this.verificationId,
    this.errorMessage,
    this.rawErrorCode,
    this.rawErrorMessage,
    this.isAccountDeleted = false,
  });
}
