import 'package:flutter/material.dart';
import '../../widgets/common/huddl_logo.dart';
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/onboarding_progress_bar.dart';

class NameInputScreen extends StatefulWidget {
  const NameInputScreen({super.key});

  @override
  State<NameInputScreen> createState() => _NameInputScreenState();
}

class _NameInputScreenState extends State<NameInputScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();

  // Track email validity separately for inline error hint
  bool _emailTouched = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool get _nameOk  => _nameCtrl.text.trim().isNotEmpty;
  bool get _emailOk => _isValidEmail(_emailCtrl.text.trim());
  bool get _canContinue => _nameOk && _emailOk;

  bool _isValidEmail(String v) {
    // Standard RFC-5322 simplified regex — good enough for UX gating
    return RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(v);
  }

  void _continue() {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    if (name.isEmpty || !_isValidEmail(email)) return;

    final svc = OnboardingDataService();
    svc.setName(name);
    svc.setEmail(email);

    Navigator.pushNamed(context, '/consent');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingAppBar(onBack: () => Navigator.pop(context)),
            OnboardingProgressBar(step: OnboardingStep.name),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),

                    // ── Brand mark — first onboarding screen only ───────
                    const Center(child: HuddlLogomark(size: 44)),
                    const SizedBox(height: 28),

                    // ── Title ───────────────────────────────────────────
                    Center(
                      child: Text(
                        'First, what should we call you?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.25,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Center(
                      child: Text(
                        'Other parents in Cambridge will see your first name only.',
                        style: TextStyle(
                          fontSize: 14,
                          color: HuddlColors.disabledText,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── First name field ────────────────────────────────
                    _UnderlineInput(
                      controller: _nameCtrl,
                      hint: 'First name',
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),

                    const SizedBox(height: 20),

                    // ── Email field ─────────────────────────────────────
                    _UnderlineInput(
                      controller: _emailCtrl,
                      hint: 'Email address',
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() {
                        _emailTouched = true;
                      }),
                      showError: _emailTouched &&
                          _emailCtrl.text.trim().isNotEmpty &&
                          !_emailOk,
                      errorText: 'Please enter a valid email address',
                    ),

                    const SizedBox(height: 10),

                    // ── Privacy reassurance note ────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Add your email for receipts & updates. Don\'t worry, you can '
                        'unsubscribe from any emails you receive from the Huddl team '
                        'directly from your inbox.',
                        style: TextStyle(
                          fontSize: 12,
                          color: HuddlColors.textSecondary,
                          height: 1.55,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Continue button ─────────────────────────────────
                    _OrangeButton(
                      label: 'Continue',
                      enabled: _canContinue,
                      onTap: _continue,
                    ),

                    const SizedBox(height: 24),
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

/// Back-button-only app bar — 44px row, no logo.
/// Logo is shown explicitly in the body of the first onboarding screen only.
class _OnboardingAppBar extends StatelessWidget {
  final VoidCallback? onBack;
  const _OnboardingAppBar({this.onBack});

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
            color: HuddlColors.nearBlack,
          ),
          onPressed: onBack ?? () => Navigator.pop(context),
        ),
      ),
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

/// Rounded outlined text field — matches main app input style.
/// Optional [showError] flag + [errorText] for inline validation messages.
class _UnderlineInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final bool showError;
  final String? errorText;

  const _UnderlineInput({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.showError = false,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          autocorrect: false,
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 16,
              color: HuddlColors.disabledText,
            ),
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: showError
                  ? const BorderSide(color: Colors.redAccent, width: 1.5)
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: showError
                  ? const BorderSide(color: Colors.redAccent, width: 1.5)
                  : const BorderSide(color: HuddlColors.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
        if (showError && errorText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              errorText!,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.redAccent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
