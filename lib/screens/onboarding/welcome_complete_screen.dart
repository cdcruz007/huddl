import 'package:flutter/material.dart';
import '../../services/onboarding_data_service.dart';

// Design tokens
const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kSuccessGreen = Color(0xFF4CAF50);
const _kSuccessBg = Color(0xFFE8F5E9);
const _kErrorRed = Color(0xFFE53935);

class WelcomeCompleteScreen extends StatelessWidget {
  const WelcomeCompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groupCount = OnboardingDataService().assignedGroupCount;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // -- Huddl logo centered at top --
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: _HuddlLogo(),
            ),

            const SizedBox(height: 24),

            // -- Title --
            const Text(
              'Welcome to Huddl!',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: _kTextDark,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 20),

            // -- GREEN success popup (before grey text) --
            if (groupCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: _kSuccessBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _kSuccessGreen.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: _kSuccessGreen, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _kSuccessGreen,
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(text: 'You\'ve been added to '),
                              TextSpan(
                                text: '$groupCount',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              TextSpan(
                                text: groupCount == 1
                                    ? ' community group!'
                                    : ' community groups!',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (groupCount > 0) const SizedBox(height: 16),

            // -- Large dynamic group count box (black background) --
            if (groupCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  decoration: BoxDecoration(
                    color: _kTextDark,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$groupCount',
                        style: const TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        groupCount == 1
                            ? 'community group'
                            : 'community groups',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (groupCount > 0) const SizedBox(height: 16),

            // -- Subtitle (grey text AFTER green popup) --
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Before we start, let your neighbours know you!',
                style: TextStyle(
                  fontSize: 14,
                  color: _kTextGray,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // -- Illustration --
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Image.asset(
                  'assets/images/illustrations/man__woman__female__male__person__shapes__shape__layout-1.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/illustrations/man__woman__female__male__person__shapes__shape__layout.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // -- Let's go! button --
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/add_photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Let\'s go!',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Shared Huddl logo --
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
