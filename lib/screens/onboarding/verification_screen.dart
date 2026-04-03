import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_header_logo.dart';
import '../../services/otp_service.dart';
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
  String? _errorMessage;
  String? _debugOTP; // Store OTP for testing display
  
  final OTPService _otpService = OTPService();
  final OnboardingDataService _onboardingData = OnboardingDataService();
  
  @override
  void initState() {
    super.initState();
    _startResendTimer();
    // Always show 123456 as the test bypass code (works in all build modes)
    _debugOTP = '123456';
  }
  
  // Load the current OTP for testing purposes
  void _loadDebugOTP() {
    final phoneNumber = _onboardingData.phoneNumber;
    final countryCode = _onboardingData.countryCode ?? '+44';
    if (phoneNumber != null) {
      // Get the stored OTP from service (for debug display)
      final fullNumber = '$countryCode$phoneNumber';
      final otpData = _otpService.getOTPForTesting(fullNumber);
      if (kDebugMode) {
        debugPrint('🔍 Loading OTP for display: $fullNumber');
        debugPrint('🔍 OTP found: $otpData');
      }
      if (otpData != null) {
        setState(() {
          _debugOTP = otpData;
        });
      } else {
        // Fallback: Try without country code
        final otpData2 = _otpService.getOTPForTesting(phoneNumber);
        if (kDebugMode) {
          debugPrint('🔍 Trying without country code: $phoneNumber');
          debugPrint('🔍 OTP found: $otpData2');
        }
        if (otpData2 != null) {
          setState(() {
            _debugOTP = otpData2;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _resendTimer?.cancel();
    super.dispose();
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
    final phoneNumber = _onboardingData.phoneNumber;
    final countryCode = _onboardingData.countryCode ?? '+44';
    
    if (phoneNumber == null) {
      setState(() {
        _errorMessage = 'Phone number not found';
      });
      return;
    }
    
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });
    
    final result = await _otpService.verifyOTP(
      phoneNumber: phoneNumber,
      otp: _codeController.text,
      countryCode: countryCode,
    );
    
    setState(() {
      _isVerifying = false;
    });
    
    if (result.success) {
      // Mark phone as verified
      _onboardingData.setPhoneVerified(true);
      
      // Ensure onboarding data is initialized and loaded
      await _onboardingData.initialize();
      
      // Assign user to default groups based on onboarding data
      final groupService = DefaultGroupService();
      final userId = _onboardingData.fullPhoneNumber ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
      
      final assignedGroups = await groupService.assignUserToDefaultGroups(userId);
      
      // Store the assigned group count and names so the Welcome screen can display them
      _onboardingData.setAssignedGroupCount(assignedGroups.length);
      _onboardingData.setAssignedGroupNames(assignedGroups.map((g) => g.name).toList());
      
      // Navigate to welcome/home screen
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/welcome_complete',
          (route) => false,
        );
      }
    } else {
      setState(() {
        _errorMessage = result.message;
      });
    }
  }
  
  Future<void> _resendOTP() async {
    final phoneNumber = _onboardingData.phoneNumber;
    final countryCode = _onboardingData.countryCode ?? '+44';
    
    if (phoneNumber == null) {
      return;
    }
    
    final success = await _otpService.resendOTP(
      phoneNumber: phoneNumber,
      countryCode: countryCode,
    );
    
    if (success) {
      _startResendTimer();
      _loadDebugOTP(); // Reload the new OTP for testing display
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New code sent to $countryCode$phoneNumber'),
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── AppBar ─────────────────────────────────────────────────
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

                    const SizedBox(height: 48),

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

                    // Continue button
                    GestureDetector(
                      onTap: (_canContinue && !_isVerifying) ? _verifyOTP : null,
                      child: Container(
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                            color: (_canContinue && !_isVerifying)
                                ? kOrange
                                : kBtnDisabled,
                            borderRadius: BorderRadius.circular(12)),
                        alignment: Alignment.center,
                        child: Text(
                          _isVerifying ? 'Verifying...' : 'Continue',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: (_canContinue && !_isVerifying)
                                  ? Colors.white
                                  : kTextGray),
                        ),
                      ),
                    ),

                    // Test bypass code — always shown so testers can proceed
                    if (_debugOTP != null) ...[
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () {
                          setState(() => _codeController.text = _debugOTP!);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: HuddlColors.warningBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: HuddlColors.warning, width: 1),
                          ),
                          child: Text(
                            'Test code: $_debugOTP  (tap to fill)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.warningDark,
                            ),
                          ),
                        ),
                      ),
                    ],
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
