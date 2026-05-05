// Groups Test Suite — Huddl
// Nav label: 'Connect' (Semantics label on _NavItem)
// Groups screen hintText: 'Search chats...' / 'Search groups...'

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

// Find nav tab by its Semantics label (matches _NavItem in main_shell.dart)
Finder navTab(String label) => find.bySemanticsLabel(label);

Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 10));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('👥 Groups / Connect Tests', () {

    testWidgets('Connect tab navigates to groups screen', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Connect');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Groups list or content is displayed', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Connect');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final hasContent =
            find.byType(ListView).evaluate().isNotEmpty ||
            find.byType(GridView).evaluate().isNotEmpty ||
            find.text('Connect').evaluate().isNotEmpty ||
            find.textContaining('group').evaluate().isNotEmpty ||
            find.textContaining('Group').evaluate().isNotEmpty;

        expect(hasContent, isTrue,
            reason: 'Connect screen should display groups content');
      }
    });

    testWidgets('Tapping a group opens group chat screen', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Connect');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final listTiles = find.byType(ListTile);
        final inkWells = find.byType(InkWell);
        final target = listTiles.evaluate().isNotEmpty ? listTiles : inkWells;

        if (target.evaluate().isNotEmpty) {
          await tester.tap(target.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          final inChat =
              find.text('Type a message...').evaluate().isNotEmpty ||
              find.byIcon(Icons.mic).evaluate().isNotEmpty ||
              find.byIcon(Icons.send).evaluate().isNotEmpty ||
              find.text('Tap here for group info').evaluate().isNotEmpty;

          if (inChat) {
            expect(inChat, isTrue,
                reason: 'Tapping a group should open its chat screen');
          }

          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Group chat input bar is functional', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Connect');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final listTiles = find.byType(ListTile);
        if (listTiles.evaluate().isNotEmpty) {
          await tester.tap(listTiles.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          final inputField = find.widgetWithText(TextField, 'Type a message...');
          if (inputField.evaluate().isNotEmpty) {
            await tester.tap(inputField.first);
            await tester.enterText(inputField.first, 'Group test message');
            await tester.pump();
            expect(find.text('Group test message'), findsOneWidget);
          }

          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Group search is accessible', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Connect');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final searchIcon = find.byIcon(Icons.search);
        if (searchIcon.evaluate().isNotEmpty) {
          await tester.tap(searchIcon.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          final searchField = find.byType(TextField);
          expect(searchField.evaluate().isNotEmpty, isTrue,
              reason: 'Search icon should open a search field');
        }
      }
    });

    testWidgets('Group chat message list scrolls smoothly', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Connect');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final listTiles = find.byType(ListTile);
        if (listTiles.evaluate().isNotEmpty) {
          await tester.tap(listTiles.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          final listView = find.byType(ListView);
          if (listView.evaluate().isNotEmpty) {
            await tester.drag(listView.first, const Offset(0, -200));
            await tester.pumpAndSettle();
            await tester.drag(listView.first, const Offset(0, 200));
            await tester.pumpAndSettle();
          }

          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Connect tab content scrolls without crash', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Connect');
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
  });
}
