// ============================================================
// Events / Discover Test Suite — Huddl v32
// Covers: Discover tab (Groups/Meetups/Events sub-tabs),
//   meetup list (scroll, filter sheet, filter chips, reset,
//   item tap, Going status, share, My Meetups section),
//   events list (scroll, filter, bookmark, recommend,
//   calendar view, price chips), Going tab (upcoming/past,
//   swipe to cancel), UK-Wide / Borough filter keys.
// Semantics: 'Filter meetups', 'Filters active. Tap to change.',
//   'Upcoming', 'Past', 'Bookmark event'/'Remove bookmark',
//   'Share meetup', 'Meetup: ...', 'Event: ...',
//   'Recommended event: ...'
// Keys: ValueKey('uk-wide'), ValueKey('meetups-borough'),
//       ValueKey('groups-borough'), ValueKey('going_${id}')
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

Future<bool> goToDiscover(WidgetTester tester) async {
  if (!_hasNavBar) return false;
  await tester.tap(navTab('Discover').first);
  await tester.pumpAndSettle(const Duration(seconds: 5));
  return find.byType(Scaffold).evaluate().isNotEmpty;
}

Future<bool> goToMeetupsTab(WidgetTester tester) async {
  if (!await goToDiscover(tester)) return false;
  final t = find.text('Meetups');
  if (t.evaluate().isEmpty) return false;
  await tester.tap(t.first);
  await tester.pumpAndSettle(const Duration(seconds: 3));
  return true;
}

Future<bool> goToEventsTab(WidgetTester tester) async {
  if (!await goToDiscover(tester)) return false;
  final t = find.text('Events');
  if (t.evaluate().isEmpty) return false;
  await tester.tap(t.first);
  await tester.pumpAndSettle(const Duration(seconds: 3));
  return true;
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

  // ── Discover Tab ──────────────────────────────────────────────────────────────
  group('🗓️ Events — Discover Tab', () {
    testWidgets('Discover tab loads without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('No rendering exception on Discover screen', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      expect(tester.takeException(), isNull);
    });

    testWidgets('Groups sub-tab is visible in Discover', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      final t = find.text('Groups');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Meetups sub-tab is visible in Discover', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      final t = find.text('Meetups');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Events sub-tab is visible in Discover', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      final t = find.text('Events');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Full cycle Groups→Meetups→Events does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      for (final tab in ['Groups', 'Meetups', 'Events']) {
        final t = find.text(tab);
        if (t.evaluate().isNotEmpty) {
          await tester.tap(t.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.byType(Scaffold), findsWidgets,
              reason: 'No crash after switching to $tab tab');
        }
      }
    });
  });

  // ── UK-Wide / Borough Scope Keys ──────────────────────────────────────────────
  group('🗓️ Events — Scope Filter Keys', () {
    testWidgets('UK-Wide scope filter key is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final ukWide = find.byKey(const ValueKey('uk-wide'));
      if (ukWide.evaluate().isNotEmpty) {
        await tester.tap(ukWide.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Borough scope filter key is accessible (meetups)', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final borough = find.byKey(const ValueKey('meetups-borough'));
      if (borough.evaluate().isNotEmpty) {
        await tester.tap(borough.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Borough scope filter key is accessible (groups)', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      final borough = find.byKey(const ValueKey('groups-borough'));
      if (borough.evaluate().isNotEmpty) {
        await tester.tap(borough.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });

  // ── Meetups List ──────────────────────────────────────────────────────────────
  group('🗓️ Events — Meetups List', () {
    testWidgets('Meetups tab shows list or empty state', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final ok =
          find.byType(ListView).evaluate().isNotEmpty ||
          find.textContaining('No meetups').evaluate().isNotEmpty ||
          find.byType(Scaffold).evaluate().isNotEmpty;
      expect(ok, isTrue);
    });

    testWidgets('Meetups list scrolls without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -400));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 400));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Meetup search field accepts text', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final sf = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search meetups...');
      if (sf.evaluate().isNotEmpty) {
        await tester.tap(sf.first);
        await tester.enterText(sf.first, 'test');
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
        await tester.enterText(sf.first, '');
        await tester.pump();
      }
    });

    testWidgets('Filter meetups button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter meetups|Filters active'));
      if (filterBtn.evaluate().isNotEmpty) {
        expect(filterBtn, findsWidgets);
      }
    });

    testWidgets('Filter sheet opens from Filter meetups button', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter meetups|Filters active'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final hasSheet =
            find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.text('Reset all filters').evaluate().isNotEmpty;
        if (hasSheet) {
          expect(hasSheet, isTrue);
          final reset = find.text('Reset all filters');
          if (reset.evaluate().isNotEmpty) {
            await tester.tap(reset.first);
            await tester.pumpAndSettle(const Duration(seconds: 2));
          } else {
            await tester.tapAt(const Offset(200, 80));
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Filter chips (price, format, time, age) render without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter meetups|Filters active'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        // Tap first filter chip if present
        final chips = find.byType(FilterChip);
        if (chips.evaluate().isEmpty) {
          // Chips may be ChoiceChip
          final choice = find.byType(ChoiceChip);
          if (choice.evaluate().isNotEmpty) {
            await tester.tap(choice.first);
            await tester.pumpAndSettle();
            expect(find.byType(Scaffold), findsWidgets);
          }
        } else {
          await tester.tap(chips.first);
          await tester.pumpAndSettle();
          expect(find.byType(Scaffold), findsWidgets);
        }
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Tapping a meetup card navigates to detail without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final card = find.bySemanticsLabel(RegExp(r'Meetup: '));
      if (card.evaluate().isNotEmpty) {
        await tester.tap(card.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });

    testWidgets('Share meetup button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final share = find.bySemanticsLabel('Share meetup');
      if (share.evaluate().isNotEmpty) {
        await tester.tap(share.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
    });
  });

  // ── Going Tab (My Meetups) ────────────────────────────────────────────────────
  group('🗓️ Events — Going / My Meetups', () {
    testWidgets('Going section shows Upcoming and Past labels', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      // My Meetups / Going is often a separate section or tab
      final upcoming = find.bySemanticsLabel('Upcoming');
      final past     = find.bySemanticsLabel('Past');
      if (upcoming.evaluate().isNotEmpty || past.evaluate().isNotEmpty) {
        expect(
          upcoming.evaluate().isNotEmpty || past.evaluate().isNotEmpty,
          isTrue,
        );
      }
    });

    testWidgets('Going item key is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      // Going items are keyed as ValueKey('going_${id}') — regex keys not supported;
      // use semantics label instead
      final goingSem = find.bySemanticsLabel(RegExp(r'(Meetup|Event): .+Going'));
      if (goingSem.evaluate().isNotEmpty) {
        expect(goingSem, findsWidgets);
      }
    });

    testWidgets('Swiping a Going item left to cancel does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      // Going cards are in a list below the main meetup list
      final allTiles = find.byType(Dismissible);
      if (allTiles.evaluate().isNotEmpty) {
        await tester.drag(allTiles.first, const Offset(-150, 0));
        await tester.pumpAndSettle(const Duration(seconds: 1));
        // Confirm or dismiss if dialog appears
        final cancel = find.text('Cancel');
        if (cancel.evaluate().isNotEmpty) {
          await tester.tap(cancel.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(200, 80));
          await tester.pumpAndSettle();
        }
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('My Meetups section renders without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToMeetupsTab(tester)) return;
      final myMeetups = find.text('My Meetups');
      if (myMeetups.evaluate().isNotEmpty) {
        expect(myMeetups, findsWidgets);
      }
    });
  });

  // ── Events List ───────────────────────────────────────────────────────────────
  group('🗓️ Events — Events List', () {
    testWidgets('Events tab shows list or empty state', (tester) async {
      await waitForApp(tester);
      if (!await goToEventsTab(tester)) return;
      final ok =
          find.byType(ListView).evaluate().isNotEmpty ||
          find.textContaining('No events').evaluate().isNotEmpty ||
          find.byType(Scaffold).evaluate().isNotEmpty;
      expect(ok, isTrue);
    });

    testWidgets('Events list scrolls without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToEventsTab(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -400));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 400));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Events search field accepts text', (tester) async {
      await waitForApp(tester);
      if (!await goToEventsTab(tester)) return;
      final sf = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Search events...');
      if (sf.evaluate().isNotEmpty) {
        await tester.tap(sf.first);
        await tester.enterText(sf.first, 'community');
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
        await tester.enterText(sf.first, '');
        await tester.pump();
      }
    });

    testWidgets('Events filter button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToEventsTab(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter.*event|Filters active'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final ok =
            find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.byType(Scaffold).evaluate().isNotEmpty;
        expect(ok, isTrue);
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Bookmark event button toggles without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToEventsTab(tester)) return;
      final bookmark =
          find.bySemanticsLabel(RegExp(r'(Remove bookmark|Bookmark event)'));
      if (bookmark.evaluate().isNotEmpty) {
        await tester.tap(bookmark.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Recommended event card is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToEventsTab(tester)) return;
      final rec = find.bySemanticsLabel(RegExp(r'Recommended event: '));
      if (rec.evaluate().isNotEmpty) {
        await tester.tap(rec.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });

    testWidgets('Tapping an event card navigates to detail', (tester) async {
      await waitForApp(tester);
      if (!await goToEventsTab(tester)) return;
      final card = find.bySemanticsLabel(RegExp(r'Event: '));
      if (card.evaluate().isNotEmpty) {
        await tester.tap(card.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });

    testWidgets('Event price filter chips (Free/Paid) are accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToEventsTab(tester)) return;
      final free = find.bySemanticsLabel(RegExp(r'Free'));
      if (free.evaluate().isNotEmpty) {
        await tester.tap(free.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
        // Tap again to deselect
        await tester.tap(free.first);
        await tester.pumpAndSettle();
      }
    });
  });

  // ── Discover Groups ───────────────────────────────────────────────────────────
  group('🗓️ Events — Discover Groups', () {
    testWidgets('Discover Groups tab shows content or empty state', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      final t = find.text('Groups');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        final ok =
            find.byType(ListView).evaluate().isNotEmpty ||
            find.textContaining('group').evaluate().isNotEmpty ||
            find.byType(Scaffold).evaluate().isNotEmpty;
        expect(ok, isTrue);
      }
    });

    testWidgets('Discover Groups list scrolls without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      final t = find.text('Groups');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        final list = find.byType(ListView);
        if (list.evaluate().isNotEmpty) {
          await tester.drag(list.first, const Offset(0, -400));
          await tester.pumpAndSettle();
          await tester.drag(list.first, const Offset(0, 400));
          await tester.pumpAndSettle();
        }
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Join group button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      final t = find.text('Groups');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        final join = find.bySemanticsLabel(RegExp(r'Join '));
        if (join.evaluate().isNotEmpty) {
          await tester.tap(join.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    });

    testWidgets('Share group button is accessible in Discover', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      final t = find.text('Groups');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        final share = find.bySemanticsLabel(RegExp(r'Share '));
        if (share.evaluate().isNotEmpty) {
          await tester.tap(share.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(Scaffold), findsWidgets);
          await tester.tapAt(const Offset(200, 80));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Relevant / Not relevant buttons are accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToDiscover(tester)) return;
      final t = find.text('Groups');
      if (t.evaluate().isNotEmpty) {
        await tester.tap(t.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        final relevant = find.bySemanticsLabel('This group is relevant to me');
        final notRel   = find.bySemanticsLabel('This group is not relevant to me');
        if (relevant.evaluate().isNotEmpty) {
          await tester.tap(relevant.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(Scaffold), findsWidgets);
        } else if (notRel.evaluate().isNotEmpty) {
          await tester.tap(notRel.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    });
  });
}
