// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — PUSH NOTIFICATION SERVICE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Responsibilities
//   1. Request permission (iOS prompt + Android 13+ POST_NOTIFICATIONS)
//   2. Acquire the FCM registration token and register it with the backend
//   3. Refresh the token when FCM rotates it
//   4. Handle foreground messages → in-app banner via local_notifications OR
//      a lightweight SnackBar when flutter_local_notifications is absent
//   5. Handle notification taps (background / terminated → navigate to correct screen)
//
// HOW TO USE
//   Call `PushNotificationService().initialise(context)` once after login.
//   Call `PushNotificationService().dispose()` on logout.
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'backend_api_service.dart';
import 'user_privacy_prefs_service.dart';

// ── Top-level background handler (must be a top-level / static function) ──────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs on Android.
  // We only need to ensure we don't crash — actual UI work happens on resume.
  debugPrint('[FCM-BG] ${message.notification?.title}: ${message.notification?.body}');
}

class PushNotificationService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _initialised = false;

  // ── Foreground message callback ───────────────────────────────────────────
  // Set by the app shell so it can display an in-app banner.
  void Function(RemoteMessage message)? onForegroundMessage;

  // ── Notification tap callback ─────────────────────────────────────────────
  // Called when the user taps a notification while the app is
  // in the background or foreground — use to navigate to the right screen.
  void Function(RemoteMessage message)? onNotificationTap;

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: initialise
  // ─────────────────────────────────────────────────────────────────────────

  /// Call once after the user is authenticated (or on every cold start when
  /// Firebase already has a current user).  Safe to call multiple times — 
  /// subsequent calls are no-ops unless [force] is true.
  Future<void> initialise({bool force = false}) async {
    if (_initialised && !force) return;
    if (kIsWeb) {
      // Web FCM requires a VAPID key — skip for now (app is mobile-first)
      _initialised = true;
      return;
    }

    try {
      // ── 1. Register background handler (must be done before anything else) ─
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // ── 2. Request permission ──────────────────────────────────────────────
      // IMPORTANT: On Android 13+ (API 33+), requestPermission() triggers the
      // POST_NOTIFICATIONS system dialog — a system-level overlay that causes
      // Firebase Test Lab Robo tests to report "Outside of app" / UiAutomator
      // timeout, ending the test with "Test failed to run".
      //
      // Fix: check the current status first. If it is already authorized or
      // denied, skip the requestPermission() call entirely (status is already
      // determined, showing the dialog again is both unnecessary and harmful
      // in automated test environments).
      //
      // On a fresh Test Lab device the status will be notDetermined on iOS.
      // On Android 13+ fresh installs it will be notDetermined, but calling
      // requestPermission with provisional:true grants silently on Android
      // without showing any system dialog.
      NotificationSettings settings;

      final currentSettings = await _messaging.getNotificationSettings();
      _log('Current permission status: ${currentSettings.authorizationStatus}');

      if (currentSettings.authorizationStatus == AuthorizationStatus.authorized ||
          currentSettings.authorizationStatus == AuthorizationStatus.provisional) {
        // Already granted — no need to prompt again
        settings = currentSettings;
        _log('Permission already granted, skipping dialog');
      } else if (currentSettings.authorizationStatus == AuthorizationStatus.denied) {
        // User previously denied — do not re-prompt (would show dialog on some
        // Android versions), just proceed without notifications
        settings = currentSettings;
        _log('Permission previously denied, skipping dialog');
      } else {
        // notDetermined — safe to ask once
        // provisional:true on Android grants silently without any system dialog
        settings = await _messaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: true,   // true = silent grant on Android (no system dialog)
          sound: true,
        );
      }

      _log('Permission: ${settings.authorizationStatus}');

      // ── 3. iOS foreground presentation options ─────────────────────────────
      if (Platform.isIOS) {
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // ── 4. Acquire + register token ────────────────────────────────────────
      await _registerToken();

      // ── 5. Listen for token refreshes ─────────────────────────────────────
      _messaging.onTokenRefresh.listen((newToken) {
        _log('Token refreshed');
        _saveToken(newToken);
      });

      // ── 6. Foreground message handler ──────────────────────────────────────
      FirebaseMessaging.onMessage.listen((message) {
        _log('Foreground: ${message.notification?.title}');
        onForegroundMessage?.call(message);
      });

      // ── 7. Background → foreground tap ────────────────────────────────────
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _log('Tapped from background: ${message.notification?.title}');
        onNotificationTap?.call(message);
      });

      // ── 8. Terminated → opened tap ────────────────────────────────────────
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _log('App opened from terminated by notification');
        onNotificationTap?.call(initialMessage);
      }

      _initialised = true;
    } catch (e) {
      _log('❌ Initialisation error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: dispose / logout
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _initialised = false;
    onForegroundMessage = null;
    onNotificationTap = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: deregister FCM token on logout / account deletion
  // ─────────────────────────────────────────────────────────────────────────

  /// Deletes the FCM registration token from the device and clears the stored
  /// token on Firestore.  Must be called **before** Firebase Auth sign-out so
  /// we still have a valid uid to write to.
  ///
  /// On iOS, [FirebaseMessaging.deleteToken()] invalidates the APNs token
  /// binding so the device stops receiving push notifications immediately.
  /// On Android it rotates the token so old pushes to the old token fail.
  /// On Web, FCM token management requires a VAPID key — we fall back to just
  /// clearing the Firestore field.
  Future<void> deregisterToken() async {
    final uid = _auth.currentUser?.uid;
    // 1. Delete the FCM token from the device (mobile only — web skips gracefully)
    if (!kIsWeb) {
      try {
        await _messaging.deleteToken();
        _log('FCM token deleted from device');
      } catch (e) {
        _log('deleteToken error (non-fatal): $e');
      }
    }
    // 2. Clear the token stored in Firestore so the backend stops targeting
    //    this device.  Works on web too — the uid is still valid pre-signOut.
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set(
          {'fcmToken': '', 'fcmUpdatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
        _log('FCM token cleared in Firestore for uid=$uid');
      } catch (e) {
        _log('Firestore fcmToken clear error (non-fatal): $e');
      }
    }
    _initialised = false;
    onForegroundMessage = null;
    onNotificationTap = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNAL HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        _log('No token available yet');
        return;
      }
      _log('Token acquired (${token.substring(0, 12)}…)');
      await _saveToken(token);
    } catch (e) {
      _log('Token acquisition error: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // Write directly to Firestore (fast, no backend round-trip needed)
    try {
      await _db.collection('users').doc(uid).update({
        'fcmToken': token,
        'fcmPlatform': Platform.isIOS ? 'ios' : 'android',
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      });
      _log('Token saved to Firestore for uid=$uid');
    } catch (e) {
      _log('Token Firestore save error: $e');
    }

    // Also register with backend (updates fcmPlatform + sets fcmUpdatedAt)
    try {
      await BackendApiService().registerFcmToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
    } catch (e) {
      // Non-fatal
      _log('Backend token registration error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATIC: check whether the user has granted permission
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> get hasPermission async {
    if (kIsWeb) return false;
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATIC: save notification prefs to Firestore so backend can read them
  // ─────────────────────────────────────────────────────────────────────────

  /// Syncs the local [UserPrivacyPrefsService] notification preferences to
  /// Firestore so the backend can respect them when sending FCM messages.
  Future<void> syncPrefsToFirestore() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = UserPrivacyPrefsService();
      await _db.collection('users').doc(uid).update({
        'notifPrefs': {
          'pushEnabled': prefs.pushEnabled,
          'groupMessages': prefs.groupMessages,
          'dmMessages': prefs.dmMessages,
          'eventReminders': prefs.eventReminders,
          'communityUpdates': prefs.communityUpdates,
          'lockScreenAlerts': prefs.lockScreenAlerts,
        },
      });
      _log('Prefs synced to Firestore');
    } catch (e) {
      _log('Prefs sync error: $e');
    }
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[PushNotificationService] $msg');
  }
}
