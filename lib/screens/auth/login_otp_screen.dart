import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/huddl_colors.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/firebase_auth_service.dart';

/// OTP verification screen shown after successful phone login.
/// Calls FirebaseAuthService.verifySmsCode() to validate the real SMS code
/// sent by Firebase — no local OTP comparison.
class LoginOtpScreen extends StatefulWidget {
  final String phoneNumber;
  // generatedOtp is kept for API compatibility but is no longer used —
  // verification is done against Firebase, not a locally-generated code.
  final String generatedOtp;

  const LoginOtpScreen({
    super.key,
    required this.phoneNumber,
    required this.generatedOtp,
  });

  @override
  State<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends State<LoginOtpScreen> {
  final _codeController = TextEditingController();
  final _authService    = FirebaseAuthService();

  int  _resendTimer  = 30;
  bool _timerRunning = true;
  bool _hasError     = false;
  bool _isVerifying  = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
    _tickTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showCodeSentSnackbar());
  }

  void _onCodeChanged() {
    setState(() {
      _hasError  = false;
      _errorText = null;
    });
    if (_codeController.text.length == 6) {
      // Dismiss the keyboard before verifying so the UI doesn't jump
      FocusManager.instance.primaryFocus?.unfocus();
      _verify();
    }
  }

  void _tickTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _timerRunning && _resendTimer > 0) {
        setState(() => _resendTimer--);
        _tickTimer();
      }
    });
  }

  @override
  void dispose() {
    _timerRunning = false;
    _codeController.dispose();
    super.dispose();
  }

  void _showCodeSentSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Verification code sent to ${widget.phoneNumber}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: HuddlColors.onboardingOrange,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Verify against Firebase (real SMS code / Firebase test number) ──────
  Future<void> _verify() async {
    if (_isVerifying) return;
    final entered = _codeController.text.trim();
    if (entered.length < 6) return;

    setState(() {
      _isVerifying = true;
      _hasError    = false;
      _errorText   = null;
    });

    final result = await _authService.verifySmsCode(entered);

    if (!mounted) return;

    if (result.isSuccess) {
      if (!mounted) return;

      if (result.requiresOnboarding) {
        // Account exists in Firebase Auth but onboarding was never completed —
        // clear any stale local data and send them through the full onboarding
        // flow so they can set their name, postcode, parent type, etc.
        await OnboardingDataService().clear();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
        return;
      }

      // ── Restore user profile from Firestore into local cache ────────────
      await _authService.restoreProfileFromFirestore();

      if (!mounted) return;
      _authService.updateLastActive();
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } else if (result.isAccountDeleted) {
      // ── Account not found — direct user to sign up ────────────────────
      setState(() => _isVerifying = false);
      if (!mounted) return;
      await _showAccountNotFoundDialog();
    } else {
      setState(() {
        _isVerifying = false;
        _hasError    = true;
        _errorText   = result.errorMessage ?? 'Incorrect code. Please try again.';
      });
      _codeController.clear();
    }
  }

  /// Shown when a valid OTP is entered but no Huddl account exists for this
  /// number. Clears any stale onboarding data then routes to the full
  /// onboarding carousel so the user can register fresh.
  Future<void> _showAccountNotFoundDialog() async {
    // Wipe any leftover onboarding state so every screen starts blank.
    await OnboardingDataService().clear();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: HuddlColors.onboardingOrange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.waving_hand_rounded,
                  size: 22, color: HuddlColors.onboardingOrange),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No account found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: const Text(
          'We couldn\'t find a Huddl account linked to this number.\n\n'
          'Join Huddl to connect with local parents — it only takes a couple '
          'of minutes to get set up.',
          style: TextStyle(fontSize: 14, height: 1.55),
        ),
        actions: [
          // "Not now" dismisses and goes back to the login entry screen
          // so the user isn't stranded on the OTP screen.
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              );
            },
            child: Text(
              'Not now',
              style: TextStyle(color: HuddlColors.disabledText),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Full onboarding journey: carousel → name → parent type → etc.
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/onboarding',
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: HuddlColors.onboardingOrange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              elevation: 0,
            ),
            child: const Text(
              'Join Huddl',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  // ── Resend: ask Firebase to send a new SMS ───────────────────────────────
  Future<void> _resendCode() async {
    if (_resendTimer > 0) return;

    setState(() {
      _hasError     = false;
      _errorText    = null;
      _resendTimer  = 30;
    });
    _codeController.clear();
    _tickTimer();

    final result = await _authService.verifyPhoneNumber(widget.phoneNumber);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.status == PhoneAuthStatus.codeSent
              ? 'New code sent to ${widget.phoneNumber}'
              : result.errorMessage ?? 'Failed to resend code. Please try again.',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: result.status == PhoneAuthStatus.codeSent
            ? HuddlColors.successGreen
            : HuddlColors.error,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Bottom sheet asking the user for their first name (shown only when the
  /// returning user has no stored name — e.g. after account deletion).
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Dismiss keyboard when tapping outside input areas
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        // Allow the scaffold to resize when the keyboard appears
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              // ── App bar ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left,
                        size: 30, color: HuddlColors.onboardingOrange),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                  ),
                  Expanded(
                    child: Center(
                      child: Image.asset(
                        'assets/images/logo_huddl_splash.png',
                        height: 34,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ]),
              ),

              // ── Scrollable body — keyboard pushes content up cleanly ─
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 32),

                      // ── Lock icon ────────────────────────────────────
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: HuddlColors.onboardingOrange.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_outline_rounded,
                            size: 32, color: HuddlColors.onboardingOrange),
                      ),

                      const SizedBox(height: 20),

                      // ── Title ────────────────────────────────────────
                      Text(
                        'Verify it\'s you',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 10),

                      // ── Subtitle ─────────────────────────────────────
                      Text(
                        'We\'ve sent a 6-digit code to\n${widget.phoneNumber}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: HuddlColors.disabledText,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 32),

                      // ── OTP boxes ────────────────────────────────────
                      _OtpBoxRow(
                        controller: _codeController,
                        hasError: _hasError,
                      ),

                      if (_hasError) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorText ?? 'Incorrect code. Please try again.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: HuddlColors.error,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 28),

                      // ── Resend button ────────────────────────────────
                      GestureDetector(
                        onTap: _resendCode,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: context.hc.inputBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: HuddlColors.inputBorderLight, width: 1),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _resendTimer > 0
                                ? 'Resend code in $_resendTimer s'
                                : 'Resend code',
                            style: TextStyle(
                              fontSize: 15,
                              color: _resendTimer > 0
                                  ? HuddlColors.disabledText
                                  : HuddlColors.onboardingOrange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Verify button ────────────────────────────────
                      _isVerifying
                          ? SizedBox(
                              height: 54,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: HuddlColors.onboardingOrange,
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : _OrangeButton(
                              key: const Key('otpVerifyButton'),
                              label: 'Verify & Log in',
                              enabled: _codeController.text.length == 6 &&
                                  !_hasError,
                              onTap: _verify,
                            ),

                      const SizedBox(height: 24),

                      Text(
                        'This keeps your Huddl account secure.',
                        style: TextStyle(
                          fontSize: 13,
                          color: HuddlColors.disabledText.withValues(alpha: 0.8),
                        ),
                        textAlign: TextAlign.center,
                      ),

                      // Extra bottom padding so content clears the keyboard
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 6-box OTP input ────────────────────────────────────────────────────────────
class _OtpBoxRow extends StatelessWidget {
  final TextEditingController controller;
  final bool hasError;

  const _OtpBoxRow({required this.controller, required this.hasError});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Hidden text field that captures input.
        //
        // IMPORTANT: Use a 1×1 SizedBox + transparent color instead of
        // Opacity(opacity:0). Opacity(0) keeps the node in the a11y tree but
        // collapses its paint bounds, so Android Accessibility / Robo Test
        // cannot reliably inject text into it via setText(). A 1-pixel
        // transparent container keeps the node fully accessible to Robo.
        // Visual OTP boxes
        AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final code = controller.text.padRight(6);
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) {
                  final filled = i < controller.text.length;
                  final char   = code[i];
                  return Container(
                    width: 46,
                    height: 56,
                    decoration: BoxDecoration(
                      color: hasError
                          ? HuddlColors.errorLight
                          : filled
                              ? HuddlColors.onboardingOrange
                                  .withValues(alpha: 0.08)
                              : context.hc.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasError
                            ? HuddlColors.error
                            : filled
                                ? HuddlColors.onboardingOrange
                                : HuddlColors.inputBorderLight,
                        width: filled ? 1.8 : 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: filled
                        ? Text(
                            char,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          )
                        : i == controller.text.length
                            ? Container(
                                width: 2,
                                height: 24,
                                color: HuddlColors.onboardingOrange,
                              )
                            : null,
                  );
                }),
              );
            },
          ),
        // Full-size transparent TextField overlaid on top of the boxes.
        // Robo Test requires a widget with real paint bounds to inject text —
        // a 1×1 SizedBox collapses to nothing in the accessibility tree.
        // This overlay is visually invisible but fully accessible to Robo.
        Positioned.fill(
          child: Semantics(
            label: 'otp_field',
            textField: true,
            child: TextField(
              key: const Key('otpField'),
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              style: const TextStyle(color: Colors.transparent),
              cursorColor: Colors.transparent,
              decoration: const InputDecoration(
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                counterText: '',
                fillColor: Colors.transparent,
                filled: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Reusable orange button ─────────────────────────────────────────────────────
class _OrangeButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _OrangeButton(
      {super.key, required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'otp_verify_button',
      button: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            color: enabled ? HuddlColors.onboardingOrange : HuddlColors.disabled,
            borderRadius: BorderRadius.circular(12),
        ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: enabled ? Colors.white : HuddlColors.disabledText,
            ),
          ),
        ),
      ),
    );
  }
}
