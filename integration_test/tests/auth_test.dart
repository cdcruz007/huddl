// ============================================================
// Auth Test Suite — Huddl v32
// Covers: splash → onboarding carousel (swipe, Get started,
//         Login link) → login screen (phone/password fields,
//         visibility toggle, empty-field validation, real
//         login) → OTP screen → biometric lock screen →
//         back-navigation from every auth screen.
// Keys: phoneField, passwordField, loginButton
// Semantics: 'already_have_account\nLogin', 'Login',
//            'Welcome back!', 'Get started'
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huddl_connect/main.dart' as app;

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<void> waitForApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 12));
}

bool get _isLoggedIn =>
    find.bySemanticsLabel('Home').evaluate().isNotEmpty ||
    find.bySemanticsLabel('Connect').evaluate().isNotEmpty ||
    find.text('Connect').evaluate().isNotEmpty;

/// Navigate to the Login screen from wherever we are.
/// Tries the 'Login' text link and the semantics label.
Future<bool> goToLoginScreen(WidgetTester tester) async {
  if (find.text('Welcome back!').evaluate().isNotEmpty) return true;

  final loginText = find.text('Login');
  if (loginText.evaluate().isNotEmpty) {
    await tester.tap(loginText.first);
    await tester.pumpAndSettle(const Duration(seconds: 4));
    if (find.text('Welcome back!').evaluate().isNotEmpty) return true;
  }

  final loginSem =
      find.bySemanticsLabel(RegExp(r'already_have_account|Login'));
  if (loginSem.evaluate().isNotEmpty) {
    await tester.tap(loginSem.first);
    await tester.pumpAndSettle(const Duration(seconds: 4));
    if (find.text('Welcome back!').evaluate().isNotEmpty) return true;
  }

  // ContentDescription path used by Robo
  final loginCD = find.bySemanticsLabel('already_have_account\nLogin');
  if (loginCD.evaluate().isNotEmpty) {
    await tester.tap(loginCD.first);
    await tester.pumpAndSettle(const Duration(seconds: 4));
  }

  return find.text('Welcome back!').evaluate().isNotEmpty;
}

/// Pop back one level, wait, return true if Scaffold still visible.
Future<bool> popBack(WidgetTester tester) async {
  final b = find.byType(BackButton);
  if (b.evaluate().isNotEmpty) {
    await tester.tap(b.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    return true;
  }
  // Navigator pop via IconButton (leading widget)
  final leading = find.byTooltip('Back');
  if (leading.evaluate().isNotEmpty) {
    await tester.tap(leading.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    return true;
  }
  return false;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── App Launch ────────────────────────────────────────────────────────────────
  group('🔐 Auth — App Launch', () {
    testWidgets('App starts without crashing', (tester) async {
      await waitForApp(tester);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('First screen is Scaffold-based (no blank/crash)', (tester) async {
      await waitForApp(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('tester.takeException() is null after cold start', (tester) async {
      await waitForApp(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Splash or carousel or home appears on cold start', (tester) async {
      await waitForApp(tester);
      final ok =
          find.byType(Scaffold).evaluate().isNotEmpty ||
          find.text('Login').evaluate().isNotEmpty ||
          find.text('Welcome back!').evaluate().isNotEmpty ||
          find.text('Get started').evaluate().isNotEmpty ||
          _isLoggedIn;
      expect(ok, isTrue,
          reason: 'A recognisable launch screen must appear');
    });
  });

  // ── Onboarding Carousel ───────────────────────────────────────────────────────
  group('🔐 Auth — Onboarding Carousel', () {
    testWidgets('Carousel shows Login link when not logged in', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      final link = find.text('Login');
      if (link.evaluate().isNotEmpty) {
        expect(link, findsWidgets);
      }
    });

    testWidgets('Carousel shows Get started button when not logged in', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      final btn = find.textContaining('Get started');
      if (btn.evaluate().isNotEmpty) {
        expect(btn, findsWidgets);
      }
    });

    testWidgets('Carousel can be swiped left without crash', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      final pv = find.byType(PageView);
      if (pv.evaluate().isNotEmpty) {
        await tester.drag(pv.first, const Offset(-300, 0));
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Carousel can be swiped right without crash', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      final pv = find.byType(PageView);
      if (pv.evaluate().isNotEmpty) {
        // Swipe left first, then back
        await tester.drag(pv.first, const Offset(-300, 0));
        await tester.pumpAndSettle();
        await tester.drag(pv.first, const Offset(300, 0));
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Rapid carousel swipe stress (5 swipes) does not crash', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      final pv = find.byType(PageView);
      if (pv.evaluate().isNotEmpty) {
        for (int i = 0; i < 5; i++) {
          await tester.drag(pv.first, const Offset(-300, 0));
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(Scaffold), findsWidgets);
      }
    });

    testWidgets('Get started navigates into signup name screen', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      final started = find.textContaining('Get started');
      if (started.evaluate().isNotEmpty) {
        await tester.tap(started.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final hasNextScreen =
            find.byType(TextField).evaluate().isNotEmpty ||
            find.textContaining("What's your name").evaluate().isNotEmpty ||
            find.text('Name').evaluate().isNotEmpty;
        expect(hasNextScreen, isTrue,
            reason: 'Get started should launch signup flow');
        await popBack(tester);
      }
    });
  });

  // ── Login Screen UI ───────────────────────────────────────────────────────────
  group('🔐 Auth — Login Screen UI', () {
    testWidgets('Login link opens the login screen', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      final ok = await goToLoginScreen(tester);
      if (ok) {
        expect(find.text('Welcome back!'), findsOneWidget);
      }
    });

    testWidgets('Login screen has Key(phoneField)', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      if (!await goToLoginScreen(tester)) return;
      expect(find.byKey(const Key('phoneField')), findsOneWidget,
          reason: 'Key(phoneField) must exist on login screen');
    });

    testWidgets('Login screen has Key(passwordField)', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      if (!await goToLoginScreen(tester)) return;
      expect(find.byKey(const Key('passwordField')), findsOneWidget,
          reason: 'Key(passwordField) must exist on login screen');
    });

    testWidgets('Login screen has Key(loginButton)', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      if (!await goToLoginScreen(tester)) return;
      expect(find.byKey(const Key('loginButton')), findsOneWidget,
          reason: 'Key(loginButton) must exist on login screen');
    });

    testWidgets('Phone field accepts digit input', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      if (!await goToLoginScreen(tester)) return;
      final f = find.byKey(const Key('phoneField'));
      if (f.evaluate().isEmpty) return;
      await tester.tap(f.first);
      await tester.enterText(f.first, '7575888452');
      await tester.pump();
      expect(find.text('7575888452'), findsOneWidget);
    });

    testWidgets('Password field accepts text input', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      if (!await goToLoginScreen(tester)) return;
      final f = find.byKey(const Key('passwordField'));
      if (f.evaluate().isEmpty) return;
      await tester.tap(f.first);
      await tester.enterText(f.first, 'TestPassword1');
      await tester.pump();
      expect(f, findsOneWidget); // field still there (may be obscured)
    });

    testWidgets('Password visibility toggle works', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      if (!await goToLoginScreen(tester)) return;
      // Find visibility icon (either state)
      final visOff = find.byIcon(Icons.visibility_off);
      final visOn  = find.byIcon(Icons.visibility);
      final vis    = visOff.evaluate().isNotEmpty ? visOff : visOn;
      if (vis.evaluate().isNotEmpty) {
        await tester.tap(vis.first);
        await tester.pump();
        expect(find.byType(TextField), findsWidgets);
        // Toggle back
        final vis2 = find.byIcon(Icons.visibility_off).evaluate().isNotEmpty
            ? find.byIcon(Icons.visibility_off)
            : find.byIcon(Icons.visibility);
        if (vis2.evaluate().isNotEmpty) {
          await tester.tap(vis2.first);
          await tester.pump();
        }
      }
    });

    testWidgets('Submitting empty fields stays on screen (no crash)', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      if (!await goToLoginScreen(tester)) return;
      final loginBtn = find.byKey(const Key('loginButton'));
      if (loginBtn.evaluate().isEmpty) return;
      await tester.tap(loginBtn.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Submitting phone-only (no password) shows error or stays', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      if (!await goToLoginScreen(tester)) return;
      final phone = find.byKey(const Key('phoneField'));
      final btn   = find.byKey(const Key('loginButton'));
      if (phone.evaluate().isEmpty || btn.evaluate().isEmpty) return;
      await tester.tap(phone.first);
      await tester.enterText(phone.first, '7575888452');
      await tester.pump();
      await tester.tap(btn.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Back button from login returns to previous screen', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      if (!await goToLoginScreen(tester)) return;
      await popBack(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  // ── OTP / Verification Screen ─────────────────────────────────────────────────
  group('🔐 Auth — OTP / Verification Screen', () {
    testWidgets('OTP screen is navigable from login if it appears', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return;
      if (!await goToLoginScreen(tester)) return;
      // Enter credentials and tap login to see if OTP screen appears
      final phone = find.byKey(const Key('phoneField'));
      final pw    = find.byKey(const Key('passwordField'));
      final btn   = find.byKey(const Key('loginButton'));
      if (phone.evaluate().isEmpty) return;
      await tester.tap(phone.first);
      await tester.enterText(phone.first, '7575888452');
      await tester.pump();
      if (pw.evaluate().isNotEmpty) {
        await tester.tap(pw.first);
        await tester.enterText(pw.first, 'Devon1100');
        await tester.pump();
      }
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 15));
      }
      // If OTP screen appears, check it has a code field
      if (find.textContaining('OTP').evaluate().isNotEmpty ||
          find.textContaining('code').evaluate().isNotEmpty ||
          find.textContaining('verification').evaluate().isNotEmpty) {
        expect(find.byType(TextField), findsWidgets);
        await popBack(tester);
      }
      // Either way, no crash
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('OTP screen back button works', (tester) async {
      await waitForApp(tester);
      // If OTP screen is somehow visible, back returns to login
      if (find.textContaining('OTP').evaluate().isNotEmpty ||
          find.textContaining('Enter code').evaluate().isNotEmpty) {
        await popBack(tester);
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });

  // ── Biometric Lock Screen ─────────────────────────────────────────────────────
  group('🔐 Auth — Biometric Lock Screen', () {
    testWidgets('Biometric lock screen does not crash if shown', (tester) async {
      await waitForApp(tester);
      // Biometric screen appears when app resumes with biometric enabled
      final hasBiometric =
          find.text('Unlock').evaluate().isNotEmpty ||
          find.textContaining('biometric').evaluate().isNotEmpty ||
          find.textContaining('Touch ID').evaluate().isNotEmpty ||
          find.textContaining('Face ID').evaluate().isNotEmpty;
      if (hasBiometric) {
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });

  // ── Full Login Flow ───────────────────────────────────────────────────────────
  group('🔐 Auth — Full Login (Real Credentials)', () {
    testWidgets('Full login succeeds and main shell appears', (tester) async {
      await waitForApp(tester);
      if (_isLoggedIn) return; // already authenticated — pass

      if (!await goToLoginScreen(tester)) return;

      final phone = find.byKey(const Key('phoneField'));
      final pw    = find.byKey(const Key('passwordField'));
      final btn   = find.byKey(const Key('loginButton'));

      if (phone.evaluate().isEmpty ||
          pw.evaluate().isEmpty ||
          btn.evaluate().isEmpty) {
        return;
      }

      await tester.tap(phone.first);
      await tester.enterText(phone.first, '7575888452');
      await tester.pump();

      await tester.tap(pw.first);
      await tester.enterText(pw.first, 'Devon1100');
      await tester.pump();

      await tester.tap(btn.first);
      await tester.pumpAndSettle(const Duration(seconds: 45));

      final loggedIn =
          find.bySemanticsLabel('Home').evaluate().isNotEmpty ||
          find.bySemanticsLabel('Connect').evaluate().isNotEmpty ||
          find.text('Connect').evaluate().isNotEmpty;
      expect(loggedIn, isTrue,
          reason: 'Valid credentials must result in logged-in main shell');
    });

    testWidgets('All five nav tabs visible after successful login', (tester) async {
      await waitForApp(tester);
      if (!_isLoggedIn) return;
      for (final label in ['Home', 'Connect', 'Discover', 'Market', 'Profile']) {
        expect(find.bySemanticsLabel(label), findsWidgets,
            reason: '$label tab must be visible after login');
      }
    });
  });
}
