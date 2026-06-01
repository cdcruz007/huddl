import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/onboarding_photo_service.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_button.dart';

// ── Data class ────────────────────────────────────────────────────────────────
class _HeroPageData {
  final String heroImageAsset;       // real photo from assets/images/
  final String? overlayStatNumber;   // e.g. "847" — shown large over image
  final String? overlayStatLabel;    // e.g. "parents in Cambridge"
  final String badge;                // small pill top-left e.g. "📍 0.3 km away"
  final String heading;              // 2 lines max, bold, white over image
  final String subheading;           // smaller, below image, nearBlack
  final Color accentColor;           // badge and stat colour
  /// Non-null only for slide 2 when a Pexels network photo was resolved.
  /// When set, _CarouselPage renders CachedNetworkImage instead of Image.asset.
  final OnboardingPhotoResult? locationPhoto;

  const _HeroPageData({
    required this.heroImageAsset,
    this.overlayStatNumber,
    this.overlayStatLabel,
    required this.badge,
    required this.heading,
    required this.subheading,
    required this.accentColor,
    this.locationPhoto,
  });
}

// ── Carousel screen ────────────────────────────────────────────────────────────
class OnboardingCarouselScreen extends StatefulWidget {
  const OnboardingCarouselScreen({super.key});

  @override
  State<OnboardingCarouselScreen> createState() =>
      _OnboardingCarouselScreenState();
}

class _OnboardingCarouselScreenState extends State<OnboardingCarouselScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // ── Location-aware photo state ────────────────────────────────────────────
  OnboardingPhotoResult? _locationPhoto;
  bool _locationPhotoLoading = true;

  @override
  void initState() {
    super.initState();
    _detectLocationPhoto();
  }

  Future<void> _detectLocationPhoto() async {
    try {
      final result = await OnboardingPhotoService().resolve();
      if (mounted) {
        setState(() {
          _locationPhoto = result;
          _locationPhotoLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locationPhotoLoading = false);
    }
  }

  // ── Pages getter — reads instance state, so cannot be static const ──────────
  List<_HeroPageData> get _pages => [
    // Slide 1 — community (unchanged, static asset)
    const _HeroPageData(
      heroImageAsset: 'assets/images/onboarding_community.webp',
      overlayStatNumber: '847',
      overlayStatLabel: 'parents in Cambridge',
      badge: '📍 Cambridge',
      heading: 'Your neighbourhood\nis full of parents like you',
      subheading:
          'Groups, meetups, and conversations — all within walking distance.',
      accentColor: HuddlColors.primary,
    ),

    // Slide 2 — meetup: dynamic based on detected location
    _HeroPageData(
      // Use local asset path when isAsset=true, otherwise fall back to default
      // (Pexels network photos are rendered via locationPhoto field below)
      heroImageAsset: (_locationPhoto?.isAsset == true &&
              !(_locationPhoto?.isDefault ?? true))
          ? _locationPhoto!.path
          : 'assets/images/onboarding_meetup.webp',
      // Pass network photos via locationPhoto — rendered as CachedNetworkImage
      locationPhoto:
          (_locationPhoto?.isAsset == false) ? _locationPhoto : null,
      overlayStatNumber: '23',
      overlayStatLabel: 'meetups this month',
      // Dynamic badge: borough name from GPS, or default text
      badge: (_locationPhoto?.borough != null &&
              !(_locationPhoto?.isDefault ?? true))
          ? '☕ This Sunday · ${_locationPhoto!.borough}'
          : '☕ This Sunday · Victoria Park',
      heading: 'Morning Coffee & Chat\nthis Sunday at 10am',
      subheading:
          '14 parents are going. Drop in, no commitment required.',
      accentColor: HuddlColors.infoBlue,
    ),

    // Slide 3 — market (unchanged, static asset)
    const _HeroPageData(
      heroImageAsset: 'assets/images/onboarding_market.webp',
      overlayStatNumber: '£0',
      overlayStatLabel: 'to join — always free',
      badge: '🛒 Preloved · Near you',
      heading: 'The neighbourhood\nbuy and sell for parents',
      subheading:
          'Buggy for £40. Baby monitor for free. All from parents nearby.',
      accentColor: HuddlColors.yellow,
    ),
  ];

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pushNamed(context, '/name_input');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── PageView — hero image + subheading ───────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: pages.length,
                itemBuilder: (_, i) => _CarouselPage(
                  data: pages[i],
                  slideIndex: i,
                  isLoading: i == 1 && _locationPhotoLoading,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Pill dot indicators — Instagram Stories pattern ───────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pages.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? HuddlColors.primary
                        : HuddlColors.gray300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 20),

            // ── CTA button — label changes on last page ──────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: HuddlButton(
                label: _currentPage < pages.length - 1
                    ? 'Next'
                    : "I'm in — let's go →",
                onPressed: _next,
                variant: HuddlButtonVariant.primary,
                fullWidth: true,
              ),
            ),

            const SizedBox(height: 12),

            // ── Already have an account ──────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: HuddlColors.disabledText,
                  ),
                ),
                Semantics(
                  label: 'already_have_account',
                  button: true,
                  child: GestureDetector(
                    key: const Key('alreadyHaveAccountButton'),
                    onTap: () => Navigator.pushNamed(context, '/login'),
                    child: Text(
                      'Login',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: HuddlColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Single carousel page — stateful for entrance animation ────────────────────
class _CarouselPage extends StatefulWidget {
  final _HeroPageData data;
  final int slideIndex;
  final bool isLoading; // true while location photo is being resolved (slide 2 only)

  const _CarouselPage({
    required this.data,
    required this.slideIndex,
    this.isLoading = false,
  });

  @override
  State<_CarouselPage> createState() => _CarouselPageState();
}

class _CarouselPageState extends State<_CarouselPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _imageScale;
  late final Animation<double> _textOpacity;

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
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Column(
        children: [
          // ── Hero image — fills 55% of screen height ──────────────────
          Transform.scale(
            scale: _imageScale.value,
            child: SizedBox(
              height: size.height * 0.55,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo — shimmer while loading, then local asset or network
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                    child: widget.isLoading
                        // Slide 2 loading: show static fallback immediately —
                        // shimmer + dark scrim looked like a broken black box.
                        // The fallback asset is replaced once GPS resolves.
                        ? Image.asset(
                            'assets/images/onboarding_meetup.webp',
                            fit: BoxFit.cover,
                          )
                        : widget.data.locationPhoto != null
                            // Pexels network photo
                            ? CachedNetworkImage(
                                imageUrl: widget.data.locationPhoto!.path,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Image.asset(
                                  'assets/images/onboarding_meetup.webp',
                                  fit: BoxFit.cover,
                                ),
                                errorWidget: (_, __, ___) => Image.asset(
                                  'assets/images/onboarding_meetup.webp',
                                  fit: BoxFit.cover,
                                ),
                              )
                            // Local asset (default Cambridge or local borough .jpg)
                            : Image.asset(
                                widget.data.heroImageAsset,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: HuddlColors.primaryPale,
                                  child: Icon(
                                    Icons.people,
                                    size: 80,
                                    color: HuddlColors.primary
                                        .withValues(alpha: 0.3),
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
                  // Badge — top-left pill
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
                        widget.data.badge,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: widget.data.accentColor,
                        ),
                      ),
                    ),
                  ),
                  // Large stat — bottom-right overlay
                  if (widget.data.overlayStatNumber != null)
                    Positioned(
                      bottom: 70,
                      right: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            widget.data.overlayStatNumber!,
                            style: GoogleFonts.poppins(
                              fontSize: 48,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                          Text(
                            widget.data.overlayStatLabel!,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Heading — bottom-left overlay
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 100,
                    child: Text(
                      widget.data.heading,
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

          // ── Subheading — below the image with fade-in ─────────────────
          FadeTransition(
            opacity: _textOpacity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Text(
                widget.data.subheading,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: HuddlColors.textSecondary,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
