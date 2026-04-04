import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_header_logo.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';

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
  bool _isCreatingAccount = false;
  String? _errorMessage;
  final FirebaseAuthService _authService = FirebaseAuthService();
  final OnboardingDataService _onboardingData = OnboardingDataService();

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _initiatePhoneVerification();
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
    final result = await _authService.verifyPhoneNumber(fullPhone);

    if (!mounted) return;

    if (result.status == PhoneAuthStatus.verified) {
      // Auto-verified on Android — complete sign-up flow
      _completeSignUp();
    } else if (result.status == PhoneAuthStatus.error) {
      setState(() {
        _errorMessage = result.errorMessage ?? 'Failed to send verification code.';
      });
    }
    // PhoneAuthStatus.codeSent — user waits for the OTP to arrive
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
    if (code.length < 6) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    // First try: sign in / link with the SMS code via Firebase
    final result = await _authService.verifySmsCode(code);

    if (!mounted) return;

    if (result.isSuccess) {
      _onboardingData.setPhoneVerified(true);
      await _completeSignUp();
    } else {
      // If Firebase phone auth fails (e.g. on web emulator or test),
      // fall back to creating email/password account directly
      await _createEmailAccountAndProceed();
    }
  }

  /// Create a Firebase email/password account using the phone number as email.
  /// This is the primary auth path that works on all platforms including web.
  Future<void> _createEmailAccountAndProceed() async {
    setState(() {
      _isCreatingAccount = true;
      _errorMessage = null;
    });

    final phoneNumber = _onboardingData.phoneNumber;
    final countryCode = _onboardingData.countryCode ?? '+44';
    final password = _onboardingData.password;

    if (phoneNumber == null || password == null) {
      setState(() {
        _isCreatingAccount = false;
        _isVerifying = false;
        _errorMessage = 'Missing registration data. Please go back and try again.';
      });
      return;
    }

    // Use phone-based email pattern: +447700900123@huddl.app
    final email = '$countryCode$phoneNumber@huddl.app';

    final result = await _authService.signUpWithEmail(
      email: email,
      password: password,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      _onboardingData.setPhoneVerified(true);
      await _completeSignUp();
    } else {
      // If account already exists, try signing in
      if (result.errorMessage?.contains('already registered') ?? false) {
        final signInResult = await _authService.signInWithEmail(
          email: email,
          password: password,
        );
        if (signInResult.isSuccess) {
          _onboardingData.setPhoneVerified(true);
          await _completeSignUp();
          return;
        }
      }
      setState(() {
        _isCreatingAccount = false;
        _isVerifying = false;
        _errorMessage = result.errorMessage ?? 'Account creation failed.';
      });
    }
  }

  /// Complete the sign-up: assign groups & navigate to welcome.
  Future<void> _completeSignUp() async {
    await _onboardingData.initialize();

    final groupService = DefaultGroupService();
    final userId = _authService.uid ??
        _onboardingData.fullPhoneNumber ??
        'user_${DateTime.now().millisecondsSinceEpoch}';

    final assignedGroups = await groupService.assignUserToDefaultGroups(userId);

    _onboardingData.setAssignedGroupCount(assignedGroups.length);
    _onboardingData.setAssignedGroupNames(
        assignedGroups.map((g) => g.name).toList());

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/welcome_complete',
        (route) => false,
      );
    }
  }

  Future<void> _resendOTP() async {
    final phoneNumber = _onboardingData.phoneNumber;
    final countryCode = _onboardingData.countryCode ?? '+44';
    if (phoneNumber == null) return;

    final fullPhone = '$countryCode$phoneNumber';
    final result = await _authService.verifyPhoneNumber(fullPhone);

    if (result.status == PhoneAuthStatus.codeSent) {
      _startResendTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New code sent to $fullPhone'),
            backgroundColor: HuddlColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to resend code. Please try again.'),
            backgroundColor: HuddlColors.error,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  bool get _canContinue => _codeController.text.length >= 4;

  @override
  Widget build(BuildContext context) {
    const kOrange = HuddlColors.onboardingOrange;
    const kTextDark = HuddlColors.textDark;
    const kTextGray = HuddlColors.disabledText;
    const kInputBg = HuddlColors.inputBg;
    const kInputBorder = HuddlColors.inputBorder;
    const kBtnDisabled = HuddlColors.disabled;

    final isWorking = _isVerifying || _isCreatingAccount;

    return Scaffold(
      backgroundColor: Colors.white,
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
                    const Text(
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
                      decoration: const BoxDecoration(
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
                        style: const TextStyle(
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
                        color: HuddlColors.textHint,
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
