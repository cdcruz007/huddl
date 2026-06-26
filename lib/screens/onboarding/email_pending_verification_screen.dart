// ═══════════════════════════════════════════════════════════════════════════════
// EmailPendingVerificationScreen
// ═══════════════════════════════════════════════════════════════════════════════
//
// Shown immediately after "Let's go!" (end of onboarding) and on any cold-start
// where the user's emailVerified flag is still false in Firestore.
//
// Behaviour:
//   • Displays the masked email so the user knows where to look.
//   • Polls /api/notifications/check-verified every 4 s.
//   • Once verified  → navigates to /home (clears stack).
//   • "Resend" button → calls /api/notifications/resend-verification,
//     throttled to once per 60 s to prevent abuse.
//   • "Wrong email? Start over" → signs out and returns to /onboarding.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import '../../theme/huddl_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgets/common/huddl_logo.dart';
import '../../services/backend_api_service.dart';
import '../../widgets/common/huddl_button.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/huddl_character.dart';

class EmailPendingVerificationScreen extends StatefulWidget {
  const EmailPendingVerificationScreen({super.key});

  @override
  State<EmailPendingVerificationScreen> createState() =>
      _EmailPendingVerificationScreenState();
}

class _EmailPendingVerificationScreenState
    extends State<EmailPendingVerificationScreen>
    with WidgetsBindingObserver {

  // ── Display state ─────────────────────────────────────────────────────────
  String _email = '';
  bool   _resending = false;
  bool   _resendCooldown = false;
  int    _resendCooldownSecs = 0;
  String? _resendMessage;

  // ── Timers ────────────────────────────────────────────────────────────────
  Timer? _pollTimer;
  Timer? _cooldownTimer;
  bool   _verified = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _email = (OnboardingDataService().email ?? '').trim();
    // RETURNING-USER-1: if this is a returning user whose previous verification
    // link may have expired, auto-send a fresh email immediately on arrival.
    // The flag is read-and-cleared in one shot so it cannot fire twice even if
    // the widget is rebuilt or the user leaves and returns to this screen.
    // _resendEmail() respects the 60s cooldown so a subsequent manual tap is
    // correctly throttled. Runs fire-and-forget (unawaited) so it doesn't
    // block the 3s polling delay that follows.
    unawaited(_autoResendIfReturningUser());
    // Give the backend 3 s to finish writing the welcome email before polling
    Future.delayed(const Duration(seconds: 3), _startPolling);
  }

  /// RETURNING-USER-1: auto-resend a fresh verification email once for
  /// returning users, then clear the flag so this is strictly one-shot.
  Future<void> _autoResendIfReturningUser() async {
    final onboarding = OnboardingDataService();
    if (!onboarding.wasReturningUser) return;
    // Clear immediately — before the await — so even if the user navigates
    // back to this screen a second time the auto-send does not repeat.
    onboarding.setWasReturningUser(false);
    if (kDebugMode) {
      debugPrint('[EmailPending] RETURNING-USER-1: auto-resending verification email');
    }
    // Small delay to let the Firebase ID token settle after verifySmsCode
    // resolved — the backend's authMiddleware needs a valid token.
    await Future.delayed(const Duration(milliseconds: 800));
    await _resendEmail();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// Resume polling when user returns from email client (app foregrounded).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_verified) {
      _checkVerified();
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  void _startPolling() {
    if (!mounted) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkVerified());
  }

  Future<void> _checkVerified() async {
    if (_verified || !mounted) return;
    try {
      final result = await BackendApiService().checkEmailVerified();
      if ((result['emailVerified'] as bool?) == true && mounted) {
        _verified = true;
        _pollTimer?.cancel();
        _navigateHome();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[EmailPending] poll error: $e');
    }
  }

  void _navigateHome() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  // ── Resend ────────────────────────────────────────────────────────────────

  Future<void> _resendEmail() async {
    if (_resending || _resendCooldown) return;
    setState(() { _resending = true; _resendMessage = null; });

    try {
      await BackendApiService().resendVerificationEmail();
      if (!mounted) return;
      setState(() {
        _resendMessage = 'Email sent! Check your inbox (and spam folder).';
        _resending       = false;
        _resendCooldown  = true;
        _resendCooldownSecs = 60;
      });
      _startCooldownTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resendMessage = 'Could not send — please try again in a moment.';
        _resending = false;
      });
      if (kDebugMode) debugPrint('[EmailPending] resend error: $e');
    }
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendCooldownSecs--;
        if (_resendCooldownSecs <= 0) {
          _resendCooldown = false;
          t.cancel();
        }
      });
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Masks the email for display: "j***@example.com"
  String _masked(String email) {
    if (email.isEmpty) return 'your email address';
    final at = email.indexOf('@');
    if (at <= 1) return email;
    return '${email[0]}***${email.substring(at)}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Scrollable content area ────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 40, 28, 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    const HuddlLogomark(size: 40),

                    const SizedBox(height: 44),

                    // Sending illustration — warm circle treatment
                    const WarmCircleIllustration(
                      assetPath: 'assets/illustrations/sending.webp',
                      size: 160,
                    ),

                    const SizedBox(height: 32),

                    Text(
                      'Check your inbox!',
                      style: HuddlText.display(),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Didn\'t get it? Tap Resend below.',
                      style: HuddlText.body(
                          color: HuddlColors.textSecondary,
                          weight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'We\'ve sent a verification email to',
                      style: HuddlText.body(color: HuddlColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _masked(_email),
                      style: HuddlText.body(weight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'Tap the link in the email \u2014 we\'ll let you straight in.',
                      style: HuddlText.body(color: HuddlColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 28),

                    // Polling indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: HuddlColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Waiting for verification\u2026',
                          style: HuddlText.body(),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Spam-folder tip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: HuddlColors.neutral50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: HuddlColors.divider,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(HuddlIcons.info,
                              color: HuddlColors.textDark, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Not there? Check your spam folder or tap to resend.',
                              style: HuddlText.body(color: HuddlColors.textDark),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Feedback after resend
                    if (_resendMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _resendMessage!,
                        style: HuddlText.body(color: _resendMessage!.startsWith('Email sent') ? Colors.green : Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Fixed bottom buttons ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  // Resend button
                  HuddlButton(
                    label: _resendCooldown
                        ? 'Resend in ${_resendCooldownSecs}s'
                        : 'Resend verification email',
                    variant: HuddlButtonVariant.primary,
                    isLoading: _resending,
                    fullWidth: true,
                    onPressed: (_resending || _resendCooldown) ? null : _resendEmail,
                  ),

                  const SizedBox(height: 12),

                  // Wrong-email escape hatch
                  TextButton(
                    onPressed: _showWrongEmailDialog,
                    style: TextButton.styleFrom(
                      foregroundColor: HuddlColors.textSecondary,
                    ),
                    child: Text(
                      'Wrong email address? Start over',
                      style: HuddlText.body(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Wrong-email dialog ────────────────────────────────────────────────────

  void _showWrongEmailDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Start over?',
            style: HuddlText.body(weight: FontWeight.w700)),
        content: Text(
          'This will sign you out and return you to the start of the '
          'sign-up flow so you can enter a different email address.',
          style: HuddlText.body(color: HuddlColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: HuddlText.body(color: HuddlColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _signOutAndRestart();
            },
            child: Text('Start over',
                style: HuddlText.body(weight: FontWeight.w600, color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _signOutAndRestart() async {
    try {
      await FirebaseAuthService().signOut();
    } catch (e) {
      if (kDebugMode) debugPrint('[EmailPending] signOut error: $e');
    }
    if (!mounted) return;
    await OnboardingDataService().clear();
    Navigator.of(context).pushNamedAndRemoveUntil('/onboarding', (_) => false);
  }
}
