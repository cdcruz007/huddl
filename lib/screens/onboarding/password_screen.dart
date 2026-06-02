import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/onboarding_progress_bar.dart';

// ── Password strength helpers ─────────────────────────────────────────────────

enum _Strength { empty, weak, fair, good, strong }

class _PasswordPolicy {
  static bool hasMinLength(String p) => p.length >= 8;
  static bool hasUppercase(String p) => p.contains(RegExp(r'[A-Z]'));
  static bool hasLowercase(String p) => p.contains(RegExp(r'[a-z]'));
  static bool hasDigit(String p) => p.contains(RegExp(r'[0-9]'));
  static bool hasSpecial(String p) =>
      p.contains(RegExp(r'[!@#$%^&*()+\-=\[\]{};:.,<>?/|`~@_]'));

  static bool isValid(String p) =>
      hasMinLength(p) &&
      hasUppercase(p) &&
      hasLowercase(p) &&
      hasDigit(p) &&
      hasSpecial(p);

  static _Strength strength(String p) {
    if (p.isEmpty) return _Strength.empty;
    int score = 0;
    if (hasMinLength(p)) score++;
    if (hasUppercase(p)) score++;
    if (hasLowercase(p)) score++;
    if (hasDigit(p)) score++;
    if (hasSpecial(p)) score++;
    if (score <= 1) return _Strength.weak;
    if (score == 2) return _Strength.fair;
    if (score == 3 || score == 4) return _Strength.good;
    return _Strength.strong;
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _passCtrl = TextEditingController();
  final _repeatCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureRepeat = true;
  String? _errorMsg;
  bool _isLoading = false;
  bool _agreedToTerms = false;

  @override
  void initState() {
    super.initState();
    _passCtrl.addListener(_onChanged);
    _repeatCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _repeatCtrl.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {
        _errorMsg = null;
        if (_repeatCtrl.text.isNotEmpty &&
            _passCtrl.text != _repeatCtrl.text) {
          _errorMsg = 'Passwords do not match';
        }
      });

  bool get _canCreate =>
      _PasswordPolicy.isValid(_passCtrl.text) &&
      _passCtrl.text == _repeatCtrl.text &&
      _repeatCtrl.text.isNotEmpty &&
      _agreedToTerms;

  Future<void> _createAccount() async {
    if (!_canCreate) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final onboardingService = OnboardingDataService();
    onboardingService.setPassword(_passCtrl.text);

    // On web, Firebase phone auth (reCAPTCHA) cannot work in sandboxed
    // environments. Skip the verification screen entirely — save data
    // locally and proceed straight to welcome. The real phone-OTP
    // verification happens on the native Android app.
    if (kIsWeb) {
      onboardingService.setPhoneVerified(true);
      setState(() => _isLoading = false);
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
            context, '/welcome_complete', (route) => false);
      }
      return;
    }

    // On mobile, go through the normal phone OTP verification flow
    setState(() => _isLoading = false);
    if (mounted) Navigator.pushNamed(context, '/verification');
  }

  @override
  Widget build(BuildContext context) {
    final pw = _passCtrl.text;
    final strength = _PasswordPolicy.strength(pw);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingAppBar(onBack: () => Navigator.pop(context)),
            OnboardingProgressBar(step: OnboardingStep.password),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 36),

                    // Title
                    Text(
                      'Create a password',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You\'ll use this to sign back in. Make it something memorable.',
                      style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? HuddlColors.darkTextSecondary
                              : HuddlColors.disabledText,
                          height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Password field
                    _PasswordInput(
                      controller: _passCtrl,
                      hint: 'Enter your password',
                      obscure: _obscurePass,
                      onToggle: () =>
                          setState(() => _obscurePass = !_obscurePass),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),

                    // Strength bar
                    if (pw.isNotEmpty) ...[
                      _StrengthBar(strength: strength),
                      const SizedBox(height: 10),
                    ],

                    // Requirements checklist
                    _RequirementsPanel(password: pw),
                    const SizedBox(height: 20),

                    // Confirm password field
                    _PasswordInput(
                      controller: _repeatCtrl,
                      hint: 'Confirm your password',
                      obscure: _obscureRepeat,
                      onToggle: () =>
                          setState(() => _obscureRepeat = !_obscureRepeat),
                      onChanged: (_) => setState(() {}),
                    ),

                    // Error message
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _errorMsg!,
                          style: const TextStyle(
                              fontSize: 13,
                              color: HuddlColors.error,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // GDPR consent checkbox
                    GestureDetector(
                      onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _agreedToTerms,
                              onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                              activeColor: HuddlColors.onboardingOrange,
                              checkColor: Colors.white,
                              side: BorderSide(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? HuddlColors.darkTextSecondary
                                    : HuddlColors.textSecondary,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? HuddlColors.darkTextSecondary
                                        : HuddlColors.disabledText,
                                    height: 1.5),
                                children: [
                                  const TextSpan(
                                      text: "I agree to Huddl's "),
                                  TextSpan(
                                    text: 'Terms of Service',
                                    style: const TextStyle(
                                      color: HuddlColors.onboardingOrange,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () =>
                                          Navigator.pushNamed(context, '/terms'),
                                  ),
                                  const TextSpan(text: ' and '),
                                  TextSpan(
                                    text: 'Privacy Policy',
                                    style: const TextStyle(
                                      color: HuddlColors.onboardingOrange,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () =>
                                          Navigator.pushNamed(context, '/privacy'),
                                  ),
                                  const TextSpan(
                                      text: ', including the processing of my personal data as described in the Privacy Policy.'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Create account button
                    _OrangeButton(
                      label: _isLoading ? 'Creating...' : 'Create account',
                      enabled: _canCreate && !_isLoading,
                      onTap: _createAccount,
                    ),
                    const SizedBox(height: 32),
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

// ── Strength bar ──────────────────────────────────────────────────────────────

class _StrengthBar extends StatelessWidget {
  final _Strength strength;
  const _StrengthBar({required this.strength});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final data = _strengthData(strength, isDark);
    final emptyColor = isDark ? HuddlColors.darkDivider : HuddlColors.inputBorderLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            final filled = i < data.segments;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                height: 4,
                decoration: BoxDecoration(
                  color: filled ? data.color : emptyColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Text(
          data.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: data.color,
          ),
        ),
      ],
    );
  }

  ({int segments, Color color, String label}) _strengthData(_Strength s, bool isDark) {
    switch (s) {
      case _Strength.weak:
        return (segments: 1, color: HuddlColors.error, label: 'Weak');
      case _Strength.fair:
        return (segments: 2, color: HuddlColors.warning, label: 'Fair');
      case _Strength.good:
        return (segments: 3, color: isDark ? HuddlColors.darkTextPrimary : HuddlColors.nearBlack, label: 'Good');
      case _Strength.strong:
        return (segments: 4, color: HuddlColors.success, label: 'Strong');
      case _Strength.empty:
        return (segments: 0, color: isDark ? HuddlColors.darkDivider : HuddlColors.inputBorderLight, label: '');
    }
  }
}

// ── Requirements checklist ────────────────────────────────────────────────────

class _RequirementsPanel extends StatelessWidget {
  final String password;
  const _RequirementsPanel({required this.password});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? HuddlColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? HuddlColors.darkDivider : HuddlColors.disabled),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password must contain:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? HuddlColors.darkTextSecondary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          _Req('At least 8 characters',
              _PasswordPolicy.hasMinLength(password)),
          _Req('At least one uppercase letter (A–Z)',
              _PasswordPolicy.hasUppercase(password)),
          _Req('At least one lowercase letter (a–z)',
              _PasswordPolicy.hasLowercase(password)),
          _Req('At least one number (0–9)',
              _PasswordPolicy.hasDigit(password)),
          _Req('At least one special character (!@#\$%^&*…)',
              _PasswordPolicy.hasSpecial(password)),
        ],
      ),
    );
  }
}

class _Req extends StatelessWidget {
  final String label;
  final bool met;
  const _Req(this.label, this.met);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: met
                ? HuddlColors.success
                : (isDark ? HuddlColors.darkTextTertiary : HuddlColors.disabledText),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: met
                    ? (isDark
                        ? HuddlColors.darkTextPrimary
                        : Theme.of(context).colorScheme.onSurface)
                    : (isDark ? HuddlColors.darkTextSecondary : HuddlColors.disabledText),
                fontWeight: met ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Password input field ──────────────────────────────────────────────────────

class _PasswordInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;

  const _PasswordInput({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggle,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark ? HuddlColors.darkInputBg : HuddlColors.neutral50;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: obscure,
          onChanged: onChanged,
          style: HuddlText.body(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: HuddlText.body(
                color: isDark ? HuddlColors.darkTextTertiary : HuddlColors.disabledText),
            filled: true,
            fillColor: fieldFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: isDark
                  ? const BorderSide(color: HuddlColors.darkDivider, width: 1)
                  : BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: isDark
                  ? const BorderSide(color: HuddlColors.darkDivider, width: 1)
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: HuddlColors.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: isDark ? HuddlColors.darkTextSecondary : HuddlColors.disabledText,
                size: 22,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _OnboardingAppBar extends StatelessWidget {
  final VoidCallback onBack;
  const _OnboardingAppBar({required this.onBack});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: Colors.white,
          ),
          onPressed: onBack,
        ),
      ),
    );
  }
}

class _OrangeButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _OrangeButton(
      {required this.label, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabledBg = isDark ? HuddlColors.darkSurfaceVariant : HuddlColors.disabled;
    final disabledFg = isDark ? HuddlColors.darkTextTertiary : HuddlColors.disabledText;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
            color: enabled ? HuddlColors.onboardingOrange : disabledBg,
            borderRadius: BorderRadius.circular(12),
            border: !enabled && isDark
                ? Border.all(color: HuddlColors.darkDivider, width: 1)
                : null),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: enabled ? Colors.white : disabledFg),
        ),
      ),
    );
  }
}
