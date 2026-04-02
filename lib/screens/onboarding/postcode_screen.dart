import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';

const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kInputBg = Color(0xFFF5F5F5);
const _kInputBorder = Color(0xFFDDDDDD);

class PostcodeScreen extends StatefulWidget {
  const PostcodeScreen({super.key});

  @override
  State<PostcodeScreen> createState() => _PostcodeScreenState();
}

class _PostcodeScreenState extends State<PostcodeScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Validates a complete UK postcode in all standard formats:
  /// AN NAA | ANN NAA | AAN NAA | AANN NAA | ANA NAA | AANA NAA
  /// Accepts with or without the space separator.
  static final _ukPostcodeRegex = RegExp(
    r'^[A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}$',
    caseSensitive: false,
  );

  bool get _canContinue =>
      _ukPostcodeRegex.hasMatch(_ctrl.text.trim());

  void _continue() async {
    if (!_canContinue) return;
    final postcode = _ctrl.text.trim().toUpperCase();
    final postcodeService = PostcodeService();

    // ── Cambridge-only launch gate ────────────────────────────────────
    if (!postcodeService.isCambridgePostcode(postcode)) {
      if (mounted) {
        Navigator.pushNamed(context, '/not_available');
      }
      return;
    }
    // ─────────────────────────────────────────────────────────────────

    final service = OnboardingDataService();
    service.setPostcode(postcode);
    if (mounted) Navigator.pushNamed(context, '/phone_number');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingAppBar(onBack: () => Navigator.pop(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    const Text(
                      'What is your postcode?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "We will connect you with other local parents. Your postcode won't be shared anywhere.",
                      style: TextStyle(
                          fontSize: 14, color: _kTextGray, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    _UnderlineInput(
                      controller: _ctrl,
                      hint: 'e.g. CB3 9DF',
                      keyboardType: TextInputType.text,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    // ── Live format hint ─────────────────────────────
                    if (_ctrl.text.trim().isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _canContinue
                              ? '✓ Valid UK postcode'
                              : 'Enter a complete UK postcode (e.g. CB3 9DF)',
                          style: TextStyle(
                            fontSize: 12,
                            color: _canContinue
                                ? const Color(0xFF27AE60)
                                : _kTextGray,
                          ),
                        ),
                      ),
                    const SizedBox(height: 32),
                    _OrangeButton(
                      label: 'Continue',
                      enabled: _canContinue,
                      onTap: _continue,
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

class _UnderlineInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final TextInputType keyboardType;

  const _UnderlineInput(
      {required this.controller,
      required this.hint,
      this.onChanged,
      this.keyboardType = TextInputType.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kInputBg,
        border: Border(bottom: BorderSide(color: _kInputBorder, width: 1.2)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: keyboardType,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          LengthLimitingTextInputFormatter(8),
          _UpperCaseTextFormatter(),
        ],
        style: const TextStyle(fontSize: 16, color: _kTextDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 16, color: _kTextGray),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
            color: enabled ? _kOrange : const Color(0xFFEEEEEE),
            borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: enabled ? Colors.white : _kTextGray)),
      ),
    );
  }
}

/// Forces every character to uppercase immediately as the user types,
/// preserving cursor position correctly.
class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    return newValue.copyWith(
      text: upper,
      selection: newValue.selection.copyWith(
        baseOffset:
            newValue.selection.baseOffset.clamp(0, upper.length),
        extentOffset:
            newValue.selection.extentOffset.clamp(0, upper.length),
      ),
    );
  }
}
