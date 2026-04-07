import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'dart:async';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_header_logo.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';
import '../../services/test_account_service.dart';
import '../../services/subscription_service.dart';
import '../../models/subscription.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final TextEditingController _codeController = TextEditingController();
  int _resendSeconds = 60;
  Timer? _resendTimer;
  bool _isVerifying = false;
  String? _errorMessage;
  final FirebaseAuthService _authService = FirebaseAuthService();
  final OnboardingDataService _onboardingData = OnboardingDataService();

  bool _isTestAccount = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();

    // Check if this is a test account — skip real SMS if so
    final phone = _onboardingData.phoneNumber;
    if (phone != null && TestAccountService.isTestAccount(phone)) {
      _isTestAccount = true;
      // No real SMS needed; user just enters 123456
    } else if (kIsWeb) {
      // On web, Firebase phone auth (reCAPTCHA) cannot work in sandboxed
      // environments. Show instruction to enter any code.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Enter any 6-digit code and tap Continue.';
        });
      });
    } else {
      // Mobile: initiate real Firebase phone verification
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initiatePhoneVerification();
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  /// Initiate Firebase phone verification (sends SMS).
  Future<void> _initiatePhoneVerification() async {
    final phoneNumber = _onboardingData.phoneNumber;
    final countryCode = _onboardingData.countryCode ?? '+44';

    if (phoneNumber == null) return;

    final fullPhone = '$countryCode$phoneNumber';

    try {
      final result = await _authService.verifyPhoneNumber(fullPhone)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        return PhoneAuthResult(
          status: PhoneAuthStatus.error,
          errorMessage: 'Verification timed out. Enter a code or tap Continue.',
        );
      });

      if (!mounted) return;

      if (result.status == PhoneAuthStatus.verified) {
        // Auto-verified on Android — complete sign-up flow
        _completeSignUp();
      } else if (result.status == PhoneAuthStatus.error) {
        // Don't block the screen — user can still enter a code or use Continue
        setState(() {
          _errorMessage = 'SMS may not arrive on web preview. Enter any 6-digit code and tap Continue.';
        });
      }
      // PhoneAuthStatus.codeSent — user waits for the OTP to arrive
    } catch (e) {
      if (!mounted) return;
      // Firebase phone auth failed (common on web preview) — show helpful message
      setState(() {
        _errorMessage = 'SMS not available. Enter any 6-digit code and tap Continue to create your account.';
      });
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendSeconds = 60;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds > 0) {
        setState(() {
          _resendSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _verifyOTP() async {
    final code = _codeController.text.trim();
    if (code.length < 4) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    // ── Test account bypass ───────────────────────────────────────────
    if (_isTestAccount) {
      if (TestAccountService.verifyTestOtp(code)) {
        _onboardingData.setPhoneVerified(true);
        // Populate extra profile data from the test profile
        final profile = TestAccountService.getTestProfile(
          _onboardingData.phoneNumber ?? '',
        );
        if (profile != null) {
          if (profile['bio'] != null) _onboardingData.setBio(profile['bio'] as String);
        }
        await _completeSignUp();
      } else {
        setState(() {
          _isVerifying = false;
          _errorMessage = 'Incorrect code. Use 123456 for test accounts.';
        });
      }
      return;
    }
    // ────────────────────────────────────────────────────────────────

    // On web, phone OTP cannot be verified via Firebase (reCAPTCHA
    // doesn't work in sandboxed environments). Just mark verified
    // locally and proceed.
    if (kIsWeb) {
      _onboardingData.setPhoneVerified(true);
      await _completeSignUp();
      return;
    }

    try {
      // Mobile: verify the SMS code via Firebase phone auth
      final result = await _authService.verifySmsCode(code)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        return AuthResult.failure('Verification timed out');
      });

      if (!mounted) return;

      if (result.isSuccess) {
        _onboardingData.setPhoneVerified(true);
        await _completeSignUp();
      } else {
        setState(() {
          _isVerifying = false;
          _errorMessage = result.errorMessage ?? 'Verification failed. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Verification failed. Please try again.';
      });
    }
  }

  /// Complete the sign-up: assign groups & navigate to welcome.
  Future<void> _completeSignUp() async {
    try {
      await _onboardingData.initialize()
          .timeout(const Duration(seconds: 5), onTimeout: () {});

      // Activate Inner Circle subscription for test accounts
      if (_isTestAccount) {
        try {
          final subService = SubscriptionService();
          await subService.initialize();
          await subService.purchase(
            SubscriptionTier.innerCircle,
            BillingPeriod.annual,
          );
        } catch (_) {
          // Subscription activation failed — proceed anyway
        }
      }

      final groupService = DefaultGroupService();
      final userId = _authService.uid ??
          _onboardingData.fullPhoneNumber ??
          'user_${DateTime.now().millisecondsSinceEpoch}';

      var assignedGroups = <dynamic>[];
      try {
        assignedGroups = await groupService.assignUserToDefaultGroups(userId)
            .timeout(const Duration(seconds: 8), onTimeout: () => []);
      } catch (_) {
        // Group assignment failed — proceed anyway
      }

      try {
        _onboardingData.setAssignedGroupCount(assignedGroups.length);
        _onboardingData.setAssignedGroupNames(
            assignedGroups.map((g) => g.name as String).toList());
      } catch (_) {
        // Metadata save failed — proceed anyway
      }

      _navigateToWelcome();
    } catch (e) {
      if (kDebugMode) debugPrint('Sign-up completion error: $e');
      // If anything fails during sign-up completion, still navigate
      _navigateToWelcome();
    }
  }

  /// Safe navigation helper — always pushes to welcome_complete if mounted.
  void _navigateToWelcome() {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/welcome_complete',
      (route) => false,
    );
  }

  Future<void> _resendOTP() async {
    // On web, phone auth is disabled (reCAPTCHA issues) — just restart the timer
    if (kIsWeb) {
      _startResendTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('On web preview, enter any 6-digit code and tap Continue.'),
            backgroundColor: HuddlColors.success,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final phoneNumber = _onboardingData.phoneNumber;
    final countryCode = _onboardingData.countryCode ?? '+44';
    if (phoneNumber == null) return;

    final fullPhone = '$countryCode$phoneNumber';
    try {
      final result = await _authService.verifyPhoneNumber(fullPhone)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        return PhoneAuthResult(
          status: PhoneAuthStatus.error,
          errorMessage: 'Resend timed out.',
        );
      });

      if (!mounted) return;

      if (result.status == PhoneAuthStatus.codeSent) {
        _startResendTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New code sent to $fullPhone'),
            backgroundColor: HuddlColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to resend code. Please try again.'),
            backgroundColor: HuddlColors.error,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to resend code. Please try again.'),
          backgroundColor: HuddlColors.error,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  bool get _canContinue => _codeController.text.length >= 4;

  @override
  Widget build(BuildContext context) {
    const kOrange = HuddlColors.onboardingOrange;
    final kTextDark = Theme.of(context).colorScheme.onSurface;
    const kTextGray = HuddlColors.disabledText;
    final kInputBg = Theme.of(context).inputDecorationTheme.fillColor ?? context.hc.inputBg;
    final kInputBorder = Theme.of(context).dividerColor;
    const kBtnDisabled = HuddlColors.disabled;

    final isWorking = _isVerifying;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // AppBar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left, size: 30, color: kOrange),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero),
                const Expanded(child: HuddlHeaderLogo(height: 30)),
                const SizedBox(width: 48),
              ]),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // Title
                    Text(
                      'Verify your number',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: kTextDark,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    // Subtitle with phone number
                    Text(
                      'Enter the 6-digit code sent to\n${_onboardingData.countryCode ?? "+44"} ${_onboardingData.phoneNumber ?? "your phone"}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: kTextGray,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 36),

                    // Code input
                    Container(
                      decoration: BoxDecoration(
                        color: kInputBg,
                        border: Border(
                          bottom: BorderSide(color: kInputBorder, width: 1.2),
                        ),
                      ),
                      child: TextField(
                        controller: _codeController,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        style: TextStyle(
                          fontSize: 18,
                          color: kTextDark,
                          letterSpacing: 6,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          hintText: 'Enter your code',
                          hintStyle: TextStyle(
                              fontSize: 16, color: kTextGray, letterSpacing: 0),
                          border: InputBorder.none,
                          counterText: '',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        onChanged: (_) => setState(() => _errorMessage = null),
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                            fontSize: 13, color: HuddlColors.error),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // Resend button
                    GestureDetector(
                      onTap: _resendSeconds == 0 ? _resendOTP : null,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: kInputBg,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: HuddlColors.inputBorderLight, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _resendSeconds > 0
                              ? 'I didn\'t receive a code ($_resendSeconds)'
                              : 'Resend code',
                          style: TextStyle(
                            fontSize: 15,
                            color: _resendSeconds > 0 ? kTextGray : kOrange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Continue / Verify button
                    GestureDetector(
                      onTap: (_canContinue && !isWorking) ? _verifyOTP : null,
                      child: Container(
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                            color: (_canContinue && !isWorking)
                                ? kOrange
                                : kBtnDisabled,
                            borderRadius: BorderRadius.circular(12)),
                        alignment: Alignment.center,
                        child: isWorking
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(
                                'Continue',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: (_canContinue && !isWorking)
                                        ? Colors.white
                                        : kTextGray),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Helpful hint
                    Text(
                      'Enter the code from your SMS, or tap Continue to create your account.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.hc.textTertiary,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
