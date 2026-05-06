// ============================================================
// Firebase Test Lab — Main Test Runner  v32
// Entry point for ALL instrumentation tests.
// Upload this APK alongside app-debug.apk to Firebase Test Lab.
// Coverage: auth, navigation, home, groups, chat, voice,
//           events, marketplace, profile, subscription,
//           performance.
// ============================================================

import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tests/auth_test.dart'         as auth_test;
import 'tests/navigation_test.dart'   as navigation_test;
import 'tests/home_test.dart'         as home_test;
import 'tests/groups_test.dart'       as groups_test;
import 'tests/chat_test.dart'         as chat_test;
import 'tests/voice_message_test.dart' as voice_test;
import 'tests/events_test.dart'       as events_test;
import 'tests/marketplace_test.dart'  as marketplace_test;
import 'tests/profile_test.dart'      as profile_test;
import 'tests/subscription_test.dart' as subscription_test;
import 'tests/performance_test.dart'  as performance_test;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Huddl — Full Integration Test Suite v32', () {
    // 1. Authentication (splash → onboarding → login → OTP → biometric)
    auth_test.main();

    // 2. Navigation (tab switching, back nav, persistence)
    navigation_test.main();

    // 3. Home (feed, composer, search, AI copilot, post actions)
    home_test.main();

    // 4. Groups / Connect (list, search, swipe, create, filter, AI)
    groups_test.main();

    // 5. Chat (group chat, DM, reactions, thread, polls, saved)
    chat_test.main();

    // 6. Voice messages (record, playback, waveform, layout)
    voice_test.main();

    // 7. Events / Discover (meetups, events, going, filters, bookmark)
    events_test.main();

    // 8. Marketplace (buy/sell/saved, create, filters, offers, delist)
    marketplace_test.main();

    // 9. Profile (view, edit, settings, My Groups/Meetups/Listings)
    profile_test.main();

    // 10. Subscriptions (plans, billing toggle, paywall gates)
    subscription_test.main();

    // 11. Performance (cold start, scroll, tab switch timing)
    performance_test.main();
  });
}
