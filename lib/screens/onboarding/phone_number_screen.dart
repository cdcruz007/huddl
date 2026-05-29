import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/onboarding_progress_bar.dart';


class PhoneNumberScreen extends StatefulWidget {
  const PhoneNumberScreen({super.key});

  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  final _ctrl = TextEditingController();
  static const _countryCode = '+44';
  static const _flagUK = '\u{1F1EC}\u{1F1E7}';

  String? _errorText;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Validation helpers ────────────────────────────────────────────────────

  /// Strips spaces and leading 0/+44 to get raw digits.
  String _normalise(String input) {
    String raw = input.replaceAll(RegExp(r'\s+'), '');
    // Strip +44 prefix if user pastes full international format
    if (raw.startsWith('+44')) raw = raw.substring(3);
    // Strip leading 0 (local format)
    if (raw.startsWith('0')) raw = raw.substring(1);
    return raw;
  }

  /// Returns null if valid, or an error message string.
  String? _validate(String raw) {
    final digits = _normalise(raw);

    if (digits.isEmpty) return null; // no error while empty

    // Must be digits only after normalisation
    if (!RegExp(r'^\d+$').hasMatch(digits)) {
      return 'Only digits are allowed';
    }

    // Must start with 7 (UK mobile subscriber numbers all start 7)
    if (digits.isNotEmpty && !digits.startsWith('7')) {
      if (digits.startsWith('1') || digits.startsWith('2')) {
        return 'Landline numbers are not accepted. Please enter a mobile number';
      }
      if (digits.startsWith('3') || digits.startsWith('8') || digits.startsWith('9')) {
        return 'This is not a UK mobile number';
      }
      return 'UK mobile numbers must start with 7 (after +44)';
    }

    // Reject premium / non-mobile 07x ranges
    if (digits.length >= 2) {
      final prefix2 = digits.substring(0, 2);
      // 70 = personal numbering, 76 = pager
      if (prefix2 == '70' || prefix2 == '76') {
        return 'Personal / pager numbers are not accepted';
      }
    }

    // Reject obviously fake numbers (all same digit)
    if (digits.length >= 6 && RegExp(r'^(\d)\1+$').hasMatch(digits)) {
      return 'Please enter a valid phone number';
    }

    // Reject sequential patterns like 1234567890
    if (digits.length >= 6 && _isSequential(digits)) {
      return 'Please enter a valid phone number';
    }

    // Length check
    if (digits.length < 10) {
      return null; // not an error yet, still typing
    }

    if (digits.length > 10) {
      return 'UK mobile numbers are 10 digits after the leading 0';
    }

    return null; // valid
  }

  bool _isSequential(String s) {
    bool ascending = true;
    bool descending = true;
    for (int i = 1; i < s.length; i++) {
      if (s.codeUnitAt(i) != s.codeUnitAt(i - 1) + 1) ascending = false;
      if (s.codeUnitAt(i) != s.codeUnitAt(i - 1) - 1) descending = false;
    }
    return ascending || descending;
  }

  /// True only when we have exactly 10 valid UK mobile digits.
  bool get _canContinue {
    final digits = _normalise(_ctrl.text);
    if (digits.length != 10) return false;
    if (!digits.startsWith('7')) return false;
    // Reject premium / non-mobile 07x ranges
    final prefix2 = digits.substring(0, 2);
    if (prefix2 == '70' || prefix2 == '76') return false;
    if (RegExp(r'^(\d)\1+$').hasMatch(digits)) return false;
    if (_isSequential(digits)) return false;
    if (_errorText != null) return false;
    return true;
  }

  /// Display-format the number as the user types: 07xxx xxx xxx
  String get _displayFormatted {
    final d = _normalise(_ctrl.text);
    if (d.isEmpty) return '';
    // Show in UK local format: 07xxx xxx xxx
    final local = '0$d';
    if (local.length <= 5) return local;
    if (local.length <= 8) return '${local.substring(0, 5)} ${local.substring(5)}';
    return '${local.substring(0, 5)} ${local.substring(5, 8)} ${local.substring(8)}';
  }

  void _onChanged(String _) {
    final error = _validate(_ctrl.text);
    setState(() => _errorText = error);
  }

  void _continue() {
    if (!_canContinue) return;
    FocusScope.of(context).unfocus(); // dismiss keyboard
    final digits = _normalise(_ctrl.text);
    // Store digits only (e.g. "7575888453") and country code separately.
    // verification_screen builds the full number as '$countryCode$phoneNumber'
    // so we must NOT include the +44 prefix in phoneNumber itself.
    OnboardingDataService().setPhoneNumber(digits, countryCode: _countryCode);
    Navigator.pushNamed(context, '/password');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final digits = _normalise(_ctrl.text);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingAppBar(onBack: () => Navigator.pop(context)),
            OnboardingProgressBar(step: OnboardingStep.phoneNumber),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Text(
                      'What is your phone number?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Enter your UK mobile number to create your account.',
                      style: TextStyle(
                          fontSize: 14, color: HuddlColors.disabledText, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),

                    // Phone input row
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).inputDecorationTheme.fillColor ?? context.hc.inputBg,
                        border: Border(
                          bottom: BorderSide(
                            color: _errorText != null ? HuddlColors.error : HuddlColors.inputBorder,
                            width: _errorText != null ? 1.8 : 1.2,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Country picker (locked to UK)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 16),
                            child: Row(
                              children: [
                                Text(_flagUK,
                                    style: TextStyle(fontSize: 22)),
                                const SizedBox(width: 6),
                                Text(
                                  _countryCode,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Divider
                          Container(
                              width: 1,
                              height: 28,
                              color: HuddlColors.inputBorder),
                          // Phone input
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 14, top: 8),
                                  child: Text(
                                    'Mobile number',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            HuddlColors.disabledText.withValues(alpha: 0.8)),
                                  ),
                                ),
                                TextField(
                                  controller: _ctrl,
                                  onChanged: _onChanged,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    _UKMobileInputFormatter(),
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  maxLength: 10,
                                  style: TextStyle(
                                      fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                                  decoration: const InputDecoration(
                                    hintText: '7700 900 123',
                                    hintStyle: TextStyle(
                                        fontSize: 16, color: HuddlColors.disabledText),
                                    border: InputBorder.none,
                                    counterText: '',
                                    contentPadding: EdgeInsets.fromLTRB(
                                        14, 2, 14, 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Error / validation feedback row
                    if (_errorText != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            _errorText!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: HuddlColors.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),

                    // Info / counter row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Live formatted preview
                        if (digits.isNotEmpty)
                          Text(
                            _displayFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              color: _canContinue ? HuddlColors.onboardingOrange : HuddlColors.disabledText,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        else
                          Text(
                            'UK mobile only (e.g. 07xxx xxx xxx)',
                            style: TextStyle(
                              fontSize: 11,
                              color: HuddlColors.disabledText.withValues(alpha: 0.8),
                            ),
                          ),
                        Text(
                          '${digits.length}/10',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _canContinue
                                ? HuddlColors.onboardingOrange
                                : HuddlColors.disabledText.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),
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

// ── UK Mobile Input Formatter ────────────────────────────────────────────────
/// Enforces that the first digit must be 7 (UK mobile subscriber prefix).
/// Strips any leading 0 the user types and rejects non-7 first digits.
class _UKMobileInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;

    // Strip any leading zeros (user habit from typing 07...)
    while (text.startsWith('0')) {
      text = text.substring(1);
    }

    // If first digit is not 7, reject the input (keep old value)
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

// ── Shared widgets ───────────────────────────────────────────────────────────
class _OnboardingAppBar extends StatelessWidget {
  final VoidCallback onBack;
  const _OnboardingAppBar({required this.onBack});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(children: [
        IconButton(
            icon: const Icon(Icons.chevron_left, size: 30, color: HuddlColors.onboardingOrange),
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
      'assets/images/huddl_logomark.png',
      height: 40,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: HuddlColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.people, color: Colors.white, size: 22),
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
            color: enabled ? HuddlColors.onboardingOrange : HuddlColors.disabled,
            borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: enabled ? Colors.white : HuddlColors.disabledText)),
      ),
    );
  }
}
