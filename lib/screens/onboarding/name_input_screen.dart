import 'package:flutter/material.dart';
import '../../services/onboarding_data_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kBtnDisabled = Color(0xFFEEEEEE);
const _kInputBg = Color(0xFFF5F5F5);
const _kInputBorder = Color(0xFFDDDDDD);

class NameInputScreen extends StatefulWidget {
  const NameInputScreen({super.key});

  @override
  State<NameInputScreen> createState() => _NameInputScreenState();
}

class _NameInputScreenState extends State<NameInputScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canContinue => _ctrl.text.trim().isNotEmpty;

  void _continue() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    OnboardingDataService().setName(name);
    Navigator.pushNamed(context, '/parent_type');
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
                    // Title
                    const Center(
                      child: Text(
                        "What's your first name?",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: _kTextDark,
                          height: 1.25,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Center(
                      child: Text(
                        'Tell us what your neighbours should call you.',
                        style: TextStyle(
                          fontSize: 14,
                          color: _kTextGray,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Input field
                    _UnderlineInput(
                      controller: _ctrl,
                      hint: 'First name',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 32),
                    // Continue button
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

// ── Shared widgets used across all onboarding screens ─────────────────────────

/// AppBar with back arrow (orange) + centered Huddl logo
class _OnboardingAppBar extends StatelessWidget {
  final VoidCallback onBack;
  const _OnboardingAppBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 30, color: _kOrange),
            onPressed: onBack,
            padding: EdgeInsets.zero,
          ),
          const Expanded(child: _HuddlLogo()),
          const SizedBox(width: 48), // balance
        ],
      ),
    );
  }
}

/// Huddl H logo + text
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

/// Full-width orange button; grey when disabled
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
          color: enabled ? _kOrange : _kBtnDisabled,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: enabled ? Colors.white : _kTextGray,
          ),
        ),
      ),
    );
  }
}

/// Underline text field (grey background, bottom border)
class _UnderlineInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _UnderlineInput({
    required this.controller,
    required this.hint,
    this.onChanged,
  });

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
