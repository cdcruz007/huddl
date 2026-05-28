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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/backend_api_service.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';

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
    // Give the backend 3 s to finish writing the welcome email before polling
    Future.delayed(const Duration(seconds: 3), _startPolling);
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
                    Image.asset(
                      'assets/images/logo_huddl_splash.png',
                      height: 34,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Text(
                        'huddl',
                        style: HuddlText.display(),
                      ),
                    ),

                    const SizedBox(height: 44),

                    // Envelope icon
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_rounded,
                        size: 56,
                        color: HuddlColors.textDark,
                      ),
                    ),

                    const SizedBox(height: 32),

                    Text(
                      'Check your inbox!',
                      style: HuddlText.display(),
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
                      'Tap the \u201cVerify My Email\u201d button in the email to unlock Huddl and meet your neighbours.',
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
                        color: const Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: HuddlColors.divider,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: HuddlColors.textDark, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Can\'t find it? Check your spam or junk folder.',
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
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_resending || _resendCooldown) ? null : _resendEmail,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.primary,
                        disabledBackgroundColor:
                            HuddlColors.primary.withValues(alpha: 0.4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _resending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              _resendCooldown
                                  ? 'Resend in ${_resendCooldownSecs}s'
                                  : 'Resend verification email',
                              style: HuddlText.body(weight: FontWeight.w600),
                            ),
                    ),
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
