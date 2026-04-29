import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show PlatformDispatcher, debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'config/firebase_options.dart';
import 'theme/huddl_theme.dart';
import 'config/router.dart';
import 'services/subscription_service.dart';
import 'services/browser_storage.dart';
import 'services/huddl_user_service.dart';
import 'services/push_notification_service.dart';
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
    // test phone numbers (e.g. +44 7575 888452 / code 123456) to work.
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
    debugPrint('Firebase init error: $e');
  }

  // ── One-time data reset (safe version — runs AFTER Firebase init) ─────────
  // v4: Only clears BrowserStorage when no Firebase Auth session is active.
  //     The old v3 reset ran unconditionally and cleared SharedPreferences for
  //     returning signed-in users, wiping cached name/postcode/etc. on install.
  //     That empty local data was then pushed back to Firestore by
  //     syncCurrentUserProfile(), overwriting real profile data with blanks.
  try {
    final resetDone = await BrowserStorage.getString('data_reset_v4');
    if (resetDone == null) {
      // Firebase is now initialized — we can safely check current user
      final hasFirebaseUser = FirebaseAuth.instance.currentUser != null;
      if (!hasFirebaseUser) {
        // No signed-in user: safe to clear stale demo/legacy cache
        await BrowserStorage.clear();
      }
      // Mark both v3 and v4 done regardless of whether we cleared
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
    debugPrint('Crashlytics init error: $e');
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
  try {
    if (FirebaseAuth.instance.currentUser != null) {
      await HuddlUserService().syncCurrentUserProfile()
          .timeout(const Duration(seconds: 5));
    }
  } catch (_) {}

  // ── Push notifications — initialise FCM and register token ────────────
  // Must run AFTER Firebase init. Safe to call when no user is signed in
  // (the service skips token registration until a UID is available).
  try {
    if (FirebaseAuth.instance.currentUser != null) {
      // Returning user — initialise FCM immediately
      unawaited(
        PushNotificationService().initialise()
            .timeout(const Duration(seconds: 10)),
      );
    }
  } catch (_) {}

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
          theme: lightTheme,
          // Dark theme removed - always use light mode
          themeMode: ThemeMode.light,
          initialRoute: '/splash',
          onGenerateRoute: AppRouter.generateRoute,
        );
      },
    );
  }
}
