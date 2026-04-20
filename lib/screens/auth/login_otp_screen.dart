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
      // ── Ensure the user has a display name set ────────────────────────
      final data = OnboardingDataService();
      await data.initialize();
      if (data.name == null || data.name!.trim().isEmpty) {
        final nameEntered = await _showNameEntrySheet();
        if (!mounted) return;
        data.setName(
          (nameEntered == null || nameEntered.trim().isEmpty)
              ? 'User'
              : nameEntered.trim(),
        );
      }
      if (!mounted) return;
      _authService.updateLastActive();
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } else {
      setState(() {
        _isVerifying = false;
        _hasError    = true;
        _errorText   = result.errorMessage ?? 'Incorrect code. Please try again.';
      });
      _codeController.clear();
    }
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
  Future<String?> _showNameEntrySheet() async {
    final nameCtrl = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            final canSave = nameCtrl.text.trim().isNotEmpty;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 28, 24, MediaQuery.of(ctx2).viewInsets.bottom + 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: HuddlColors.disabledText.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: HuddlColors.onboardingOrange.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.waving_hand_rounded,
                        size: 28, color: HuddlColors.onboardingOrange),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Welcome! What should we\ncall you?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your first name to personalise your experience.',
                    style: TextStyle(
                      fontSize: 14,
                      color: HuddlColors.disabledText,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Container(
                    decoration: BoxDecoration(
                      color: context.hc.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: HuddlColors.inputBorderLight, width: 1),
                    ),
                    child: TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface),
                      decoration: const InputDecoration(
                        hintText: 'Your first name',
                        hintStyle: TextStyle(
                            fontSize: 16, color: HuddlColors.disabledText),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                      onChanged: (_) => setLocal(() {}),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) Navigator.pop(ctx2, v.trim());
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: canSave
                        ? () => Navigator.pop(ctx2, nameCtrl.text.trim())
                        : null,
                    child: Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        color: canSave
                            ? HuddlColors.onboardingOrange
                            : HuddlColors.disabled,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: canSave
                              ? Colors.white
                              : HuddlColors.disabledText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── App bar ────────────────────────────────────────────────
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

                    // ── Lock icon ──────────────────────────────────────
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: HuddlColors.onboardingOrange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_outline_rounded,
                          size: 32, color: HuddlColors.onboardingOrange),
                    ),

                    const SizedBox(height: 24),

                    // ── Title ──────────────────────────────────────────
                    Text(
                      'Verify it\'s you',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    // ── Subtitle ───────────────────────────────────────
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

                    // ── OTP boxes ──────────────────────────────────────
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

                    const SizedBox(height: 32),

                    // ── Resend button ──────────────────────────────────
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

                    const SizedBox(height: 24),

                    // ── Verify button ──────────────────────────────────
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

// ── 6-box OTP input ────────────────────────────────────────────────────────────
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
