import 'package:flutter/material.dart';
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';


class DueDateScreen extends StatefulWidget {
  const DueDateScreen({super.key});

  @override
  State<DueDateScreen> createState() => _DueDateScreenState();
}

class _DueDateScreenState extends State<DueDateScreen> {
  late FixedExtentScrollController _yearCtrl;

  final _now = DateTime.now();
  late int _selYear;

  // Show current year through 4 years ahead (reasonable expecting window)
  late List<int> _years;

  @override
  void initState() {
    super.initState();
    _years = List.generate(5, (i) => _now.year + i);
    // Default to next year as most likely due year
    _selYear = _now.year + 1;
    _yearCtrl = FixedExtentScrollController(
      initialItem: _years.indexOf(_selYear),
    );
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    super.dispose();
  }

  void _continue() {
    // Store just the year — that's all the group service needs
    final service = OnboardingDataService();
    service.setDueDate('$_selYear');

    // If user also selected "I have a child", go to child_info next
    // before continuing to postcode
    if (service.stagesOfLife.contains('parent')) {
      Navigator.pushNamed(context, '/child_info');
    } else {
      Navigator.pushNamed(context, '/postcode');
    }
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
                  children: [
                    const SizedBox(height: 28),

                    // ── Title ────────────────────────────────────────
                    const Text(
                      'When is your baby due?',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.textDark,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'Select the year your baby is expected. This helps us connect you with other expecting parents.',
                      style: TextStyle(
                        fontSize: 14,
                        color: HuddlColors.disabledText,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    // ── Year-only drum picker ─────────────────────────
                    Center(
                      child: SizedBox(
                        width: 160,
                        height: 200,
                        child: _DrumPicker(
                          controller: _yearCtrl,
                          items: _years.map((y) => y.toString()).toList(),
                          onSelected: (i) =>
                              setState(() => _selYear = _years[i]),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Selected year display ─────────────────────────
                    Text(
                      'Due $_selYear',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.onboardingOrange,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Illustration ──────────────────────────────────
                    Expanded(
                      child: Image.asset(
                        'assets/images/illustrations/Group_3603.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink(),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── Continue button pinned ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: _OrangeButton(
                label: 'Continue',
                enabled: true,
                onTap: _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Drum-roll scroll picker ───────────────────────────────────────────────────
class _DrumPicker extends StatelessWidget {
  final FixedExtentScrollController controller;
  final List<String> items;
  final ValueChanged<int> onSelected;

  const _DrumPicker({
    required this.controller,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Selection highlight bar
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: HuddlColors.onboardingOrange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HuddlColors.onboardingOrange.withValues(alpha: 0.30), width: 1.5),
          ),
        ),
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: 52,
          perspective: 0.003,
          diameterRatio: 1.6,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: onSelected,
          childDelegate: ListWheelChildBuilderDelegate(
            builder: (ctx, i) {
              if (i < 0 || i >= items.length) return null;
              final selected =
                  controller.hasClients && controller.selectedItem == i;
              return Center(
                child: Text(
                  items[i],
                  style: TextStyle(
                    fontSize: selected ? 28 : 20,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w400,
                    color: selected ? HuddlColors.onboardingOrange : HuddlColors.disabledText,
                  ),
                ),
              );
            },
            childCount: items.length,
          ),
        ),
      ],
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
          icon: const Icon(Icons.chevron_left, size: 30, color: HuddlColors.onboardingOrange),
          onPressed: onBack,
          padding: EdgeInsets.zero,
        ),
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
