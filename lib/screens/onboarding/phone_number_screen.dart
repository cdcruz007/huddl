import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/onboarding_data_service.dart';

const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kInputBg = Color(0xFFF5F5F5);
const _kInputBorder = Color(0xFFDDDDDD);

class PhoneNumberScreen extends StatefulWidget {
  const PhoneNumberScreen({super.key});

  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  final _ctrl = TextEditingController();
  final String _countryCode = '+44';
  // Flag emoji for UK
  static const _flagUK = '🇬🇧';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // UK numbers are always 10 digits (e.g. 07575888888 → enter 7575888888,
  // or with leading 0: 07575888888). We accept exactly 10 or 11 digits.
  // Standard: subscriber number entered without country code = 10 digits
  // (07xxx xxxxxx → 10 digits including the leading 0, or
  //  7xxx xxxxxx  → 10 digits without the leading 0)
  // We enforce exactly 10 digits to match the UK mobile/landline standard.
  bool get _canContinue => _ctrl.text.trim().length == 10;

  void _continue() {
    if (!_canContinue) return;
    final full = '$_countryCode${_ctrl.text.trim()}';
    OnboardingDataService().setPhoneNumber(full);
    Navigator.pushNamed(context, '/password');
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
                      'What is your phone number?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Create your account using phone number',
                      style: TextStyle(
                          fontSize: 14, color: _kTextGray, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),

                    // Phone input row
                    Container(
                      decoration: const BoxDecoration(
                        color: _kInputBg,
                        border: Border(
                            bottom:
                                BorderSide(color: _kInputBorder, width: 1.2)),
                      ),
                      child: Row(
                        children: [
                          // Country picker
                          GestureDetector(
                            onTap: () {},
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 16),
                              child: Row(
                                children: [
                                  const Text(_flagUK, style: TextStyle(fontSize: 22)),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.keyboard_arrow_down,
                                      size: 20, color: _kTextGray),
                                ],
                              ),
                            ),
                          ),
                          // Divider
                          Container(
                              width: 1,
                              height: 28,
                              color: const Color(0xFFDDDDDD)),
                          // Phone input
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 14, top: 8),
                                  child: Text(
                                    'Phone number',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            _kTextGray.withValues(alpha: 0.8)),
                                  ),
                                ),
                                TextField(
                                  controller: _ctrl,
                                  onChanged: (_) => setState(() {}),
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  maxLength: 10,
                                  style: const TextStyle(
                                      fontSize: 16, color: _kTextDark),
                                  decoration: InputDecoration(
                                    hintText: 'e.g. 7700900123',
                                    hintStyle: const TextStyle(
                                        fontSize: 16, color: _kTextGray),
                                    border: InputBorder.none,
                                    counterText: '',
                                    contentPadding: const EdgeInsets.fromLTRB(
                                        14, 2, 14, 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 6),
                    // Digit counter hint
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Enter 10-digit UK number (without +44)',
                          style: TextStyle(
                            fontSize: 11,
                            color: _kTextGray.withValues(alpha: 0.8),
                          ),
                        ),
                        Text(
                          '${_ctrl.text.trim().length}/10',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _canContinue
                                ? _kOrange
                                : _kTextGray.withValues(alpha: 0.8),
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
