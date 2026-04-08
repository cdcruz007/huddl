import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'config/firebase_options.dart';
import 'theme/huddl_theme.dart';
import 'config/router.dart';
import 'services/subscription_service.dart';
import 'services/browser_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── One-time data reset for user 7575888452 ────────────────────────────
  // Clears all stale profile data, created groups, meetups, DMs, etc.
  // The flag ensures this only runs once per browser.
  try {
    final resetDone = await BrowserStorage.getString('data_reset_v2');
    if (resetDone == null) {
      await BrowserStorage.clear();
      await BrowserStorage.setString('data_reset_v2', 'done');
    }
  } catch (_) {
    // Ignore — app will still launch
  }

  // ── Global error handler ────────────────────────────────────────────────
  // Replace the default blank-screen error widget with a visible red error
  // card so we can always tell what broke instead of seeing grey/blank.
  ErrorWidget.builder = (FlutterErrorDetails details) {
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
                Text(details.exceptionAsString(),
                    style:
                        const TextStyle(fontSize: 13, color: Colors.black87)),
              ],
            ),
          ),
        ),
      ),
    );
  };

  // Initialize Firebase with platform-specific options
  // Use a timeout so the app always launches even if Firebase is slow
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 10));
  } catch (e) {
    // Firebase init failed or timed out — app will still launch
    // but Firebase features will be unavailable
    debugPrint('Firebase init error: $e');
  }

  // Pre-initialize subscription service for app-wide access
  try {
    await SubscriptionService().initialize()
        .timeout(const Duration(seconds: 5));
  } catch (_) {
    // Subscription init failed — app will still launch with default (explorer)
  }

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
