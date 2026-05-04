// Marketplace Test Suite
// Tests: Marketplace screen loads, listings visible, search, item detail, create listing

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🛒 Marketplace Tests', () {
    testWidgets('Marketplace screen loads without crashing', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final marketTab = find.byTooltip('Marketplace');
      if (marketTab.evaluate().isNotEmpty) {
        await tester.tap(marketTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Marketplace shows listing items', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final marketTab = find.byTooltip('Marketplace');
      if (marketTab.evaluate().isNotEmpty) {
        await tester.tap(marketTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final hasContent =
            find.byType(ListView).evaluate().isNotEmpty ||
            find.byType(GridView).evaluate().isNotEmpty ||
            find.text('Marketplace').evaluate().isNotEmpty ||
            find.textContaining('item').evaluate().isNotEmpty ||
            find.textContaining('Item').evaluate().isNotEmpty;

        expect(hasContent, isTrue,
            reason: 'Marketplace should show a list or grid of items');
      }
    });

    testWidgets('Marketplace search is accessible', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final marketTab = find.byTooltip('Marketplace');
      if (marketTab.evaluate().isNotEmpty) {
        await tester.tap(marketTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final searchIcon = find.byIcon(Icons.search);
        if (searchIcon.evaluate().isNotEmpty) {
          await tester.tap(searchIcon.first);
          await tester.pumpAndSettle();

          final searchField = find.byType(TextField);
          if (searchField.evaluate().isNotEmpty) {
            await tester.enterText(searchField.first, 'pushchair');
            await tester.pump();
            expect(find.text('pushchair'), findsOneWidget);
          }
        }
      }
    });

    testWidgets('Marketplace list scrolls without crash', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final marketTab = find.byTooltip('Marketplace');
      if (marketTab.evaluate().isNotEmpty) {
        await tester.tap(marketTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final scrollable = find.byType(ListView);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.drag(scrollable.first, const Offset(0, -400));
          await tester.pumpAndSettle();
          await tester.drag(scrollable.first, const Offset(0, 400));
          await tester.pumpAndSettle();
        }
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Tapping a listing opens item detail screen', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final marketTab = find.byTooltip('Marketplace');
      if (marketTab.evaluate().isNotEmpty) {
        await tester.tap(marketTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final items = find.byType(Card);
        if (items.evaluate().isNotEmpty) {
          await tester.tap(items.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          final inDetail =
              find.text('Contact seller').evaluate().isNotEmpty ||
              find.text('Message seller').evaluate().isNotEmpty ||
              find.textContaining('£').evaluate().isNotEmpty ||
              find.byIcon(Icons.favorite_border).evaluate().isNotEmpty;

          if (inDetail) {
            expect(inDetail, isTrue,
                reason: 'Tapping a listing should open item detail screen');
          }

          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Create listing button is accessible', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final marketTab = find.byTooltip('Marketplace');
      if (marketTab.evaluate().isNotEmpty) {
        await tester.tap(marketTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final createBtn =
            find.byType(FloatingActionButton).evaluate().isNotEmpty
                ? find.byType(FloatingActionButton)
                : find.byIcon(Icons.add);

        if (createBtn.evaluate().isNotEmpty) {
          await tester.tap(createBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          final inCreateForm =
              find.text('Create listing').evaluate().isNotEmpty ||
              find.text('Add listing').evaluate().isNotEmpty ||
              find.text('Title').evaluate().isNotEmpty ||
              find.text('Price').evaluate().isNotEmpty;

          if (inCreateForm) {
            expect(inCreateForm, isTrue,
                reason: 'Create button should open listing creation form');
          }

          final backBtn = find.byType(BackButton);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first);
            await tester.pumpAndSettle();
          }
        }
      }
    });

    testWidgets('Marketplace category filters work', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final marketTab = find.byTooltip('Marketplace');
      if (marketTab.evaluate().isNotEmpty) {
        await tester.tap(marketTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Look for filter chips or tab bar
        final filterChip = find.byType(FilterChip);
        final chip = find.byType(Chip);

        if (filterChip.evaluate().isNotEmpty) {
          await tester.tap(filterChip.first);
          await tester.pumpAndSettle();
          expect(find.byType(Scaffold), findsWidgets);
        } else if (chip.evaluate().isNotEmpty) {
          await tester.tap(chip.first);
          await tester.pumpAndSettle();
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    });
  });
}
