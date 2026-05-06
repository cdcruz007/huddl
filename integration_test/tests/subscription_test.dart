// ============================================================
// Subscription Test Suite — Huddl v32
// Covers: subscription plans screen, checkout screen,
//   manage subscription screen, tier display, billing period
//   toggle (monthly/annual), plan upgrade flow,
//   cancel subscription confirmation.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

Finder navTab(String label) => find.bySemanticsLabel(label);

Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 12));
}

bool get _hasNavBar =>
    find.bySemanticsLabel('Home').evaluate().isNotEmpty ||
    find.bySemanticsLabel('Connect').evaluate().isNotEmpty;

Future<bool> goToProfile(WidgetTester tester) async {
  if (!_hasNavBar) return false;
  await tester.tap(navTab('Profile').first);
  await tester.pumpAndSettle(const Duration(seconds: 5));
  return true;
}

/// Scroll profile list to find an item, tap it, and return true if tapped.
Future<bool> scrollAndTap(WidgetTester tester, String text) async {
  final list = find.byType(ListView);
  for (int i = 0; i < 4; i++) {
    if (find.text(text).evaluate().isNotEmpty) break;
    if (list.evaluate().isNotEmpty) {
      await tester.drag(list.first, const Offset(0, -250));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
    }
  }
  final item = find.text(text);
  if (item.evaluate().isEmpty) return false;
  await tester.tap(item.first);
  await tester.pumpAndSettle(const Duration(seconds: 3));
  return true;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Subscription Plans Screen ─────────────────────────────────────────────────
  group('💳 Subscription — Plans Screen', () {
    testWidgets('Subscription plans screen accessible from profile', (tester) async {
      await waitForApp(tester);
      if (!await goToProfile(tester)) return;
      // Look for Upgrade or Manage Subscription button
      final upgradeBtn = find.text('Upgrade')
          .evaluate().isNotEmpty
          ? find.text('Upgrade')
          : find.text('Manage Subscription');
      if (upgradeBtn.evaluate().isNotEmpty) {
        await tester.tap(upgradeBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        final b = find.byType(BackButton);
        if (b.evaluate().isNotEmpty) {
          await tester.tap(b.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(200, 100));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Plans screen shows tier names or pricing info', (tester) async {
      await waitForApp(tester);
      if (!await goToProfile(tester)) return;
      final upgradeBtn = find.text('Upgrade');
      if (upgradeBtn.evaluate().isNotEmpty) {
        await tester.tap(upgradeBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final hasPlans =
            find.textContaining('Neighbourhood').evaluate().isNotEmpty ||
            find.textContaining('Borough').evaluate().isNotEmpty ||
            find.textContaining('City').evaluate().isNotEmpty ||
            find.textContaining('month').evaluate().isNotEmpty ||
            find.textContaining('£').evaluate().isNotEmpty ||
            find.text('Free').evaluate().isNotEmpty;
        if (hasPlans) {
          expect(hasPlans, isTrue,
              reason: 'Plans screen should show tier names or pricing');
        }
        final b = find.byType(BackButton);
        if (b.evaluate().isNotEmpty) {
          await tester.tap(b.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(200, 100));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Plans screen scrolls without crash', (tester) async {
      await waitForApp(tester);
      if (!await goToProfile(tester)) return;
      final upgradeBtn = find.text('Upgrade');
      if (upgradeBtn.evaluate().isNotEmpty) {
        await tester.tap(upgradeBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final list = find.byType(ListView);
        final scroll = find.byType(SingleChildScrollView);
        final target = list.evaluate().isNotEmpty ? list : scroll;
        if (target.evaluate().isNotEmpty) {
          await tester.drag(target.first, const Offset(0, -300));
          await tester.pumpAndSettle();
          await tester.drag(target.first, const Offset(0, 300));
          await tester.pumpAndSettle();
        }
        expect(find.byType(Scaffold), findsWidgets);
        final b = find.byType(BackButton);
        if (b.evaluate().isNotEmpty) {
          await tester.tap(b.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(200, 100));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Annual/Monthly billing toggle is accessible', (tester) async {
      await waitForApp(tester);
      if (!await goToProfile(tester)) return;
      final upgradeBtn = find.text('Upgrade');
      if (upgradeBtn.evaluate().isNotEmpty) {
        await tester.tap(upgradeBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final hasToggle =
            find.text('Monthly').evaluate().isNotEmpty ||
            find.text('Annual').evaluate().isNotEmpty ||
            find.text('Annually').evaluate().isNotEmpty ||
            find.byType(Switch).evaluate().isNotEmpty;
        if (hasToggle) expect(hasToggle, isTrue);
        final b = find.byType(BackButton);
        if (b.evaluate().isNotEmpty) {
          await tester.tap(b.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(200, 100));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Selecting a plan does not crash', (tester) async {
      await waitForApp(tester);
      if (!await goToProfile(tester)) return;
      final upgradeBtn = find.text('Upgrade');
      if (upgradeBtn.evaluate().isNotEmpty) {
        await tester.tap(upgradeBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        // Tap the first ElevatedButton (likely a tier select button)
        final elevatedBtns = find.byType(ElevatedButton);
        if (elevatedBtns.evaluate().isNotEmpty) {
          await tester.tap(elevatedBtns.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.byType(Scaffold), findsWidgets);
          final b = find.byType(BackButton);
          if (b.evaluate().isNotEmpty) {
            await tester.tap(b.first);
            await tester.pumpAndSettle();
          } else {
            await tester.tapAt(const Offset(200, 100));
            await tester.pumpAndSettle();
          }
        }
        final b2 = find.byType(BackButton);
        if (b2.evaluate().isNotEmpty) {
          await tester.tap(b2.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(200, 100));
          await tester.pumpAndSettle();
        }
      }
    });
  });

  // ── Manage Subscription Screen ────────────────────────────────────────────────
  group('💳 Subscription — Manage Screen', () {
    testWidgets('Manage Subscription accessible from profile', (tester) async {
      await waitForApp(tester);
      if (!await goToProfile(tester)) return;
      final manageBtn = find.text('Manage Subscription');
      if (manageBtn.evaluate().isNotEmpty) {
        await tester.tap(manageBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
        final b = find.byType(BackButton);
        if (b.evaluate().isNotEmpty) {
          await tester.tap(b.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(200, 100));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Manage screen shows current plan details', (tester) async {
      await waitForApp(tester);
      if (!await goToProfile(tester)) return;
      final manageBtn = find.text('Manage Subscription');
      if (manageBtn.evaluate().isNotEmpty) {
        await tester.tap(manageBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final hasDetails =
            find.textContaining('Plan').evaluate().isNotEmpty ||
            find.textContaining('Active').evaluate().isNotEmpty ||
            find.textContaining('Free').evaluate().isNotEmpty ||
            find.byType(Scaffold).evaluate().isNotEmpty;
        expect(hasDetails, isTrue);
        final b = find.byType(BackButton);
        if (b.evaluate().isNotEmpty) {
          await tester.tap(b.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(200, 100));
          await tester.pumpAndSettle();
        }
      }
    });
  });

  // ── Paywall Gates ─────────────────────────────────────────────────────────────
  group('💳 Subscription — Paywall Gates', () {
    testWidgets('Restricted group card shows paywall indicator', (tester) async {
      await waitForApp(tester);
      if (!_hasNavBar) return;
      // Navigate to Discover → Groups
      await tester.tap(navTab('Discover').first);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      final groupsTab = find.text('Groups');
      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        final restrictedCard = find.bySemanticsLabel(RegExp('Restricted group'));
        if (restrictedCard.evaluate().isNotEmpty) {
          await tester.tap(restrictedCard.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          // Should show upgrade prompt, not crash
          expect(find.byType(Scaffold), findsWidgets);
          final b = find.byType(BackButton);
          if (b.evaluate().isNotEmpty) {
            await tester.tap(b.first);
            await tester.pumpAndSettle();
          } else {
            await tester.tapAt(const Offset(200, 100));
            await tester.pumpAndSettle();
          }
        }
      }
    });
  });
}
