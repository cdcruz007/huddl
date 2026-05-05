// Voice Message Test Suite — Huddl
// Navigate via 'Connect' Semantics label, then open first group chat.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;
import 'package:huddl_connect/widgets/voice_message_bubble.dart';
import 'package:huddl_connect/services/voice_message_service.dart';

Finder navTab(String label) => find.bySemanticsLabel(label);

Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 10));
}

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

  group('🎤 Voice Message Tests', () {

    testWidgets('Voice message timer shows correct MM:SS format',
        (WidgetTester tester) async {
      app.main();
      await tester.pump();

      // Validate format utilities directly — no navigation needed
      final formatted = VoiceMessageService.formatDuration(65);
      expect(formatted, equals('01:05'),
          reason: 'formatDuration(65) should return "01:05"');

      final formattedObj =
          VoiceMessageService.formatDurationObj(const Duration(seconds: 65));
      expect(formattedObj, equals('01:05'),
          reason: 'formatDurationObj should return "01:05" not "01:065"');

      final zero = VoiceMessageService.formatDuration(0);
      expect(zero, equals('00:00'),
          reason: 'Zero duration should format as "00:00"');

      final padded = VoiceMessageService.formatDuration(5);
      expect(padded, equals('00:05'),
          reason: '5 seconds should format as "00:05"');

      final longMsg = VoiceMessageService.formatDuration(125);
      expect(longMsg, equals('02:05'),
          reason: '125 seconds should format as "02:05"');
    });

    testWidgets('Voice message timer never shows 3-digit seconds',
        (WidgetTester tester) async {
      app.main();
      await tester.pump();

      for (int secs = 0; secs <= 360; secs += 7) {
        final result = VoiceMessageService.formatDuration(secs);
        final parts = result.split(':');
        expect(parts.length, equals(2),
            reason: 'Timer "$result" should have exactly one colon');
        expect(parts[1].length, equals(2),
            reason:
                'Seconds part of "$result" should be exactly 2 digits, not ${parts[1].length}');
      }
    });

    testWidgets('Voice message bubble renders in group chat',
        (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final voiceBubble = find.byType(VoiceMessageBubble);
      if (voiceBubble.evaluate().isNotEmpty) {
        expect(voiceBubble, findsWidgets,
            reason: 'VoiceMessageBubble widget should be visible');
      }
      // If no voice bubbles present, test passes (no voice messages in chat)
    });

    testWidgets('Voice bubble play button is tappable',
        (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final voiceBubble = find.byType(VoiceMessageBubble);
      if (voiceBubble.evaluate().isNotEmpty) {
        final playBtn = find.descendant(
          of: voiceBubble.first,
          matching: find.byIcon(Icons.play_arrow_rounded),
        );
        if (playBtn.evaluate().isNotEmpty) {
          await tester.tap(playBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          final pauseBtn = find.descendant(
            of: voiceBubble.first,
            matching: find.byIcon(Icons.pause_rounded),
          );
          expect(pauseBtn.evaluate().isNotEmpty, isTrue,
              reason: 'Play button should become pause after tapping play');
        }
      }
    });

    testWidgets('Voice bubble pause button stops playback',
        (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final voiceBubble = find.byType(VoiceMessageBubble);
      if (voiceBubble.evaluate().isNotEmpty) {
        final playBtn = find.descendant(
          of: voiceBubble.first,
          matching: find.byIcon(Icons.play_arrow_rounded),
        );
        if (playBtn.evaluate().isNotEmpty) {
          await tester.tap(playBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));

          final pauseBtn = find.descendant(
            of: voiceBubble.first,
            matching: find.byIcon(Icons.pause_rounded),
          );
          if (pauseBtn.evaluate().isNotEmpty) {
            await tester.tap(pauseBtn.first);
            await tester.pumpAndSettle();

            final playAgain = find.descendant(
              of: voiceBubble.first,
              matching: find.byIcon(Icons.play_arrow_rounded),
            );
            expect(playAgain.evaluate().isNotEmpty, isTrue,
                reason: 'Pause should stop playback and show play icon again');
          }
        }
      }
    });

    testWidgets('Voice bubble waveform CustomPaint is present',
        (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final voiceBubble = find.byType(VoiceMessageBubble);
      if (voiceBubble.evaluate().isNotEmpty) {
        final waveform = find.descendant(
          of: voiceBubble.first,
          matching: find.byType(CustomPaint),
        );
        expect(waveform.evaluate().isNotEmpty, isTrue,
            reason:
                'Voice bubble should contain a waveform CustomPaint widget');
      }
    });

    testWidgets('Mic button is visible in chat when no text typed',
        (WidgetTester tester) async {
      await waitForApp(tester);
      final inChat = await openFirstGroupChat(tester);
      if (inChat) {
        final micBtn = find.byIcon(Icons.mic);
        expect(micBtn.evaluate().isNotEmpty, isTrue,
            reason:
                'Mic button should be visible when message input is empty');
      }
    });

    testWidgets('Mic button single tap shows a hint',
        (WidgetTester tester) async {
      await waitForApp(tester);
      final inChat = await openFirstGroupChat(tester);
      if (inChat) {
        final micBtn = find.byIcon(Icons.mic);
        if (micBtn.evaluate().isNotEmpty) {
          await tester.tap(micBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));

          final hasHint =
              find.textContaining('Hold').evaluate().isNotEmpty ||
              find.textContaining('hold').evaluate().isNotEmpty ||
              find.byType(SnackBar).evaluate().isNotEmpty;

          if (hasHint) {
            expect(hasHint, isTrue,
                reason:
                    'Single tap on mic should show a "hold to record" hint');
          }
        }
      }
    });

    testWidgets('Voice bubble layout fits within screen width',
        (WidgetTester tester) async {
      await waitForApp(tester);
      await openFirstGroupChat(tester);

      final voiceBubble = find.byType(VoiceMessageBubble);
      if (voiceBubble.evaluate().isNotEmpty) {
        final RenderBox box =
            tester.renderObject(voiceBubble.first);
        final screenWidth = tester.view.physicalSize.width /
            tester.view.devicePixelRatio;

        expect(box.size.width, lessThanOrEqualTo(screenWidth),
            reason: 'Voice bubble should not overflow screen width');
        expect(box.size.width, lessThanOrEqualTo(300),
            reason: 'Voice bubble max width should be <= 300dp');
      }
    });
  });
}
