import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../services/onboarding_data_service.dart';
import '../legal/terms_of_service_screen.dart';
import '../legal/privacy_policy_detail_screen.dart';

const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kInputBg = Color(0xFFF5F5F5);
const _kInputBorder = Color(0xFFDDDDDD);
const _kErrorRed = Color(0xFFE53935);
const _kGreen = Color(0xFF27AE60); // Style guide success green

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
      _repeatCtrl.text.isNotEmpty;

  Future<void> _createAccount() async {
    if (!_canCreate) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    final onboardingService = OnboardingDataService();
    onboardingService.setPassword(_passCtrl.text);
    setState(() => _isLoading = false);
    if (mounted) Navigator.pushNamed(context, '/verification');
  }

  @override
  Widget build(BuildContext context) {
    final pw = _passCtrl.text;
    final strength = _PasswordPolicy.strength(pw);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingAppBar(onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 36),

                    // Title
                    const Text(
                      'Create a password',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose a strong password to keep your account secure.',
                      style: TextStyle(
                          fontSize: 14, color: _kTextGray, height: 1.5),
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
                              color: _kErrorRed,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Terms
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                            fontSize: 13, color: _kTextGray, height: 1.5),
                        children: [
                          const TextSpan(
                              text: "By continuing, you agree to Huddl's "),
                          TextSpan(
                            text: 'Terms of Service',
                            style: const TextStyle(
                              color: _kOrange,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const TermsOfServiceScreen(),
                                  ),
                                );
                              },
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: const TextStyle(
                              color: _kOrange,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const PrivacyPolicyDetailScreen(),
                                  ),
                                );
                              },
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
    final data = _strengthData(strength);
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
                  color: filled ? data.color : const Color(0xFFE0E0E0),
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

  ({int segments, Color color, String label}) _strengthData(_Strength s) {
    switch (s) {
      case _Strength.weak:
        return (segments: 1, color: _kErrorRed, label: 'Weak');
      case _Strength.fair:
        return (segments: 2, color: const Color(0xFFFF9800), label: 'Fair');
      case _Strength.good:
        return (segments: 3, color: const Color(0xFF2196F3), label: 'Good');
      case _Strength.strong:
        return (segments: 4, color: _kGreen, label: 'Strong');
      case _Strength.empty:
        return (segments: 0, color: const Color(0xFFE0E0E0), label: '');
    }
  }
}

// ── Requirements checklist ────────────────────────────────────────────────────

class _RequirementsPanel extends StatelessWidget {
  final String password;
  const _RequirementsPanel({required this.password});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Password must contain:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _kTextDark,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: met ? _kGreen : _kTextGray,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: met ? _kTextDark : _kTextGray,
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
    return Container(
      decoration: const BoxDecoration(
        color: _kInputBg,
        border: Border(bottom: BorderSide(color: _kInputBorder, width: 1.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8),
            child: Text(
              hint,
              style: const TextStyle(fontSize: 11, color: _kTextGray),
            ),
          ),
          TextField(
            controller: controller,
            obscureText: obscure,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 16, color: _kTextDark),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.fromLTRB(16, 2, 16, 12),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _kTextGray,
                  size: 22,
                ),
                onPressed: onToggle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _OnboardingAppBar extends StatelessWidget {
  final VoidCallback onBack;
  const _OnboardingAppBar({required this.onBack});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(children: [
        IconButton(
            icon: const Icon(Icons.chevron_left, size: 30, color: _kOrange),
            onPressed: onBack,
            padding: EdgeInsets.zero),
        const Expanded(child: _HuddlLogo()),
        const SizedBox(width: 48),
      ]),
    );
  }
}

class _HuddlLogo extends StatelessWidget {
  const _HuddlLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_huddl_splash.png',
      height: 34,
      fit: BoxFit.contain,
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
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
            color: enabled ? _kOrange : const Color(0xFFEEEEEE),
            borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: enabled ? Colors.white : _kTextGray),
        ),
      ),
    );
  }
}
