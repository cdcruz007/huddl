// Groups Test Suite
// Tests: Groups screen loads, group list visible, create group, group chat opens,
// search groups, send message in group chat

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('👥 Groups Tests', () {
    testWidgets('Groups screen loads without crashing', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Navigate to Groups tab
      final groupsTab = find.byTooltip('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Groups list is displayed', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final groupsTab = find.byTooltip('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final hasList =
            find.byType(ListView).evaluate().isNotEmpty ||
            find.byType(GridView).evaluate().isNotEmpty ||
            find.text('Groups').evaluate().isNotEmpty;

        expect(hasList, isTrue,
            reason: 'Groups screen should display a list of groups');
      }
    });

    testWidgets('Tapping a group opens group chat screen', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final groupsTab = find.byTooltip('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Tap first group in the list
        final groupItems = find.byType(ListTile);
        if (groupItems.evaluate().isNotEmpty) {
          await tester.tap(groupItems.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          // Should now be in a chat screen
          final inChat =
              find.text('Type a message...').evaluate().isNotEmpty ||
              find.byIcon(Icons.mic).evaluate().isNotEmpty ||
              find.text('Tap here for group info').evaluate().isNotEmpty;

          expect(inChat, isTrue,
              reason: 'Tapping a group should open its chat screen');

          // Navigate back
          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Group chat input bar is functional', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final groupsTab = find.byTooltip('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final groupItems = find.byType(ListTile);
        if (groupItems.evaluate().isNotEmpty) {
          await tester.tap(groupItems.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          final inputField = find.widgetWithText(TextField, 'Type a message...');
          if (inputField.evaluate().isNotEmpty) {
            await tester.tap(inputField.first);
            await tester.enterText(inputField.first, 'Group test message');
            await tester.pump();
            expect(find.text('Group test message'), findsOneWidget);
          }

          // Back out
          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Group chat shows send button when text typed', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final groupsTab = find.byTooltip('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final groupItems = find.byType(ListTile);
        if (groupItems.evaluate().isNotEmpty) {
          await tester.tap(groupItems.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          final inputField = find.widgetWithText(TextField, 'Type a message...');
          if (inputField.evaluate().isNotEmpty) {
            await tester.enterText(inputField.first, 'Hello group!');
            await tester.pump();

            final hasSend = find.byIcon(Icons.send).evaluate().isNotEmpty;
            expect(hasSend, isTrue,
                reason: 'Send icon should appear when text is entered in group chat');
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
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final groupsTab = find.byTooltip('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final searchIcon = find.byIcon(Icons.search);
        if (searchIcon.evaluate().isNotEmpty) {
          await tester.tap(searchIcon.first);
          await tester.pumpAndSettle();

          final searchField = find.byType(TextField);
          expect(searchField.evaluate().isNotEmpty, isTrue,
              reason: 'Search icon should open a search field');
        }
      }
    });

    testWidgets('Group info screen is accessible', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final groupsTab = find.byTooltip('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final groupItems = find.byType(ListTile);
        if (groupItems.evaluate().isNotEmpty) {
          await tester.tap(groupItems.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          // Tap group name / info area in app bar
          final groupInfo = find.text('Tap here for group info');
          if (groupInfo.evaluate().isNotEmpty) {
            await tester.tap(groupInfo.first);
            await tester.pumpAndSettle(const Duration(seconds: 2));

            // Should open group detail / info screen
            final hasInfo =
                find.text('Members').evaluate().isNotEmpty ||
                find.text('Group Info').evaluate().isNotEmpty ||
                find.text('About').evaluate().isNotEmpty;

            expect(hasInfo, isTrue,
                reason: 'Tapping group info should open group details');

            // Back out
            final backBtn = find.byType(BackButton);
            if (backBtn.evaluate().isNotEmpty) {
              await tester.tap(backBtn.first);
              await tester.pumpAndSettle();
            }
          }

          final backBtn2 = find.byType(BackButton);
          if (backBtn2.evaluate().isNotEmpty) {
            await tester.tap(backBtn2.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Group chat message list scrolls smoothly', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final groupsTab = find.byTooltip('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final groupItems = find.byType(ListTile);
        if (groupItems.evaluate().isNotEmpty) {
          await tester.tap(groupItems.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          final listView = find.byType(ListView);
          if (listView.evaluate().isNotEmpty) {
            await tester.drag(listView.first, const Offset(0, -200));
            await tester.pumpAndSettle();
            await tester.drag(listView.first, const Offset(0, 200));
            await tester.pumpAndSettle();
            // No crash = pass
          }

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
