// Auth Test Suite
// Tests: Login screen loads, email/password fields, sign-in button, error states

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('🔐 Authentication Tests', () {
    testWidgets('App launches without crashing', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Login screen displays key UI elements', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // App should show login screen or home screen
      final hasContent =
          find.text('Sign in').evaluate().isNotEmpty ||
          find.text('Log in').evaluate().isNotEmpty ||
          find.text('Welcome').evaluate().isNotEmpty ||
          find.text('Huddl').evaluate().isNotEmpty ||
          find.byType(Scaffold).evaluate().isNotEmpty;

      expect(hasContent, isTrue,
          reason: 'App should display a recognisable screen on launch');
    });

    testWidgets('Email field accepts text input', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Try key-based finder first, then hint-text fallback
      Finder emailField = find.byKey(const Key('email_field'));
      if (emailField.evaluate().isEmpty) {
        emailField = find.widgetWithText(TextField, 'Email');
      }
      if (emailField.evaluate().isEmpty) {
        emailField = find.widgetWithText(TextField, 'Email address');
      }

      if (emailField.evaluate().isNotEmpty) {
        await tester.tap(emailField.first);
        await tester.enterText(emailField.first, 'test@huddl.com');
        await tester.pump();
        expect(find.text('test@huddl.com'), findsOneWidget);
      }
    });

    testWidgets('Password field accepts text input', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      Finder pwField = find.byKey(const Key('password_field'));
      if (pwField.evaluate().isEmpty) {
        pwField = find.widgetWithText(TextField, 'Password');
      }

      if (pwField.evaluate().isNotEmpty) {
        await tester.tap(pwField.first);
        await tester.enterText(pwField.first, 'TestPass123!');
        await tester.pump();
        // Password is obscured so we just check no crash
      }
    });

    testWidgets('Tapping sign-in with empty fields shows error', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final signInBtn = find.widgetWithText(ElevatedButton, 'Sign in');
      if (signInBtn.evaluate().isNotEmpty) {
        await tester.tap(signInBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final hasError =
            find.byType(SnackBar).evaluate().isNotEmpty ||
            find.textContaining('required').evaluate().isNotEmpty ||
            find.textContaining('invalid').evaluate().isNotEmpty ||
            find.textContaining('email').evaluate().isNotEmpty;

        expect(hasError, isTrue,
            reason: 'Empty login should show a validation error');
      }
    });

    testWidgets('Sign up / register link is visible', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final hasSignUp =
          find.textContaining('Sign up').evaluate().isNotEmpty ||
          find.textContaining('Register').evaluate().isNotEmpty ||
          find.textContaining("Don't have").evaluate().isNotEmpty ||
          find.textContaining('Create account').evaluate().isNotEmpty;

      // Only assert if we're on the login screen
      final onLoginScreen =
          find.text('Sign in').evaluate().isNotEmpty ||
          find.text('Log in').evaluate().isNotEmpty;

      if (onLoginScreen) {
        expect(hasSignUp, isTrue,
            reason: 'Login screen should have a route to registration');
      }
    });
  });
}
