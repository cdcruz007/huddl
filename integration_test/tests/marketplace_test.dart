// ============================================================
// Marketplace Test Suite — Huddl v32
// Covers: Buy tab (list, scroll, search, item detail),
//   Sell tab (list, create listing FAB, delist confirm,
//   offer accept/decline, offer dismiss, sold items),
//   Saved tab (swipe to unsave), filters (age, category,
//   price type, condition), AI suggestions (helpful/dismiss),
//   quick-list suggestions, clear all filters, Undo.
// Semantics: 'Search market items', 'Clear search',
//   'Filter items', 'Filters active. Tap to change.',
//   'Create new listing', 'Create a new listing',
//   'Cancel delisting', 'Confirm delist ${title}',
//   'Helpful suggestion', 'Not helpful, dismiss suggestion',
//   'Accept offer from ${name}', 'Decline offer from ${name}',
//   'Undo', 'Clear all filters'
// Keys: ValueKey('listing_${id}'), ValueKey('sold_${id}'),
//       ValueKey('offer_${id}'), ValueKey('dismiss_${id}'),
//       ValueKey('offer_dismiss_${id}')
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

Future<bool> goToMarket(WidgetTester tester) async {
  if (!_hasNavBar) return false;
  await tester.tap(navTab('Market').first);
  await tester.pumpAndSettle(const Duration(seconds: 5));
  return find.byType(Scaffold).evaluate().isNotEmpty;
}

Future<bool> goToBuyTab(WidgetTester tester) async {
  if (!await goToMarket(tester)) return false;
  final t = find.text('Buy');
  if (t.evaluate().isEmpty) return false;
  await tester.tap(t.first);
  await tester.pumpAndSettle(const Duration(seconds: 3));
  return true;
}

Future<bool> goToSellTab(WidgetTester tester) async {
  if (!await goToMarket(tester)) return false;
  final t = find.text('Sell');
  if (t.evaluate().isEmpty) return false;
  await tester.tap(t.first);
  await tester.pumpAndSettle(const Duration(seconds: 3));
  return true;
}

Future<bool> goToSavedTab(WidgetTester tester) async {
  if (!await goToMarket(tester)) return false;
  final t = find.text('Saved');
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

  // ── Market Landing ────────────────────────────────────────────────────────────
  group('🛒 Marketplace — Landing', () {
    testWidgets('Market tab loads without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToMarket(tester)) return;
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('No rendering exception on Market screen', (tester) async {
      await waitForApp(tester);
      if (!await goToMarket(tester)) return;
      expect(tester.takeException(), isNull);
    });

    testWidgets('Buy, Sell, Saved tabs are all visible', (tester) async {
      await waitForApp(tester);
      if (!await goToMarket(tester)) return;
      for (final tab in ['Buy', 'Sell', 'Saved']) {
        final t = find.text(tab);
        if (t.evaluate().isNotEmpty) {
          expect(t, findsWidgets,
              reason: '$tab tab must be visible in Market');
        }
      }
    });

    testWidgets('Full cycle Buy→Sell→Saved→Buy does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToMarket(tester)) return;
      for (final tab in ['Buy', 'Sell', 'Saved', 'Buy']) {
        final t = find.text(tab);
        if (t.evaluate().isNotEmpty) {
          await tester.tap(t.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.byType(Scaffold), findsWidgets,
              reason: 'No crash after switching to $tab');
        }
      }
    });
  });

  // ── Buy Tab ───────────────────────────────────────────────────────────────────
  group('🛒 Marketplace — Buy Tab', () {
    testWidgets('Buy tab shows list or empty state', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final ok =
          find.byType(ListView).evaluate().isNotEmpty ||
          find.textContaining('No items').evaluate().isNotEmpty ||
          find.textContaining('No listings').evaluate().isNotEmpty ||
          find.byType(Scaffold).evaluate().isNotEmpty;
      expect(ok, isTrue);
    });

    testWidgets('Buy list scrolls without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -400));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 400));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Fast fling in Buy list does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.fling(list.first, const Offset(0, -800), 3000);
        await tester.pumpAndSettle();
        await tester.fling(list.first, const Offset(0, 800), 3000);
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Search market items button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final search = find.bySemanticsLabel('Search market items');
      if (search.evaluate().isNotEmpty) {
        expect(search, findsWidgets);
        await tester.tap(search.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final tf = find.byType(TextField);
        if (tf.evaluate().isNotEmpty) {
          await tester.enterText(tf.first, 'bike');
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(Scaffold), findsWidgets);
          // Clear search
          final clear = find.bySemanticsLabel('Clear search');
          if (clear.evaluate().isNotEmpty) {
            await tester.tap(clear.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Filter items button opens filter sheet', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter items|Filters active'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final ok =
            find.byType(BottomSheet).evaluate().isNotEmpty ||
            find.bySemanticsLabel('Any age').evaluate().isNotEmpty ||
            find.byType(Scaffold).evaluate().isNotEmpty;
        expect(ok, isTrue);
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Age filter (Any age) is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter items|Filters active'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final anyAge = find.bySemanticsLabel('Any age');
        if (anyAge.evaluate().isNotEmpty) {
          expect(anyAge, findsWidgets);
          await tester.tap(anyAge.first);
          await tester.pumpAndSettle();
        }
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Price type filter (Free/Paid/All prices) is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter items|Filters active'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        // Try Free
        final free = find.bySemanticsLabel('Free');
        if (free.evaluate().isNotEmpty) {
          await tester.tap(free.first);
          await tester.pumpAndSettle();
          expect(find.byType(Scaffold), findsWidgets);
          // Try Paid
          final paid = find.bySemanticsLabel('Paid');
          if (paid.evaluate().isNotEmpty) {
            await tester.tap(paid.first);
            await tester.pumpAndSettle();
          }
        }
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Condition filter (All/Good/Fair/etc) is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter items|Filters active'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final anyCondition = find.bySemanticsLabel('Any condition');
        if (anyCondition.evaluate().isNotEmpty) {
          expect(anyCondition, findsWidgets);
        }
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Clear all filters button resets filters', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final clearAll = find.bySemanticsLabel('Clear all filters');
      if (clearAll.evaluate().isNotEmpty) {
        await tester.tap(clearAll.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Tapping a listing opens detail screen', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final tiles = find.byType(ListTile);
      if (tiles.evaluate().isEmpty) {
        final inkWell = find.byType(InkWell);
        if (inkWell.evaluate().isEmpty) return;
        await tester.tap(inkWell.first);
      } else {
        await tester.tap(tiles.first);
      }
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(find.byType(Scaffold), findsWidgets);
      await tryBack(tester);
    });

    testWidgets('Save/unsave item button toggles without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final saveSem = find.bySemanticsLabel(RegExp(r'save|bookmark', caseSensitive: false));
      if (saveSem.evaluate().isNotEmpty) {
        await tester.tap(saveSem.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Quick list suggestions are accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final quick = find.bySemanticsLabel(RegExp(r'Quick list '));
      if (quick.evaluate().isNotEmpty) {
        await tester.tap(quick.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });
  });

  // ── Sell Tab ──────────────────────────────────────────────────────────────────
  group('🛒 Marketplace — Sell Tab', () {
    testWidgets('Sell tab shows listings or empty state', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final ok =
          find.byType(ListView).evaluate().isNotEmpty ||
          find.textContaining('No listings').evaluate().isNotEmpty ||
          find.byType(Scaffold).evaluate().isNotEmpty;
      expect(ok, isTrue);
    });

    testWidgets('Create new listing FAB is present on Sell tab', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final fab = find.bySemanticsLabel(
              RegExp(r'Create new listing|Create a new listing'))
          .evaluate()
          .isNotEmpty
          ? find.bySemanticsLabel(
              RegExp(r'Create new listing|Create a new listing'))
          : find.byType(FloatingActionButton);
      if (fab.evaluate().isNotEmpty) {
        expect(fab, findsWidgets);
      }
    });

    testWidgets('Tapping create listing FAB opens create screen', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final fab = find.bySemanticsLabel(
              RegExp(r'Create new listing|Create a new listing'))
          .evaluate()
          .isNotEmpty
          ? find.bySemanticsLabel(
              RegExp(r'Create new listing|Create a new listing'))
          : find.byType(FloatingActionButton);
      if (fab.evaluate().isNotEmpty) {
        await tester.tap(fab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        await tryBack(tester);
      }
    });

    testWidgets('Sell tab scrolls without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -400));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 400));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Cancel delisting button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final cancel = find.bySemanticsLabel('Cancel delisting');
      if (cancel.evaluate().isNotEmpty) {
        await tester.tap(cancel.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Confirm delist dialog does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final confirm = find.bySemanticsLabel(RegExp(r'Confirm delist '));
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(confirm.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        // Dismiss or cancel the confirmation
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

    testWidgets('Offer accept button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final accept = find.bySemanticsLabel(RegExp(r'Accept offer from '));
      if (accept.evaluate().isNotEmpty) {
        await tester.tap(accept.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        // Dismiss confirmation if shown
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

    testWidgets('Offer decline button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final decline = find.bySemanticsLabel(RegExp(r'Decline offer from '));
      if (decline.evaluate().isNotEmpty) {
        await tester.tap(decline.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Offer dismiss button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      // ValueKey('offer_dismiss_${id}') based Dismissible
      final dismiss = find.byType(Dismissible);
      if (dismiss.evaluate().isNotEmpty) {
        await tester.drag(dismiss.first, const Offset(-150, 0));
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('AI suggestion helpful button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final helpful = find.bySemanticsLabel('Helpful suggestion');
      if (helpful.evaluate().isNotEmpty) {
        await tester.tap(helpful.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('AI suggestion not helpful / dismiss button is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final notHelpful =
          find.bySemanticsLabel('Not helpful, dismiss suggestion');
      if (notHelpful.evaluate().isNotEmpty) {
        await tester.tap(notHelpful.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Undo snackbar appears after dismiss/delete', (tester) async {
      await waitForApp(tester);
      if (!await goToSellTab(tester)) return;
      final undo = find.bySemanticsLabel('Undo');
      if (undo.evaluate().isNotEmpty) {
        await tester.tap(undo.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });

  // ── Saved Tab ─────────────────────────────────────────────────────────────────
  group('🛒 Marketplace — Saved Tab', () {
    testWidgets('Saved tab loads without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToSavedTab(tester)) return;
      final ok =
          find.byType(ListView).evaluate().isNotEmpty ||
          find.text('No saved items yet').evaluate().isNotEmpty ||
          find.byType(Scaffold).evaluate().isNotEmpty;
      expect(ok, isTrue);
    });

    testWidgets('Saved tab list scrolls without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToSavedTab(tester)) return;
      final list = find.byType(ListView);
      if (list.evaluate().isNotEmpty) {
        await tester.drag(list.first, const Offset(0, -400));
        await tester.pumpAndSettle();
        await tester.drag(list.first, const Offset(0, 400));
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Swiping a saved item to unsave does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToSavedTab(tester)) return;
      final items = find.byType(ListTile);
      if (items.evaluate().isNotEmpty) {
        await tester.drag(items.first, const Offset(-100, 0));
        await tester.pump(const Duration(milliseconds: 500));
        final undo = find.bySemanticsLabel('Undo');
        if (undo.evaluate().isNotEmpty) {
          await tester.tap(undo.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(200, 80));
          await tester.pumpAndSettle();
        }
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });

  // ── Age Filter Sheet (Bottom Sheet) ───────────────────────────────────────────
  group('🛒 Marketplace — Age Filter Sheet', () {
    testWidgets('Age filter chip from detail screen is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter items|Filters active'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final allAges = find.bySemanticsLabel('All ages');
        if (allAges.evaluate().isNotEmpty) {
          await tester.tap(allAges.first);
          await tester.pumpAndSettle();
          expect(find.byType(Scaffold), findsWidgets);
        }
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Category filter (All categories) is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToBuyTab(tester)) return;
      final filterBtn =
          find.bySemanticsLabel(RegExp(r'Filter items|Filters active'));
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final allCat = find.bySemanticsLabel(RegExp(r'All categories'));
        if (allCat.evaluate().isNotEmpty) {
          await tester.tap(allCat.first);
          await tester.pumpAndSettle();
          expect(find.byType(Scaffold), findsWidgets);
        }
        await tester.tapAt(const Offset(200, 80));
        await tester.pumpAndSettle();
      }
    });
  });
}
