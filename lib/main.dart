import 'package:flutter/material.dart';
import 'theme/huddl_theme.dart';
import 'config/router.dart';
import 'services/subscription_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
