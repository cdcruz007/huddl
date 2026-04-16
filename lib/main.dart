import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, PlatformDispatcher, TargetPlatform, defaultTargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

    // Set appVerificationDisabledForTesting on iOS so Firebase skips the
    // APNs silent-push assertion for test phone numbers. This must be set
    // AFTER Firebase.initializeApp() completes. Safe for production: only
    // numbers listed in Firebase Console → Authentication → Test numbers
    // are affected; real numbers still go through normal SMS verification.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      FirebaseAuth.instance.setSettings(appVerificationDisabledForTesting: true);
    }
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // ── Crashlytics: catch all Flutter + async errors ──────────────────────
  // This replaces the old ErrorWidget builder and gives us real crash reports
  // in the Firebase Console → Crashlytics dashboard for every build.
  try {
    final crashlytics = FirebaseCrashlytics.instance;

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
