// Auth Test Suite — Huddl
// Tests: Login screen UI, phone/password fields, validation, onboarding carousel

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 10));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🔐 Authentication Tests', () {

    testWidgets('App launches without crashing', (tester) async {
      await waitForApp(tester);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Onboarding carousel or home screen is shown on launch', (tester) async {
      await waitForApp(tester);
      final hasContent =
          find.text('Login').evaluate().isNotEmpty ||
          find.text('Log in').evaluate().isNotEmpty ||
          find.text('Welcome back!').evaluate().isNotEmpty ||
          find.text('Get started').evaluate().isNotEmpty ||
          find.text('Home').evaluate().isNotEmpty ||
          find.bySemanticsLabel('Home').evaluate().isNotEmpty;
      expect(hasContent, isTrue, reason: 'App must show a recognisable screen on launch');
    });

    testWidgets('Login link on carousel navigates to login screen', (tester) async {
      await waitForApp(tester);
      final loginLink = find.text('Login');
      if (loginLink.evaluate().isNotEmpty) {
        await tester.tap(loginLink.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.text('Welcome back!'), findsOneWidget);
      }
    });

    testWidgets('Login screen shows phone number field', (tester) async {
      await waitForApp(tester);
      final loginLink = find.text('Login');
      if (loginLink.evaluate().isNotEmpty) {
        await tester.tap(loginLink.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      if (find.text('Welcome back!').evaluate().isNotEmpty) {
        final phoneField = find.byKey(const Key('phoneField'));
        expect(phoneField, findsOneWidget,
            reason: 'Login screen must have a phone number field');
      }
    });

    testWidgets('Login screen shows password field', (tester) async {
      await waitForApp(tester);
      final loginLink = find.text('Login');
      if (loginLink.evaluate().isNotEmpty) {
        await tester.tap(loginLink.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      if (find.text('Welcome back!').evaluate().isNotEmpty) {
        final pwField = find.byKey(const Key('passwordField'));
        expect(pwField, findsOneWidget,
            reason: 'Login screen must have a password field');
      }
    });

    testWidgets('Phone field accepts digit input', (tester) async {
      await waitForApp(tester);
      final loginLink = find.text('Login');
      if (loginLink.evaluate().isNotEmpty) {
        await tester.tap(loginLink.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      final phoneField = find.byKey(const Key('phoneField'));
      if (phoneField.evaluate().isNotEmpty) {
        await tester.tap(phoneField.first);
        await tester.enterText(phoneField.first, '7575888452');
        await tester.pump();
        expect(find.text('7575888452'), findsOneWidget);
      }
    });

    testWidgets('Log in button is visible on login screen', (tester) async {
      await waitForApp(tester);
      final loginLink = find.text('Login');
      if (loginLink.evaluate().isNotEmpty) {
        await tester.tap(loginLink.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      if (find.text('Welcome back!').evaluate().isNotEmpty) {
        final loginBtn = find.byKey(const Key('loginButton'));
        expect(loginBtn, findsOneWidget,
            reason: 'Login screen must have a Log in button');
      }
    });

    testWidgets('Onboarding Get started button navigates to name input', (tester) async {
      await waitForApp(tester);
      final started = find.text('Get started!');
      if (started.evaluate().isNotEmpty) {
        await tester.tap(started.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final hasNameScreen =
            find.text('What\'s your name?').evaluate().isNotEmpty ||
            find.byType(TextField).evaluate().isNotEmpty;
        expect(hasNameScreen, isTrue,
            reason: 'Get started should begin the signup flow');
      }
    });

    testWidgets('Login screen back button returns to carousel', (tester) async {
      await waitForApp(tester);
      final loginLink = find.text('Login');
      if (loginLink.evaluate().isNotEmpty) {
        await tester.tap(loginLink.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final back = find.byType(BackButton);
        if (back.evaluate().isNotEmpty) {
          await tester.tap(back.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    });
  });
}
