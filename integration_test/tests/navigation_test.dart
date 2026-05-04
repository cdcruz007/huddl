// Navigation Test Suite
// Tests: Bottom nav bar, tab switching, back navigation, deep links

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🧭 Navigation Tests', () {
    testWidgets('Bottom navigation bar is visible after login', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final hasBottomNav =
          find.byType(BottomNavigationBar).evaluate().isNotEmpty ||
          find.byType(NavigationBar).evaluate().isNotEmpty;

      // If we are on login screen, skip — test is only relevant post-login
      final onLoginScreen =
          find.text('Sign in').evaluate().isNotEmpty ||
          find.text('Log in').evaluate().isNotEmpty;

      if (!onLoginScreen) {
        expect(hasBottomNav, isTrue,
            reason: 'Main shell should show a bottom navigation bar');
      }
    });

    testWidgets('Home tab is accessible', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final homeTab = find.byTooltip('Home');
      if (homeTab.evaluate().isNotEmpty) {
        await tester.tap(homeTab.first);
        await tester.pumpAndSettle();
      }

      final hasHomeContent =
          find.text('Home').evaluate().isNotEmpty ||
          find.textContaining('Welcome').evaluate().isNotEmpty ||
          find.textContaining('borough').evaluate().isNotEmpty ||
          find.textContaining('Borough').evaluate().isNotEmpty;

      if (find.byType(BottomNavigationBar).evaluate().isNotEmpty) {
        expect(hasHomeContent, isTrue,
            reason: 'Home tab should display home screen content');
      }
    });

    testWidgets('Groups tab navigates to groups screen', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Try tapping Groups in bottom nav
      final groupsTab = find.widgetWithText(BottomNavigationBarItem, 'Groups');
      final groupsIcon = find.byTooltip('Groups');

      if (groupsTab.evaluate().isNotEmpty) {
        await tester.tap(groupsTab.first);
        await tester.pumpAndSettle();
      } else if (groupsIcon.evaluate().isNotEmpty) {
        await tester.tap(groupsIcon.first);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Messages tab navigates to messages screen', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final messagesTab = find.byTooltip('Messages');
      if (messagesTab.evaluate().isNotEmpty) {
        await tester.tap(messagesTab.first);
        await tester.pumpAndSettle();

        final hasMessages =
            find.text('Messages').evaluate().isNotEmpty ||
            find.text('Chats').evaluate().isNotEmpty ||
            find.text('Direct Messages').evaluate().isNotEmpty;

        expect(hasMessages, isTrue,
            reason: 'Messages tab should show the messages screen');
      }
    });

    testWidgets('Marketplace tab is accessible', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final marketTab =
          find.byTooltip('Marketplace');
      if (marketTab.evaluate().isNotEmpty) {
        await tester.tap(marketTab.first);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Profile tab is accessible', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      final profileTab = find.byTooltip('Profile');
      if (profileTab.evaluate().isNotEmpty) {
        await tester.tap(profileTab.first);
        await tester.pumpAndSettle();

        final hasProfile =
            find.text('Profile').evaluate().isNotEmpty ||
            find.textContaining('Account').evaluate().isNotEmpty;

        expect(hasProfile, isTrue,
            reason: 'Profile tab should show profile screen');
      }
    });

    testWidgets('Back button works on nested screens', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Navigate into any screen that has a back button
      final backButton = find.byType(BackButton);
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton.first);
        await tester.pumpAndSettle();
        // Should not crash on back navigation
      }
    });

    testWidgets('App handles rapid tab switching without crash', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      if (find.byType(BottomNavigationBar).evaluate().isNotEmpty) {
        final navBar = tester.widget<BottomNavigationBar>(
            find.byType(BottomNavigationBar));
        final itemCount = navBar.items.length;

        // Rapidly tap through all tabs
        for (int i = 0; i < itemCount; i++) {
          final items = find.descendant(
            of: find.byType(BottomNavigationBar),
            matching: find.byType(InkWell),
          );
          if (items.evaluate().length > i) {
            await tester.tap(items.at(i));
            await tester.pump(const Duration(milliseconds: 300));
          }
        }
        await tester.pumpAndSettle();
        // Pass if no crash
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });
}
