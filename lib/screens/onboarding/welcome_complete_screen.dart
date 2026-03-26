import 'package:flutter/material.dart';

// Design tokens from screenshot 14
const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);

class WelcomeCompleteScreen extends StatelessWidget {
  const WelcomeCompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Huddl logo centered at top ─────────────────────────────
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: _HuddlLogo(),
            ),

            const SizedBox(height: 24),

            // ── Title ──────────────────────────────────────────────────
            const Text(
              'Welcome to Huddl!',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: _kTextDark,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 10),

            // ── Subtitle ───────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Before we start, let your neighbors know you!',
                style: TextStyle(
                  fontSize: 14,
                  color: _kTextGray,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // ── Illustration: community group celebrating together ─────
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

            // ── Let's go! button ───────────────────────────────────────
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

// ── Shared Huddl logo ─────────────────────────────────────────────────────────
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
