import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import '../../theme/huddl_colors.dart';


/// OTP verification screen shown after successful phone+password login.
/// Accepts [phoneNumber] (display) and [generatedOtp] (the 6-digit code
/// produced by LoginScreen).  In production this would be the SMS code.
class LoginOtpScreen extends StatefulWidget {
  final String phoneNumber;
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
  int  _resendTimer   = 30;
  bool _timerRunning  = true;
  bool _hasError      = false;
  bool _isVerifying   = false;
  // New OTP generated on resend
  late String _currentOtp;

  @override
  void initState() {
    super.initState();
    _currentOtp = widget.generatedOtp;
    _codeController.addListener(_onCodeChanged);
    _tickTimer();
    // Show the demo OTP as a snackbar after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _showOtpSnackbar());
  }

  void _onCodeChanged() {
    setState(() => _hasError = false);
    // Auto-verify when 6 digits entered
    if (_codeController.text.length == 6) {
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

  // ── Generate a new 6-digit OTP ──────────────────────────────────────────
  String _generateOtp() {
    final rng = math.Random();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  void _showOtpSnackbar() {
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

  Future<void> _verify() async {
    if (_isVerifying) return;
    final entered = _codeController.text.trim();
    if (entered.length < 6) return;

    setState(() => _isVerifying = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // Accept the generated OTP or universal demo code 123456
    if (entered == _currentOtp || entered == '123456') {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } else {
      setState(() {
        _hasError    = true;
        _isVerifying = false;
      });
      _codeController.clear();
    }
  }

  void _resendCode() {
    if (_resendTimer > 0) return;
    final newOtp = _generateOtp();
    setState(() {
      _currentOtp   = newOtp;
      _resendTimer  = 30;
      _hasError     = false;
    });
    _codeController.clear();
    _tickTimer();
    _showOtpSnackbar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── App bar with back + logo ──────────────────────────────
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

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // ── Lock icon ────────────────────────────────────
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: HuddlColors.onboardingOrange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_outline_rounded,
                          size: 32, color: HuddlColors.onboardingOrange),
                    ),

                    const SizedBox(height: 24),

                    // ── Title ─────────────────────────────────────────
                    const Text(
                      'Verify it\'s you',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.textDark,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    // ── Subtitle ──────────────────────────────────────
                    Text(
                      'We\'ve sent a 6-digit code to\n${widget.phoneNumber}',
                      style: const TextStyle(
                        fontSize: 15,
                        color: HuddlColors.disabledText,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    // ── OTP code boxes ────────────────────────────────
                    _OtpBoxRow(
                      controller: _codeController,
                      hasError: _hasError,
                    ),

                    if (_hasError) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Incorrect code. Please try again.',
                        style: TextStyle(
                          fontSize: 13,
                          color: HuddlColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // ── Resend button ─────────────────────────────────
                    GestureDetector(
                      onTap: _resendCode,
                      child: Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: HuddlColors.inputBg,
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

                    const SizedBox(height: 24),

                    // ── Verify button ─────────────────────────────────
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
                            label: 'Verify & Log in',
                            enabled: _codeController.text.length == 6 &&
                                !_hasError,
                            onTap: _verify,
                          ),

                    const SizedBox(height: 32),

                    // ── Help note ─────────────────────────────────────
                    Text(
                      'This keeps your Huddl account secure.',
                      style: TextStyle(
                        fontSize: 13,
                        color: HuddlColors.disabledText.withValues(alpha: 0.8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 6-box OTP input ───────────────────────────────────────────────────────────
class _OtpBoxRow extends StatelessWidget {
  final TextEditingController controller;
  final bool hasError;

  const _OtpBoxRow({required this.controller, required this.hasError});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Hidden text field that captures input
        Opacity(
          opacity: 0,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
          ),
        ),
        // Visual OTP boxes
        GestureDetector(
          onTap: () => FocusScope.of(context).requestFocus(FocusNode()),
          child: AnimatedBuilder(
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
                              ? HuddlColors.onboardingOrange.withValues(alpha: 0.08)
                              : HuddlColors.inputBg,
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
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.textDark,
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
      {required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
    );
  }
}
