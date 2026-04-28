import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'onboarding_data_service.dart';
import 'huddl_user_service.dart';
import 'postcode_service.dart';
import 'subscription_service.dart';
import 'backend_api_service.dart';
import '../models/subscription.dart';

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
          await _createUserProfile(userCred.user!.uid);
          _log('verifySmsCode(web): profile created (isNewUser=$isNewUser, isOnboarding=$isOnboarding)');
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
        // Check if this account still needs onboarding (isOnboarding=true in Firestore)
        bool needsOnboarding = false;
        try {
          final doc = await _db.collection('users').doc(userCred.user!.uid).get()
              .timeout(const Duration(seconds: 3));
          needsOnboarding = (doc.data()?['isOnboarding'] as bool?) ?? false;
        } catch (_) {}
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

      if (isNewUser) {
        // Genuinely new Firebase Auth user — create profile
        await _createUserProfile(userCred.user!.uid);
        _log('verifySmsCode: new user — profile created');
      } else {
        // Firebase Auth already knows this phone number.
        final profileExists = await hasUserProfile();

        if (!profileExists && isOnboarding) {
          // Stale Auth entry from a previously deleted account, but the user
          // is going through onboarding again → create a fresh Firestore
          // profile so they can complete registration normally.
          await _createUserProfile(userCred.user!.uid);
          _log('verifySmsCode: stale Auth entry re-used during onboarding — '
              'created fresh profile for uid=${userCred.user?.uid}');
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
      // Check if this account still needs onboarding (isOnboarding=true in Firestore)
      bool needsOnboarding = false;
      try {
        final doc = await _db.collection('users').doc(userCred.user!.uid).get()
            .timeout(const Duration(seconds: 3));
        needsOnboarding = (doc.data()?['isOnboarding'] as bool?) ?? false;
      } catch (_) {}
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
    await _auth.signOut();
    _verificationId = null;
    _resendToken = null;
    _webConfirmationResult = null;
  }

  /// Permanently deletes the Firebase Auth account and ALL associated
  /// Firestore data for the currently signed-in user (GDPR Art. 17).
  ///
  /// Collections purged: users, subscriptions, group_messages, direct_messages,
  /// conversations, notifications, meetups.
  ///
  /// Returns an error message on failure, or null on success.
  Future<String?> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return 'No signed-in user found.';
    final uid = user.uid;
    try {
      // ── 1. Delete user's Firestore document ───────────────────────────
      await _safeDelete(() => _db.collection('users').doc(uid).delete());

      // ── 2. Delete all subscriptions owned by this user ────────────────
      await _deleteQueryResults(
        _db.collection('subscriptions').where('userId', isEqualTo: uid),
      );

      // ── 3. Delete group messages sent by this user ────────────────────
      await _deleteQueryResults(
        _db.collection('group_messages').where('senderId', isEqualTo: uid),
      );

      // ── 4. Delete direct messages sent or received by this user ───────
      await _deleteQueryResults(
        _db.collection('direct_messages').where('senderId', isEqualTo: uid),
      );
      await _deleteQueryResults(
        _db.collection('direct_messages').where('receiverId', isEqualTo: uid),
      );

      // ── 5. Delete conversations involving this user ────────────────────
      await _deleteQueryResults(
        _db.collection('conversations').where('participantIds', arrayContains: uid),
      );

      // ── 6. Delete notifications addressed to this user ────────────────
      await _deleteQueryResults(
        _db.collection('notifications').where('userId', isEqualTo: uid),
      );

      // ── 7. Delete meetups created by this user ────────────────────────
      await _deleteQueryResults(
        _db.collection('meetups').where('creatorId', isEqualTo: uid),
      );

      // ── 8. Delete the Firebase Auth account last ──────────────────────
      await user.delete();
      _verificationId = null;
      _resendToken = null;
      _webConfirmationResult = null;
      return null; // success
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

  /// Deletes all documents returned by [query] in batches of 500.
  Future<void> _deleteQueryResults(Query query) async {
    try {
      const batchSize = 500;
      QuerySnapshot snapshot;
      do {
        snapshot = await query.limit(batchSize).get();
        if (snapshot.docs.isEmpty) break;
        final batch = _db.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } while (snapshot.docs.length == batchSize);
    } catch (_) {
      // Non-fatal: collection may not exist or security rules may block it.
    }
  }

  Future<bool> hasUserProfile() async {
    if (uid == null) return false;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists;
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
  Future<bool> checkPhoneHasAccount(String fullPhoneNumber) async {
    try {
      // Normalise the number the same way _createUserProfile stores it —
      // strip spaces so both "+44 7700 900123" and "+447700900123" match.
      final normalised = fullPhoneNumber.replaceAll(RegExp(r'\s+'), '');

      // Query by the 'phone' field stored in the user document.
      // We try both spaced and compact forms for robustness.
      final query = await _db
          .collection('users')
          .where('phone', whereIn: [fullPhoneNumber, normalised])
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
    if (uid == null) return false;
    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
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
            await _db.collection('users').doc(uid).update({
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

      // Bio
      final firestoreBio = (data['bio'] as String?) ?? '';
      if (firestoreBio.isNotEmpty && (onboarding.bio == null || onboarding.bio!.isEmpty)) {
        onboarding.setBio(firestoreBio);
      }

      // Photo URL
      final firestorePhoto = (data['photoUrl'] as String?) ?? '';
      if (firestorePhoto.isNotEmpty &&
          (onboarding.profilePhotoPath == null || onboarding.profilePhotoPath!.isEmpty)) {
        onboarding.setProfilePhotoObjectUrl(firestorePhoto);
      }

      // ── Restore subscription tier from Firestore ─────────────────────────
      // On a fresh install BrowserStorage is empty so SubscriptionService
      // defaults to 'explorer'. Fetch the subscriptions collection and
      // reinstate the correct tier so all paid features are immediately
      // accessible without requiring the user to go through a payment flow.
      try {
        final subDocs = await _db
            .collection('subscriptions')
            .where('userId', isEqualTo: uid)
            .get()
            .timeout(const Duration(seconds: 5));
        if (subDocs.docs.isNotEmpty) {
          final subData = subDocs.docs.first.data();
          final tierStr = (subData['tier'] as String?) ?? 'explorer';
          final isActive = (subData['isActive'] as bool?) ?? false;
          if (isActive && tierStr != 'explorer') {
            final tier = SubscriptionTier.values.firstWhere(
              (t) => t.name == tierStr,
              orElse: () => SubscriptionTier.explorer,
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
      return (onboarding.name ?? '').trim().isNotEmpty;
    } catch (e) {
      _log('restoreProfileFromFirestore: error $e');
      return false;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // USER PROFILE
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _createUserProfile(String userId) async {
    final onboarding = OnboardingDataService();
    await onboarding.initialize(forceReload: true);

    // Resolve borough via postcodes.io so the exact admin district is used.
    final postcode = onboarding.postcode ?? '';
    final borough = await PostcodeService().lookupBoroughAsync(postcode) ?? '';

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
      'bio': onboarding.bio ?? '',
      'photoUrl': '',
      'tier': 'explorer',
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
      'isTrial': false,         // Welcome is free forever — NOT a trial
      'trialDaysRemaining': 0,  // No time limit on Welcome tier
      'isFoundingMember': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Trigger a full profile sync so all fields are set correctly
    await HuddlUserService().syncCurrentUserProfile();

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
