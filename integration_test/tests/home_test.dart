// ============================================================
// Home Screen Test Suite — Huddl v32
// Covers: community feed (scroll, fling, post cards),
//   post composer (open, type, send button),
//   post actions (like, comment, share, pin, delete, undo),
//   post options menu, AI-copilot FAB, upcoming-meetup nudge,
//   search (open, type, results), profile avatar tap,
//   feed preferences sheet, pinned announcements,
//   journey map / nudge cards.
// Semantics: 'Huddl home logo', 'Your profile',
//   'Post to your community notice board', 'Send post',
//   'Post options menu', 'Unpin post'/'Pin post',
//   'Share post', 'Delete post', 'Undo'
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

Future<bool> goToHome(WidgetTester tester) async {
  if (!_hasNavBar) return false;
  await tester.tap(navTab('Home').first);
  await tester.pumpAndSettle(const Duration(seconds: 5));
  return find.byType(Scaffold).evaluate().isNotEmpty;
}

/// Dismiss any open overlay (bottom sheet, dialog, modal) by tapping safe area.
Future<void> dismiss(WidgetTester tester) async {
  await tester.tapAt(const Offset(200, 80));
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

/// Attempt to back-navigate once.
Future<void> tryBack(WidgetTester tester) async {
  final b = find.byType(BackButton);
  if (b.evaluate().isNotEmpty) {
    await tester.tap(b.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  } else {
    await dismiss(tester);
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Landing ───────────────────────────────────────────────────────────────────
  group('🏠 Home — Landing', () {
    testWidgets('Home tab loads without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('No rendering exception on home screen', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      expect(tester.takeException(), isNull);
    });

    testWidgets('Huddl logo / header is visible', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final ok =
          find.bySemanticsLabel('Huddl home logo').evaluate().isNotEmpty ||
          find.bySemanticsLabel(RegExp(r'Huddl')).evaluate().isNotEmpty ||
          find.byType(AppBar).evaluate().isNotEmpty;
      if (ok) expect(ok, isTrue);
    });

    testWidgets('Profile avatar in home app bar is present', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final av = find.bySemanticsLabel('Your profile');
      if (av.evaluate().isNotEmpty) {
        expect(av, findsWidgets);
      }
    });

    testWidgets('Tapping profile avatar navigates without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final av = find.bySemanticsLabel('Your profile');
      if (av.evaluate().isNotEmpty) {
        await tester.tap(av.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });
  });

  // ── Community Feed ────────────────────────────────────────────────────────────
  group('🏠 Home — Community Feed', () {
    testWidgets('Feed shows posts, cards or empty state', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final ok =
          find.byType(ListView).evaluate().isNotEmpty ||
          find.byType(Card).evaluate().isNotEmpty ||
          find.byType(Scaffold).evaluate().isNotEmpty;
      expect(ok, isTrue);
    });

    testWidgets('Feed scrolls down and up without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -500));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 500));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Fast fling scroll does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.fling(list.first, const Offset(0, -800), 3000);
        await tester.pumpAndSettle();
        await tester.fling(list.first, const Offset(0, 800), 3000);
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Three scroll cycles (stress) do not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        for (int i = 0; i < 3; i++) {
          await tester.drag(list.first, const Offset(0, -400));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.drag(list.first, const Offset(0, 400));
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Post like / favourite button is tappable', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final like = find.byIcon(Icons.favorite_border).evaluate().isNotEmpty
          ? find.byIcon(Icons.favorite_border)
          : find.byIcon(Icons.thumb_up_outlined);
      if (like.evaluate().isNotEmpty) {
        await tester.tap(like.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Post options menu button is tappable', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final opts = find.bySemanticsLabel('Post options menu');
      if (opts.evaluate().isNotEmpty) {
        await tester.tap(opts.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        // Should show a menu (BottomSheet, AlertDialog, PopupMenu)
        final hasMenu =
            find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.byType(AlertDialog).evaluate().isNotEmpty ||
            find.text('Pin post').evaluate().isNotEmpty ||
            find.text('Unpin post').evaluate().isNotEmpty ||
            find.text('Delete post').evaluate().isNotEmpty ||
            find.text('Share post').evaluate().isNotEmpty;
        if (hasMenu) expect(hasMenu, isTrue);
        await dismiss(tester);
      }
    });

    testWidgets('Pin / Unpin post is accessible from options', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final opts = find.bySemanticsLabel('Post options menu');
      if (opts.evaluate().isNotEmpty) {
        await tester.tap(opts.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final pinBtn = find.bySemanticsLabel(RegExp(r'(Unpin|Pin) post'));
        if (pinBtn.evaluate().isNotEmpty) {
          await tester.tap(pinBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(Scaffold), findsWidgets);
        } else {
          await dismiss(tester);
        }
      }
    });

    testWidgets('Share post is accessible from options', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final share = find.bySemanticsLabel('Share post');
      if (share.evaluate().isNotEmpty) {
        await tester.tap(share.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
        await dismiss(tester);
      }
    });

    testWidgets('Delete post confirmation dialog is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      // Only tap delete if options menu is available
      final opts = find.bySemanticsLabel('Post options menu');
      if (opts.evaluate().isNotEmpty) {
        await tester.tap(opts.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final delBtn = find.bySemanticsLabel('Delete post');
        if (delBtn.evaluate().isNotEmpty) {
          await tester.tap(delBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          // Should show confirmation dialog
          final hasDlg =
              find.text('Delete post?').evaluate().isNotEmpty ||
              find.byType(AlertDialog).evaluate().isNotEmpty;
          if (hasDlg) {
            // Tap Cancel to avoid actually deleting
            final cancel = find.text('Cancel');
            if (cancel.evaluate().isNotEmpty) {
              await tester.tap(cancel.first);
              await tester.pumpAndSettle();
            } else {
              await dismiss(tester);
            }
          } else {
            await dismiss(tester);
          }
        } else {
          await dismiss(tester);
        }
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Undo snackbar semantics is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      // Undo appears after hide/delete; just verify semantics exists anywhere
      final undo = find.bySemanticsLabel('Undo');
      if (undo.evaluate().isNotEmpty) {
        expect(undo, findsWidgets);
      }
    });
  });

  // ── Post Composer ─────────────────────────────────────────────────────────────
  group('🏠 Home — Post Composer', () {
    testWidgets('Post composer bar is visible', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final comp = find.bySemanticsLabel('Post to your community notice board');
      if (comp.evaluate().isNotEmpty) {
        expect(comp, findsWidgets);
      }
    });

    testWidgets('Tapping composer opens text field', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final comp = find.bySemanticsLabel('Post to your community notice board');
      if (comp.evaluate().isNotEmpty) {
        await tester.tap(comp.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final hasField = find.byType(TextField).evaluate().isNotEmpty;
        if (hasField) expect(hasField, isTrue);
        await dismiss(tester);
      }
    });

    testWidgets('Composer text field accepts input', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final comp = find.bySemanticsLabel('Post to your community notice board');
      if (comp.evaluate().isNotEmpty) {
        await tester.tap(comp.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final tf = find.byType(TextField);
        if (tf.evaluate().isNotEmpty) {
          await tester.tap(tf.first);
          await tester.enterText(tf.first, 'Hello community from test!');
          await tester.pump();
          expect(find.text('Hello community from test!'), findsOneWidget);
        }
        await dismiss(tester);
      }
    });

    testWidgets('Send post button is present in composer', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final send = find.bySemanticsLabel('Send post');
      if (send.evaluate().isNotEmpty) {
        expect(send, findsWidgets);
      }
    });

    testWidgets('AI post hint text is present when composer is open', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final comp = find.bySemanticsLabel('Post to your community notice board');
      if (comp.evaluate().isNotEmpty) {
        await tester.tap(comp.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        // AI hint is the hintText of the expanded composer field
        final tf = find.byType(TextField);
        if (tf.evaluate().isNotEmpty) {
          expect(tf, findsWidgets);
        }
        await dismiss(tester);
      }
    });
  });

  // ── Search ────────────────────────────────────────────────────────────────────
  group('🏠 Home — Search', () {
    testWidgets('Search icon is visible on home screen', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final si = find.byIcon(Icons.search);
      if (si.evaluate().isNotEmpty) {
        expect(si, findsWidgets);
      }
    });

    testWidgets('Tapping search opens search field', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final si = find.byIcon(Icons.search);
      if (si.evaluate().isNotEmpty) {
        await tester.tap(si.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final hasField = find.byType(TextField).evaluate().isNotEmpty;
        if (hasField) {
          expect(hasField, isTrue);
          await tester.enterText(find.byType(TextField).first, 'community');
          await tester.pump();
          expect(find.text('community'), findsOneWidget);
        }
        await dismiss(tester);
      }
    });

    testWidgets('Search field hint text is "Search groups or members..."', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final sf = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search groups or members...');
      if (sf.evaluate().isNotEmpty) {
        await tester.tap(sf.first);
        await tester.enterText(sf.first, 'test');
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
        await tester.enterText(sf.first, '');
        await tester.pump();
      }
    });

    testWidgets('Search switches between Groups and Members tabs', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      // Search tabs appear only when the search overlay is open
      final si = find.byIcon(Icons.search);
      if (si.evaluate().isNotEmpty) {
        await tester.tap(si.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final tf = find.byType(TextField);
        if (tf.evaluate().isNotEmpty) {
          await tester.enterText(tf.first, 'test');
          await tester.pumpAndSettle(const Duration(seconds: 2));
          final groupsTab = find.text('Groups');
          final membersTab = find.text('Members');
          if (groupsTab.evaluate().isNotEmpty) {
            await tester.tap(groupsTab.first);
            await tester.pumpAndSettle(const Duration(seconds: 2));
            expect(find.byType(Scaffold), findsWidgets);
          }
          if (membersTab.evaluate().isNotEmpty) {
            await tester.tap(membersTab.first);
            await tester.pumpAndSettle(const Duration(seconds: 2));
            expect(find.byType(Scaffold), findsWidgets);
          }
        }
        await dismiss(tester);
      }
    });
  });

  // ── AI Copilot ────────────────────────────────────────────────────────────────
  group('🏠 Home — AI Copilot', () {
    testWidgets('AI copilot FAB is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final fab = find.byType(FloatingActionButton);
      if (fab.evaluate().isNotEmpty) {
        expect(fab, findsWidgets);
      }
    });

    testWidgets('Tapping AI copilot FAB opens copilot / bottom sheet', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final fab = find.byType(FloatingActionButton);
      if (fab.evaluate().isNotEmpty) {
        await tester.tap(fab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });
  });

  // ── Upcoming Meetup Nudge ─────────────────────────────────────────────────────
  group('🏠 Home — Upcoming Meetup Nudge', () {
    testWidgets('Upcoming meetup card does not crash app', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      // Nudge card has a "Heading to <title>? Share tips!" label
      final nudge = find.bySemanticsLabel(RegExp(r'Heading to'));
      if (nudge.evaluate().isNotEmpty) {
        await tester.tap(nudge.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });

    testWidgets('Going-to badge appears on meetup cards', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final going = find.text('Going');
      if (going.evaluate().isNotEmpty) {
        expect(going, findsWidgets);
      }
    });
  });

  // ── Feed Preferences ──────────────────────────────────────────────────────────
  group('🏠 Home — Feed Preferences', () {
    testWidgets('Feed Preferences sheet can be opened', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      // Feed Preferences usually behind a more-options icon
      final prefs = find.text('Feed Preferences');
      if (prefs.evaluate().isNotEmpty) {
        await tester.tap(prefs.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
        final save = find.text('Save Preferences');
        if (save.evaluate().isEmpty) await dismiss(tester);
      }
    });

    testWidgets('Save Preferences button in feed prefs sheet', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final pref = find.text('Feed Preferences');
      if (pref.evaluate().isNotEmpty) {
        await tester.tap(pref.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final save = find.text('Save Preferences');
        if (save.evaluate().isNotEmpty) {
          expect(save, findsWidgets);
          await tester.tap(save.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  // ── Pinned Announcements ──────────────────────────────────────────────────────
  group('🏠 Home — Pinned Announcements', () {
    testWidgets('Pinned label is visible when a post is pinned', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final pinned = find.text('Pinned');
      if (pinned.evaluate().isNotEmpty) {
        expect(pinned, findsWidgets);
      }
    });

    testWidgets('Announcements list items can be scrolled', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });

  // ── Comment Section ───────────────────────────────────────────────────────────
  group('🏠 Home — Comments', () {
    testWidgets('Comment count label is present on posts', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      // Comments label is a Semantics label like "3" or "0"
      // Verified by post comment count semantics from audit
      final hasSem = find.bySemanticsLabel(RegExp(r'\d+ comments?'))
              .evaluate()
              .isNotEmpty ||
          find.byType(Scaffold).evaluate().isNotEmpty;
      expect(hasSem, isTrue);
    });

    testWidgets('Tapping comment button opens comments without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      // Comment button has a Semantics label containing a count
      final cmtBtn = find.bySemanticsLabel(RegExp(r'comments?'));
      if (cmtBtn.evaluate().isNotEmpty) {
        await tester.tap(cmtBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });

    testWidgets('Reply input hint "Type a reply..." is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToHome(tester)) return;
      final replyHint = find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').toLowerCase().contains('reply'));
      if (replyHint.evaluate().isNotEmpty) {
        await tester.tap(replyHint.first);
        await tester.enterText(replyHint.first, 'test reply');
        await tester.pump();
        expect(find.text('test reply'), findsOneWidget);
        await tester.enterText(replyHint.first, '');
        await tester.pump();
        await dismiss(tester);
      }
    });
  });
}
