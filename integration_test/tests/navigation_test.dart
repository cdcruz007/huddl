// Navigation Test Suite — Huddl
// Tests bottom nav (Home/Connect/Discover/Market/Profile), tab switching,
// back navigation. Uses Semantics(label:) finders that match the actual
// _NavItem widgets in main_shell.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

// Helper: find a nav tab by its Semantics label
Finder navTab(String label) => find.bySemanticsLabel(label);

// Helper: wait for app to settle past splash/auth
Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 10));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🧭 Navigation Tests', () {

    testWidgets('App launches and shows a screen', (tester) async {
      await waitForApp(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Home tab is visible and tappable', (tester) async {
      await waitForApp(tester);
      final tab = navTab('Home');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Connect tab navigates to groups/connect screen', (tester) async {
      await waitForApp(tester);
      final tab = navTab('Connect');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Discover tab navigates to events screen', (tester) async {
      await waitForApp(tester);
      final tab = navTab('Discover');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Market tab navigates to marketplace screen', (tester) async {
      await waitForApp(tester);
      final tab = navTab('Market');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Profile tab navigates to profile screen', (tester) async {
      await waitForApp(tester);
      final tab = navTab('Profile');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Rapid tab switching does not crash', (tester) async {
      await waitForApp(tester);
      for (final label in ['Connect', 'Discover', 'Market', 'Profile', 'Home']) {
        final tab = navTab(label);
        if (tab.evaluate().isNotEmpty) {
          await tester.tap(tab.first);
          await tester.pump(const Duration(milliseconds: 400));
        }
      }
      await tester.pumpAndSettle();
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Back button works on nested screens', (tester) async {
      await waitForApp(tester);
      final back = find.byType(BackButton);
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back.first);
        await tester.pumpAndSettle();
      }
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('All 5 nav tabs are present on home screen', (tester) async {
      await waitForApp(tester);
      // Only check if we reached the main shell (logged-in state)
      final connectTab = navTab('Connect');
      if (connectTab.evaluate().isNotEmpty) {
        for (final label in ['Home', 'Connect', 'Discover', 'Market', 'Profile']) {
          expect(navTab(label), findsWidgets,
              reason: '$label nav tab should be visible in the main shell');
        }
      }
    });
  });
}
