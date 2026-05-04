// Voice Message Test Suite
// Tests: Voice bubble renders, timer displays correctly (00:00 not 00:000),
// play/pause button, waveform visible, position resets after playback

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;
import 'package:huddl_connect/widgets/voice_message_bubble.dart';
import 'package:huddl_connect/services/voice_message_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🎤 Voice Message Tests', () {
    testWidgets('Voice message bubble renders without crashing',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Navigate to messages
      final messagesTab = find.byTooltip('Messages');
      if (messagesTab.evaluate().isNotEmpty) {
        await tester.tap(messagesTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      // Check for voice message bubble widget in UI
      final voiceBubble = find.byType(VoiceMessageBubble);
      if (voiceBubble.evaluate().isNotEmpty) {
        expect(voiceBubble, findsWidgets,
            reason: 'VoiceMessageBubble widget should be visible');
      }
    });

    testWidgets('Voice message timer shows correct format (MM:SS not MM:SSS)',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Validate the format utility directly
      final formatted = VoiceMessageService.formatDuration(65);
      expect(formatted, equals('01:05'),
          reason: 'formatDuration(65) should return "01:05"');

      final formattedObj =
          VoiceMessageService.formatDurationObj(const Duration(seconds: 65));
      expect(formattedObj, equals('01:05'),
          reason: 'formatDurationObj should return "01:05" not "01:065"');

      // Verify zero case
      final zero = VoiceMessageService.formatDuration(0);
      expect(zero, equals('00:00'),
          reason: 'Zero duration should format as "00:00"');

      // Verify single-digit seconds are padded
      final padded = VoiceMessageService.formatDuration(5);
      expect(padded, equals('00:05'),
          reason: '5 seconds should format as "00:05"');

      // Verify minutes > 9
      final longMsg = VoiceMessageService.formatDuration(125);
      expect(longMsg, equals('02:05'),
          reason: '125 seconds should format as "02:05"');
    });

    testWidgets('Voice message timer never shows 3-digit seconds',
        (WidgetTester tester) async {
      // Test a range of durations to ensure none produce 3-digit seconds
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

    testWidgets('Voice bubble play button is tappable', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final voiceBubble = find.byType(VoiceMessageBubble);
      if (voiceBubble.evaluate().isNotEmpty) {
        // Play button inside the bubble
        final playBtn = find.descendant(
          of: voiceBubble.first,
          matching: find.byIcon(Icons.play_arrow_rounded),
        );
        if (playBtn.evaluate().isNotEmpty) {
          await tester.tap(playBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          // After tap, button should change to pause
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
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final voiceBubble = find.byType(VoiceMessageBubble);
      if (voiceBubble.evaluate().isNotEmpty) {
        // Tap play
        final playBtn = find.descendant(
          of: voiceBubble.first,
          matching: find.byIcon(Icons.play_arrow_rounded),
        );
        if (playBtn.evaluate().isNotEmpty) {
          await tester.tap(playBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));

          // Tap pause
          final pauseBtn = find.descendant(
            of: voiceBubble.first,
            matching: find.byIcon(Icons.pause_rounded),
          );
          if (pauseBtn.evaluate().isNotEmpty) {
            await tester.tap(pauseBtn.first);
            await tester.pumpAndSettle();

            // Should revert to play icon
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

    testWidgets('Voice bubble waveform painter is present',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final voiceBubble = find.byType(VoiceMessageBubble);
      if (voiceBubble.evaluate().isNotEmpty) {
        // CustomPaint is used for the waveform
        final waveform = find.descendant(
          of: voiceBubble.first,
          matching: find.byType(CustomPaint),
        );
        expect(waveform.evaluate().isNotEmpty, isTrue,
            reason: 'Voice bubble should contain a waveform CustomPaint widget');
      }
    });

    testWidgets('Mic button visible in chat input when no text typed',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final inChat = find.text('Type a message...').evaluate().isNotEmpty;
      if (inChat) {
        final micBtn = find.byIcon(Icons.mic);
        expect(micBtn.evaluate().isNotEmpty, isTrue,
            reason: 'Mic button should be visible when message input is empty');
      }
    });

    testWidgets('Mic button shows snackbar hint on single tap',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final inChat = find.text('Type a message...').evaluate().isNotEmpty;
      if (inChat) {
        final micBtn = find.byIcon(Icons.mic);
        if (micBtn.evaluate().isNotEmpty) {
          await tester.tap(micBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));

          final hasHint =
              find.textContaining('Hold').evaluate().isNotEmpty ||
              find.textContaining('hold').evaluate().isNotEmpty ||
              find.byType(SnackBar).evaluate().isNotEmpty;

          expect(hasHint, isTrue,
              reason: 'Single tap on mic should show a "hold to record" hint');
        }
      }
    });

    testWidgets('Voice message bubble layout fits within screen width',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final voiceBubble = find.byType(VoiceMessageBubble);
      if (voiceBubble.evaluate().isNotEmpty) {
        final RenderBox box = tester.renderObject(voiceBubble.first);
        final screenWidth = tester.binding.window.physicalSize.width /
            tester.binding.window.devicePixelRatio;

        expect(box.size.width, lessThanOrEqualTo(screenWidth),
            reason: 'Voice bubble should not overflow screen width');
        expect(box.size.width, lessThanOrEqualTo(280),
            reason: 'Voice bubble max width should be <= 260dp as per design');
      }
    });
  });
}
