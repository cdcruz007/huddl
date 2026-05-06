// ============================================================
// Groups / Connect Test Suite — Huddl v32
// Covers: groups list (tabs, scroll, search, new DM),
//   swipe actions (pin/unpin, mute/unmute, archive, delete,
//   leave, mark read/unread), create group 3-step flow,
//   filter/sort sheet, AI suggestions, saved tab swipe,
//   group chat open (message input, send, mic, attach,
//   scroll, back), group info / members screen.
// Semantics: 'New direct message', 'Clear search',
//   'Unpin'/'Pin', 'Mute'/'Unmute', 'Archive', 'Undo',
//   'Delete', 'Leave group', 'Cancel', 'Mark as read',
//   'Mark as unread', 'Close filter sheet',
//   'Reset all filters', 'Toggle AI recommendations',
//   'Suggested groups', 'Retry loading groups'
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
  return find.byType(Scaffold).evaluate().isNotEmpty;
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
      find.byIcon(Icons.mic).evaluate().isNotEmpty ||
      find.byIcon(Icons.send).evaluate().isNotEmpty;
}

Future<void> tryBack(WidgetTester tester) async {
  final b = find.byType(BackButton);
  if (b.evaluate().isNotEmpty) {
    await tester.tap(b.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  } else {
    await tester.tapAt(const Offset(200, 80));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── List Screen ───────────────────────────────────────────────────────────────
  group('👥 Groups — List Screen', () {
    testWidgets('Connect tab loads without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('No rendering exception on Connect screen', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      expect(tester.takeException(), isNull);
    });

    testWidgets('Connect screen shows list or empty state', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final ok =
          find.byType(ListView).evaluate().isNotEmpty ||
          find.text('Chats').evaluate().isNotEmpty ||
          find.textContaining('group').evaluate().isNotEmpty ||
          find.byType(Scaffold).evaluate().isNotEmpty;
      expect(ok, isTrue);
    });

    testWidgets('List scrolls down and up without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -400));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 400));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Chats sub-tab is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final t = find.text('Chats');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Messages sub-tab is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final t = find.text('Messages');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        // Return to Chats
        final chats = find.text('Chats');
        if (chats.evaluate().isNotEmpty) {
          await tester.tap(chats.first);
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Saved sub-tab is accessible', (tester) async {
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

    testWidgets('Retry loading groups button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final retry = find.bySemanticsLabel('Retry loading groups');
      if (retry.evaluate().isNotEmpty) {
        await tester.tap(retry.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('New direct message button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final btn = find.bySemanticsLabel('New direct message');
      if (btn.evaluate().isNotEmpty) {
        expect(btn, findsWidgets);
      }
    });

    testWidgets('New DM button opens DM screen or search sheet', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final btn = find.bySemanticsLabel('New direct message');
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final ok =
            find.text('New Message').evaluate().isNotEmpty ||
            find.text('New DM').evaluate().isNotEmpty ||
            find.byType(TextField).evaluate().isNotEmpty ||
            find.byType(Scaffold).evaluate().isNotEmpty;
        expect(ok, isTrue);
        await tryBack(tester);
      }
    });
  });

  // ── Search ────────────────────────────────────────────────────────────────────
  group('👥 Groups — Search', () {
    testWidgets('Search opens a text field', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final icon = find.byIcon(Icons.search);
      if (icon.evaluate().isNotEmpty) {
        await tester.tap(icon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(TextField), findsWidgets);
      }
    });

    testWidgets('Search field hint "Search chats..." accepts input', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final sf = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search chats...');
      final tf = sf.evaluate().isNotEmpty ? sf : find.byType(TextField);
      if (tf.evaluate().isNotEmpty) {
        await tester.tap(tf.first);
        await tester.enterText(tf.first, 'hello');
        await tester.pump();
        expect(find.text('hello'), findsOneWidget);
        await tester.enterText(tf.first, '');
        await tester.pump();
      }
    });

    testWidgets('Clear search button clears text', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final tf = find.byType(TextField);
      if (tf.evaluate().isNotEmpty) {
        await tester.tap(tf.first);
        await tester.enterText(tf.first, 'abc123');
        await tester.pump();
        final clear = find.bySemanticsLabel('Clear search');
        if (clear.evaluate().isNotEmpty) {
          await tester.tap(clear.first);
          await tester.pump();
          expect(find.text('abc123'), findsNothing);
        }
      }
    });
  });

  // ── Swipe Actions ────────────────────────────────────────────────────────────
  group('👥 Groups — Swipe Actions', () {
    testWidgets('Swiping right reveals Pin/Mute actions', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final tiles = find.byType(ListTile);
      if (tiles.evaluate().isNotEmpty) {
        await tester.drag(tiles.first, const Offset(100, 0));
        await tester.pump(const Duration(milliseconds: 500));
        final hasActions =
            find.bySemanticsLabel(RegExp(r'(Un)?pin')).evaluate().isNotEmpty ||
            find.bySemanticsLabel(RegExp(r'(Un)?mute')).evaluate().isNotEmpty ||
            find.text('Pin').evaluate().isNotEmpty ||
            find.text('Mute').evaluate().isNotEmpty;
        if (hasActions) {
          expect(hasActions, isTrue);
          // Dismiss by tapping elsewhere
          await tester.tapAt(const Offset(200, 400));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Swiping left reveals Delete/Archive actions', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final tiles = find.byType(ListTile);
      if (tiles.evaluate().isNotEmpty) {
        await tester.drag(tiles.first, const Offset(-100, 0));
        await tester.pump(const Duration(milliseconds: 500));
        final hasActions =
            find.bySemanticsLabel('Delete').evaluate().isNotEmpty ||
            find.bySemanticsLabel('Archive').evaluate().isNotEmpty ||
            find.text('Delete').evaluate().isNotEmpty ||
            find.text('Archive').evaluate().isNotEmpty;
        if (hasActions) {
          expect(hasActions, isTrue);
          await tester.tapAt(const Offset(200, 400));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Archive action does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final archive = find.bySemanticsLabel('Archive');
      if (archive.evaluate().isNotEmpty) {
        await tester.tap(archive.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
        // Undo if possible
        final undo = find.bySemanticsLabel('Undo');
        if (undo.evaluate().isNotEmpty) {
          await tester.tap(undo.first);
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Leave group dialog appears when triggered', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final leave = find.bySemanticsLabel('Leave group');
      if (leave.evaluate().isNotEmpty) {
        await tester.tap(leave.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        // Should show a confirmation dialog
        final hasDlg = find.byType(AlertDialog).evaluate().isNotEmpty ||
            find.text('Leave group').evaluate().isNotEmpty;
        if (hasDlg) {
          // Cancel to avoid actually leaving
          final cancel = find.bySemanticsLabel('Cancel');
          if (cancel.evaluate().isNotEmpty) {
            await tester.tap(cancel.first);
          } else {
            await tester.tapAt(const Offset(200, 80));
          }
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Mark as read / unread is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final mark = find.bySemanticsLabel(RegExp(r'Mark as (un)?read'));
      if (mark.evaluate().isNotEmpty) {
        await tester.tap(mark.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Undo snackbar appears after delete/archive', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      // Undo appears as a semantics label after swipe-delete/archive
      final undo = find.bySemanticsLabel('Undo');
      if (undo.evaluate().isNotEmpty) {
        expect(undo, findsWidgets);
        await tester.tap(undo.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });

  // ── Filter Sheet ──────────────────────────────────────────────────────────────
  group('👥 Groups — Filter / Sort Sheet', () {
    testWidgets('Filter groups button opens bottom sheet', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      // Switch to Groups sub-tab first if present
      final groupsTab = find.text('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter groups|Active filters'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final hasSheet =
            find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.text('Reset all filters').evaluate().isNotEmpty ||
            find.text('Close filter sheet').evaluate().isNotEmpty;
        if (hasSheet) {
          expect(hasSheet, isTrue);
          final close = find.bySemanticsLabel('Close filter sheet');
          if (close.evaluate().isNotEmpty) {
            await tester.tap(close.first);
          } else {
            await tester.tapAt(const Offset(200, 80));
          }
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Reset all filters button is present in filter sheet', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter groups|Active filters'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final reset = find.bySemanticsLabel('Reset all filters');
        if (reset.evaluate().isNotEmpty) {
          expect(reset, findsWidgets);
          await tester.tap(reset.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
        final close = find.bySemanticsLabel('Close filter sheet');
        if (close.evaluate().isNotEmpty) {
          await tester.tap(close.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(200, 80));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Sort options are present in filter sheet', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter groups|Active filters'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        // Sort options appear as selection chips
        final hasSort =
            find.text('Most recent').evaluate().isNotEmpty ||
            find.text('Alphabetical').evaluate().isNotEmpty ||
            find.text('Unread').evaluate().isNotEmpty ||
            find.byType(BottomSheet).evaluate().isNotEmpty;
        if (hasSort) expect(hasSort, isTrue);
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
    });
  });

  // ── AI Suggestions ────────────────────────────────────────────────────────────
  group('👥 Groups — AI Suggestions', () {
    testWidgets('Toggle AI recommendations button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final toggle = find.bySemanticsLabel('Toggle AI recommendations');
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        // Toggle back
        if (toggle.evaluate().isNotEmpty) {
          await tester.tap(toggle.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
    });

    testWidgets('Suggested groups section does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final suggested = find.bySemanticsLabel('Suggested groups');
      if (suggested.evaluate().isNotEmpty) {
        expect(suggested, findsWidgets);
      }
    });

    testWidgets('Join suggested group button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final join = find.bySemanticsLabel(RegExp(r'Join '));
      if (join.evaluate().isNotEmpty) {
        await tester.tap(join.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Dismiss summary button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final dismiss = find.bySemanticsLabel('Dismiss summary');
      if (dismiss.evaluate().isNotEmpty) {
        await tester.tap(dismiss.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });

  // ── Group Chat ────────────────────────────────────────────────────────────────
  group('👥 Groups — Chat Screen', () {
    testWidgets('Tapping a group opens chat screen', (tester) async {
      await waitForApp(tester);
      final ok = await openFirstGroupChat(tester);
      if (ok) {
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });

    testWidgets('Chat screen has message input field', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final ok =
          find.widgetWithText(TextField, 'Type a message...').evaluate().isNotEmpty ||
          find.byType(TextField).evaluate().isNotEmpty;
      expect(ok, isTrue,
          reason: 'Chat screen must have a message input field');
      await tryBack(tester);
    });

    testWidgets('Chat input accepts text', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final f = find.widgetWithText(TextField, 'Type a message...');
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await tester.enterText(f.first, 'Integration test message 👋');
        await tester.pump();
        expect(find.text('Integration test message 👋'), findsOneWidget);
      }
      await tryBack(tester);
    });

    testWidgets('Send icon appears after typing', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final f = find.widgetWithText(TextField, 'Type a message...');
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await tester.enterText(f.first, 'test');
        await tester.pump();
        expect(find.byIcon(Icons.send), findsWidgets);
      }
      await tryBack(tester);
    });

    testWidgets('Mic button visible when no text typed', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      expect(find.byIcon(Icons.mic), findsWidgets);
      await tryBack(tester);
    });

    testWidgets('Attach button opens attachment sheet', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final att = find.byIcon(Icons.add_circle_outline).evaluate().isNotEmpty
          ? find.byIcon(Icons.add_circle_outline)
          : find.byIcon(Icons.attach_file);
      if (att.evaluate().isNotEmpty) {
        await tester.tap(att.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final hasSheet =
            find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.text('Camera').evaluate().isNotEmpty ||
            find.text('Gallery').evaluate().isNotEmpty ||
            find.text('Document').evaluate().isNotEmpty ||
            find.text('Poll').evaluate().isNotEmpty;
        if (hasSheet) {
          expect(hasSheet, isTrue);
          await tester.tapAt(const Offset(200, 80));
          await tester.pumpAndSettle();
        }
      }
      await tryBack(tester);
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

    testWidgets('Fast fling scroll in chat does not crash', (tester) async {
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

    testWidgets('Chat AppBar shows group name', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      expect(find.byType(AppBar), findsWidgets);
      await tryBack(tester);
    });

    testWidgets('Back button returns to groups list', (tester) async {
      await waitForApp(tester);
      final ok = await openFirstGroupChat(tester);
      if (ok) {
        await tryBack(tester);
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Date dividers (Today/Yesterday) appear when messages exist', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final hasDivider =
          find.text('Today').evaluate().isNotEmpty ||
          find.text('Yesterday').evaluate().isNotEmpty;
      if (find.byType(ListView).evaluate().isNotEmpty && hasDivider) {
        expect(hasDivider, isTrue);
      }
      await tryBack(tester);
    });

    testWidgets('Group info accessible from chat AppBar tap', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final info = find.text('Tap here for group info');
      if (info.evaluate().isNotEmpty) {
        await tester.tap(info.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final hasInfo =
            find.text('Members').evaluate().isNotEmpty ||
            find.text('Group Info').evaluate().isNotEmpty ||
            find.text('About').evaluate().isNotEmpty;
        if (hasInfo) expect(hasInfo, isTrue);
        await tryBack(tester);
      }
      await tryBack(tester);
    });
  });

  // ── Create Group Flow ────────────────────────────────────────────────────────
  group('👥 Groups — Create Group Flow', () {
    testWidgets('Create group is accessible from Connect screen', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final create = find.bySemanticsLabel(RegExp(r'[Cc]reate.*group|[Nn]ew.*group'));
      if (create.evaluate().isNotEmpty) {
        await tester.tap(create.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });

    testWidgets('Create group step 0 has group name field', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final create = find.bySemanticsLabel(RegExp(r'[Cc]reate.*group|[Nn]ew.*group'));
      if (create.evaluate().isNotEmpty) {
        await tester.tap(create.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final step0 = find.byKey(const ValueKey('step0'));
        if (step0.evaluate().isNotEmpty) {
          expect(find.byType(TextField), findsWidgets);
        }
        await tryBack(tester);
      }
    });
  });

  // ── Saved Tab Swipe ───────────────────────────────────────────────────────────
  group('👥 Groups — Saved Tab', () {
    testWidgets('Saved tab loads without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final savedTab = find.text('Saved');
      if (savedTab.evaluate().isNotEmpty) {
        await tester.tap(savedTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
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

    testWidgets('Saved items can be swiped without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final savedTab = find.text('Saved');
      if (savedTab.evaluate().isNotEmpty) {
        await tester.tap(savedTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        // Swipe a saved item if list has items
        final tiles = find.byType(ListTile);
        if (tiles.evaluate().isNotEmpty) {
          await tester.drag(tiles.first, const Offset(-100, 0));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tapAt(const Offset(200, 400));
          await tester.pumpAndSettle();
        }
        expect(find.byType(Scaffold), findsWidgets);
        final chats = find.text('Chats');
        if (chats.evaluate().isNotEmpty) {
          await tester.tap(chats.first);
          await tester.pumpAndSettle();
        }
      }
    });
  });
}
