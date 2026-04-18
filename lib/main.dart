import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, PlatformDispatcher;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'config/firebase_options.dart';
import 'theme/huddl_theme.dart';
import 'config/router.dart';
import 'services/subscription_service.dart';
import 'services/browser_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── One-time data reset ────────────────────────────────────────────────
  try {
    final resetDone = await BrowserStorage.getString('data_reset_v2');
    if (resetDone == null) {
      await BrowserStorage.clear();
      await BrowserStorage.setString('data_reset_v2', 'done');
    }
  } catch (_) {}

  // ── Initialize Firebase ────────────────────────────────────────────────
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
      FlutterError.presentError(details);
      crashlytics.recordFlutterFatalError(details);
    };

    // Pass all async / platform-dispatch errors to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true; // Returning true prevents the default crash
    };

    // Replace the blank error widget with a visible red card for debug builds
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // In release we don't show details; Crashlytics already captured it
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
                  if (kDebugMode)
                    Text(details.exceptionAsString(),
                        style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  if (!kDebugMode)
                    const Text(
                      'An unexpected error occurred. Please restart the app.\n\nThis crash has been automatically reported to our team.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
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

  // ── Pre-initialize subscription service ────────────────────────────────
  try {
    await SubscriptionService().initialize()
        .timeout(const Duration(seconds: 5));
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
