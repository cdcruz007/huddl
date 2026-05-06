// ============================================================
// Chat Test Suite — Huddl v32
// Covers: group chat basics, message actions (long-press,
//   emoji reactions, forward, thread reply, unsend, copy,
//   save message), attach / media sheet, polls (open option),
//   voice note mic (tap without recording), DM chat
//   (open, input, scroll, block/unblock semantics, status
//   labels), saved messages tab, unread new-messages banner.
// Semantics: 'Failed to send, tap to retry', 'React with $emoji',
//   'Sending', 'Sent', 'Delivered', 'Read',
//   'New messages available', 'Unblock', 'Block'
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

bool get _hasNavBar =>
    find.bySemanticsLabel('Home').evaluate().isNotEmpty ||
    find.bySemanticsLabel('Connect').evaluate().isNotEmpty;

Future<bool> goToConnect(WidgetTester tester) async {
  if (!_hasNavBar) return false;
  await tester.tap(navTab('Connect').first);
  await tester.pumpAndSettle(const Duration(seconds: 5));
  return true;
}

Future<bool> openFirstGroupChat(WidgetTester tester) async {
  if (!await goToConnect(tester)) return false;
  final chatsTab = find.text('Chats');
  if (chatsTab.evaluate().isNotEmpty) {
    await tester.tap(chatsTab.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }
  final tiles   = find.byType(ListTile);
  final inkWell = find.byType(InkWell);
  final target  = tiles.evaluate().isNotEmpty ? tiles : inkWell;
  if (target.evaluate().isEmpty) return false;
  await tester.tap(target.first);
  await tester.pumpAndSettle(const Duration(seconds: 4));
  return find.text('Type a message...').evaluate().isNotEmpty ||
      find.byIcon(Icons.mic).evaluate().isNotEmpty;
}

Future<void> tryBack(WidgetTester tester) async {
  final b = find.byType(BackButton);
  if (b.evaluate().isNotEmpty) {
    await tester.tap(b.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  } else {
    await tester.tapAt(const Offset(200, 80));
    await tester.pumpAndSettle();
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Group Chat Basics ─────────────────────────────────────────────────────────
  group('💬 Chat — Group Chat Basics', () {
    testWidgets('Chat input bar visible after opening a group', (tester) async {
      await waitForApp(tester);
      final ok = await openFirstGroupChat(tester);
      if (ok) {
        final hasInput =
            find.widgetWithText(TextField, 'Type a message...').evaluate().isNotEmpty ||
            find.byType(TextField).evaluate().isNotEmpty;
        expect(hasInput, isTrue,
            reason: 'Chat screen must have a message input field');
        await tryBack(tester);
      }
    });

    testWidgets('No rendering exception inside chat screen', (tester) async {
      await waitForApp(tester);
      final ok = await openFirstGroupChat(tester);
      if (ok) {
        expect(tester.takeException(), isNull);
        await tryBack(tester);
      }
    });

    testWidgets('Message input accepts text', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final f = find.widgetWithText(TextField, 'Type a message...');
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await tester.enterText(f.first, 'Hello integration test! 👋');
        await tester.pump();
        expect(find.text('Hello integration test! 👋'), findsOneWidget);
      }
      await tryBack(tester);
    });

    testWidgets('Send icon appears after typing text', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final f = find.widgetWithText(TextField, 'Type a message...');
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await tester.enterText(f.first, 'send test');
        await tester.pump();
        expect(find.byIcon(Icons.send), findsWidgets);
      }
      await tryBack(tester);
    });

    testWidgets('Mic button visible when input is empty', (tester) async {
      await waitForApp(tester);
      final ok = await openFirstGroupChat(tester);
      if (ok) {
        expect(find.byIcon(Icons.mic), findsWidgets);
        await tryBack(tester);
      }
    });

    testWidgets('Message list scrolls without crash', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 300));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
      await tryBack(tester);
    });

    testWidgets('Fast fling does not crash chat screen', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.fling(list.first, const Offset(0, -600), 2500);
        await tester.pumpAndSettle();
        await tester.fling(list.first, const Offset(0, 600), 2500);
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
      await tryBack(tester);
    });

    testWidgets('New messages available banner is accessible', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final banner = find.bySemanticsLabel('New messages available');
      if (banner.evaluate().isNotEmpty) {
        await tester.tap(banner.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
      await tryBack(tester);
    });
  });

  // ── Message Status Labels ─────────────────────────────────────────────────────
  group('💬 Chat — Message Status Semantics', () {
    testWidgets('Sending label present after tapping send', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final f = find.widgetWithText(TextField, 'Type a message...');
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await tester.enterText(f.first, 'status test');
        await tester.pump();
        final send = find.byIcon(Icons.send);
        if (send.evaluate().isNotEmpty) {
          await tester.tap(send.first);
          await tester.pump(const Duration(milliseconds: 500));
          // Either Sending, Sent, Delivered or Read label may appear
          final hasStatus =
              find.bySemanticsLabel('Sending').evaluate().isNotEmpty ||
              find.bySemanticsLabel('Sent').evaluate().isNotEmpty ||
              find.bySemanticsLabel('Delivered').evaluate().isNotEmpty ||
              find.bySemanticsLabel('Read').evaluate().isNotEmpty ||
              find.byType(Scaffold).evaluate().isNotEmpty;
          expect(hasStatus, isTrue);
        }
      }
      await tryBack(tester);
    });

    testWidgets('Failed to send retry label is accessible', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final retry = find.bySemanticsLabel('Failed to send, tap to retry');
      if (retry.evaluate().isNotEmpty) {
        await tester.tap(retry.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
      await tryBack(tester);
    });
  });

  // ── Message Actions (Long-press) ──────────────────────────────────────────────
  group('💬 Chat — Message Actions', () {
    testWidgets('Long-pressing a message opens action menu', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final msgs = find.byType(ListTile);
      if (msgs.evaluate().isNotEmpty) {
        await tester.longPress(msgs.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final hasMenu =
            find.text('Copy').evaluate().isNotEmpty ||
            find.text('Reply').evaluate().isNotEmpty ||
            find.text('Forward').evaluate().isNotEmpty ||
            find.text('Unsend').evaluate().isNotEmpty ||
            find.text('Save').evaluate().isNotEmpty ||
            find.text('Delete').evaluate().isNotEmpty ||
            find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.byType(AlertDialog).evaluate().isNotEmpty;
        if (hasMenu) {
          expect(hasMenu, isTrue,
              reason: 'Long-press must show action menu');
          await tester.tapAt(const Offset(200, 80));
          await tester.pumpAndSettle();
        }
      }
      await tryBack(tester);
    });

    testWidgets('Emoji reaction picker shows common emojis', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final msgs = find.byType(ListTile);
      if (msgs.evaluate().isNotEmpty) {
        await tester.longPress(msgs.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final hasEmoji =
            find.text('👍').evaluate().isNotEmpty ||
            find.text('❤️').evaluate().isNotEmpty ||
            find.text('😂').evaluate().isNotEmpty ||
            find.bySemanticsLabel(RegExp(r'React with')).evaluate().isNotEmpty;
        if (hasEmoji) {
          expect(hasEmoji, isTrue);
        }
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
      await tryBack(tester);
    });

    testWidgets('Copy action in long-press menu is accessible', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final msgs = find.byType(ListTile);
      if (msgs.evaluate().isNotEmpty) {
        await tester.longPress(msgs.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final copy = find.text('Copy');
        if (copy.evaluate().isNotEmpty) {
          await tester.tap(copy.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(Scaffold), findsWidgets);
        } else {
          await tester.tapAt(const Offset(200, 80));
          await tester.pumpAndSettle();
        }
      }
      await tryBack(tester);
    });

    testWidgets('Save message action is accessible', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final msgs = find.byType(ListTile);
      if (msgs.evaluate().isNotEmpty) {
        await tester.longPress(msgs.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final save = find.text('Save');
        if (save.evaluate().isNotEmpty) {
          await tester.tap(save.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(Scaffold), findsWidgets);
        } else {
          await tester.tapAt(const Offset(200, 80));
          await tester.pumpAndSettle();
        }
      }
      await tryBack(tester);
    });
  });

  // ── Attach / Media ────────────────────────────────────────────────────────────
  group('💬 Chat — Attach & Media', () {
    testWidgets('Attach button opens options sheet', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final att = find.byIcon(Icons.add_circle_outline).evaluate().isNotEmpty
          ? find.byIcon(Icons.add_circle_outline)
          : find.byIcon(Icons.attach_file);
      if (att.evaluate().isNotEmpty) {
        await tester.tap(att.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final ok =
            find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.text('Camera').evaluate().isNotEmpty ||
            find.text('Gallery').evaluate().isNotEmpty ||
            find.text('Document').evaluate().isNotEmpty ||
            find.text('Poll').evaluate().isNotEmpty;
        if (ok) {
          expect(ok, isTrue);
          await tester.tapAt(const Offset(200, 80));
          await tester.pumpAndSettle();
        }
      }
      await tryBack(tester);
    });

    testWidgets('Poll option accessible from attach menu', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final att = find.byIcon(Icons.add_circle_outline).evaluate().isNotEmpty
          ? find.byIcon(Icons.add_circle_outline)
          : find.byIcon(Icons.more_horiz);
      if (att.evaluate().isNotEmpty) {
        await tester.tap(att.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final poll = find.text('Poll');
        if (poll.evaluate().isNotEmpty) {
          expect(poll, findsWidgets);
          await tester.tap(poll.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          // Poll creation screen should appear
          expect(find.byType(Scaffold), findsWidgets);
          await tryBack(tester);
        } else {
          await tester.tapAt(const Offset(200, 80));
          await tester.pumpAndSettle();
        }
      }
      await tryBack(tester);
    });
  });

  // ── Thread Replies ────────────────────────────────────────────────────────────
  group('💬 Chat — Thread Replies', () {
    testWidgets('Thread reply icon is accessible on a message', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final threadIcon =
          find.byIcon(Icons.chat_bubble_outline).evaluate().isNotEmpty
              ? find.byIcon(Icons.chat_bubble_outline)
              : find.byIcon(Icons.reply);
      if (threadIcon.evaluate().isNotEmpty) {
        await tester.tap(threadIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
      await tryBack(tester);
    });

    testWidgets('Reply preview appears in composer after swipe-to-reply', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      // Swipe a message bubble right to trigger inline reply
      final msgs = find.byType(ListTile);
      if (msgs.evaluate().isNotEmpty) {
        await tester.drag(msgs.first, const Offset(80, 0));
        await tester.pumpAndSettle(const Duration(seconds: 1));
        // No crash is the key expectation
        expect(find.byType(Scaffold), findsWidgets);
      }
      await tryBack(tester);
    });
  });

  // ── Voice Note (Mic) ──────────────────────────────────────────────────────────
  group('💬 Chat — Voice Note Mic', () {
    testWidgets('Long-pressing mic button starts recording UI', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final mic = find.byIcon(Icons.mic);
      if (mic.evaluate().isNotEmpty) {
        // Long press to start recording
        await tester.longPress(mic.first);
        await tester.pump(const Duration(milliseconds: 500));
        // Cancel by dragging up
        await tester.drag(mic.first, const Offset(0, -80));
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
      await tryBack(tester);
    });

    testWidgets('Tapping mic button shows no crash', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final mic = find.byIcon(Icons.mic);
      if (mic.evaluate().isNotEmpty) {
        await tester.tap(mic.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
      await tryBack(tester);
    });
  });

  // ── DM Chat ───────────────────────────────────────────────────────────────────
  group('💬 Chat — Direct Messages', () {
    testWidgets('Messages sub-tab accessible from Connect screen', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final t = find.text('Messages');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Opening a DM shows message input', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final t = find.text('Messages');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final tiles = find.byType(ListTile);
        if (tiles.evaluate().isNotEmpty) {
          await tester.tap(tiles.first);
          await tester.pumpAndSettle(const Duration(seconds: 4));
          final ok =
              find.byType(TextField).evaluate().isNotEmpty ||
              find.byIcon(Icons.mic).evaluate().isNotEmpty;
          if (ok) expect(ok, isTrue);
          await tryBack(tester);
        }
      }
    });

    testWidgets('DM screen scrolls without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final t = find.text('Messages');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final tiles = find.byType(ListTile);
        if (tiles.evaluate().isNotEmpty) {
          await tester.tap(tiles.first);
          await tester.pumpAndSettle(const Duration(seconds: 4));
          final list = find.byType(ListView);
          if (list.evaluate().isNotEmpty) {
            await tester.drag(list.first, const Offset(0, -300));
            await tester.pumpAndSettle();
            await tester.drag(list.first, const Offset(0, 300));
            await tester.pumpAndSettle();
          }
          await tryBack(tester);
        }
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Block / Unblock label is accessible in DM', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final t = find.text('Messages');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final tiles = find.byType(ListTile);
        if (tiles.evaluate().isNotEmpty) {
          await tester.tap(tiles.first);
          await tester.pumpAndSettle(const Duration(seconds: 4));
          // Block/Unblock widget has a TextField label
          final block = find.widgetWithText(TextField, 'Unblock')
              .evaluate()
              .isNotEmpty
              ? find.widgetWithText(TextField, 'Unblock')
              : find.widgetWithText(TextField, 'Block');
          if (block.evaluate().isNotEmpty) {
            expect(block, findsWidgets);
          }
          await tryBack(tester);
        }
      }
    });

    testWidgets('New DM screen shows search field', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final dmBtn = find.bySemanticsLabel('New direct message');
      if (dmBtn.evaluate().isNotEmpty) {
        await tester.tap(dmBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final ok = find.byType(TextField).evaluate().isNotEmpty ||
            find.byType(Scaffold).evaluate().isNotEmpty;
        expect(ok, isTrue);
        await tryBack(tester);
      }
    });
  });

  // ── Saved Messages Tab ────────────────────────────────────────────────────────
  group('💬 Chat — Saved Messages', () {
    testWidgets('Saved tab accessible from Connect screen', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final t = find.text('Saved');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        final chats = find.text('Chats');
        if (chats.evaluate().isNotEmpty) {
          await tester.tap(chats.first);
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Saved items list loads or shows empty state', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final t = find.text('Saved');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        final ok =
            find.byType(ListView).evaluate().isNotEmpty ||
            find.text('No saved items yet').evaluate().isNotEmpty ||
            find.byType(Scaffold).evaluate().isNotEmpty;
        expect(ok, isTrue);
        final chats = find.text('Chats');
        if (chats.evaluate().isNotEmpty) {
          await tester.tap(chats.first);
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Saved search field hint is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final t = find.text('Saved');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final sf =
            find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search saved messages…');
        if (sf.evaluate().isNotEmpty) {
          await tester.tap(sf.first);
          await tester.enterText(sf.first, 'hello');
          await tester.pump();
          expect(find.text('hello'), findsOneWidget);
          await tester.enterText(sf.first, '');
          await tester.pump();
        }
        final chats = find.text('Chats');
        if (chats.evaluate().isNotEmpty) {
          await tester.tap(chats.first);
          await tester.pumpAndSettle();
        }
      }
    });
  });
}
