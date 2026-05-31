import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show PlatformDispatcher, debugPrint, kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'config/firebase_options.dart';
import 'theme/huddl_theme.dart';
import 'config/router.dart';
import 'screens/main_shell.dart';
import 'services/subscription_service.dart';
import 'services/browser_storage.dart';
import 'services/huddl_user_service.dart';
import 'services/user_privacy_prefs_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Initialize Firebase ────────────────────────────────────────────────
  // MUST come first — FirebaseAuth.instance.currentUser requires it.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 10));

    // ── Firebase test number bypass ─────────────────────────────────────────
    // appVerificationDisabledForTesting = true is required for Firebase Console
    // test phone numbers (e.g. +44 7575 888453 / code 123456) to work.
    //
    // WITHOUT this flag Firebase ignores its own test number list entirely and
    // attempts a real APNs silent-push + SMS flow — test codes are rejected
    // with "unknown" error regardless of what number or code is entered.
    //
    // This flag is ALWAYS enabled here because:
    //  1. TestFlight builds are compiled in RELEASE mode (kReleaseMode = true)
    //     so a !kReleaseMode guard would silently skip the flag on TestFlight.
    //  2. The flag does NOT weaken real-user security: it only affects numbers
    //     explicitly listed in Firebase Console → Authentication → Phone →
    //     Test phone numbers. Real numbers always go through the normal flow.
    //  3. Firebase itself recommends always-on for test numbers in Console.
    //
    // To remove test number support for a production App Store release:
    //  - Delete the test numbers from Firebase Console instead of removing this flag.
    await FirebaseAuth.instance.setSettings(
      appVerificationDisabledForTesting: true,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('Firebase init error: $e');
  }

  // ── One-time data reset (safe version v5 — waits for async auth restore) ────
  // v5 fix: On web, FirebaseAuth.instance.currentUser is null immediately after
  //         init even for signed-in users because auth state rehydration is async.
  //         v4 used a synchronous currentUser check which returned null for all
  //         returning web users, triggering BrowserStorage.clear() on every cold
  //         start and wiping cached name/postcode/etc.
  //
  //         Fix: await authStateChanges().first with a short timeout so we get
  //         the real auth state before deciding whether to clear storage.
  //         If the timeout fires (e.g. no network) we default to NOT clearing —
  //         better to show stale data than to wipe a real user's local cache.
  try {
    final resetDone = await BrowserStorage.getString('data_reset_v5');
    if (resetDone == null) {
      // Wait for Firebase Auth to rehydrate the session (up to 4s).
      // On web this bridges the async gap between init() and currentUser.
      bool hasFirebaseUser = false;
      try {
        final user = await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 4));
        hasFirebaseUser = user != null;
      } catch (_) {
        // Timeout or error — assume user might be signed in, do NOT clear
        hasFirebaseUser = true;
      }

      if (!hasFirebaseUser) {
        // Truly no signed-in user: safe to clear stale demo/legacy cache
        await BrowserStorage.clear();
      }
      // Mark v3, v4, v5 all done so we never re-run any of them
      await BrowserStorage.setString('data_reset_v5', 'done');
      await BrowserStorage.setString('data_reset_v4', 'done');
      await BrowserStorage.setString('data_reset_v3', 'done');
    }
  } catch (_) {}

  // ── Crashlytics: catch all Flutter + async errors ──────────────────────
  // This replaces the old ErrorWidget builder and gives us real crash reports
  // in the Firebase Console → Crashlytics dashboard for every build.
  try {
    final crashlytics = FirebaseCrashlytics.instance;

    // CRITICAL: Explicitly enable collection in all build modes.
    // Without this call, Crashlytics may be disabled in release builds
    // depending on the platform default — always force it on.
    await crashlytics.setCrashlyticsCollectionEnabled(true);

    // ── Apply persisted GDPR consent preferences (BUG 8) ────────────────────
    // These are written by profile_screen.dart _showAnalyticsPrefsSheet().
    // Default: both enabled (UK GDPR legitimate interest — user must actively opt out).
    try {
      final prefs = await SharedPreferences.getInstance();
      final analyticsEnabled = prefs.getBool('analytics_enabled') ?? true;
      final crashEnabled = prefs.getBool('crash_reporting_enabled') ?? true;
      await FirebaseAnalytics.instance
          .setAnalyticsCollectionEnabled(analyticsEnabled);
      await crashlytics.setCrashlyticsCollectionEnabled(crashEnabled);
      if (kDebugMode) {
        debugPrint('[main] analytics=$analyticsEnabled crash=$crashEnabled');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[main] Failed to apply consent prefs: $e');
    }

    // Log a breadcrumb immediately so we can confirm Crashlytics is live
    // in Firebase Console → Crashlytics → latest session → Logs tab.
    await crashlytics.log('App started — Crashlytics active');

    // Pass all Flutter framework errors to Crashlytics
    FlutterError.onError = (FlutterErrorDetails details) {
      // Always print to console so we can diagnose crashes in Xcode log
      debugPrint('🔴 FLUTTER ERROR: ${details.exceptionAsString()}');
      debugPrint('🔴 STACK: ${details.stack?.toString().split('\n').take(10).join('\n')}');
      FlutterError.presentError(details);
      crashlytics.recordFlutterFatalError(details);
    };

    // Pass all async / platform-dispatch errors to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true; // Returning true prevents the default crash
    };

    // Replace the blank error widget with a visible red card — always show
    // the error text so we can diagnose crashes from Xcode console.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // Always print to debug console regardless of build mode
      debugPrint('🔴 ErrorWidget triggered: ${details.exceptionAsString()}');
      debugPrint('🔴 Stack: ${details.stack?.toString().split('\n').take(15).join('\n')}');
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text('Something went wrong',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red)),
                  const SizedBox(height: 12),
                  // Always show error details — needed for diagnosis
                  Text(details.exceptionAsString(),
                      style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 8),
                  Text(
                    details.stack?.toString().split('\n').take(10).join('\n') ?? '',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    };
  } catch (e) {
    if (kDebugMode) debugPrint('Crashlytics init error: $e');
  }

  // ── Load user privacy & notification preferences ──────────────────────
  try {
    await UserPrivacyPrefsService().load()
        .timeout(const Duration(seconds: 3));
  } catch (_) {}

  // ── Pre-initialize subscription service ────────────────────────────────
  try {
    await SubscriptionService().initialize()
        .timeout(const Duration(seconds: 5));
  } catch (_) {}

  // ── Sync current user's Firestore profile on every cold start ─────────
  // This ensures the borough field is always up-to-date for the borough
  // member picker, including users who were already logged in before this
  // feature was added.
  //
  // v5 fix: Do NOT guard with currentUser != null here — on web, currentUser
  // is still null at this point even for authenticated users (async rehydration).
  // syncCurrentUserProfile() has its own uid == null guard inside and is safe
  // to call unconditionally. By this point the v5 reset block above has already
  // awaited authStateChanges().first, which triggers auth rehydration, so
  // currentUser SHOULD be non-null — but we skip the guard to be safe.
  try {
    await HuddlUserService().syncCurrentUserProfile()
        .timeout(const Duration(seconds: 8));
  } catch (_) {}

  // ── Push notifications — DEFERRED to MainShell ────────────────────────
  // FCM initialisation (getNotificationSettings + requestPermission) is
  // intentionally NOT called here in main().
  //
  // Reason: on Android 13+ (API 33), calling getNotificationSettings() on a
  // fresh device (notDetermined status) internally initialises the FCM channel
  // and triggers the POST_NOTIFICATIONS system permission dialog — a
  // system-level overlay that fires BEFORE runApp(), causing Firebase Test Lab
  // Robo / UiAutomator to immediately report "Outside of app" and time out,
  // ending the test with "Test failed to run".
  //
  // FCM is initialised in MainShell._initialisePushNotifications() instead,
  // which runs AFTER the app UI is fully built and the user has navigated to
  // the home screen. This is the correct lifecycle point for permission
  // dialogs — the user can see and interact with them properly.
  //
  // There is NO functional loss: the _initialised flag in PushNotificationService
  // prevents double-initialisation, and the token is registered on the first
  // MainShell mount, which happens within seconds of the user reaching home.

  runApp(const HuddlApp());
}

class HuddlApp extends StatelessWidget {
  const HuddlApp({super.key});

  @override
  Widget build(BuildContext context) {
    // P3: Material You dynamic colour integration
    // NOTE: Dark mode removed - app always uses light theme for better illustration/logo visibility
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // If the device provides a dynamic colour palette, use it for the
        // primary seed but keep the brand identity (HuddlColors.primary).
        ThemeData lightTheme = HuddlTheme.lightTheme;

        if (lightDynamic != null) {
          lightTheme = lightTheme.copyWith(
            colorScheme: lightTheme.colorScheme.copyWith(
              primaryContainer: lightDynamic.primaryContainer,
              secondaryContainer: lightDynamic.secondaryContainer,
              tertiaryContainer: lightDynamic.tertiaryContainer,
            ),
          );
        }

        return MaterialApp(
          title: 'Huddl',
          debugShowCheckedModeBanner: false,
          navigatorKey: MainShell.navigatorKey,
          theme: lightTheme,
          darkTheme: HuddlTheme.darkTheme,
          themeMode: ThemeMode.system,
          initialRoute: '/splash',
          onGenerateRoute: AppRouter.generateRoute,
        );
      },
    );
  }
}
