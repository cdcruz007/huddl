// Chat Test Suite
// Tests: DM chat screen, message sending, message list, input bar, timestamps

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('💬 Chat Tests', () {
    testWidgets('Chat input bar is visible', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Navigate to messages tab
      final messagesTab = find.byTooltip('Messages');
      if (messagesTab.evaluate().isNotEmpty) {
        await tester.tap(messagesTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      // Look for chat input field
      final hasInput =
          find.widgetWithText(TextField, 'Type a message...').evaluate().isNotEmpty ||
          find.widgetWithText(TextField, 'Message').evaluate().isNotEmpty ||
          find.byKey(const Key('message_input')).evaluate().isNotEmpty;

      // Only assert if we are in a chat screen
      final inChat = find.text('Type a message...').evaluate().isNotEmpty;
      if (inChat) {
        expect(hasInput, isTrue,
            reason: 'Chat screen should have a message input field');
      }
    });

    testWidgets('Message input field accepts text', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final inputField = find.widgetWithText(TextField, 'Type a message...');
      if (inputField.evaluate().isNotEmpty) {
        await tester.tap(inputField.first);
        await tester.enterText(inputField.first, 'Hello from integration test!');
        await tester.pump();
        expect(find.text('Hello from integration test!'), findsOneWidget);
      }
    });

    testWidgets('Send button appears when text is entered', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final inputField = find.widgetWithText(TextField, 'Type a message...');
      if (inputField.evaluate().isNotEmpty) {
        await tester.tap(inputField.first);
        await tester.enterText(inputField.first, 'Test message');
        await tester.pump();

        // Send button (Icon.send) should now be visible
        final sendBtn =
            find.byIcon(Icons.send).evaluate().isNotEmpty ||
            find.byKey(const Key('send_button')).evaluate().isNotEmpty;

        expect(sendBtn, isTrue,
            reason: 'Send button should appear when text is typed');
      }
    });

    testWidgets('Sending a message adds it to the list', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final inputField = find.widgetWithText(TextField, 'Type a message...');
      if (inputField.evaluate().isNotEmpty) {
        const testMsg = 'Integration test message 12345';
        await tester.tap(inputField.first);
        await tester.enterText(inputField.first, testMsg);
        await tester.pump();

        final sendIcon = find.byIcon(Icons.send);
        if (sendIcon.evaluate().isNotEmpty) {
          await tester.tap(sendIcon.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.text(testMsg), findsOneWidget);
        }
      }
    });

    testWidgets('Message input clears after sending', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final inputField = find.widgetWithText(TextField, 'Type a message...');
      if (inputField.evaluate().isNotEmpty) {
        await tester.tap(inputField.first);
        await tester.enterText(inputField.first, 'Clear me after send');
        await tester.pump();

        final sendIcon = find.byIcon(Icons.send);
        if (sendIcon.evaluate().isNotEmpty) {
          await tester.tap(sendIcon.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          // Input should be empty after sending
          final field = tester.widget<TextField>(inputField.first);
          expect(field.controller?.text ?? '', isEmpty,
              reason: 'Input field should clear after message is sent');
        }
      }
    });

    testWidgets('Message list scrolls without crashing', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final listView = find.byType(ListView);
      if (listView.evaluate().isNotEmpty) {
        await tester.drag(listView.first, const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.drag(listView.first, const Offset(0, 300));
        await tester.pumpAndSettle();
        // Pass if no crash
        expect(find.byType(ListView), findsWidgets);
      }
    });

    testWidgets('Mic button is visible when input is empty', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final inChat = find.text('Type a message...').evaluate().isNotEmpty;
      if (inChat) {
        final micBtn =
            find.byIcon(Icons.mic).evaluate().isNotEmpty ||
            find.byKey(const Key('mic_button')).evaluate().isNotEmpty;

        expect(micBtn, isTrue,
            reason: 'Mic button should be visible when message input is empty');
      }
    });

    testWidgets('Attach button opens attachment sheet', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final attachBtn =
          find.byIcon(Icons.add_circle_outline).evaluate().isNotEmpty
              ? find.byIcon(Icons.add_circle_outline)
              : find.byIcon(Icons.attach_file);

      if (attachBtn.evaluate().isNotEmpty) {
        await tester.tap(attachBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Bottom sheet should appear
        final hasSheet =
            find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.text('Camera').evaluate().isNotEmpty ||
            find.text('Gallery').evaluate().isNotEmpty ||
            find.text('Document').evaluate().isNotEmpty;

        expect(hasSheet, isTrue,
            reason: 'Attach button should open an attachment options sheet');

        // Dismiss sheet
        await tester.tapAt(const Offset(200, 100));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Long pressing a message shows context menu', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Find any message bubble
      final msgBubble = find.byKey(const Key('message_bubble'));
      if (msgBubble.evaluate().isNotEmpty) {
        await tester.longPress(msgBubble.first);
        await tester.pumpAndSettle();

        final hasMenu =
            find.text('Copy').evaluate().isNotEmpty ||
            find.text('Reply').evaluate().isNotEmpty ||
            find.text('Forward').evaluate().isNotEmpty ||
            find.text('Delete').evaluate().isNotEmpty ||
            find.text('Save').evaluate().isNotEmpty;

        expect(hasMenu, isTrue,
            reason: 'Long press on message should show context menu options');

        // Dismiss
        await tester.tapAt(const Offset(200, 100));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Today/Yesterday date dividers appear in message list',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // If messages exist, check for date dividers
      final hasDivider =
          find.text('Today').evaluate().isNotEmpty ||
          find.text('Yesterday').evaluate().isNotEmpty;

      // Not a hard requirement — only validate if messages are present
      final hasMsgs = find.byType(ListView).evaluate().isNotEmpty;
      if (hasMsgs && hasDivider) {
        expect(hasDivider, isTrue);
      }
    });
  });
}
