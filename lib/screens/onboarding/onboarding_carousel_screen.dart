import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';

// Soft salmon/peach matching the supplied screenshots: light warm coral.
// 0xFFFCA878 == HuddlColors.primary (inlined to keep this file self-contained).

class OnboardingCarouselScreen extends StatefulWidget {
  const OnboardingCarouselScreen({super.key});

  @override
  State<OnboardingCarouselScreen> createState() =>
      _OnboardingCarouselScreenState();
}

class _OnboardingCarouselScreenState extends State<OnboardingCarouselScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _PageData(
      illustration:
          'assets/images/illustrations/onboarding_welcome_illustration.png',
      title: 'Welcome to Huddl!',
      subtitle: 'The app for ALL parents,',
      body: 'Connect with parents who are at the same stage of their parenting journey as you.',
    ),
    _PageData(
      illustration:
          'assets/images/illustrations/onboarding_chat_illustration.png',
      title: 'Join local community groups and build trusted networks',
      subtitle: null,
      body: 'Connect with like-minded people. Others are here to share their story.',
    ),
    _PageData(
      illustration:
          'assets/images/illustrations/onboarding_two_people_illustration.png',
      title: 'You are the Mum and Dad next door',
      subtitle: null,
      body: "At Huddl, you're not just another person on a forum filled with strangers.",
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Logo: H icon only (no "huddl" text) ─────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: _HuddlIconOnly(),
            ),

            // ── Carousel pages ───────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _CarouselPage(data: _pages[i]),
              ),
            ),

            // ── Dot indicators — small circles ───────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? HuddlColors.onboardingOrange : HuddlColors.gray300,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),

            const SizedBox(height: 28),

            // ── Get started button ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.onboardingOrange,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Get started!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Already have an account ──────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Already have an account? ',
                  style: TextStyle(fontSize: 14, color: HuddlColors.disabledText),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/login'),
                  child: const Text(
                    'Login',
                    style: TextStyle(
                      fontSize: 14,
                      color: HuddlColors.onboardingOrange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

// ── Single carousel page ──────────────────────────────────────────────────────
class _CarouselPage extends StatelessWidget {
  final _PageData data;
  const _CarouselPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Illustration
          Expanded(
            child: Image.asset(
              data.illustration,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

          const SizedBox(height: 20),

          // Title
          Text(
            data.title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),

          if (data.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              data.subtitle!,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 12),

          // Body
          Text(
            data.body,
            style: const TextStyle(
              fontSize: 14,
              color: HuddlColors.disabledText,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Huddl full logo (H icon + "huddl" wordmark — matches splash screen) ──────
class _HuddlIconOnly extends StatelessWidget {
  const _HuddlIconOnly();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_huddl_splash.png',
      height: 34,
      fit: BoxFit.contain,
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────
class _PageData {
  final String illustration;
  final String title;
  final String? subtitle;
  final String body;
  const _PageData({
    required this.illustration,
    required this.title,
    required this.subtitle,
    required this.body,
  });
}
