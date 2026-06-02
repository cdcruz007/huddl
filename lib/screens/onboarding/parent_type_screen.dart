import 'package:flutter/material.dart';
import '../../theme/huddl_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/onboarding_progress_bar.dart';


class ParentTypeScreen extends StatefulWidget {
  const ParentTypeScreen({super.key});

  @override
  State<ParentTypeScreen> createState() => _ParentTypeScreenState();
}

class _ParentTypeScreenState extends State<ParentTypeScreen>
    with SingleTickerProviderStateMixin {
  String? _selected; // 'Mum' or 'Dad'

  // Entrance animation — same controller pattern as _CarouselPage
  late final AnimationController _ctrl;
  late final Animation<double> _imageScale;
  late final Animation<double> _contentFade;

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

  void _continue() {
    if (_selected == null) return;
    final onboarding = OnboardingDataService();
    onboarding.setParentType(_selected!);
    Navigator.pushNamed(context, '/stage_of_life');
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
              OnboardingProgressBar(step: OnboardingStep.parentType),

              // ── Hero photo — 42% screen height, matches carousel language ──
              Transform.scale(
                scale: _imageScale.value,
                child: SizedBox(
                  height: size.height * 0.42,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Real photo — full bleed, rounded bottom corners
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(28),
                        ),
                        child: Image.asset(
                          'assets/images/onboarding_community.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: HuddlColors.primaryPale,
                            child: Icon(
                              HuddlIcons.usersThree,
                              size: 80,
                              color: HuddlColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                      // Gradient scrim — bottom 50% darkens for text legibility
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
                      // Badge pill — top-left, same style as carousel
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
                            '👋 Welcome to Huddl',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.onboardingOrange,
                            ),
                          ),
                        ),
                      ),
                      // Heading — bottom-left overlay
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: Text(
                          'Every parent\nbelongs here',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
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
                          'I am a...',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Find other parents from your local community.',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: HuddlColors.disabledText,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Mum option
                        _ParentTypeCard(
                          label: 'Mum',
                          subtitle: 'Join as a parent',
                          icon: HuddlIcons.user,
                          accentColor: HuddlColors.onboardingOrange,
                          selected: _selected == 'Mum',
                          onTap: () => setState(() => _selected = 'Mum'),
                        ),
                        const SizedBox(height: 12),
                        // Dad option
                        _ParentTypeCard(
                          label: 'Dad',
                          subtitle: 'Join as a parent',
                          icon: HuddlIcons.user,
                          accentColor: HuddlColors.onboardingOrange,
                          selected: _selected == 'Dad',
                          onTap: () => setState(() => _selected = 'Dad'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Continue button — pinned to bottom, outside scroll
              FadeTransition(
                opacity: _contentFade,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                  child: _OrangeButton(
                    label: 'Continue',
                    enabled: _selected != null,
                    onTap: _continue,
                    color: HuddlColors.onboardingOrange,
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
          color: selected ? accentColor.withValues(alpha: 0.04) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accentColor : HuddlColors.divider,
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
                      color: selected ? accentColor : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: HuddlText.caption(color: HuddlColors.disabledText),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(HuddlIcons.checkCircle, size: 22, color: accentColor),
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
          onPressed: onBack,
        ),
      ),
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
    this.color = HuddlColors.onboardingOrange,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: enabled ? color : HuddlColors.disabled,
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
