import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/tutorial_service.dart';
import '../../widgets/huddl_character.dart';

// =============================================================================
// TUTORIAL OVERLAY v2 — cinematic full-screen walkthrough
//
// Design philosophy:
//   Each step owns the entire screen. No underlying app visible.
//   Emotional headline + one sentence body + specific CTA.
//   Step-specific background colour — each screen feels like a distinct moment.
//   HuddlCharacter illustration centred above the text.
//   Progress dots at top. CTA at bottom. Swipe left/right to navigate.
//   Final step: full orange screen, white CTA — same energy as the splash.
//
// Reference: Duolingo (interactive moments), Spotify (full-screen visual),
//   Airbnb (emotional copy that sells feeling, not features).
// =============================================================================

class TutorialOverlay extends StatefulWidget {
  final void Function(int tabIndex) onTabSwitch;
  final VoidCallback? onComplete;

  const TutorialOverlay({
    super.key,
    required this.onTabSwitch,
    this.onComplete,
  });

  /// Convenience launcher — pushes as an opaque full-screen route.
  /// opaque: true so the underlying app is not rendered during the tutorial.
  /// onTabSwitch still fires per step so the correct tab is active on exit.
  static Future<void> show(
    BuildContext context, {
    required void Function(int tabIndex) onTabSwitch,
    VoidCallback? onComplete,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => TutorialOverlay(
          onTabSwitch: onTabSwitch,
          onComplete: onComplete,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with TickerProviderStateMixin {

  int _current = 0;
  bool _animating = false;

  // ── Per-step entrance animations ─────────────────────────────────────────
  late final AnimationController _enterCtrl;
  late final Animation<double>   _enterFade;
  late final Animation<double>   _enterScale;
  late final Animation<Offset>   _enterSlide;

  // ── CTA button breathing scale ────────────────────────────────────────────
  late final AnimationController _ctaCtrl;
  late final Animation<double>   _ctaScale;

  // ── Background colour tween ───────────────────────────────────────────────
  late final AnimationController _bgCtrl;
  Color _fromBg = Colors.white;
  Color _toBg   = Colors.white;

  List<TutorialStep> get _steps => TutorialService.steps;
  TutorialStep get _step => _steps[_current];
  bool get _isLast => _current == _steps.length - 1;

  // ── Background colour per step ────────────────────────────────────────────
  Color _bgForStep(int index) {
    final step = _steps[index];
    if (step.stepKey == 'ready')  return Color(step.accentColor); // full orange
    if (step.stepKey == 'market') return Colors.white;
    return Colors.white;
  }

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // ── Entrance animation — 500ms ────────────────────────────────────────
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _enterFade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _enterScale = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic),
    );
    _enterSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));

    // ── CTA pulse — gentle breathing, 1600ms ─────────────────────────────
    _ctaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _ctaScale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _ctaCtrl, curve: Curves.easeInOut),
    );

    // ── Background colour cross-fade — 400ms ─────────────────────────────
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _toBg   = _bgForStep(0);
    _fromBg = _toBg;
    _enterCtrl.forward();

    // Defer first tab-switch past build to avoid setState-during-build crash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTabSwitch(_step.tabIndex);
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _ctaCtrl.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _goTo(int index) async {
    if (_animating) return;
    _animating = true;
    HapticFeedback.lightImpact();

    // Start background colour transition
    _fromBg = _bgForStep(_current);
    _toBg   = _bgForStep(index);
    _bgCtrl.reset();
    _bgCtrl.forward();

    // Fade + slide content out
    await _enterCtrl.reverse();

    setState(() => _current = index);
    widget.onTabSwitch(_steps[index].tabIndex);

    // Flip status bar icons on the orange final step
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: _steps[index].stepKey == 'ready'
          ? Brightness.light  // white icons on orange
          : Brightness.dark,  // dark icons on white/cream
    ));

    // Fade + slide content back in
    await _enterCtrl.forward();
    _animating = false;
  }

  Future<void> _next() async {
    if (_isLast) {
      await _finish();
      return;
    }
    await _goTo(_current + 1);
  }

  Future<void> _prev() async {
    if (_current > 0) await _goTo(_current - 1);
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await TutorialService().markCompleted();
    widget.onComplete?.call();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    await TutorialService().markCompleted();
    widget.onComplete?.call();
    if (mounted) Navigator.of(context).pop();
  }

  // ── Map illustrationMood string → HuddlMood enum ─────────────────────────

  HuddlMood _moodForStep(String mood) {
    switch (mood) {
      case 'waving':      return HuddlMood.waving;
      case 'community':   return HuddlMood.neutral;
      case 'exploring':   return HuddlMood.curious;
      case 'market':      return HuddlMood.supportive;
      case 'celebrating': return HuddlMood.celebrating;
      default:            return HuddlMood.neutral;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size     = MediaQuery.of(context).size;
    final step     = _step;
    final accent   = Color(step.accentColor);
    final onOrange = step.stepKey == 'ready';

    final textColor    = onOrange ? Colors.white : HuddlColors.nearBlack;
    final subtextColor = onOrange
        ? Colors.white.withValues(alpha: 0.80)
        : HuddlColors.textSecondary;

    return AnimatedBuilder(
      animation: _bgCtrl,
      builder: (_, child) {
        final bg = Color.lerp(_fromBg, _toBg, _bgCtrl.value) ?? _toBg;
        return Scaffold(backgroundColor: bg, body: child);
      },
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) { _next(); }
          else if (v > 200) { _prev(); }
        },
        child: SafeArea(
          child: FadeTransition(
            opacity: _enterFade,
            child: SlideTransition(
              position: _enterSlide,
              child: Column(
                children: [

                  // ── Top row: progress dots + skip ──────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Row(
                      children: [
                        // Progress dots — active pill expands to 24px wide
                        Row(
                          children: List.generate(_steps.length, (i) {
                            final active = i == _current;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.only(right: 6),
                              width:  active ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: active
                                    ? accent
                                    : (onOrange
                                        ? Colors.white.withValues(alpha: 0.40)
                                        : HuddlColors.gray300),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          }),
                        ),
                        const Spacer(),
                        // Skip — hidden on final step
                        if (!_isLast)
                          GestureDetector(
                            onTap: _skip,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                'Skip',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: onOrange
                                      ? Colors.white.withValues(alpha: 0.70)
                                      : HuddlColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── Illustration — upper half of screen ────────────────
                  Expanded(
                    flex: 5,
                    child: ScaleTransition(
                      scale: _enterScale,
                      child: Center(
                        child: HuddlCharacter(
                          mood: _moodForStep(step.illustrationMood),
                          size: size.height * 0.28,
                        ),
                      ),
                    ),
                  ),

                  // ── Text content — lower half ──────────────────────────
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [

                          // Step pill — e.g. "2 of 5"
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: accent.withValues(
                                  alpha: onOrange ? 0.25 : 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_current + 1} of ${_steps.length}',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: onOrange ? Colors.white : accent,
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Headline — the emotional hook, max 7 words
                          Text(
                            step.headline,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                              height: 1.2,
                              letterSpacing: -0.3,
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Body — one sentence maximum
                          Text(
                            step.body,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: subtextColor,
                              height: 1.55,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── CTA button ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: ScaleTransition(
                      scale: _ctaScale,
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: onOrange ? Colors.white : accent,
                            foregroundColor: onOrange ? accent : Colors.white,
                            elevation: onOrange ? 0 : 2,
                            shadowColor: accent.withValues(alpha: 0.30),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            step.ctaLabel,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Back link — step 2+ only, hidden on final step ─────
                  if (_current > 0 && !_isLast)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: GestureDetector(
                        onTap: _prev,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '← Back',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: onOrange
                                  ? Colors.white.withValues(alpha: 0.65)
                                  : HuddlColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 20),

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
