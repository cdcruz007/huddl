import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/tutorial_service.dart';

/// Full-screen semi-transparent overlay that walks the user through each
/// tab of the app with a brief explanation and CTA highlight.
///
/// Usage:
/// ```dart
/// TutorialOverlay.show(context, onTabSwitch: (index) {
///   mainShellState.switchTab(index);
/// });
/// ```
class TutorialOverlay extends StatefulWidget {
  final void Function(int tabIndex) onTabSwitch;
  final VoidCallback? onComplete;

  const TutorialOverlay({
    super.key,
    required this.onTabSwitch,
    this.onComplete,
  });

  /// Convenience launcher — pushes the overlay as a full-screen route.
  static Future<void> show(
    BuildContext context, {
    required void Function(int tabIndex) onTabSwitch,
    VoidCallback? onComplete,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => TutorialOverlay(
          onTabSwitch: onTabSwitch,
          onComplete: onComplete,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _current = 0;
  late final AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  List<TutorialStep> get _steps => TutorialService.steps;
  TutorialStep get _step => _steps[_current];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _setupAnimations();
    _animCtrl.forward();
    // Switch to first tab
    widget.onTabSwitch(_step.tabIndex);
  }

  void _setupAnimations() {
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _goTo(int index) async {
    await _animCtrl.reverse();
    setState(() => _current = index);
    widget.onTabSwitch(_steps[index].tabIndex);
    _animCtrl.forward();
  }

  Future<void> _next() async {
    if (_current < _steps.length - 1) {
      await _goTo(_current + 1);
    } else {
      await _finish();
    }
  }

  Future<void> _prev() async {
    if (_current > 0) await _goTo(_current - 1);
  }

  Future<void> _finish() async {
    await TutorialService().markCompleted();
    widget.onComplete?.call();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    await TutorialService().markCompleted();
    widget.onComplete?.call();
    if (mounted) Navigator.of(context).pop();
  }

  IconData _iconForName(String name) {
    switch (name) {
      case 'home':
        return Icons.home;
      case 'people':
        return Icons.people;
      case 'groups':
        return Icons.groups;
      case 'storefront':
        return Icons.storefront;
      case 'flight':
        return Icons.flight;
      case 'local_offer':
        return Icons.local_offer;
      case 'person':
        return Icons.person;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPad = mq.padding.bottom + 90; // clear the bottom nav bar

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── Dark overlay ─────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // absorb taps
              child: Container(
                color: Colors.black.withValues(alpha: 0.62),
              ),
            ),
          ),

          // ── Skip button (top-right) ──────────────────────────
          Positioned(
            top: mq.padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: _skip,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3), width: 1),
                ),
                child: Text(
                  'Skip tutorial',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ),

          // ── Step counter (top-left) ──────────────────────────
          Positioned(
            top: mq.padding.top + 16,
            left: 20,
            child: Text(
              '${_current + 1} / ${_steps.length}',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),

          // ── Central card ─────────────────────────────────────
          Positioned(
            left: 20,
            right: 20,
            bottom: bottomPad + 16,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: _buildCard(),
              ),
            ),
          ),

          // ── Progress dots ────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPad - 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _steps.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _current ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _current
                        ? HuddlColors.primary
                        : Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    final isLast = _current == _steps.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Icon badge ──────────────────────────────────
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  HuddlColors.primary.withValues(alpha: 0.12),
                  HuddlColors.primary.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconForName(_step.iconName),
              color: HuddlColors.primary,
              size: 28,
            ),
          ),

          const SizedBox(height: 16),

          // ── Tab name chip ──────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: HuddlColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _step.title,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: HuddlColors.primary,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Headline ───────────────────────────────────
          Text(
            _step.headline,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: HuddlColors.textDark,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 10),

          // ── Body text ──────────────────────────────────
          Text(
            _step.body,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: HuddlColors.textSecondary,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 14),

          // ── CTA highlight ──────────────────────────────
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1), // warm amber tint
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: HuddlColors.accentAmber.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app,
                    color: HuddlColors.accentAmber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _step.ctaLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.accentAmber.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Navigation buttons ─────────────────────────
          Row(
            children: [
              // Back
              if (_current > 0)
                Expanded(
                  child: GestureDetector(
                    onTap: _prev,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: HuddlColors.gray300),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Back',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_current > 0) const SizedBox(width: 12),

              // Next / Get started
              Expanded(
                flex: _current == 0 ? 1 : 1,
                child: GestureDetector(
                  onTap: _next,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: HuddlColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color:
                              HuddlColors.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      isLast ? 'Get started!' : 'Next',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
