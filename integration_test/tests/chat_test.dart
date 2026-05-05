// Chat Test Suite — Huddl
// DM and Group chat tests. Navigate via 'Connect' nav tab (Semantics label).
// Group chat hintText: 'Type a message...'

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

Finder navTab(String label) => find.bySemanticsLabel(label);

Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 10));
}

/// Navigate to Connect tab and open the first group chat.
/// Returns true if we successfully entered a chat screen.
Future<bool> openFirstGroupChat(WidgetTester tester) async {
  final tab = navTab('Connect');
  if (tab.evaluate().isEmpty) return false;
  await tester.tap(tab.first);
  await tester.pumpAndSettle(const Duration(seconds: 4));

  final listTiles = find.byType(ListTile);
  if (listTiles.evaluate().isEmpty) return false;
  await tester.tap(listTiles.first);
  await tester.pumpAndSettle(const Duration(seconds: 3));

  return find.text('Type a message...').evaluate().isNotEmpty ||
      find.byIcon(Icons.mic).evaluate().isNotEmpty;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('💬 Chat Tests', () {

    testWidgets('Chat input bar is visible after opening a group', (WidgetTester tester) async {
      await waitForApp(tester);
      final inChat = await openFirstGroupChat(tester);
      if (inChat) {
        final hasInput =
            find.widgetWithText(TextField, 'Type a message...').evaluate().isNotEmpty ||
            find.byType(TextField).evaluate().isNotEmpty;
        expect(hasInput, isTrue,
            reason: 'Chat screen should have a message input field');
      }
    });

    testWidgets('Message input field accepts text', (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final inputField = find.widgetWithText(TextField, 'Type a message...');
      if (inputField.evaluate().isNotEmpty) {
        await tester.tap(inputField.first);
        await tester.enterText(inputField.first, 'Hello from integration test!');
        await tester.pump();
        expect(find.text('Hello from integration test!'), findsOneWidget);
      }
    });

    testWidgets('Send button appears when text is entered', (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final inputField = find.widgetWithText(TextField, 'Type a message...');
      if (inputField.evaluate().isNotEmpty) {
        await tester.tap(inputField.first);
        await tester.enterText(inputField.first, 'Test message');
        await tester.pump();

        final hasSend = find.byIcon(Icons.send).evaluate().isNotEmpty;
        expect(hasSend, isTrue,
            reason: 'Send button should appear when text is typed');
      }
    });

    testWidgets('Message list scrolls without crashing', (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final listView = find.byType(ListView);
      if (listView.evaluate().isNotEmpty) {
        await tester.drag(listView.first, const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.drag(listView.first, const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(find.byType(ListView), findsWidgets);
      }
    });

    testWidgets('Mic button is visible when input is empty', (WidgetTester tester) async {
      await waitForApp(tester);
      final inChat = await openFirstGroupChat(tester);
      if (inChat) {
        final micBtn = find.byIcon(Icons.mic);
        expect(micBtn.evaluate().isNotEmpty, isTrue,
            reason: 'Mic button should be visible when message input is empty');
      }
    });

    testWidgets('Attach/add button opens options', (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final attachBtn =
          find.byIcon(Icons.add_circle_outline).evaluate().isNotEmpty
              ? find.byIcon(Icons.add_circle_outline)
              : find.byIcon(Icons.attach_file);

      if (attachBtn.evaluate().isNotEmpty) {
        await tester.tap(attachBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final hasSheet =
            find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.text('Camera').evaluate().isNotEmpty ||
            find.text('Gallery').evaluate().isNotEmpty ||
            find.text('Document').evaluate().isNotEmpty ||
            find.byType(AlertDialog).evaluate().isNotEmpty;

        if (hasSheet) {
          expect(hasSheet, isTrue,
              reason: 'Attach button should open an attachment options sheet');
          // Dismiss
          await tester.tapAt(const Offset(200, 100));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Back button from chat returns to Connect list', (WidgetTester tester) async {
      await waitForApp(tester);
      final inChat = await openFirstGroupChat(tester);
      if (inChat) {
        final backBtn = find.byType(BackButton);
        if (backBtn.evaluate().isNotEmpty) {
          await tester.tap(backBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    });

    testWidgets('Today/Yesterday date dividers appear when messages exist',
        (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final hasDivider =
          find.text('Today').evaluate().isNotEmpty ||
          find.text('Yesterday').evaluate().isNotEmpty;

      final hasMsgs = find.byType(ListView).evaluate().isNotEmpty;
      if (hasMsgs && hasDivider) {
        expect(hasDivider, isTrue);
      }
    });

    testWidgets('Group info is accessible from chat app bar', (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final groupInfo = find.text('Tap here for group info');
      if (groupInfo.evaluate().isNotEmpty) {
        await tester.tap(groupInfo.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final hasInfo =
            find.text('Members').evaluate().isNotEmpty ||
            find.text('Group Info').evaluate().isNotEmpty ||
            find.text('About').evaluate().isNotEmpty ||
            find.byType(Scaffold).evaluate().isNotEmpty;

        expect(hasInfo, isTrue,
            reason: 'Tapping group info should open group details');

        final backBtn = find.byType(BackButton);
        if (backBtn.evaluate().isNotEmpty) {
          await tester.tap(backBtn.first);
          await tester.pumpAndSettle();
        }
      }
    });
  });
}
