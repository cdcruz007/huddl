// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — PUSH NOTIFICATION SERVICE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Responsibilities
//   1. Request permission (iOS prompt + Android 13+ POST_NOTIFICATIONS)
//   2. Acquire the FCM registration token and register it with the backend
//   3. Refresh the token when FCM rotates it
//   4. Handle foreground messages → in-app OverlayEntry banner (main_shell.dart).
//      flutter_local_notifications is present but used ONLY for Android channel
//      creation at startup (ANDROID-CHANNEL-MISSING-1), NOT for foreground display.
//   5. Handle notification taps (background / terminated → navigate to correct screen)
//
// HOW TO USE
//   Call `PushNotificationService().initialise(context)` once after login.
//   Call `PushNotificationService().dispose()` on logout.
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'backend_api_service.dart';
import 'user_privacy_prefs_service.dart';
import 'notification_copy_service.dart';

// ── Top-level background handler (must be a top-level / static function) ──────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs on Android.
  // We only need to ensure we don't crash — actual UI work happens on resume.
  if (kDebugMode) {
    debugPrint('[FCM-BG] ${message.notification?.title}: ${message.notification?.body}');
  }
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

  // ANDROID-CHANNEL-MISSING-1: Used solely to call createNotificationChannel().
  // We do NOT use flutter_local_notifications for foreground display — that is
  // handled by the OverlayEntry banner in main_shell.dart, verified working
  // 26 Aug 2026 (tests A1/A5/B1 passed). This plugin instance exists only to
  // register the Android OS channel entries at startup.
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;

  // ── Foreground message callback ───────────────────────────────────────────
  // Set by the app shell so it can display an in-app banner.
  void Function(RemoteMessage message)? onForegroundMessage;

  // ── Notification tap callback ─────────────────────────────────────────────
  // Called when the user taps a notification while the app is
  // in the background or foreground — use to navigate to the right screen.
  void Function(RemoteMessage message)? onNotificationTap;

  // ── Navigator key for deep-link routing ──────────────────────────────────
  // Set this after the app shell mounts so NotificationCopyService.handleTap()
  // can push named routes directly, without needing a BuildContext.
  GlobalKey<NavigatorState>? navigatorKey;

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

      // ── 1b. Create Android notification channels ───────────────────────────
      // ANDROID-CHANNEL-MISSING-1: Must run BEFORE requestPermission() so the
      // channels exist from the moment the first push can arrive. Failures are
      // non-fatal — wrapped in try/catch with Crashlytics logging so a bad
      // channel-creation call never blocks token registration.
      await _createAndroidChannels();

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
        _dispatchTap(message);
      });

      // ── 8. Terminated → opened tap ────────────────────────────────────────
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _log('App opened from terminated by notification');
        _dispatchTap(initialMessage);
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

  // Tap dispatch — routes via NotificationCopyService when a navigator key
  // is registered, otherwise falls back to onNotificationTap.
  void _dispatchTap(RemoteMessage message) {
    final key = navigatorKey;
    if (key != null && key.currentState != null) {
      // NotificationCopyService handles all 9 payload types with typed routing.
      NotificationCopyService.handleTap(message, key);
    } else {
      // Fall back to the shell handler during early startup (navigator not yet mounted).
      onNotificationTap?.call(message);
    }
  }

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

  // ─────────────────────────────────────────────────────────────────────────
  // ANDROID-CHANNEL-MISSING-1: Create notification channels
  // ─────────────────────────────────────────────────────────────────────────

  /// Registers the two Huddl notification channels with the Android OS.
  ///
  /// On Android 8+ (API 26+) a notification whose [channelId] does not match
  /// a registered channel is **silently dropped** by the OS — FCM returns
  /// success, the backend logs success, and the device shows nothing.
  ///
  /// Two channels are created because:
  ///   - The backend targets 'huddl_messages' in its FCM android.notification block.
  ///   - 'huddl_system_alerts' is registered as belt-and-braces for any push
  ///     that omits channelId. The manifest default is now 'huddl_messages'
  ///     (changed as part of ANDROID-CHANNEL-MISSING-1), so this channel is
  ///     no longer the active fallback, but must still exist to avoid drops.
  /// Both must exist so neither path can silently drop.
  ///
  /// iOS is explicitly guarded out — iOS has no channel concept and the
  /// flutter_local_notifications calls are no-ops there, but the guard makes
  /// the intent clear and avoids any future platform-specific side-effects.
  Future<void> _createAndroidChannels() async {
    if (!Platform.isAndroid) return;
    try {
      // '@mipmap/ic_launcher' is the only notification-compatible drawable
      // that exists in this project. There is NO ic_notification resource —
      // using that name makes initialize() throw, the catch swallows it, and
      // NO channels are created (the exact defect in commit 4b2884af).
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      final bool? initOk = await _localNotifications.initialize(initSettings);
      if (initOk != true) {
        throw StateError(
          'FlutterLocalNotificationsPlugin.initialize() returned $initOk — '
          'Android notification channels cannot be created. '
          'Push notifications will be silently dropped by the OS.',
        );
      }

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin == null) {
        // Throwing rather than returning ensures the failure is visible in
        // Crashlytics. A silent return is what hid this defect previously.
        throw StateError(
          'AndroidFlutterLocalNotificationsPlugin is null on an Android device — '
          'channels cannot be created and push notifications will be silently dropped.',
        );
      }

      // Channel 1 — the channel the backend explicitly targets.
      // Importance.high is REQUIRED for heads-up banners and lock-screen alerts.
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'huddl_messages',
          'Messages',
          description: 'Direct messages and group messages from other parents',
          importance: Importance.high,
          playSound: true,
        ),
      );

      // Channel 2 — fallback for any push that omits an explicit channelId.
      // NOTE: the manifest default is now 'huddl_messages' (changed as part of
      // this fix), so this is belt-and-braces rather than the active default.
      // Importance.defaultImportance: shade delivery, no heads-up banner —
      // appropriate for non-urgent system/account notifications.
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'huddl_system_alerts',
          'Huddl Updates',
          description: 'Account, safety and app updates from Huddl',
          importance: Importance.defaultImportance,
          playSound: true,
        ),
      );

      _log('✅ Android notification channels created (huddl_messages, huddl_system_alerts)');
    } catch (e, stackTrace) {
      // Non-fatal: log to Crashlytics and continue. A channel-creation failure
      // must not prevent FCM token registration or the rest of initialise().
      FirebaseCrashlytics.instance.recordError(
        e,
        stackTrace,
        reason: 'ANDROID-CHANNEL-MISSING-1 channel creation failed',
        fatal: false,
      );
      _log('❌ Android channel creation failed — push will NOT display: $e');
    }
  }

  void _log(String msg) {
    if (kDebugMode) {
      if (kDebugMode) debugPrint('[PushNotificationService] $msg');
    }
  }
}
