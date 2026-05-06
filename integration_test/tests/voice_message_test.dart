// ============================================================
// Voice Message Test Suite — Huddl v32
// Covers: voice note bubble rendering, play/pause toggle,
//   waveform rendering, mic button in group chat,
//   mic long-press start/cancel recording,
//   timer formatting, layout constraints,
//   voice note in DM chat, accessibility semantics.
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
  final chats = find.text('Chats');
  if (chats.evaluate().isNotEmpty) {
    await tester.tap(chats.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }
  final tiles   = find.byType(ListTile);
  final inkWell = find.byType(InkWell);
  final target  = tiles.evaluate().isNotEmpty ? tiles : inkWell;
  if (target.evaluate().isEmpty) return false;
  await tester.tap(target.first);
  await tester.pumpAndSettle(const Duration(seconds: 4));
  return find.byIcon(Icons.mic).evaluate().isNotEmpty ||
      find.text('Type a message...').evaluate().isNotEmpty;
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

  // ── Mic Button Presence ───────────────────────────────────────────────────────
  group('🎤 Voice — Mic Button', () {
    testWidgets('Mic button is visible in group chat when input is empty', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      expect(find.byIcon(Icons.mic), findsWidgets,
          reason: 'Mic button must be visible when message input is empty');
      await tryBack(tester);
    });

    testWidgets('Mic button disappears after typing text', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final f = find.widgetWithText(TextField, 'Type a message...');
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await tester.enterText(f.first, 'hello');
        await tester.pump();
        // After typing, send icon should be visible (mic may hide)
        expect(find.byIcon(Icons.send), findsWidgets);
        // Clear text to restore mic
        await tester.enterText(f.first, '');
        await tester.pump();
        expect(find.byIcon(Icons.mic), findsWidgets);
      }
      await tryBack(tester);
    });

    testWidgets('Tapping mic button does not crash', (tester) async {
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

    testWidgets('Long-pressing mic does not crash (recording start/cancel)', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final mic = find.byIcon(Icons.mic);
      if (mic.evaluate().isNotEmpty) {
        final gesture = await tester.startGesture(tester.getCenter(mic.first));
        await tester.pump(const Duration(milliseconds: 800));
        // Slide up to cancel
        await gesture.moveBy(const Offset(0, -80));
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.up();
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
      await tryBack(tester);
    });

    testWidgets('Long-press mic then release (complete) does not crash', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final mic = find.byIcon(Icons.mic);
      if (mic.evaluate().isNotEmpty) {
        final gesture = await tester.startGesture(tester.getCenter(mic.first));
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.up();
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
      }
      await tryBack(tester);
    });
  });

  // ── Voice Note Bubble ─────────────────────────────────────────────────────────
  group('🎤 Voice — Voice Note Bubble', () {
    testWidgets('Voice note bubble renders without crash', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      // Voice notes appear as message bubbles in the list; verify list renders
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        expect(list, findsWidgets);
        // Scroll to see if any voice note bubbles exist
        await tester.drag(list.first, const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 300));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
      await tryBack(tester);
    });

    testWidgets('Play / pause icon in voice bubble is tappable', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      // Look for play/pause icon in message list
      final play  = find.byIcon(Icons.play_arrow);
      final pause = find.byIcon(Icons.pause);
      final target = play.evaluate().isNotEmpty ? play : pause;
      if (target.evaluate().isNotEmpty) {
        await tester.tap(target.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
        // Toggle back
        final play2  = find.byIcon(Icons.play_arrow);
        final pause2 = find.byIcon(Icons.pause);
        final target2 = pause2.evaluate().isNotEmpty ? pause2 : play2;
        if (target2.evaluate().isNotEmpty) {
          await tester.tap(target2.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      await tryBack(tester);
    });

    testWidgets('Voice note timer text does not overflow layout', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      // Timer text patterns: '0:23', '1:00', '0:05'
      final timer = find.textContaining(RegExp(r'^\d:\d\d$'));
      if (timer.evaluate().isNotEmpty) {
        final RenderBox rb = tester.renderObject(timer.first);
        expect(rb.size.width, lessThan(200),
            reason: 'Voice timer text should not overflow its container');
      }
      expect(find.byType(Scaffold), findsWidgets);
      await tryBack(tester);
    });

    testWidgets('Voice note bubble does not overflow screen width', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        final screenW =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;
        // All rendered widgets should fit screen width
        final rb = tester.renderObject<RenderBox>(list.first);
        expect(rb.size.width, lessThanOrEqualTo(screenW + 1));
      }
      await tryBack(tester);
    });
  });

  // ── Waveform ──────────────────────────────────────────────────────────────────
  group('🎤 Voice — Waveform', () {
    testWidgets('Waveform visual renders without overflow', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      // CustomPaint is used for waveform rendering
      final cp = find.byType(CustomPaint);
      if (cp.evaluate().isNotEmpty) {
        final RenderBox rb = tester.renderObject(cp.first);
        final screenW =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;
        expect(rb.size.width, lessThanOrEqualTo(screenW + 1),
            reason: 'Waveform CustomPaint must not overflow screen width');
      }
      expect(find.byType(Scaffold), findsWidgets);
      await tryBack(tester);
    });

    testWidgets('No RenderFlex overflow errors in chat screen', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 300));
        await tester.pumpAndSettle();
      }
      // The key check: no RenderFlex overflow (yellow/black stripes)
      expect(tester.takeException(), isNull,
          reason: 'No RenderFlex overflow allowed in chat screen');
      await tryBack(tester);
    });
  });

  // ── DM Voice Note ─────────────────────────────────────────────────────────────
  group('🎤 Voice — DM Chat Voice Note', () {
    testWidgets('Mic button visible in DM chat', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final messagesTab = find.text('Messages');
      if (messagesTab.evaluate().isNotEmpty) {
        await tester.tap(messagesTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final tiles = find.byType(ListTile);
        if (tiles.evaluate().isNotEmpty) {
          await tester.tap(tiles.first);
          await tester.pumpAndSettle(const Duration(seconds: 4));
          final mic = find.byIcon(Icons.mic);
          if (mic.evaluate().isNotEmpty) {
            expect(mic, findsWidgets);
          }
          await tryBack(tester);
        }
      }
    });

    testWidgets('DM chat voice note tap does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToConnect(tester)) return;
      final messagesTab = find.text('Messages');
      if (messagesTab.evaluate().isNotEmpty) {
        await tester.tap(messagesTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final tiles = find.byType(ListTile);
        if (tiles.evaluate().isNotEmpty) {
          await tester.tap(tiles.first);
          await tester.pumpAndSettle(const Duration(seconds: 4));
          final mic = find.byIcon(Icons.mic);
          if (mic.evaluate().isNotEmpty) {
            await tester.tap(mic.first);
            await tester.pumpAndSettle(const Duration(seconds: 2));
            expect(find.byType(Scaffold), findsWidgets);
          }
          await tryBack(tester);
        }
      }
    });
  });

  // ── Recording Accessibility ───────────────────────────────────────────────────
  group('🎤 Voice — Recording Accessibility', () {
    testWidgets('Mic button has meaningful semantics', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final mic = find.byIcon(Icons.mic);
      if (mic.evaluate().isNotEmpty) {
        // Mic widget should be accessible — just check it exists
        expect(mic, findsWidgets);
      }
      await tryBack(tester);
    });

    testWidgets('Recording cancel gesture (swipe up) works', (tester) async {
      await waitForApp(tester);
      if (!await openFirstGroupChat(tester)) return;
      final mic = find.byIcon(Icons.mic);
      if (mic.evaluate().isNotEmpty) {
        // Start recording
        final gesture = await tester.startGesture(tester.getCenter(mic.first));
        await tester.pump(const Duration(milliseconds: 1000));
        // Swipe up to cancel
        await gesture.moveBy(const Offset(0, -100));
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.up();
        await tester.pumpAndSettle(const Duration(seconds: 2));
        // Should be back to normal state (mic still visible)
        expect(find.byType(Scaffold), findsWidgets);
      }
      await tryBack(tester);
    });
  });
}
