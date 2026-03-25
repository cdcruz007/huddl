import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

// Design tokens matching source project AppColors
const _kPrimary = Color(0xFFFF7043); // primary brand orange
const _kTextPrimary = Color(0xFF2C2C2C); // dark text
const _kTextSecondary = Color(0xFF666666); // secondary text

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Logo at the top
              Align(
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  'assets/images/logo_huddl.png',
                  height: 40,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Orange illustration circle
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: _kPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(110),
                      ),
                      child: const Icon(
                        Icons.people_rounded,
                        size: 120,
                        color: _kPrimary,
                      ),
                    ),
                    const SizedBox(height: 56),
                    // Hero headline
                    const Text(
                      'Welcome to\nHuddl',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 40,
                        color: _kTextPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Subheadline
                    const Text(
                      'Connect with local parents\nand discover events near you',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: _kTextSecondary,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              // Bottom CTA section
              Column(
                children: [
                  // Primary orange button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const OnboardingScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Secondary text button
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Already have an account? Log in',
                      style: TextStyle(
                        color: _kPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
