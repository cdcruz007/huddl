import 'package:flutter/material.dart';
import '../../theme/huddl_icons.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/funnel_analytics.dart';
import '../../services/postcode_service.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/onboarding_progress_bar.dart';


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

  bool _isChecking = false;

  void _continue() async {
    if (!_canContinue || _isChecking) return;
    final postcode = _ctrl.text.trim().toUpperCase();
    final postcodeService = PostcodeService();

    setState(() => _isChecking = true);

    // ── Authoritative full-postcode lookup via postcodes.io ───────────
    // lookupBoroughAsync resolves the admin_district from the FULL postcode
    // (e.g. "CB1 2AB" → "Cambridge", "N1 9GU" → "Islington") and caches
    // the result in PostcodeService._cache.  We also persist it directly
    // to OnboardingDataService so it survives app restarts without needing
    // another API call.
    final borough = await postcodeService.lookupBoroughAsync(postcode);
    if (!mounted) return;
    setState(() => _isChecking = false);

    // ONBOARD-BOROUGH-1 + LAYER-4-POSTCODE-ORDER-1: check borough resolution
    // FIRST. A null borough means the postcodes.io lookup timed out / returned
    // no admin_district — a transient failure. The user must retry, NOT be
    // wrongly routed to /not_available (they may actually be in Cambridge).
    if (borough == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We couldn\'t confirm your area. Check your connection and try again.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return; // stay on postcode screen; retry on transient fix
    }

    // Cambridge-only launch gate — only reached with a resolved (non-null) borough.
    // Borough is guaranteed non-null here; no async string-pattern fallback needed.
    final isCambridge = PostcodeService.isCambridgeBoroughStatic(borough);
    if (!isCambridge) {
      Navigator.pushNamed(context, '/not_available');
      return;
    }
    // ──────────────────────────────────────────────────────────────────

    final service = OnboardingDataService();
    service.setPostcode(postcode);
    service.setBorough(borough); // ONBOARD-BOROUGH-1: unconditional — guaranteed non-null
    // LAYER-16-NO-FUNNEL-1: funnel step 3 — Cambridge postcode accepted (success branch only).
    // NOT fired on null-borough retry or /not_available redirect.
    FunnelAnalytics.log('onboarding_postcode_accepted');
    if (mounted) Navigator.pushNamed(context, '/phone_number');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // Scaffold automatically resizes when keyboard appears
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingAppBar(onBack: () => Navigator.pop(context)),
            OnboardingProgressBar(step: OnboardingStep.postcode),
            Expanded(
              child: SingleChildScrollView(
                // Ensures content scrolls up when keyboard appears
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Text(
                      'Where in Cambridge are you?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Builder(builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      final baseColor = isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;
                      final boldColor = isDark ? HuddlColors.darkTextPrimary : HuddlColors.nearBlack;
                      return RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: baseColor,
                            height: 1.55,
                          ),
                          children: [
                            const TextSpan(
                              text: "We'll show you parents and groups ",
                            ),
                            TextSpan(
                              text: 'within walking distance.',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: boldColor,
                                fontSize: 16,
                              ),
                            ),
                            const TextSpan(
                              text: '\n\nYour exact location is never shared.',
                            ),
                          ],
                        ),
                      );
                    }),
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
                              ? '✓ ${PostcodeService().getBoroughFromPostcode(_ctrl.text.trim().toUpperCase()) ?? 'Valid UK postcode'}'
                              : 'Enter a complete UK postcode (e.g. CB3 9DF)',
                          style: TextStyle(
                            fontSize: 12,
                            color: _canContinue
                                ? HuddlColors.success
                                : HuddlColors.disabledText,
                          ),
                        ),
                      ),
                    const SizedBox(height: 32),
                    _OrangeButton(
                      label: _isChecking ? 'Checking…' : 'Continue',
                      enabled: _canContinue && !_isChecking,
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
          tooltip: 'Back',
          icon: const Icon(
            HuddlIcons.arrowBack,
            size: 18,
            color: Colors.white,
          ),
          onPressed: onBack,
        ),
      ),
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
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark ? HuddlColors.darkInputBg : HuddlColors.neutral50;
    final hintColor = isDark ? HuddlColors.darkTextTertiary : HuddlColors.disabledText;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        LengthLimitingTextInputFormatter(8),
        _UpperCaseTextFormatter(),
      ],
      style: HuddlText.body(color: Theme.of(context).colorScheme.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: HuddlText.body(color: hintColor),
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
          borderSide: const BorderSide(color: HuddlColors.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        child: Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: enabled ? Colors.white : disabledFg)),
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
