import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/onboarding_progress_bar.dart';


class StageOfLifeScreen extends StatefulWidget {
  const StageOfLifeScreen({super.key});

  @override
  State<StageOfLifeScreen> createState() => _StageOfLifeScreenState();
}

class _StageOfLifeScreenState extends State<StageOfLifeScreen>
    with SingleTickerProviderStateMixin {
  // Multi-select: use a Set so toggling works correctly
  final Set<String> _selected = {};

  // Entrance animation — matches parent_type + child_info pattern
  late final AnimationController _ctrl;
  late final Animation<double> _imageScale;
  late final Animation<double> _contentFade;

  static const _stages = [
    _StageItem(id: 'aspiring',  label: 'Trying for a baby',  icon: Icons.favorite_border),
    _StageItem(id: 'expecting', label: 'Expecting a baby',    icon: Icons.child_friendly),
    _StageItem(id: 'parent',    label: 'I have a child',      icon: Icons.face),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _imageScale = Tween<double>(begin: 1.04, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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
    OnboardingDataService().setStagesOfLife(_selected.toList());

    if (_selected.contains('expecting')) {
      Navigator.pushNamed(context, '/due_date');
    } else if (_selected.contains('parent')) {
      Navigator.pushNamed(context, '/child_info');
    } else {
      Navigator.pushNamed(context, '/postcode');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OnboardingAppBar(onBack: () => Navigator.pop(context)),
              OnboardingProgressBar(step: OnboardingStep.stageOfLife),

              // ── Hero photo — 40% height, meetup photo rotates the set ─────
              // parent_type=community, stage_of_life=meetup, due_date=community(offset)
              Transform.scale(
                scale: _imageScale.value,
                child: SizedBox(
                  height: size.height * 0.40,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(28),
                        ),
                        child: Image.asset(
                          'assets/images/onboarding_meetup.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: HuddlColors.primaryPale,
                            child: Icon(
                              Icons.people,
                              size: 80,
                              color: HuddlColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                      // Gradient scrim
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(28),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.62),
                              ],
                              stops: const [0.35, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Badge pill — top-left
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '☕ Parents near you',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.onboardingOrange,
                            ),
                          ),
                        ),
                      ),
                      // Heading overlay — bottom-left
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: Text(
                          'Find your people\nat every stage',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Cards + button — fade in after image settles ──────────────
              Expanded(
                child: FadeTransition(
                  opacity: _contentFade,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your stage of life',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Connect with others at the same stage. You can choose more than one.',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: HuddlColors.disabledText,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Stage cards — independently toggleable
                        ..._stages.map((s) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _StageCard(
                                item: s,
                                selected: _selected.contains(s.id),
                                onTap: () => _toggle(s.id),
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
              ),

              // Continue button — pinned to bottom
              FadeTransition(
                opacity: _contentFade,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                  child: _OrangeButton(
                    label: 'Continue',
                    enabled: _selected.isNotEmpty,
                    onTap: _continue,
                  ),
                ),
              ),
            ],
          ),
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
          color: selected
              ? HuddlColors.onboardingOrange.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? HuddlColors.onboardingOrange : HuddlColors.divider,
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: HuddlColors.onboardingOrange
                    .withValues(alpha: selected ? 0.18 : 0.10),
                shape: BoxShape.circle,
                border:
                    Border.all(color: HuddlColors.onboardingOrange, width: 1.5),
              ),
              child:
                  Icon(item.icon, color: HuddlColors.onboardingOrange, size: 20),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (selected)
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: HuddlColors.onboardingOrange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 15),
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
  const _StageItem(
      {required this.id, required this.label, required this.icon});
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
            icon: const Icon(Icons.chevron_left,
                size: 30, color: HuddlColors.onboardingOrange),
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
            color: enabled
                ? HuddlColors.onboardingOrange
                : HuddlColors.disabled,
            borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color:
                    enabled ? Colors.white : HuddlColors.disabledText)),
      ),
    );
  }
}
