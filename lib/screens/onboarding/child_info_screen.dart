import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/onboarding_data_service.dart';

const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kInputBg = Color(0xFFF5F5F5);
const _kInputBorder = Color(0xFFDDDDDD);

class ChildInfoScreen extends StatefulWidget {
  const ChildInfoScreen({super.key});

  @override
  State<ChildInfoScreen> createState() => _ChildInfoScreenState();
}

class _ChildInfoScreenState extends State<ChildInfoScreen> {
  final List<_ChildEntry> _children = [_ChildEntry()];

  @override
  void dispose() {
    for (final c in _children) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canContinue => _children.any(
      (c) => c.yearCtrl.text.trim().length == 4);

  void _addChild() {
    setState(() => _children.add(_ChildEntry()));
  }

  void _continue() {
    if (!_canContinue) return;
    final data = _children
        .where((c) => c.yearCtrl.text.trim().isNotEmpty)
        .map((c) => {
              'name': c.nameCtrl.text.trim(),
              'birthday': c.yearCtrl.text.trim(),
            })
        .toList();
    OnboardingDataService().setChildren(data);
    Navigator.pushNamed(context, '/postcode');
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),
                    const Text(
                      'Your child',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Meet parents with children the same age as yours. Date\nof birth won\'t be shared.',
                      style: TextStyle(
                          fontSize: 14, color: _kTextGray, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Illustration
                    Image.asset(
                      'assets/images/illustrations/man__woman__female__male__person__shapes__shape__layout.png',
                      height: 160,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox(height: 160),
                    ),

                    const SizedBox(height: 24),

                    // Child inputs
                    ...List.generate(_children.length, (i) {
                      final child = _children[i];
                      return Column(
                        children: [
                          if (i > 0) const SizedBox(height: 20),
                          _UnderlineInput(
                            controller: child.nameCtrl,
                            hint: 'Child name (optional)',
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          _UnderlineInput(
                            controller: child.yearCtrl,
                            hint: 'Year of birth (yyyy)',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      );
                    }),

                    const SizedBox(height: 16),

                    // Add another child button
                    GestureDetector(
                      onTap: _addChild,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Add another child',
                              style: TextStyle(
                                  fontSize: 15, color: _kTextGray),
                            ),
                            Icon(Icons.add, color: _kOrange, size: 22),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            // Continue button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: _OrangeButton(
                  label: 'Continue',
                  enabled: _canContinue,
                  onTap: _continue),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildEntry {
  final nameCtrl = TextEditingController();
  final yearCtrl = TextEditingController();
  void dispose() {
    nameCtrl.dispose();
    yearCtrl.dispose();
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
  final List<TextInputFormatter>? inputFormatters;

  const _UnderlineInput({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
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
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
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
