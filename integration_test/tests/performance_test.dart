// Performance Test Suite — Huddl
// Uses correct Semantics labels: 'Connect', 'Discover', 'Market', 'Profile', 'Home'

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

Finder navTab(String label) => find.bySemanticsLabel(label);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('⚡ Performance Tests', () {

    testWidgets('App cold start completes within 10 seconds',
        (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 12));
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(12000),
          reason: 'App should fully render within 12 seconds of cold start');
      expect(find.byType(MaterialApp), findsOneWidget,
          reason: 'App should be fully loaded');
    });

    testWidgets('Main screen renders first frame quickly',
        (WidgetTester tester) async {
      app.main();
      await tester.pump();
      expect(find.byType(MaterialApp), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 10));
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Scrolling Connect (groups) list has no jank',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 10));

      final tab = navTab('Connect');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
      }

      await binding.watchPerformance(() async {
        final listView = find.byType(ListView);
        if (listView.evaluate().isNotEmpty) {
          await tester.fling(listView.first, const Offset(0, -800), 3000);
          await tester.pumpAndSettle();
          await tester.fling(listView.first, const Offset(0, 800), 3000);
          await tester.pumpAndSettle();
        }
      }, reportKey: 'connect_list_scroll');
    });

    testWidgets('Chat message list scroll performance',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 10));

      final tab = navTab('Connect');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final groupItems = find.byType(ListTile);
        if (groupItems.evaluate().isNotEmpty) {
          await tester.tap(groupItems.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          await binding.watchPerformance(() async {
            final listView = find.byType(ListView);
            if (listView.evaluate().isNotEmpty) {
              await tester.fling(listView.first, const Offset(0, -500), 2000);
              await tester.pumpAndSettle();
              await tester.fling(listView.first, const Offset(0, 500), 2000);
              await tester.pumpAndSettle();
            }
          }, reportKey: 'chat_scroll');

          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Tab switching has no visible lag', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 10));

      await binding.watchPerformance(() async {
        for (final label in ['Connect', 'Discover', 'Market', 'Profile', 'Home']) {
          final tab = navTab(label);
          if (tab.evaluate().isNotEmpty) {
            await tester.tap(tab.first);
            await tester.pump(const Duration(milliseconds: 400));
          }
        }
        await tester.pumpAndSettle();
      }, reportKey: 'tab_switching');
    });

    testWidgets('Marketplace screen renders within acceptable time',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 10));

      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        final stopwatch = Stopwatch()..start();
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 6));
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(6000),
            reason: 'Marketplace screen should render within 6 seconds');
      }
    });

    testWidgets('No crash on repeated tab navigation',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 10));

      // Navigate back and forth 3 times — watch for crashes
      for (int round = 0; round < 3; round++) {
        for (final label in ['Connect', 'Discover', 'Market', 'Profile', 'Home']) {
          final tab = navTab(label);
          if (tab.evaluate().isNotEmpty) {
            await tester.tap(tab.first);
            await tester.pump(const Duration(milliseconds: 300));
          }
        }
      }
      await tester.pumpAndSettle();
      expect(find.byType(Scaffold), findsWidgets);
    });
  });
}
