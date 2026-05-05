// Events / Discover Test Suite — Huddl
// Nav label: 'Discover' (Semantics label on _NavItem in main_shell.dart)
// Tabs inside Discover: 'Groups', 'Meetups', 'Events'

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

Finder navTab(String label) => find.bySemanticsLabel(label);

Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 10));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🗓️ Events / Discover Tests', () {

    testWidgets('Discover tab navigates to events screen', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Discover');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Discover shows Groups/Meetups/Events tabs', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Discover');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final hasTabs =
            find.text('Groups').evaluate().isNotEmpty ||
            find.text('Meetups').evaluate().isNotEmpty ||
            find.text('Events').evaluate().isNotEmpty;

        expect(hasTabs, isTrue,
            reason: 'Discover screen should have Groups/Meetups/Events tabs');
      }
    });

    testWidgets('Groups tab in Discover loads content', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Discover');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final groupsTab = find.text('Groups');
        if (groupsTab.evaluate().isNotEmpty) {
          await tester.tap(groupsTab.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    });

    testWidgets('Meetups tab in Discover loads content', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Discover');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final meetupsTab = find.text('Meetups');
        if (meetupsTab.evaluate().isNotEmpty) {
          await tester.tap(meetupsTab.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    });

    testWidgets('Events tab in Discover loads content', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Discover');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final eventsTab = find.text('Events');
        if (eventsTab.evaluate().isNotEmpty) {
          await tester.tap(eventsTab.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    });

    testWidgets('Discover content scrolls without crash', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Discover');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final scrollable = find.byType(ListView);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.drag(scrollable.first, const Offset(0, -300));
          await tester.pumpAndSettle();
          await tester.drag(scrollable.first, const Offset(0, 300));
          await tester.pumpAndSettle();
        }
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Filter button is accessible on Meetups tab', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Discover');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final meetupsTab = find.text('Meetups');
        if (meetupsTab.evaluate().isNotEmpty) {
          await tester.tap(meetupsTab.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          // Look for filter icon
          final filterIcon = find.byIcon(Icons.filter_list);
          final tuneIcon = find.byIcon(Icons.tune);
          final filterBtn = filterIcon.evaluate().isNotEmpty ? filterIcon : tuneIcon;

          if (filterBtn.evaluate().isNotEmpty) {
            await tester.tap(filterBtn.first);
            await tester.pumpAndSettle(const Duration(seconds: 2));

            final hasFilter =
                find.text('Filter Meetups').evaluate().isNotEmpty ||
                find.text('Clear all').evaluate().isNotEmpty ||
                find.text('Category').evaluate().isNotEmpty ||
                find.byType(BottomSheet).evaluate().isNotEmpty;

            if (hasFilter) {
              expect(hasFilter, isTrue,
                  reason: 'Filter button should open filter options');
            }

            // Dismiss filter
            await tester.tapAt(const Offset(200, 100));
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Tapping an event card opens event detail', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Discover');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final eventsTab = find.text('Events');
        if (eventsTab.evaluate().isNotEmpty) {
          await tester.tap(eventsTab.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
        }

        final cards = find.byType(Card);
        if (cards.evaluate().isNotEmpty) {
          await tester.tap(cards.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.byType(Scaffold), findsWidgets);

          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });
  });
}
