import 'package:flutter/material.dart';
import '../../services/onboarding_data_service.dart';

const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kBtnDisabled = Color(0xFFEEEEEE);
const _kCardBorder = Color(0xFFE8E8E8);

class StageOfLifeScreen extends StatefulWidget {
  const StageOfLifeScreen({super.key});

  @override
  State<StageOfLifeScreen> createState() => _StageOfLifeScreenState();
}

class _StageOfLifeScreenState extends State<StageOfLifeScreen> {
  // Multi-select: use a Set so toggling works correctly
  final Set<String> _selected = {};

  static const _stages = [
    _StageItem(
      id: 'aspiring',
      label: 'Trying for a baby',
      icon: Icons.favorite_border,
    ),
    _StageItem(
      id: 'expecting',
      label: 'Expecting a baby',
      icon: Icons.child_friendly,
    ),
    _StageItem(
      id: 'parent',
      label: 'I have a child',
      icon: Icons.face,
    ),
  ];

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _continue() {
    if (_selected.isEmpty) return;

    // Save all selected stages to onboarding service
    OnboardingDataService().setStagesOfLife(_selected.toList());

    // Navigation logic:
    // - expecting  → due date screen first
    // - parent     → child info screen first
    // - expecting + parent → due date (child info is next in that flow)
    // - aspiring only → postcode
    if (_selected.contains('expecting')) {
      Navigator.pushNamed(context, '/due_date');
    } else if (_selected.contains('parent')) {
      Navigator.pushNamed(context, '/child_info');
    } else {
      // aspiring only
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 36),
                    const Text(
                      'Your stage of life',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Connect with others who are at the same stage of life as\nyou. You can choose more than one option.',
                      style: TextStyle(
                        fontSize: 14,
                        color: _kTextGray,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Stage cards — each independently toggleable
                    ..._stages.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _StageCard(
                            item: s,
                            selected: _selected.contains(s.id),
                            onTap: () => _toggle(s.id),
                          ),
                        )),

                    const Spacer(),
                    _OrangeButton(
                      label: 'Continue',
                      enabled: _selected.isNotEmpty,
                      onTap: _continue,
                    ),
                    const SizedBox(height: 28),
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

class _StageCard extends StatelessWidget {
  final _StageItem item;
  final bool selected;
  final VoidCallback onTap;
  const _StageCard(
      {required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: selected ? _kOrange.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _kOrange : _kCardBorder,
            width: selected ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _kOrange.withValues(alpha: selected ? 0.18 : 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _kOrange, width: 1.5),
              ),
              child: Icon(item.icon, color: _kOrange, size: 20),
            ),
            const SizedBox(width: 18),
            // Label
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w500,
                  color: _kTextDark,
                ),
              ),
            ),
            // Checkmark tick when selected
            if (selected)
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: _kOrange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 15,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StageItem {
  final String id;
  final String label;
  final IconData icon;
  const _StageItem({required this.id, required this.label, required this.icon});
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
