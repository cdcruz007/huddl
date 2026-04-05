import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/firebase_options.dart';
import 'theme/huddl_theme.dart';
import 'config/router.dart';
import 'services/subscription_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  await SubscriptionService().initialize();
  runApp(const HuddlApp());
}

class HuddlApp extends StatelessWidget {
  const HuddlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Huddl',
      debugShowCheckedModeBanner: false,
      theme: HuddlTheme.lightTheme,
      initialRoute: '/splash',
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
