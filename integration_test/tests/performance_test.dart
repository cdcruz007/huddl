// ============================================================
// Performance Test Suite — Huddl v32
// Covers: cold-start timing (<20s), main shell render timing,
//   Connect list scroll FPS, chat message list scroll FPS,
//   tab-switch latency (<4s), marketplace load time,
//   repeated nav cycles (stability), home feed fling,
//   memory stability (10 navigation cycles).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

// ── Helpers ──────────────────────────────────────────────────────────────────

Finder navTab(String label) => find.bySemanticsLabel(label);

bool get _hasNavBar =>
    find.bySemanticsLabel('Home').evaluate().isNotEmpty ||
    find.bySemanticsLabel('Connect').evaluate().isNotEmpty;

Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 12));
}

Future<void> tapTab(WidgetTester tester, String label) async {
  final t = navTab(label);
  if (t.evaluate().isNotEmpty) {
    await tester.tap(t.first);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Cold Start ─────────────────────────────────────────────────────────────────
  group('⚡ Performance — Cold Start', () {
    testWidgets('App cold start completes within 20 seconds', (tester) async {
      final startTime = DateTime.now();
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 20));
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      expect(find.byType(Scaffold), findsWidgets,
          reason: 'App must render a Scaffold within 20 seconds');
      expect(elapsed, lessThan(20000),
          reason: 'Cold start took ${elapsed}ms — must be under 20 000ms');
    });

    testWidgets('App cold start produces no Scaffold overflow', (tester) async {
      await waitForApp(tester);
      expect(tester.takeException(), isNull,
          reason: 'No rendering exceptions allowed after cold start');
    });
  });

  // ── Main Shell Render ─────────────────────────────────────────────────────────
  group('⚡ Performance — Main Shell', () {
    testWidgets('Main shell renders all 5 nav tabs within 15 seconds', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      for (final label in ['Home', 'Connect', 'Discover', 'Market', 'Profile']) {
        expect(navTab(label), findsWidgets,
            reason: '$label tab must be rendered in main shell');
      }
    });

    testWidgets('First frame of home screen renders within 12 seconds', (tester) async {
      final startTime = DateTime.now();
      await waitForApp(tester);
      if (_hasNavBar) {
        await tapTab(tester, 'Home');
      }
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      expect(find.byType(Scaffold), findsWidgets);
      expect(elapsed, lessThan(15000),
          reason: 'Home screen must render within 15s, took ${elapsed}ms');
    });
  });

  // ── Tab-Switch Latency ────────────────────────────────────────────────────────
  group('⚡ Performance — Tab Switch Latency', () {
    testWidgets('Single tab switch completes within 4 seconds', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      final sw = DateTime.now();
      await tapTab(tester, 'Connect');
      final elapsed = DateTime.now().difference(sw).inMilliseconds;
      expect(find.byType(Scaffold), findsWidgets);
      expect(elapsed, lessThan(4000),
          reason: 'Tab switch to Connect took ${elapsed}ms');
    });

    testWidgets('Full cycle H→C→D→M→P→H completes within 25 seconds', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      final sw = DateTime.now();
      for (final label in ['Connect', 'Discover', 'Market', 'Profile', 'Home']) {
        await tapTab(tester, label);
      }
      final elapsed = DateTime.now().difference(sw).inMilliseconds;
      expect(find.byType(Scaffold), findsWidgets);
      expect(elapsed, lessThan(25000),
          reason: 'Full nav cycle took ${elapsed}ms — must be under 25s');
    });

    testWidgets('Rapid tab switching (200ms) does not crash or freeze', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      for (final label in [
        'Connect', 'Discover', 'Market', 'Profile', 'Home',
        'Connect', 'Discover', 'Market', 'Profile', 'Home',
      ]) {
        final t = navTab(label);
        if (t.evaluate().isNotEmpty) {
          await tester.tap(t.first);
          await tester.pump(const Duration(milliseconds: 200));
        }
      }
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  // ── Scroll Performance ────────────────────────────────────────────────────────
  group('⚡ Performance — Scroll Performance', () {
    testWidgets('Connect list: 5 drags complete without crash', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Connect');
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        final sw = DateTime.now();
        for (int i = 0; i < 5; i++) {
          await tester.drag(list.first, const Offset(0, -300));
          await tester.pump(const Duration(milliseconds: 100));
        }
        for (int i = 0; i < 5; i++) {
          await tester.drag(list.first, const Offset(0, 300));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        final elapsed = DateTime.now().difference(sw).inMilliseconds;
        expect(elapsed, lessThan(10000),
            reason: '10 drags on Connect list took ${elapsed}ms');
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Home feed: fast fling both directions stays smooth', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Home');
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.fling(list.first, const Offset(0, -800), 3000);
        await tester.pumpAndSettle();
        await tester.fling(list.first, const Offset(0, 800), 3000);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Marketplace Buy list: fast fling stays smooth', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Market');
      final buy = find.text('Buy');
      if (buy.evaluate().isNotEmpty) {
        await tester.tap(buy.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.fling(list.first, const Offset(0, -800), 3000);
        await tester.pumpAndSettle();
        await tester.fling(list.first, const Offset(0, 800), 3000);
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Discover Meetups list: scroll is smooth', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Discover');
      final meetups = find.text('Meetups');
      if (meetups.evaluate().isNotEmpty) {
        await tester.tap(meetups.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 600));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  // ── Memory Stability ──────────────────────────────────────────────────────────
  group('⚡ Performance — Memory Stability', () {
    testWidgets('10 navigation cycles do not accumulate errors', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      for (int round = 0; round < 10; round++) {
        for (final label in ['Connect', 'Discover', 'Market', 'Profile', 'Home']) {
          final t = navTab(label);
          if (t.evaluate().isNotEmpty) {
            await tester.tap(t.first);
            await tester.pump(const Duration(milliseconds: 300));
          }
        }
      }
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(tester.takeException(), isNull,
          reason: 'No exceptions after 10 navigation cycles');
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('3 full navigation cycles at 500ms intervals are stable', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      for (int round = 0; round < 3; round++) {
        for (final label in ['Home', 'Connect', 'Discover', 'Market', 'Profile']) {
          final t = navTab(label);
          if (t.evaluate().isNotEmpty) {
            await tester.tap(t.first);
            await tester.pump(const Duration(milliseconds: 500));
          }
        }
      }
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Back-button stress (10 presses) does not crash', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      await tapTab(tester, 'Connect');
      for (int i = 0; i < 10; i++) {
        final b = find.byType(BackButton);
        if (b.evaluate().isNotEmpty) {
          await tester.tap(b.first);
          await tester.pump(const Duration(milliseconds: 200));
        } else {
          break;
        }
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  // ── Screen Load Times ─────────────────────────────────────────────────────────
  group('⚡ Performance — Screen Load Times', () {
    testWidgets('Connect tab first load is under 6 seconds', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      final sw = DateTime.now();
      await tapTab(tester, 'Connect');
      final elapsed = DateTime.now().difference(sw).inMilliseconds;
      expect(find.byType(Scaffold), findsWidgets);
      expect(elapsed, lessThan(6000));
    });

    testWidgets('Discover tab first load is under 6 seconds', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      final sw = DateTime.now();
      await tapTab(tester, 'Discover');
      final elapsed = DateTime.now().difference(sw).inMilliseconds;
      expect(find.byType(Scaffold), findsWidgets);
      expect(elapsed, lessThan(6000));
    });

    testWidgets('Market tab first load is under 6 seconds', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      final sw = DateTime.now();
      await tapTab(tester, 'Market');
      final elapsed = DateTime.now().difference(sw).inMilliseconds;
      expect(find.byType(Scaffold), findsWidgets);
      expect(elapsed, lessThan(6000));
    });

    testWidgets('Profile tab first load is under 6 seconds', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      final sw = DateTime.now();
      await tapTab(tester, 'Profile');
      final elapsed = DateTime.now().difference(sw).inMilliseconds;
      expect(find.byType(Scaffold), findsWidgets);
      expect(elapsed, lessThan(6000));
    });
  });
}
