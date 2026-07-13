import 'package:flutter/material.dart';
import '../../theme/huddl_icons.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/onboarding_data_service.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/onboarding_progress_bar.dart';


class ChildInfoScreen extends StatefulWidget {
  const ChildInfoScreen({super.key});

  @override
  State<ChildInfoScreen> createState() => _ChildInfoScreenState();
}

class _ChildInfoScreenState extends State<ChildInfoScreen>
    with SingleTickerProviderStateMixin {
  final List<_ChildEntry> _children = [_ChildEntry()];

  // Entrance animation — same pattern as parent_type_screen
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
    final size       = MediaQuery.of(context).size;
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OnboardingAppBar(onBack: () => Navigator.pop(context)),
              OnboardingProgressBar(step: OnboardingStep.childInfo),

              // ── Hero photo — collapses to zero when the keyboard opens so it
              //    never clips or overlaps the form fields below.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                height: keyboardUp ? 0 : size.height * 0.34,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: Transform.scale(
                  scale: _imageScale.value,
                  child: SizedBox(
                    height: size.height * 0.34,
                    child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Real photo — meetup photo works well here (parents at park)
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
                              HuddlIcons.childCare,
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
                              stops: const [0.3, 1.0],
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
                            '👶 About your family',
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
                          'Meet parents with\nkids the same age',
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
              ), // AnimatedContainer

              // ── Form area — fades in after image settles ──────────────────
              Expanded(
                child: FadeTransition(
                  opacity: _contentFade,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your child',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Date of birth won\'t be shared with other parents.',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: HuddlColors.disabledText,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),

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

                        // Add another child
                        GestureDetector(
                          onTap: _addChild,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: HuddlColors.inputBorderLight),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Add another child',
                                  style: TextStyle(
                                      fontSize: 15, color: HuddlColors.disabledText),
                                ),
                                Icon(HuddlIcons.add,
                                    color: HuddlColors.onboardingOrange, size: 22),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),
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
                    enabled: _canContinue,
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
      decoration: BoxDecoration(
        color: Theme.of(context).inputDecorationTheme.fillColor ?? context.hc.inputBg,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1.2)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: HuddlText.body(color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: HuddlText.body(color: HuddlColors.disabledText),
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
