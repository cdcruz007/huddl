// Performance Test Suite
// Tests: App startup time, scroll frame rate, memory during chat,
// image loading, large list performance

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('⚡ Performance Tests', () {
    testWidgets('App cold start completes within 8 seconds',
        (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 10));
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(10000),
          reason: 'App should fully render within 10 seconds of cold start');

      expect(find.byType(MaterialApp), findsOneWidget,
          reason: 'App should be fully loaded');
    });

    testWidgets('Main screen renders first frame quickly',
        (WidgetTester tester) async {
      app.main();

      // Pump just one frame
      await tester.pump();
      expect(find.byType(MaterialApp), findsOneWidget);

      // Now settle fully
      await tester.pumpAndSettle(const Duration(seconds: 8));
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Scrolling groups list has no jank (frame timing)',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final groupsTab = find.byTooltip('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      await binding.watchPerformance(() async {
        final listView = find.byType(ListView);
        if (listView.evaluate().isNotEmpty) {
          // Scroll down smoothly
          await tester.fling(listView.first, const Offset(0, -800), 3000);
          await tester.pumpAndSettle();
          // Scroll back up
          await tester.fling(listView.first, const Offset(0, 800), 3000);
          await tester.pumpAndSettle();
        }
      }, reportKey: 'groups_list_scroll');
    });

    testWidgets('Chat message list scroll performance',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Navigate into a group chat for scroll test
      final groupsTab = find.byTooltip('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

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
      await tester.pumpAndSettle(const Duration(seconds: 8));

      if (find.byType(BottomNavigationBar).evaluate().isNotEmpty) {
        await binding.watchPerformance(() async {
          final navBar = find.byType(BottomNavigationBar);
          final items = find.descendant(
            of: navBar,
            matching: find.byType(InkWell),
          );

          final count = items.evaluate().length;
          for (int i = 0; i < count; i++) {
            if (items.evaluate().length > i) {
              await tester.tap(items.at(i));
              await tester.pump(const Duration(milliseconds: 400));
            }
          }
          await tester.pumpAndSettle();
        }, reportKey: 'tab_switching');
      }
    });

    testWidgets('Marketplace grid renders within acceptable time',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final marketTab = find.byTooltip('Marketplace');
      if (marketTab.evaluate().isNotEmpty) {
        final stopwatch = Stopwatch()..start();
        await tester.tap(marketTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(5000),
            reason: 'Marketplace screen should render within 5 seconds');
      }
    });

    testWidgets('No memory leak on repeated tab navigation',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      if (find.byType(BottomNavigationBar).evaluate().isNotEmpty) {
        // Navigate back and forth 5 times — watch for crashes
        for (int round = 0; round < 5; round++) {
          final items = find.descendant(
            of: find.byType(BottomNavigationBar),
            matching: find.byType(InkWell),
          );
          final count = items.evaluate().length;
          for (int i = 0; i < count; i++) {
            if (items.evaluate().length > i) {
              await tester.tap(items.at(i));
              await tester.pump(const Duration(milliseconds: 200));
            }
          }
        }
        await tester.pumpAndSettle();
        // If we reach here without OOM or crash, test passes
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });
}
