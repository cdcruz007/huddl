import 'package:flutter/material.dart';
import '../../theme/huddl_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/onboarding_progress_bar.dart';


class DueDateScreen extends StatefulWidget {
  const DueDateScreen({super.key});

  @override
  State<DueDateScreen> createState() => _DueDateScreenState();
}

class _DueDateScreenState extends State<DueDateScreen>
    with SingleTickerProviderStateMixin {
  late FixedExtentScrollController _yearCtrl;

  final _now = DateTime.now();
  late int _selYear;

  // Show current year through 4 years ahead
  late List<int> _years;

  // Entrance animation — matches carousel + parent_type pattern
  late final AnimationController _ctrl;
  late final Animation<double> _imageScale;
  late final Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();
    _years = List.generate(5, (i) => _now.year + i);
    _selYear = _now.year + 1;
    _yearCtrl = FixedExtentScrollController(
      initialItem: _years.indexOf(_selYear),
    );

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
    _yearCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _continue() {
    final service = OnboardingDataService();
    service.setDueDate('$_selYear');

    if (service.stagesOfLife.contains('parent')) {
      Navigator.pushNamed(context, '/child_info');
    } else {
      Navigator.pushNamed(context, '/postcode');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OnboardingAppBar(onBack: () => Navigator.pop(context)),
              OnboardingProgressBar(step: OnboardingStep.dueDate),

              // ── Hero photo — 38% height, warm community image ─────────────
              // Slightly smaller than parent_type (42%) since picker needs space
              Transform.scale(
                scale: _imageScale.value,
                child: SizedBox(
                  height: size.height * 0.38,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(28),
                        ),
                        child: Image.asset(
                          'assets/images/onboarding_community.jpg',
                          fit: BoxFit.cover,
                          // Offset to show the warmer, more intimate part of photo
                          alignment: const Alignment(0.0, 0.3),
                          errorBuilder: (_, __, ___) => Container(
                            color: HuddlColors.primaryPale,
                            child: Icon(
                              HuddlIcons.childFriendly,
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
                                Colors.black.withValues(alpha: 0.60),
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
                            '🤰 Expecting a baby',
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
                          'Connect with parents\nat the same stage',
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

              // ── Picker + content — fades in after image settles ───────────
              Expanded(
                child: FadeTransition(
                  opacity: _contentFade,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Column(
                      children: [
                        Text(
                          'When is your baby due?',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Helps us connect you with other expecting parents nearby.',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: HuddlColors.disabledText,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),

                        // ── Year drum picker ──────────────────────────
                        Center(
                          child: SizedBox(
                            width: 160,
                            height: 180,
                            child: _DrumPicker(
                              controller: _yearCtrl,
                              items: _years.map((y) => y.toString()).toList(),
                              onSelected: (i) =>
                                  setState(() => _selYear = _years[i]),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ── Selected year display ─────────────────────
                        Text(
                          'Due $_selYear',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.onboardingOrange,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Continue button — pinned to bottom ────────────────────────
              FadeTransition(
                opacity: _contentFade,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                  child: _OrangeButton(
                    label: 'Continue',
                    enabled: true,
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
            border: Border.all(
              color: HuddlColors.onboardingOrange.withValues(alpha: 0.30),
              width: 1.5,
            ),
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
                    color: selected
                        ? HuddlColors.onboardingOrange
                        : HuddlColors.disabledText,
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
