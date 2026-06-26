import 'package:flutter/material.dart';
import './theme/huddl_icons.dart';
import 'package:flutter/foundation.dart' show PlatformDispatcher, debugPrint, kDebugMode, kIsWeb;
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
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
import 'services/firebase_auth_service.dart';

/// True only when the app is built with --dart-define=QA_BUILD=true.
/// Use this for QA / TestFlight builds that need Firebase Console test phone
/// numbers. Public App Store / Play Store builds must NOT pass this flag —
/// it defaults to false so real users get full phone-number verification.
const bool kQaBuild = bool.fromEnvironment('QA_BUILD', defaultValue: false);

/// Returns the route to use as [MaterialApp.initialRoute].
///
/// On web, if the browser was opened at /privacy or /terms directly
/// (e.g. from an email link), we use that path so the user lands on the
/// correct public screen without being bounced through /splash auth logic.
/// All other starts — including every native-app cold start — use /splash.
String _resolveInitialRoute() {
  if (kIsWeb) {
    final path = Uri.base.path;
    if (path == '/privacy' || path == '/terms') return path;
  }
  return '/splash';
}

void main() async {
  // Path URL strategy MUST be called before WidgetsFlutterBinding.
  // This switches Flutter web from hash routing (/#/route) to path routing
  // (/route) so that cold hits from email links land on the correct route.
  // No new pub dependency — flutter_web_plugins is part of the Flutter SDK.
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  WidgetsFlutterBinding.ensureInitialized();

  // ── Initialize Firebase ────────────────────────────────────────────────
  // MUST come first — FirebaseAuth.instance.currentUser requires it.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 10));

    // ── Firebase test number bypass ─────────────────────────────────────────
    // appVerificationDisabledForTesting disables real APNs/SMS verification and
    // allows Firebase Console test phone numbers to work. It must be FALSE for
    // public store builds (real users) and TRUE only for QA / TestFlight builds.
    //
    // WHY NOT !kReleaseMode: TestFlight is compiled in release mode, so a
    // !kReleaseMode guard would silently leave the flag off on TestFlight and
    // break test-number sign-in there. A build-time flag is the correct gate.
    //
    // HOW TO USE:
    //  - QA / TestFlight build: pass --dart-define=QA_BUILD=true at build time.
    //    This sets kQaBuild=true → appVerificationDisabledForTesting=true →
    //    Firebase Console test numbers (e.g. +44 7575 888453 / 123456) work.
    //  - Public App Store / Play Store build: omit --dart-define=QA_BUILD
    //    (or pass QA_BUILD=false). kQaBuild defaults to false → full phone
    //    verification is active → real users are not affected.
    //
    // NOTE: enabling this flag also disables Firebase anti-abuse checks, so it
    // MUST NOT ship to production. The defaultValue: false ensures it does not.
    await FirebaseAuth.instance.setSettings(
      appVerificationDisabledForTesting: kQaBuild,
    );

    // ── Firebase App Check (APPCHECK-1) ────────────────────────────────────
    // Non-punitive until enforcement is turned ON in Firebase console.
    // Debug provider is used in debug builds (emits a debug token to console);
    // production builds use Play Integrity (Android) and App Attest with
    // DeviceCheck fallback (iOS). No webProvider — app is mobile-only.
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: kDebugMode
            ? AndroidProvider.debug
            : AndroidProvider.playIntegrity,
        appleProvider: kDebugMode
            ? AppleProvider.debug
            : AppleProvider.appAttestWithDeviceCheckFallback,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[AppCheck] activate failed: $e');
    }
  } catch (e) {
    if (kDebugMode) {
      if (kDebugMode) debugPrint('Firebase init error: $e');
    }
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
        if (kDebugMode) {
          debugPrint('[main] analytics=$analyticsEnabled crash=$crashEnabled');
        }
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
      if (kDebugMode) {
        debugPrint('🔴 FLUTTER ERROR: ${details.exceptionAsString()}');
      }
      if (kDebugMode) {
        debugPrint('🔴 STACK: ${details.stack?.toString().split('\n').take(10).join('\n')}');
      }
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
      if (kDebugMode) {
        debugPrint('🔴 ErrorWidget triggered: ${details.exceptionAsString()}');
      }
      if (kDebugMode) {
        debugPrint('🔴 Stack: ${details.stack?.toString().split('\n').take(15).join('\n')}');
      }
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(HuddlIcons.error, color: Colors.red, size: 48),
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
    if (kDebugMode) {
      if (kDebugMode) debugPrint('Crashlytics init error: $e');
    }
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
  // ORPHAN-GUARD-1: Only call syncCurrentUserProfile() when the signed-in
  // user has a COMPLETE, committed profile (isOnboarding==false AND
  // borough non-empty). Calling it for a half-provisioned Auth session
  // (orphan uid) triggers a Firestore set on users/{uid} that will be
  // PERMISSION_DENIED — the stale token has never cleared the auth gate
  // in Firestore rules (isOwner + birthYear/Month/Day is int checks).
  //
  // hasCompletedOnboarding() checks:
  //   • doc.exists (no Firestore doc → false)
  //   • isOnboarding == false (explicit false only — absent/true → false)
  //   • borough.isNotEmpty (null-borough = broken account → false)
  // Any of those failing → skip the sync so we never trigger a denied
  // write at startup. The splash router will then route the user to
  // /onboarding (or sign-out the orphan — see ORPHAN-DETECT-1 in splash).
  //
  // Timeout: 5 s for the Firestore probe, 8 s total safety net.
  // Fail OPEN (catch _): on network error we skip sync rather than block
  // startup — the sync will happen again on the next launch or after login.
  try {
    final profileComplete = await FirebaseAuthService()
        .hasCompletedOnboarding()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (profileComplete) {
      await HuddlUserService().syncCurrentUserProfile()
          .timeout(const Duration(seconds: 8));
    } else {
      if (kDebugMode) {
        debugPrint('[main] syncCurrentUserProfile skipped — profile not complete (orphan guard)');
      }
    }
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

  runApp(HuddlApp(initialRoute: _resolveInitialRoute()));
}

class HuddlApp extends StatelessWidget {
  const HuddlApp({super.key, this.initialRoute = '/splash'});

  final String initialRoute;

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
          initialRoute: initialRoute,
          onGenerateRoute: AppRouter.generateRoute,
        );
      },
    );
  }
}
