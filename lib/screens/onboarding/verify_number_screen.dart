import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Design tokens from screenshot 13
const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kBtnDisabled = Color(0xFFEEEEEE);

class VerifyNumberScreen extends StatefulWidget {
  const VerifyNumberScreen({super.key});

  @override
  State<VerifyNumberScreen> createState() => _VerifyNumberScreenState();
}

class _VerifyNumberScreenState extends State<VerifyNumberScreen> {
  final _codeController = TextEditingController();
  int _resendTimer = 26;
  bool _timerRunning = true;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() => setState(() {}));
    _tickTimer();
  }

  void _tickTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _timerRunning && _resendTimer > 0) {
        setState(() => _resendTimer--);
        _tickTimer();
      }
    });
  }

  @override
  void dispose() {
    _timerRunning = false;
    _codeController.dispose();
    super.dispose();
  }

  bool get _canContinue => _codeController.text.trim().length >= 4;

  void _continue() {
    if (!_canContinue) return;
    Navigator.pushNamed(context, '/welcome_complete');
  }

  void _resendCode() {
    if (_resendTimer > 0) return;
    setState(() => _resendTimer = 26);
    _tickTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── AppBar ─────────────────────────────────────────────────
            _OnboardingAppBar(onBack: () => Navigator.pop(context)),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // Title
                    const Text(
                      'Verify your number',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 48),

                    // ── Code input ─────────────────────────────────────
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF5F5F5),
                        border: Border(
                          bottom:
                              BorderSide(color: Color(0xFFDDDDDD), width: 1.2),
                        ),
                      ),
                      child: TextField(
                        controller: _codeController,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        style: const TextStyle(
                          fontSize: 18,
                          color: _kTextDark,
                          letterSpacing: 6,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter your code',
                          hintStyle: TextStyle(
                            fontSize: 16,
                            color: _kTextGray,
                            letterSpacing: 0,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Resend button ──────────────────────────────────
                    GestureDetector(
                      onTap: _resendCode,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFE0E0E0), width: 1),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _resendTimer > 0
                              ? 'I didn\'t receive a code ($_resendTimer)'
                              : 'Resend code',
                          style: TextStyle(
                            fontSize: 15,
                            color: _resendTimer > 0
                                ? _kTextGray
                                : _kOrange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Continue button ────────────────────────────────
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
            color: enabled ? _kOrange : _kBtnDisabled,
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
