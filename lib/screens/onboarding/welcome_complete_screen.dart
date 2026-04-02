import 'package:flutter/material.dart';
import '../../services/onboarding_data_service.dart';

// Design tokens
const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kPeachBg = Color(0xFFFFF3ED); // soft peach from palette

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

            // -- Dynamic group assignment info box --
            if (groupCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                  decoration: BoxDecoration(
                    color: _kPeachBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _kOrange.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Large dynamic number
                      Text(
                        '$groupCount',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: _kTextDark,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        groupCount == 1
                            ? 'community group'
                            : 'community groups',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _kOrange,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'You\'ve been added to your local community groups based on your selections.',
                        style: TextStyle(
                          fontSize: 13,
                          color: _kTextGray,
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

            if (groupCount > 0) const SizedBox(height: 16),

            // -- Subtitle --
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
