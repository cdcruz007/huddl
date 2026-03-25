import 'package:flutter/material.dart';
import 'theme/huddl_theme.dart';
import 'screens/auth/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HuddlApp());
}

class HuddlApp extends StatelessWidget {
  const HuddlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'huddl',
      debugShowCheckedModeBanner: false,
      theme: HuddlTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
