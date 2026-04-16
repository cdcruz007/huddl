import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'dart:async';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_header_logo.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';
import '../../widgets/onboarding_progress_bar.dart';


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

  // Separate state for the "sending code" phase vs "verifying code" phase
  bool _isSendingCode = false;
  String? _errorMessage;
  String? _infoMessage;

  final FirebaseAuthService _authService = FirebaseAuthService();
  final OnboardingDataService _onboardingData = OnboardingDataService();

  @override
  void initState() {
    super.initState();
    _startResendTimer();

    if (kIsWeb) {
      // On web, Firebase phone auth (reCAPTCHA) cannot work in sandboxed
      // environments. Show instruction to enter any code.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _infoMessage = 'On web preview, enter any 6-digit code and tap Continue.';
        });
      });
    } else {
      // Mobile: show "sending" state immediately, then initiate Firebase
      setState(() {
        _isSendingCode = true;
        _infoMessage = 'Sending code to your phone…';
      });
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

  /// Build the phone number string sent to Firebase verifyPhoneNumber.
  ///
  /// Firebase Console always reformats numbers with spaces regardless of how
  /// they are entered — e.g. typing "+447575888452" is saved as "+44 7575 888452".
  /// Test number matching is an exact string comparison, so the app must send
  /// the number in the same spaced format Firebase stores it.
  ///
  /// UK (+44) 10-digit numbers are formatted as: +44 XXXX XXXXXX
  ///   stored "7575888452"  →  "+44 7575 888452"
  ///   stored "07575888452" →  "+44 7575 888452"  (leading 0 stripped)
  String _buildFullPhoneNumber() {
    final rawDigits = _onboardingData.phoneNumber ?? '';
    final cc = _onboardingData.countryCode ?? '+44';
    final digits = rawDigits.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return cc;
    // Strip leading zero if present (e.g. "07575888452" → "7575888452")
    final local = digits.startsWith('0') ? digits.substring(1) : digits;
    // UK: format as "+44 XXXX XXXXXX" — exactly how Firebase Console stores it
    if (cc == '+44' && local.length == 10) {
      return '$cc ${local.substring(0, 4)} ${local.substring(4)}';
    }
    // Other countries: single space between code and number
    return '$cc $local';
  }

  /// Display string for the UI subtitle — same as _buildFullPhoneNumber()
  /// since both now use the spaced format.
  String _displayPhone() => _buildFullPhoneNumber();

  /// Initiate Firebase phone verification (sends SMS).
  Future<void> _initiatePhoneVerification() async {
    if (!mounted) return;

    setState(() {
      _isSendingCode = true;
      _errorMessage = null;
      _infoMessage = 'Sending code to your phone…';
    });

    final phoneNumber = _onboardingData.phoneNumber;
    if (phoneNumber == null || phoneNumber.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isSendingCode = false;
        _errorMessage = 'No phone number found. Please go back and enter your number.';
      });
      return;
    }

    final fullPhone = _buildFullPhoneNumber();
    if (kDebugMode) debugPrint('[VerificationScreen] Initiating verification for: $fullPhone');

    try {
      // Re-run configure() immediately before the call to guarantee
      // appVerificationDisabledForTesting is active on this platform thread.
      await _authService.configure();

      final result = await _authService.verifyPhoneNumber(fullPhone)
          .timeout(const Duration(seconds: 45), onTimeout: () {
        return PhoneAuthResult(
          status: PhoneAuthStatus.codeSent,
          verificationId: '',
          errorMessage: 'SMS may be delayed. Enter your code when it arrives.',
        );
      });

      if (!mounted) return;

      setState(() => _isSendingCode = false);

      if (result.status == PhoneAuthStatus.verified) {
        // Auto-verified on Android — complete sign-up flow
        _completeSignUp();
      } else if (result.status == PhoneAuthStatus.codeSent) {
        // SMS sent — show helpful message
        setState(() {
          _infoMessage = result.errorMessage ?? 'Code sent! Check your SMS.';
          _errorMessage = null;
        });
      } else if (result.status == PhoneAuthStatus.error) {
        setState(() {
          _errorMessage = result.errorMessage ??
              'Could not send SMS. Tap "Retry" to try again.';
          _infoMessage = null;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VerificationScreen] _initiatePhoneVerification error: $e');
      if (!mounted) return;
      setState(() {
        _isSendingCode = false;
        _errorMessage = 'Could not send verification code. Tap "Retry" to try again.';
        _infoMessage = null;
      });
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    if (mounted) {
      setState(() {
        _resendSeconds = 60;
      });
    }

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
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

    // Dismiss keyboard before processing
    FocusScope.of(context).unfocus();

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

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
          .timeout(const Duration(seconds: 15), onTimeout: () {
        return AuthResult.failure('Verification timed out. Please try again.');
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

    _startResendTimer();
    await _initiatePhoneVerification();
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

    final displayPhone = _displayPhone();

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

            OnboardingProgressBar(step: OnboardingStep.verification),

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
                      'Enter the 6-digit code sent to\n$displayPhone',  // e.g. +44 7575888452
                      style: const TextStyle(
                        fontSize: 14,
                        color: kTextGray,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 24),

                    // ── "Sending code" loading indicator ─────────────────
                    if (_isSendingCode) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kOrange,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _infoMessage ?? 'Sending code…',
                            style: const TextStyle(
                              fontSize: 14,
                              color: kTextGray,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ] else if (_infoMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _infoMessage!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: HuddlColors.success,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      const SizedBox(height: 12),
                    ],

                    // Code input (shown even while sending so user can
                    // start typing as soon as SMS arrives)
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
                        onChanged: (_) => setState(() {
                          _errorMessage = null;
                        }),
                      ),
                    ),

                    // Error message
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                  fontSize: 13, color: HuddlColors.error),
                            ),
                          ),
                          // Retry button inline with error
                          if (!_isSendingCode)
                            TextButton(
                              onPressed: _initiatePhoneVerification,
                              style: TextButton.styleFrom(
                                foregroundColor: kOrange,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Retry',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Resend button
                    GestureDetector(
                      onTap: (_resendSeconds == 0 && !_isSendingCode)
                          ? _resendOTP
                          : null,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: kInputBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: HuddlColors.inputBorderLight, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _resendSeconds > 0
                              ? 'I didn\'t receive a code ($_resendSeconds)'
                              : 'Resend code',
                          style: TextStyle(
                            fontSize: 15,
                            color: (_resendSeconds > 0 || _isSendingCode)
                                ? kTextGray
                                : kOrange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Continue / Verify button
                    GestureDetector(
                      onTap: (_canContinue && !isWorking && !_isSendingCode)
                          ? _verifyOTP
                          : null,
                      child: Container(
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                            color: (_canContinue && !isWorking && !_isSendingCode)
                                ? kOrange
                                : kBtnDisabled,
                            borderRadius: BorderRadius.circular(12)),
                        alignment: Alignment.center,
                        child: isWorking
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(
                                'Continue',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: (_canContinue && !isWorking && !_isSendingCode)
                                        ? Colors.white
                                        : kTextGray),
                              ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Helpful hint
                    Text(
                      'Enter the 6-digit code from your SMS message.',
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
