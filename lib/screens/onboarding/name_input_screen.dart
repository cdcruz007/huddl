import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../theme/huddl_icons.dart';
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

  // AGE-1 — DOB picker state
  // Defaults to 25 years ago so the wheel opens in an adult range.
  // The user must actively scroll to their real DOB — no trivial bypass.
  DateTime _selectedDob = DateTime(
    DateTime.now().year - 25,
    DateTime.now().month,
    DateTime.now().day,
  );
  bool _dobPicked = false; // true once the user dismisses the picker sheet

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool get _nameOk  => _nameCtrl.text.trim().isNotEmpty;
  bool get _emailOk => _isValidEmail(_emailCtrl.text.trim());
  // AGE-1: require explicit DOB pick before Continue is enabled.
  bool get _canContinue => _nameOk && _emailOk && _dobPicked;

  bool _isValidEmail(String v) {
    return RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(v);
  }

  // AGE-1: compute completed years between dob and today.
  int _ageFromDob(DateTime dob) {
    final today = DateTime.now();
    int age = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age;
  }

  // AGE-1: open the DOB picker sheet.
  Future<void> _pickDob() async {
    DateTime tempDob = _selectedDob;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: HuddlColors.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Date of birth',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _selectedDob,
                  maximumDate: DateTime.now(),
                  minimumDate: DateTime(1900),
                  onDateTimeChanged: (d) => tempDob = d,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      color: HuddlColors.onboardingOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );

    setState(() {
      _selectedDob = tempDob;
      _dobPicked = true;
    });
  }

  void _continue() {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    if (name.isEmpty || !_isValidEmail(email) || !_dobPicked) return;

    // AGE-1 client gate — server enforces independently via Firestore rules.
    final age = _ageFromDob(_selectedDob);
    if (age < 18) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/age_restricted',
        (route) => route.settings.name == '/splash',
      );
      return;
    }

    final svc = OnboardingDataService();
    svc.setName(name);
    svc.setEmail(email);
    svc.setDateOfBirth(_selectedDob); // AGE-1

    Navigator.pushNamed(context, '/consent');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                    Center(
                      child: Text(
                        'Other parents in Cambridge will see your first name only.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? HuddlColors.darkTextSecondary
                              : HuddlColors.disabledText,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Date of birth picker — AGE-1 ────────────────────
                    _DobPickerRow(
                      dob: _selectedDob,
                      picked: _dobPicked,
                      onTap: _pickDob,
                    ),

                    const SizedBox(height: 20),

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
                        'For account recovery and occasional updates. Unsubscribe any time.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? HuddlColors.darkTextSecondary
                              : HuddlColors.textSecondary,
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
            HuddlIcons.arrowBack,
            size: 18,
            color: Colors.white,
          ),
          onPressed: onBack ?? () => Navigator.pop(context),
        ),
      ),
    );
  }
}

/// Full-width orange button; dark-mode-aware disabled state
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
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: enabled ? Colors.white : disabledFg,
          ),
        ),
      ),
    );
  }
}

// ── AGE-1: DOB picker row ──────────────────────────────────────────────────────
/// Tappable row that opens the date-of-birth picker sheet.
/// Shows a placeholder until the user confirms a DOB, then shows the
/// formatted date.  Uses the same filled-box style as _UnderlineInput.
class _DobPickerRow extends StatelessWidget {
  final DateTime dob;
  final bool picked;
  final VoidCallback onTap;

  const _DobPickerRow({
    required this.dob,
    required this.picked,
    required this.onTap,
  });

  String _formatted(DateTime d) {
    final day   = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark ? HuddlColors.darkInputBg : HuddlColors.neutral50;
    final hintColor = isDark ? HuddlColors.darkTextTertiary : HuddlColors.disabledText;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: fieldFill,
          borderRadius: BorderRadius.circular(12),
          border: isDark
              ? Border.all(color: HuddlColors.darkDivider, width: 1)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.cake_outlined,
              size: 20,
              color: picked ? HuddlColors.primary : hintColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                picked ? _formatted(dob) : 'Date of birth',
                style: TextStyle(
                  fontSize: 16,
                  color: picked ? textColor : hintColor,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: hintColor,
            ),
          ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark ? HuddlColors.darkInputBg : HuddlColors.neutral50;
    final hintColor = isDark ? HuddlColors.darkTextTertiary : HuddlColors.disabledText;
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
            hintStyle: TextStyle(
              fontSize: 16,
              color: hintColor,
            ),
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
              borderSide: showError
                  ? const BorderSide(color: Colors.redAccent, width: 1.5)
                  : isDark
                      ? const BorderSide(color: HuddlColors.darkDivider, width: 1)
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
