import 'package:flutter/material.dart';
import '../../services/onboarding_data_service.dart';

const _kOrange = Color(0xFFFCA878);
const _kBlue = Color(0xFF5B8DEF);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kBtnDisabled = Color(0xFFEEEEEE);
const _kCardBorder = Color(0xFFE8E8E8);

class ParentTypeScreen extends StatefulWidget {
  const ParentTypeScreen({super.key});

  @override
  State<ParentTypeScreen> createState() => _ParentTypeScreenState();
}

class _ParentTypeScreenState extends State<ParentTypeScreen> {
  String? _selected; // 'Mum', 'Dad', or 'provider'

  void _continue() {
    if (_selected == null) return;

    final onboarding = OnboardingDataService();

    if (_selected == 'provider') {
      // Service provider path — set parent type and go to provider onboarding
      onboarding.setParentType('provider');
      Navigator.pushNamed(context, '/provider_onboarding');
    } else {
      // Parent path — continue through normal onboarding
      onboarding.setParentType(_selected!);
      Navigator.pushNamed(context, '/stage_of_life');
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 36),
                    // Title
                    const Center(
                      child: Text(
                        'I am a...',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: _kTextDark,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Find other Dads and Mums from your local community.',
                        style: TextStyle(
                          fontSize: 14,
                          color: _kTextGray,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Mum option
                    _ParentTypeCard(
                      label: 'Mum',
                      subtitle: 'Join as a parent',
                      icon: Icons.face,
                      accentColor: _kOrange,
                      selected: _selected == 'Mum',
                      onTap: () => setState(() => _selected = 'Mum'),
                    ),
                    const SizedBox(height: 14),
                    // Dad option
                    _ParentTypeCard(
                      label: 'Dad',
                      subtitle: 'Join as a parent',
                      icon: Icons.face_2,
                      accentColor: _kOrange,
                      selected: _selected == 'Dad',
                      onTap: () => setState(() => _selected = 'Dad'),
                    ),
                    const SizedBox(height: 14),

                    // ── Provide Local Help — HIDDEN for now (will be used later) ──
                    // Commented out to avoid dead-code warnings.  Uncomment and
                    // replace the surrounding comment markers to re-enable.
                    //
                    // Row(children: [
                    //   Expanded(child: Divider(color: _kCardBorder, thickness: 1)),
                    //   Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                    //     child: Text('or', style: TextStyle(fontSize: 13, color: _kTextGray, fontWeight: FontWeight.w500))),
                    //   Expanded(child: Divider(color: _kCardBorder, thickness: 1)),
                    // ]),
                    // const SizedBox(height: 14),
                    // _ParentTypeCard(
                    //   label: 'Provide Local Help',
                    //   subtitle: 'Doula, Nanny, Babysitter, Tutor & more',
                    //   icon: Icons.handshake_outlined,
                    //   accentColor: _kBlue,
                    //   selected: _selected == 'provider',
                    //   onTap: () => setState(() => _selected = 'provider'),
                    // ),

                    // Illustration at bottom
                    const SizedBox(height: 12),
                    Center(
                      child: Image.asset(
                        'assets/images/illustrations/parent_type_illustration.png',
                        height: 140,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox(height: 140),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Continue button pinned to bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: _OrangeButton(
                label: _selected == 'provider' ? 'Set Up My Profile' : 'Continue',
                enabled: _selected != null,
                onTap: _continue,
                color: _selected == 'provider' ? _kBlue : _kOrange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentTypeCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final bool selected;
  final VoidCallback onTap;

  const _ParentTypeCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: selected ? accentColor.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accentColor : _kCardBorder,
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
            // Circle icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: accentColor, width: 1.5),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: selected ? accentColor : _kTextDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: _kTextGray),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 22, color: accentColor),
          ],
        ),
      ),
    );
  }
}

// ── Shared onboarding widgets ─────────────────────────────────────────────────
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
          const SizedBox(width: 48),
        ],
      ),
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
  final Color color;
  const _OrangeButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.color = _kOrange,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: enabled ? color : _kBtnDisabled,
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
