import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/logo_widget.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/test_account_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading       = false;
  String? _errorMessage;
  String? _phoneError;

  // Country code — locked to UK (+44) matching onboarding
  static const _countryCode = '+44';

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── UK phone validation (same rules as onboarding phone_number_screen) ──
  String _normalise(String input) {
    String raw = input.replaceAll(RegExp(r'\s+'), '');
    if (raw.startsWith('+44')) raw = raw.substring(3);
    if (raw.startsWith('0')) raw = raw.substring(1);
    return raw;
  }

  String? _validatePhone(String raw) {
    final digits = _normalise(raw);
    if (digits.isEmpty) return null;
    if (!RegExp(r'^\d+$').hasMatch(digits)) return 'Only digits are allowed';
    if (digits.isNotEmpty && !digits.startsWith('7')) {
      if (digits.startsWith('1') || digits.startsWith('2')) {
        return 'Landline numbers are not accepted';
      }
      return 'UK mobile numbers must start with 7 (after +44)';
    }
    if (digits.length >= 2) {
      final prefix2 = digits.substring(0, 2);
      if (prefix2 == '70' || prefix2 == '76') {
        return 'Personal / pager numbers are not accepted';
      }
    }
    if (digits.length >= 6 && RegExp(r'^(\d)\1+$').hasMatch(digits)) {
      return 'Please enter a valid phone number';
    }
    if (digits.length > 10) {
      return 'UK mobile numbers are 10 digits after the leading 0';
    }
    return null;
  }

  bool get _isPhoneValid {
    final digits = _normalise(_phoneController.text);
    if (digits.length != 10) return false;
    if (!digits.startsWith('7')) return false;
    final prefix2 = digits.substring(0, 2);
    if (prefix2 == '70' || prefix2 == '76') return false;
    if (RegExp(r'^(\d)\1+$').hasMatch(digits)) return false;
    return true;
  }

  // ── Password validation (same rules as onboarding password_screen) ──
  bool get _isPasswordValid {
    final pwd = _passwordController.text;
    if (pwd.length < 8) return false;
    if (!RegExp(r'[A-Z]').hasMatch(pwd)) return false;
    if (!RegExp(r'[a-z]').hasMatch(pwd)) return false;
    if (!RegExp(r'[0-9]').hasMatch(pwd)) return false;
    return true;
  }

  /// Whether the current phone number is a recognised test account.
  bool get _isTestPhone {
    final digits = _normalise(_phoneController.text);
    return digits.length == 10 && TestAccountService.isTestAccount(digits);
  }

  bool get _canLogin {
    if (!_isPhoneValid) return false;
    // Test accounts don't require a password
    if (_isTestPhone) return true;
    return _isPasswordValid;
  }

  final FirebaseAuthService _authService = FirebaseAuthService();

  Future<void> _handleLogin() async {
    if (!_canLogin) return;
    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    final digits = _normalise(_phoneController.text);

    // ── Test account bypass ───────────────────────────────────────────
    // For designated test accounts, skip Firebase phone OTP
    // and go straight to the OTP verification screen with test OTP.
    if (TestAccountService.isTestAccount(digits)) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/login_otp',
        arguments: {
          'phoneNumber': '$_countryCode$digits',
          'generatedOtp': TestAccountService.testOtp,
          'isTestAccount': 'true',
        },
      );
      return;
    }
    // ────────────────────────────────────────────────────────────────

    // Phone-only auth: initiate Firebase phone verification (sends SMS OTP)
    final fullPhone = '$_countryCode$digits';

    try {
      final result = await _authService.verifyPhoneNumber(fullPhone)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        return PhoneAuthResult(
          status: PhoneAuthStatus.error,
          errorMessage: 'Verification timed out. Please try again.',
        );
      });

      if (!mounted) return;

      if (result.status == PhoneAuthStatus.verified) {
        // Auto-verified (Android) — go straight to home
        _authService.updateLastActive();
        setState(() => _isLoading = false);
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      } else if (result.status == PhoneAuthStatus.codeSent) {
        // SMS sent — go to OTP screen
        setState(() => _isLoading = false);
        Navigator.pushNamed(
          context,
          '/login_otp',
          arguments: {
            'phoneNumber': fullPhone,
            'generatedOtp': '',
            'isTestAccount': 'false',
          },
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result.errorMessage ?? 'Failed to send verification code.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Login failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: HuddlColors.primary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),

              // ── Logo ──────────────────────────────────────────
              const LogoWidget(height: 44),

              const SizedBox(height: 44),

              // ── Title ────────────────────────────────────────
              Text(
                'Welcome back!',
                style: AppTextStyles.h1.copyWith(color: HuddlColors.textDark),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 10),

              Text(
                'Log in with your UK mobile number',
                style: AppTextStyles.body1.copyWith(color: HuddlColors.textSecondary),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 44),

              // ── Phone number field (UK format) ──────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phone number',
                    style: AppTextStyles.inputLabel.copyWith(
                      color: HuddlColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Country code (locked to UK)
                      Container(
                        padding: const EdgeInsets.only(bottom: 10),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: HuddlColors.gray300),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text('\u{1F1EC}\u{1F1E7}',
                                style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 6),
                            Text(
                              _countryCode,
                              style: AppTextStyles.body1.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            _UKMobileInputFormatter(),
                            LengthLimitingTextInputFormatter(10),
                          ],
                          maxLength: 10,
                          style: AppTextStyles.body1,
                          decoration: InputDecoration(
                            hintText: '7700 900 123',
                            hintStyle: AppTextStyles.inputHint,
                            counterText: '',
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: _phoneError != null
                                      ? HuddlColors.error
                                      : HuddlColors.gray300),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: _phoneError != null
                                      ? HuddlColors.error
                                      : HuddlColors.primary,
                                  width: 2),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: _phoneError != null
                                      ? HuddlColors.error
                                      : HuddlColors.gray300),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (_) {
                            final err = _validatePhone(_phoneController.text);
                            setState(() => _phoneError = err);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_phoneError != null) ...[
                    const SizedBox(height: 4),
                    Text(_phoneError!,
                        style: TextStyle(
                            fontSize: 12,
                            color: HuddlColors.error,
                            fontWeight: FontWeight.w500)),
                  ],
                ],
              ),

              const SizedBox(height: 32),

              // ── Test account badge (shown when test number detected) ──
              if (_isTestPhone) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE7F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.science_outlined, color: const Color(0xFF7C4DFF), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Test Account Detected',
                              style: AppTextStyles.body2.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF7C4DFF),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'No password needed. You\'ll verify with OTP 123456.',
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF7C4DFF).withValues(alpha: 0.8),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Password field (hidden for test accounts) ─────────
              if (!_isTestPhone) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Password',
                      style: AppTextStyles.inputLabel.copyWith(
                        color: HuddlColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: AppTextStyles.body1,
                      decoration: InputDecoration(
                        hintText: 'Min 8 chars, upper+lower+digit',
                        hintStyle: AppTextStyles.inputHint,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: HuddlColors.textSecondary,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                        border: const UnderlineInputBorder(
                          borderSide: BorderSide(color: HuddlColors.gray300),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: HuddlColors.primary, width: 2),
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: HuddlColors.gray300),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _handleLogin(),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Forgot password ──────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showForgotPasswordFlow,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Forgot password?',
                      style: AppTextStyles.body2.copyWith(
                        color: HuddlColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // ── Error message ────────────────────────────────
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: HuddlColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: AppTextStyles.body2.copyWith(
                      color: HuddlColors.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 16),

              // ── Log in button ────────────────────────────────
              _isLoading
                  ? SizedBox(
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: HuddlColors.primary,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : PrimaryButton(
                      text: _isTestPhone ? 'Continue to OTP' : 'Log in',
                      onPressed: _canLogin ? _handleLogin : null,
                    ),

              const SizedBox(height: 40),

              // ── Sign up link ─────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: AppTextStyles.body2.copyWith(
                      color: HuddlColors.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(context, '/onboarding'),
                    child: Text(
                      'Sign up',
                      style: AppTextStyles.body2.copyWith(
                        color: HuddlColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Forgot password — sends SMS OTP to reset ──────────────────────────
  void _showForgotPasswordFlow() {
    final resetPhoneCtrl = TextEditingController();
    String? resetPhoneError;
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: HuddlColors.gray300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Reset password',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.textDark)),
                const SizedBox(height: 8),
                Text(
                    'Enter your UK mobile number. We\'ll send an SMS code to verify your identity.',
                    style: TextStyle(
                        fontSize: 14,
                        color: HuddlColors.textSecondary,
                        height: 1.4)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: HuddlColors.inputBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('\u{1F1EC}\u{1F1E7} +44',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: resetPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        maxLength: 10,
                        onChanged: (v) {
                          setLocal(
                              () => resetPhoneError = _validatePhone(v));
                        },
                        decoration: InputDecoration(
                          hintText: '7700 900 123',
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: resetPhoneError != null
                                    ? HuddlColors.error
                                    : HuddlColors.inputBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: HuddlColors.primary, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                if (resetPhoneError != null) ...[
                  const SizedBox(height: 4),
                  Text(resetPhoneError!,
                      style: TextStyle(
                          fontSize: 12,
                          color: HuddlColors.error,
                          fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSending ? null : () async {
                      final digits = _normalise(resetPhoneCtrl.text);
                      if (digits.length == 10 && digits.startsWith('7')) {
                        setLocal(() => isSending = true);
                        final fullPhone = '+44$digits';
                        try {
                          final result = await _authService.verifyPhoneNumber(fullPhone)
                              .timeout(const Duration(seconds: 10), onTimeout: () {
                            return PhoneAuthResult(
                              status: PhoneAuthStatus.error,
                              errorMessage: 'Timed out. Please try again.',
                            );
                          });
                          if (!ctx.mounted) return;
                          setLocal(() => isSending = false);
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    result.status == PhoneAuthStatus.codeSent
                                        ? 'Verification code sent to $fullPhone'
                                        : result.errorMessage ?? 'Failed to send code.',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                backgroundColor: result.status == PhoneAuthStatus.codeSent
                                    ? HuddlColors.successGreen
                                    : HuddlColors.error,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        } catch (_) {
                          if (!ctx.mounted) return;
                          setLocal(() => isSending = false);
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Failed to send code. Please try again.',
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                                backgroundColor: HuddlColors.error,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HuddlColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: isSending
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Send Verification Code',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── UK Mobile Input Formatter (same as onboarding) ──────────────────────────
class _UKMobileInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;
    while (text.startsWith('0')) {
      text = text.substring(1);
    }
    if (text.isNotEmpty && text[0] != '7') {
      return oldValue;
    }
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: text.length.clamp(0, text.length),
      ),
    );
  }
}
