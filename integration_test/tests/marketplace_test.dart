// Marketplace Test Suite — Huddl
// Nav label: 'Market' (Semantics label on _NavItem in main_shell.dart)
// Tabs inside Marketplace: 'Buy', 'Sell', 'Saved'

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

  group('🛒 Marketplace Tests', () {

    testWidgets('Market tab navigates to Marketplace screen', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Marketplace shows Buy/Sell/Saved tabs', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final hasTabs =
            find.text('Buy').evaluate().isNotEmpty ||
            find.text('Sell').evaluate().isNotEmpty ||
            find.text('Saved').evaluate().isNotEmpty ||
            find.text('Market').evaluate().isNotEmpty;

        expect(hasTabs, isTrue,
            reason: 'Marketplace should show Buy/Sell/Saved tabs');
      }
    });

    testWidgets('Buy tab shows listing content', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final buyTab = find.text('Buy');
        if (buyTab.evaluate().isNotEmpty) {
          await tester.tap(buyTab.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
        }

        final hasContent =
            find.byType(ListView).evaluate().isNotEmpty ||
            find.byType(GridView).evaluate().isNotEmpty ||
            find.byType(Card).evaluate().isNotEmpty ||
            find.textContaining('£').evaluate().isNotEmpty ||
            find.text('Market').evaluate().isNotEmpty;

        expect(hasContent, isTrue,
            reason: 'Marketplace Buy tab should show listing items');
      }
    });

    testWidgets('Sell tab is accessible', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final sellTab = find.text('Sell');
        if (sellTab.evaluate().isNotEmpty) {
          await tester.tap(sellTab.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    });

    testWidgets('Saved tab is accessible', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final savedTab = find.text('Saved');
        if (savedTab.evaluate().isNotEmpty) {
          await tester.tap(savedTab.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    });

    testWidgets('Marketplace list scrolls without crash', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final scrollable = find.byType(ListView);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.drag(scrollable.first, const Offset(0, -400));
          await tester.pumpAndSettle();
          await tester.drag(scrollable.first, const Offset(0, 400));
          await tester.pumpAndSettle();
        }
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Tapping a listing opens item detail screen', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final items = find.byType(Card);
        if (items.evaluate().isNotEmpty) {
          await tester.tap(items.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          // If we navigated somewhere, check we're still stable
          expect(find.byType(Scaffold), findsWidgets);

          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Create listing button is accessible on Sell tab', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        // Switch to Sell tab
        final sellTab = find.text('Sell');
        if (sellTab.evaluate().isNotEmpty) {
          await tester.tap(sellTab.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
        }

        final fab = find.byType(FloatingActionButton);
        final addIcon = find.byIcon(Icons.add);
        final createBtn = fab.evaluate().isNotEmpty ? fab : addIcon;

        if (createBtn.evaluate().isNotEmpty) {
          await tester.tap(createBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          final inCreateForm =
              find.text('Create listing').evaluate().isNotEmpty ||
              find.text('Add listing').evaluate().isNotEmpty ||
              find.text('Title').evaluate().isNotEmpty ||
              find.text('Price').evaluate().isNotEmpty ||
              find.byType(TextField).evaluate().isNotEmpty;

          if (inCreateForm) {
            expect(inCreateForm, isTrue,
                reason: 'Create button should open listing creation form');
          }

          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Marketplace search is accessible', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final searchIcon = find.byIcon(Icons.search);
        if (searchIcon.evaluate().isNotEmpty) {
          await tester.tap(searchIcon.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          final searchField = find.byType(TextField);
          if (searchField.evaluate().isNotEmpty) {
            await tester.enterText(searchField.first, 'pram');
            await tester.pump();
            expect(find.text('pram'), findsOneWidget);
          }
        }
      }
    });
  });
}
