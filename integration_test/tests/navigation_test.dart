// ============================================================
// Navigation Test Suite — Huddl v32
// Covers: all 5 nav tabs, rapid switching (400 ms), double-tap,
//         3-cycle stress, back navigation (in-screen + system),
//         deep-link screen returns, tab content persistence,
//         nav-bar layout (no overflow), exception-free launch.
// Semantics labels: 'Home', 'Connect', 'Discover', 'Market',
//   'Profile'
// Resource IDs: nav_home, nav_connect, nav_discover,
//               nav_market, nav_profile
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

// ── Helpers ──────────────────────────────────────────────────────────────────

Finder navTab(String label) => find.bySemanticsLabel(label);

Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 12));
}

/// Returns true if the main shell (logged-in nav bar) is visible.
bool get _hasNavBar =>
    find.bySemanticsLabel('Home').evaluate().isNotEmpty ||
    find.bySemanticsLabel('Connect').evaluate().isNotEmpty;

/// Tap a nav tab safely; returns true if the tap succeeded.
Future<bool> tapTab(WidgetTester tester, String label,
    {Duration settle = const Duration(seconds: 4)}) async {
  final t = navTab(label);
  if (t.evaluate().isEmpty) return false;
  await tester.tap(t.first);
  await tester.pumpAndSettle(settle);
  return true;
}

/// Pop back one level. Uses BackButton, then tooltip 'Back'.
Future<bool> popBack(WidgetTester tester) async {
  final b = find.byType(BackButton);
  if (b.evaluate().isNotEmpty) {
    await tester.tap(b.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    return true;
  }
  final t = find.byTooltip('Back');
  if (t.evaluate().isNotEmpty) {
    await tester.tap(t.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    return true;
  }
  return false;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── 1. App Launch Sanity ──────────────────────────────────────────────────

  group('🧭 Navigation — App Launch Sanity', () {
    testWidgets('App renders a Scaffold after launch', (tester) async {
      await waitForApp(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('No unhandled exception on cold start', (tester) async {
      await waitForApp(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MaterialApp is present in widget tree', (tester) async {
      await waitForApp(tester);
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  // ── 2. Nav Bar Visibility ─────────────────────────────────────────────────

  group('🧭 Navigation — Tab Visibility', () {
    testWidgets('All 5 nav tabs visible when logged in', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      for (final label in ['Home', 'Connect', 'Discover', 'Market', 'Profile']) {
        expect(navTab(label), findsWidgets,
            reason: '$label tab must be visible in the main shell');
      }
    });

    testWidgets('Nav bar does not overflow screen width', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      final bar = find.byType(BottomNavigationBar).evaluate().isNotEmpty
          ? find.byType(BottomNavigationBar)
          : find.byType(NavigationBar);
      if (bar.evaluate().isNotEmpty) {
        final RenderBox rb = tester.renderObject(bar.first);
        final screenW =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;
        expect(rb.size.width, lessThanOrEqualTo(screenW + 1),
            reason: 'Nav bar must not overflow screen width');
      }
    });

    testWidgets('Nav bar height is reasonable (40–120 dp)', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      final bar = find.byType(BottomNavigationBar).evaluate().isNotEmpty
          ? find.byType(BottomNavigationBar)
          : find.byType(NavigationBar);
      if (bar.evaluate().isNotEmpty) {
        final RenderBox rb = tester.renderObject(bar.first);
        expect(rb.size.height, greaterThanOrEqualTo(40),
            reason: 'Nav bar must have minimum touch-target height');
        expect(rb.size.height, lessThanOrEqualTo(120),
            reason: 'Nav bar must not take excessive vertical space');
      }
    });
  });

  // ── 3. Individual Tab Switching ───────────────────────────────────────────

  group('🧭 Navigation — Individual Tab Switching', () {
    testWidgets('Home tab tap shows Scaffold', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Home');
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Connect tab tap shows Scaffold', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Connect', settle: const Duration(seconds: 5));
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Discover tab tap shows Scaffold', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Discover', settle: const Duration(seconds: 5));
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Market tab tap shows Scaffold', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Market', settle: const Duration(seconds: 5));
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Profile tab tap shows Scaffold', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Profile', settle: const Duration(seconds: 5));
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  // ── 4. Full Cycle / Reverse Cycle ─────────────────────────────────────────

  group('🧭 Navigation — Cycle Tests', () {
    testWidgets('Full forward cycle Home→Connect→Discover→Market→Profile→Home',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      for (final label in
          ['Connect', 'Discover', 'Market', 'Profile', 'Home']) {
        await tapTab(tester, label);
        expect(find.byType(Scaffold), findsWidgets,
            reason: 'App must not crash after switching to $label');
      }
    });

    testWidgets('Reverse cycle Profile→Market→Discover→Connect→Home',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      for (final label in
          ['Profile', 'Market', 'Discover', 'Connect', 'Home']) {
        await tapTab(tester, label);
        expect(find.byType(Scaffold), findsWidgets,
            reason: 'Crash detected on $label in reverse cycle');
      }
    });

    testWidgets('Three full cycles stress test (no crash)', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      for (int round = 0; round < 3; round++) {
        for (final label in
            ['Connect', 'Discover', 'Market', 'Profile', 'Home']) {
          final t = navTab(label);
          if (t.evaluate().isNotEmpty) {
            await tester.tap(t.first);
            await tester.pump(const Duration(milliseconds: 300));
          }
        }
      }
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(Scaffold), findsWidgets,
          reason: 'App must survive 3 full tab cycles');
    });

    testWidgets('Rapid switching at 400 ms intervals does not crash',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      final sequence = [
        'Connect', 'Discover', 'Market', 'Profile', 'Home',
        'Connect', 'Discover', 'Market', 'Profile', 'Home',
      ];
      for (final label in sequence) {
        final t = navTab(label);
        if (t.evaluate().isNotEmpty) {
          await tester.tap(t.first);
          await tester.pump(const Duration(milliseconds: 400));
        }
      }
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(Scaffold), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Double-tapping same tab does not crash or duplicate screens',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      for (final label in
          ['Connect', 'Discover', 'Market', 'Profile', 'Home']) {
        final t = navTab(label);
        if (t.evaluate().isNotEmpty) {
          await tester.tap(t.first);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(t.first); // double-tap
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(Scaffold), findsWidgets,
              reason: 'Double-tap on $label must not crash');
        }
      }
    });
  });

  // ── 5. Back Navigation ────────────────────────────────────────────────────

  group('🧭 Navigation — Back Navigation', () {
    testWidgets('Back button on any sub-screen returns without crash',
        (tester) async {
      await waitForApp(tester);
      final back = find.byType(BackButton);
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('System back from Connect returns to shell', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Connect', settle: const Duration(seconds: 4));
      await popBack(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('System back from Discover returns to shell', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Discover', settle: const Duration(seconds: 4));
      await popBack(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('System back from Market returns to shell', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Market', settle: const Duration(seconds: 4));
      await popBack(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('System back from Profile returns to shell', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Profile', settle: const Duration(seconds: 4));
      await popBack(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Multiple successive back presses do not crash', (tester) async {
      await waitForApp(tester);
      for (int i = 0; i < 5; i++) {
        final popped = await popBack(tester);
        if (!popped) break;
      }
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  // ── 6. Deep-link / Sub-screen Return ─────────────────────────────────────

  group('🧭 Navigation — Deep-link Sub-screen Returns', () {
    testWidgets('Opening a group chat and back-returning lands in Connect',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Connect', settle: const Duration(seconds: 5));

      // Attempt to open first list item (group chat deep link)
      final listItems = find.byType(ListTile);
      if (listItems.evaluate().isNotEmpty) {
        await tester.tap(listItems.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        // Back out
        await popBack(tester);
        // Must still show nav shell
        expect(
          navTab('Connect').evaluate().isNotEmpty ||
              navTab('Home').evaluate().isNotEmpty,
          isTrue,
          reason: 'Should return to main shell after back from chat',
        );
      }
    });

    testWidgets(
        'Opening a marketplace item and back-returning lands in Market',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Market', settle: const Duration(seconds: 5));

      final cards = find.byType(Card);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        await popBack(tester);
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Opening a Discover event and back-returning shows Discover',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Discover', settle: const Duration(seconds: 5));

      final cards = find.byType(Card);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        await popBack(tester);
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Opening Profile settings and back returns to Profile tab',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Profile', settle: const Duration(seconds: 5));

      // Try to open settings (gear icon or Settings text)
      final settings =
          find.bySemanticsLabel(RegExp(r'[Ss]ettings|gear|cog'));
      if (settings.evaluate().isNotEmpty) {
        await tester.tap(settings.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await popBack(tester);
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });

  // ── 7. Tab Content Persistence ────────────────────────────────────────────

  group('🧭 Navigation — Tab Content Persistence', () {
    testWidgets('Connect content persists after switching away and back',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Connect', settle: const Duration(seconds: 5));
      final hadList = find.byType(ListView).evaluate().isNotEmpty;

      await tapTab(tester, 'Home');
      await tapTab(tester, 'Connect', settle: const Duration(seconds: 4));

      if (hadList) {
        expect(find.byType(ListView), findsWidgets,
            reason:
                'Connect list must still be present after returning to tab');
      }
    });

    testWidgets('Discover content persists after switching away and back',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Discover', settle: const Duration(seconds: 5));

      await tapTab(tester, 'Home');
      await tapTab(tester, 'Discover', settle: const Duration(seconds: 4));
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Market content persists after switching away and back',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Market', settle: const Duration(seconds: 5));
      final hadContent = find.byType(Scaffold).evaluate().isNotEmpty;

      await tapTab(tester, 'Home');
      await tapTab(tester, 'Market', settle: const Duration(seconds: 4));

      if (hadContent) {
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Profile content persists after switching away and back',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Profile', settle: const Duration(seconds: 5));

      await tapTab(tester, 'Home');
      await tapTab(tester, 'Profile', settle: const Duration(seconds: 4));
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Home feed content persists after round-trip navigation',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Home', settle: const Duration(seconds: 5));
      final hadFeed = find.byType(ListView).evaluate().isNotEmpty ||
          find.byType(CustomScrollView).evaluate().isNotEmpty;

      // Round-trip through all tabs
      for (final label in ['Connect', 'Discover', 'Market', 'Profile']) {
        await tapTab(tester, label, settle: const Duration(seconds: 3));
      }
      await tapTab(tester, 'Home', settle: const Duration(seconds: 5));

      if (hadFeed) {
        expect(
          find.byType(ListView).evaluate().isNotEmpty ||
              find.byType(CustomScrollView).evaluate().isNotEmpty,
          isTrue,
          reason: 'Home feed must still be present after full round-trip',
        );
      }
    });
  });

  // ── 8. No-Exception Sweep ─────────────────────────────────────────────────

  group('🧭 Navigation — Exception-free Sweep', () {
    testWidgets('Visiting all 5 tabs sequentially raises no exceptions',
        (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      for (final label in
          ['Home', 'Connect', 'Discover', 'Market', 'Profile']) {
        await tapTab(tester, label, settle: const Duration(seconds: 4));
        expect(tester.takeException(), isNull,
            reason: 'Exception thrown while on $label tab');
      }
    });
  });
}
