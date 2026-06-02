// ============================================================
// Firebase Test Lab — Main Test Runner  v33
// Entry point for ALL instrumentation tests.
// Upload this APK alongside app-debug.apk to Firebase Test Lab.
//
// Coverage:
//   Existing: auth, navigation, home, groups, chat, voice,
//             events, marketplace, profile, subscription, performance
//   QA Workflows A–H (new):
//     A — Audio & AI Pipeline      (mock_channels platform mocks)
//     B — Chat & Threading
//     C — Data Persistence & Save
//     D — OS Permissions
//     E — Marketplace
//     F — Geolocation / Nearby
//     G — Groups, Services & Polls
//     H — SEND Hub
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

// QA Hardening — Workflows A–H
import 'tests/workflow_a_audio_ai_test.dart'             as wf_a;
import 'tests/workflow_b_chat_threading_test.dart'        as wf_b;
import 'tests/workflow_c_data_persistence_test.dart'      as wf_c;
import 'tests/workflow_d_permissions_test.dart'           as wf_d;
import 'tests/workflow_e_marketplace_test.dart'           as wf_e;
import 'tests/workflow_f_geolocation_test.dart'           as wf_f;
import 'tests/workflow_g_groups_services_polls_test.dart' as wf_g;
import 'tests/workflow_h_send_hub_test.dart'              as wf_h;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Huddl — Full Integration Test Suite v33', () {
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

    // ── QA Hardening Workflows A–H ────────────────────────────────────────
    // A. Audio & AI Pipeline (voice record/play, Gemini copilot)
    wf_a.main();

    // B. Chat & Threading (send states, thread reply, DM)
    wf_b.main();

    // C. Data Persistence & Save/Bookmark (listing saves, preferences)
    wf_c.main();

    // D. OS Permissions (mic, location, notification — grant/deny/permanent)
    wf_d.main();

    // E. Marketplace (browse, create listing, image picker, saves)
    wf_e.main();

    // F. Geolocation / Nearby (GPS mock, borough scope, permission denied)
    wf_f.main();

    // G. Groups, Services & Polls (join, directory, filter, polls)
    wf_g.main();

    // H. SEND Hub (age filter, category filter, preferences, security)
    wf_h.main();
  });
}
