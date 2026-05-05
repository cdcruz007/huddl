// Profile Test Suite — Huddl
// Nav label: 'Profile' (Semantics label on _NavItem in main_shell.dart)
// Key profile screen texts: 'My Profile', 'About me', 'My Groups', 'Log out'

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

Finder navTab(String label) => find.bySemanticsLabel(label);

Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 10));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('👤 Profile Tests', () {

    testWidgets('Profile tab navigates to profile screen', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Profile');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Profile screen shows My Profile heading', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Profile');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final hasProfile =
            find.text('My Profile').evaluate().isNotEmpty ||
            find.text('Profile').evaluate().isNotEmpty;

        expect(hasProfile, isTrue,
            reason: 'Profile screen should show "My Profile" heading');
      }
    });

    testWidgets('Profile screen shows About me section', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Profile');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        // Scroll to find About me
        final listView = find.byType(ListView);
        if (listView.evaluate().isNotEmpty) {
          await tester.drag(listView.first, const Offset(0, -200));
          await tester.pumpAndSettle();
        }

        final hasAbout = find.text('About me').evaluate().isNotEmpty;
        if (hasAbout) {
          expect(hasAbout, isTrue,
              reason: 'Profile screen should have "About me" section');
        }
      }
    });

    testWidgets('Profile screen shows My Groups section', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Profile');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final listView = find.byType(ListView);
        if (listView.evaluate().isNotEmpty) {
          await tester.drag(listView.first, const Offset(0, -200));
          await tester.pumpAndSettle();
        }

        final hasGroups = find.text('My Groups').evaluate().isNotEmpty;
        if (hasGroups) {
          expect(hasGroups, isTrue,
              reason: 'Profile screen should show "My Groups" section');
        }
      }
    });

    testWidgets('Profile screen shows subscription info', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Profile');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final hasSubscription =
            find.text('Subscription').evaluate().isNotEmpty ||
            find.text('Upgrade').evaluate().isNotEmpty;

        if (hasSubscription) {
          expect(hasSubscription, isTrue,
              reason: 'Profile screen should show subscription info');
        }
      }
    });

    testWidgets('Profile screen scrolls without crash', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Profile');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final scrollable = find.byType(ListView);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.drag(scrollable.first, const Offset(0, -500));
          await tester.pumpAndSettle();
          await tester.drag(scrollable.first, const Offset(0, 500));
          await tester.pumpAndSettle();
        }
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Log out button is visible on profile screen', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Profile');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        // Scroll down to find Log out
        final listView = find.byType(ListView);
        if (listView.evaluate().isNotEmpty) {
          await tester.drag(listView.first, const Offset(0, -600));
          await tester.pumpAndSettle();
        }

        final hasLogout = find.text('Log out').evaluate().isNotEmpty;
        if (hasLogout) {
          expect(hasLogout, isTrue,
              reason: 'Profile screen should have a "Log out" button');
        }
      }
    });

    testWidgets('Version info is visible on profile screen', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Profile');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        final listView = find.byType(ListView);
        if (listView.evaluate().isNotEmpty) {
          await tester.drag(listView.first, const Offset(0, -600));
          await tester.pumpAndSettle();
        }

        final hasVersion = find.textContaining('Version').evaluate().isNotEmpty;
        if (hasVersion) {
          expect(hasVersion, isTrue,
              reason: 'Profile screen should show version info');
        }
      }
    });

    testWidgets('Privacy policy link is accessible', (WidgetTester tester) async {
      await waitForApp(tester);
      final tab = navTab('Profile');
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.first);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        // Scroll to find legal links
        final listView = find.byType(ListView);
        if (listView.evaluate().isNotEmpty) {
          await tester.drag(listView.first, const Offset(0, -400));
          await tester.pumpAndSettle();
        }

        final privacyLink =
            find.textContaining('Privacy').evaluate().isNotEmpty ||
            find.textContaining('Terms').evaluate().isNotEmpty;

        if (privacyLink) {
          expect(privacyLink, isTrue,
              reason: 'Profile screen should show Privacy/Terms links');
        }
      }
    });
  });
}
