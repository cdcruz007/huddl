// Firebase Test Lab — Main Test Runner
// Entry point for all instrumentation tests.
// Upload this APK alongside app-debug.apk to Firebase Test Lab.

import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tests/auth_test.dart' as auth_test;
import 'tests/navigation_test.dart' as navigation_test;
import 'tests/groups_test.dart' as groups_test;
import 'tests/chat_test.dart' as chat_test;
import 'tests/voice_message_test.dart' as voice_test;
import 'tests/events_test.dart' as events_test;
import 'tests/marketplace_test.dart' as marketplace_test;
import 'tests/profile_test.dart' as profile_test;
import 'tests/performance_test.dart' as performance_test;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Huddl — Full Integration Test Suite', () {
    auth_test.main();
    navigation_test.main();
    groups_test.main();
    chat_test.main();
    voice_test.main();
    events_test.main();
    marketplace_test.main();
    profile_test.main();
    performance_test.main();
  });
}
