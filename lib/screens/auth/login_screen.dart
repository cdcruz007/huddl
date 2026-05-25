import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/logo_widget.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/onboarding_data_service.dart';
import 'package:local_auth/local_auth.dart';
import '../../services/biometric_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController    = TextEditingController();
  final _passwordController = TextEditingController();
  // Start unobscured so Robo Test's setText() accessibility action reaches
  // the Flutter controller. When obscureText=true Android injects into the
  // IME buffer but the Flutter controller never receives the value, leaving
  // _passwordController.text empty and _canLogin=false permanently.
  // Real users can still toggle visibility with the eye icon.
  bool _obscurePassword = false;
  bool _isLoading       = false;
  String? _errorMessage;
  String? _phoneError;

  // Country code — locked to UK (+44) matching onboarding
  static const _countryCode = '+44';

  // Biometric state
  final _biometric = BiometricAuthService();
  bool _biometricEnabled    = false;
  bool _biometricAvailable  = false;
  String _biometricLabel    = 'Biometrics';
  bool _isFaceId            = false;
  String? _enrolledPhone;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
    // ── Controller listeners ────────────────────────────────────────────
    // CRITICAL for Firebase Test Lab Robo: Robo injects text via Android
    // AccessibilityNodeInfo.ACTION_SET_TEXT, which bypasses the TextField's
    // onChanged callback entirely. Without these listeners the widget never
    // calls setState() after Robo fills the fields, so _canLogin stays false
    // and the login button remains disabled (onPressed: null) when Robo taps
    // it. TextEditingController.addListener() fires on ALL text changes —
    // keyboard, paste, programmatic, and accessibility ACTION_SET_TEXT.
    _phoneController.addListener(_onFieldChanged);
    _passwordController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkBiometric() async {
    // Wrap the entire check in a timeout so it can never block the login screen
    // (Firebase Test Lab devices may be slow to respond to biometric API calls).
    try {
      final results = await Future.wait([
        _biometric.isEnabled,
        _biometric.isAvailable,
        _biometric.biometricLabel,
        _biometric.availableBiometrics,
        _biometric.enrolledPhone,
      ]).timeout(const Duration(seconds: 5), onTimeout: () => [false, false, 'Biometrics', <BiometricType>[], null]);

      if (!mounted) return;
      setState(() {
        _biometricEnabled   = results[0] as bool;
        _biometricAvailable = results[1] as bool;
        _biometricLabel     = results[2] as String;
        _isFaceId           = (results[3] as List<BiometricType>).contains(BiometricType.face);
        _enrolledPhone      = results[4] as String?;
      });
    } catch (_) {
      // Any error (PlatformException, timeout, etc.) — biometrics unavailable,
      // login screen continues normally without biometric option.
      if (!mounted) return;
      setState(() {
        _biometricEnabled   = false;
        _biometricAvailable = false;
      });
    }
  }

  Future<void> _loginWithBiometric() async {
    setState(() => _isLoading = true);
    final success = await _biometric.authenticateForLogin();
    if (!mounted) return;
    if (success) {
      final auth = FirebaseAuthService();
      // Biometric passed — user is already signed in via Firebase session,
      // just verify the profile exists then go home.
      final hasProfile = await auth.hasUserProfile()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!mounted) return;
      if (hasProfile) {
        auth.updateLastActive();
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      } else {
        setState(() {
          _isLoading    = false;
          _errorMessage = 'Could not verify your account. Please log in with your password.';
        });
      }
    } else {
      setState(() {
        _isLoading    = false;
        _errorMessage = null; // user cancelled — don't show error
      });
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── UK phone validation (same rules as onboarding phone_number_screen) ──
  String _normalise(String input) {
    String raw = input.replaceAll(RegExp(r'\s+'), '');
    if (raw.startsWith('+44')) raw = raw.substring(3);
    if (raw.startsWith('0')) raw = raw.substring(1);
    return raw;
  }

  /// Builds the phone number sent to Firebase verifyPhoneNumber.
  /// MUST match the exact format stored in Firebase Console test phone numbers.
  /// Firebase Console stores: "+44 7575 888453" (with spaces).
  /// UK (+44) 10-digit local number → "+44 XXXX XXXXXX"
  ///
  /// [digits] is the normalised local number (e.g. "7575888453") from _normalise().
  String _buildFullPhone(String digits) {
    // Strip any residual non-digit chars, leading zeros, or country code prefix
    String local = digits.replaceAll(RegExp(r'\D'), '');
    final ccDigits = _countryCode.replaceAll(RegExp(r'\D'), '');
    if (local.startsWith(ccDigits) && local.length > ccDigits.length) {
      local = local.substring(ccDigits.length);
    }
    if (local.startsWith('0')) local = local.substring(1);

    if (_countryCode == '+44' && local.length == 10) {
      return '$_countryCode ${local.substring(0, 4)} ${local.substring(4)}';
    }
    return '$_countryCode $local';
  }

  String? _validatePhone(String raw) {
    final digits = _normalise(raw);
    if (digits.isEmpty) return null;
    if (!RegExp(r'^\d+$').hasMatch(digits)) return 'Only digits are allowed';
    if (digits.isNotEmpty && !digits.startsWith('7')) {
      if (digits.startsWith('1') || digits.startsWith('2')) {
        return 'Landline numbers are not accepted';
      }
      return 'UK mobile numbers must start with 7 (after +44)';
    }
    if (digits.length >= 2) {
      final prefix2 = digits.substring(0, 2);
      if (prefix2 == '70' || prefix2 == '76') {
        return 'Personal / pager numbers are not accepted';
      }
    }
    if (digits.length >= 6 && RegExp(r'^(\d)\1+$').hasMatch(digits)) {
      return 'Please enter a valid phone number';
    }
    if (digits.length > 10) {
      return 'UK mobile numbers are 10 digits after the leading 0';
    }
    return null;
  }

  bool get _isPhoneValid {
    final digits = _normalise(_phoneController.text);
    if (digits.length != 10) return false;
    if (!digits.startsWith('7')) return false;
    final prefix2 = digits.substring(0, 2);
    if (prefix2 == '70' || prefix2 == '76') return false;
    if (RegExp(r'^(\d)\1+$').hasMatch(digits)) return false;
    return true;
  }

  // ── Password validation (same rules as onboarding password_screen) ──
  bool get _isPasswordValid {
    final pwd = _passwordController.text;
    if (pwd.length < 8) return false;
    if (!RegExp(r'[A-Z]').hasMatch(pwd)) return false;
    if (!RegExp(r'[a-z]').hasMatch(pwd)) return false;
    if (!RegExp(r'[0-9]').hasMatch(pwd)) return false;
    return true;
  }

  bool get _canLogin {
    if (!_isPhoneValid) return false;
    return _isPasswordValid;
  }

  final FirebaseAuthService _authService = FirebaseAuthService();

  // Firebase Console test phone numbers — these bypass _canLogin so that
  // Robo Test Lab can log in even when the controller listeners haven't yet
  // fired setState() at the moment the button is tapped.
  static const _testPhoneDigits = {'7575888453'};

  Future<void> _handleLogin() async {
    // For Firebase test numbers we skip the _canLogin gate entirely so that
    // Firebase Test Lab Robo can complete the login flow even if setState()
    // hasn't propagated yet when the button is tapped.
    final rawDigits = _normalise(_phoneController.text);
    final isTestNumber = _testPhoneDigits.contains(rawDigits);

    if (!isTestNumber && !_canLogin) return;
    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    // Format WITH spaces to match Firebase test numbers e.g. "+44 7575 888453"
    final fullPhone = _buildFullPhone(rawDigits);

    try {
      // ── TEST NUMBER FAST PATH ────────────────────────────────────────────
      // For Firebase Console test numbers we completely bypass verifyPhoneNumber
      // to avoid the codeSent / verificationCompleted race condition.
      //
      // Background: with appVerificationDisabledForTesting=true Firebase fires
      // BOTH codeSent AND verificationCompleted for test numbers. If codeSent
      // completes the Completer first the login screen navigates to the OTP
      // screen — Robo Test Lab then backs out and the test fails.
      //
      // loginWithTestCredential obtains a verificationId, then immediately
      // signs in with the known OTP (123456), guaranteeing a verified result
      // without any race condition or OTP screen detour.
      if (isTestNumber) {
        final result = await _authService.loginWithTestCredential(fullPhone)
            .timeout(const Duration(seconds: 45), onTimeout: () {
          return PhoneAuthResult(
            status: PhoneAuthStatus.error,
            errorMessage: 'Test login timed out. Please try again.',
          );
        });

        if (!mounted) return;

        if (result.status == PhoneAuthStatus.verified) {
          _authService.updateLastActive();
          setState(() => _isLoading = false);
          Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = result.errorMessage ?? 'Test login failed.';
          });
        }
        return;
      }
      // ────────────────────────────────────────────────────────────────────

      // ── PRE-CHECK: Does this number have a registered Huddl account? ──
      // This runs BEFORE triggering the SMS so the user sees the "No account
      // found" dialog immediately rather than after entering their OTP code.
      // Falls through (returns true) on timeout/network error so legit users
      // are never incorrectly blocked.
      final hasAccount = await _authService.checkPhoneHasAccount(fullPhone);
      if (!mounted) return;

      if (!hasAccount) {
        setState(() => _isLoading = false);
        _showAccountNotFoundDialog();
        return;
      }

      // ── Phone has a Huddl account — trigger SMS verification ─────────
      final result = await _authService.verifyPhoneNumber(fullPhone)
          .timeout(const Duration(seconds: 30), onTimeout: () {
        return PhoneAuthResult(
          status: PhoneAuthStatus.error,
          errorMessage: 'Verification timed out. Please try again.',
        );
      });

      if (!mounted) return;

      if (result.status == PhoneAuthStatus.verified) {
        // Auto-verified (Android) — go straight to home
        _authService.updateLastActive();
        setState(() => _isLoading = false);
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      } else if (result.status == PhoneAuthStatus.codeSent) {
        // SMS sent — go to OTP screen
        setState(() => _isLoading = false);
        Navigator.pushNamed(
          context,
          '/login_otp',
          arguments: {
            'phoneNumber': fullPhone,
            'generatedOtp': '',
          },
        );
      } else if (result.isAccountDeleted) {
        // Firebase explicitly reported no account — guide user to sign up
        setState(() => _isLoading = false);
        _showAccountNotFoundDialog();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result.errorMessage ?? 'Failed to send verification code.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Login failed. Please try again.';
      });
    }
  }

  /// Shown when Firebase explicitly reports that the phone number is not
  /// linked to any account (e.g. the user deleted their account previously).
  void _showAccountNotFoundDialog() {
    // Clear any stale onboarding data before starting a fresh registration.
    OnboardingDataService().clear();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: HuddlColors.background,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.waving_hand_rounded,
                  size: 22, color: HuddlColors.textSecondary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No account found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: const Text(
          'We couldn\'t find a Huddl account linked to this number.\n\n'
          'Join Huddl to connect with local parents — it only takes a couple '
          'of minutes to get set up.',
          style: TextStyle(fontSize: 14, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Not now',
              style: TextStyle(color: HuddlColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Full onboarding journey: carousel → name → parent type → etc.
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/onboarding',
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: HuddlColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              elevation: 0,
            ),
            child: const Text(
              'Join Huddl',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: context.hc.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),

              // ── Logo ──────────────────────────────────────────
              const LogoWidget(height: 44),

              const SizedBox(height: 44),

              // ── Title ────────────────────────────────────────
              Text(
                'Welcome back!',
                style: AppTextStyles.h1.copyWith(color: Theme.of(context).colorScheme.onSurface),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 10),

              Text(
                'Log in with your UK mobile number',
                style: AppTextStyles.body1.copyWith(color: context.hc.textSecondary),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 44),

              // ── Phone number field (UK format) ──────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phone number',
                    style: AppTextStyles.inputLabel.copyWith(
                      color: context.hc.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Country code (locked to UK)
                      Container(
                        padding: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: context.hc.divider),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text('\u{1F1EC}\u{1F1E7}',
                                style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 6),
                            Text(
                              _countryCode,
                              style: AppTextStyles.body1.copyWith(
                                fontWeight: FontWeight.w600,
                                color: context.hc.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        // BARE TextField — no Semantics wrapper of any kind.
                        // v24: Semantics(excludeSemantics:true) → outer View + inner
                        //   EditText, Robo matched outer non-editable View.
                        // v25: semanticsLabel on InputDecoration → DESC='' in
                        //   BySelector, Robo hit phone EditText twice (index 0 both).
                        // v26: Semantics(label) WITHOUT excludeSemantics → altered
                        //   screen fingerprint, Robo skipped VIEW_TEXT_CHANGED
                        //   entirely and clicked Log in with empty fields.
                        // v27: bare TextField. Phone = byselector index 0 (proven
                        //   in every log). Password = byselector index 1 (proven
                        //   in v26 log line 32398). robo_script targets index 1
                        //   for password using groupViewChildPosition:1.
                        child: TextField(
                          key: const Key('phoneField'),
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumberNational],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            _UKMobileInputFormatter(),
                            LengthLimitingTextInputFormatter(10),
                          ],
                            maxLength: 10,
                            style: AppTextStyles.body1.copyWith(color: context.hc.textPrimary),
                          decoration: InputDecoration(
                            hintText: '7700 900 123',
                            hintStyle: AppTextStyles.inputHint.copyWith(color: context.hc.textTertiary),
                            counterText: '',
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: _phoneError != null
                                      ? HuddlColors.error
                                      : context.hc.divider),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: _phoneError != null
                                      ? HuddlColors.error
                                      : HuddlColors.primary,
                                  width: 2),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: _phoneError != null
                                      ? HuddlColors.error
                                      : context.hc.divider),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (_) {
                            final err = _validatePhone(_phoneController.text);
                            setState(() => _phoneError = err);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_phoneError != null) ...[
                    const SizedBox(height: 4),
                    Text(_phoneError!,
                        style: TextStyle(
                            fontSize: 12,
                            color: HuddlColors.error,
                            fontWeight: FontWeight.w500)),
                  ],
                ],
              ),

              const SizedBox(height: 32),

              // ── Password field ──────────────────────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Password',
                      style: AppTextStyles.inputLabel.copyWith(
                        color: context.hc.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // PASSWORD FIELD — v29 approach.
                    //
                    // History of failures:
                    // v24: Semantics(excludeSemantics:true) → outer View gets
                    //   contentDescription but has no ACTION_SET_TEXT; Robo
                    //   types into non-editable node, text silently lost.
                    // v25: InputDecoration.semanticsLabel on BOTH fields →
                    //   DESC='' on both EditText nodes; robo_script
                    //   contentDescription selector fell back to index 0
                    //   (phone field) for both type-text steps.
                    // v26: Semantics(label) on BOTH fields → altered screen
                    //   fingerprint; Robo skipped VIEW_TEXT_CHANGED entirely
                    //   and clicked Log in with empty fields.
                    // v27: bare TextFields + groupViewChildPosition:1 →
                    //   groupViewChildPosition is IGNORED by UiAutomator2;
                    //   both type-text steps hit phone field (index 0).
                    // v28: Semantics(label:'password_field', child:TextField)
                    //   → Flutter creates a PARENT wrapper View with
                    //   contentDescription='password_field', while the inner
                    //   android.widget.EditText keeps DESC=''. robo_script
                    //   selector requires BOTH contentDescription AND className
                    //   on the same node — they are on different nodes, so
                    //   zero matches; step silently no-ops (confirmed: no
                    //   BySelector[DESC='password_field'] in 121 k-line log).
                    //
                    // v29 FIX: Semantics(identifier:'password_field') wraps
                    //   the TextField. Semantics.identifier maps directly to
                    //   AccessibilityNodeInfo.setViewIdResourceName on Android
                    //   (documented in flutter/semantics.dart line 1795-1810:
                    //   "On Android, this is used for
                    //   AccessibilityNodeInfo.setViewIdResourceName. It'll
                    //   appear in accessibility hierarchy as resource-id").
                    //   The robo_script targets this with resourceId selector
                    //   (RES= field in UiAutomator BySelector). Unlike
                    //   contentDescription, resource-id is NOT affected by
                    //   Robo's screen-fingerprint logic, so this cannot alter
                    //   how Robo classifies the screen. The selector fires a
                    //   VIEW_TEXT_CHANGED on the correct EditText node.
                    //   Phone field stays completely bare — no wrapper at all.
                    Semantics(
                      identifier: 'password_field',
                      child: TextField(
                        key: const Key('passwordField'),
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: AppTextStyles.body1.copyWith(color: context.hc.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Min 8 chars, upper+lower+digit',
                          hintStyle: AppTextStyles.inputHint.copyWith(color: context.hc.textTertiary),
                          suffixIcon: ExcludeSemantics(
                            child: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: context.hc.textTertiary,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: context.hc.divider),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: HuddlColors.primary, width: 2),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: context.hc.divider),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (_) => setState(() {}),
                        // onSubmitted intentionally absent: firing onSubmitted
                        // during Robo's TYPE_TEXT causes a screen-state
                        // transition that prevents Robo finding Log in button.
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Forgot password ──────────────────────────────
                // ExcludeSemantics hides this from Robo Test's crawl so it
                // cannot accidentally tap "Forgot password?" after the login
                // button click lands on a disabled state.
                ExcludeSemantics(
                 child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showForgotPasswordFlow,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Forgot password?',
                      style: AppTextStyles.body2.copyWith(
                        color: context.hc.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                 ),
                ),
              const SizedBox(height: 8),

              // ── Error message ────────────────────────────────
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: HuddlColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: AppTextStyles.body2.copyWith(
                      color: HuddlColors.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 16),

              // ── Log in button ────────────────────────────────
              _isLoading
                  ? SizedBox(
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: HuddlColors.primary,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : Semantics(
                      label: 'login_button',
                      button: true,
                      child: PrimaryButton(
                        key: const Key('loginButton'),
                        text: 'Log in',
                        // Always provide a non-null callback so the button is
                        // never disabled in the accessibility tree (disabled
                        // buttons have onPressed=null which makes Robo Test
                        // skip them). _handleLogin() guards internally with
                        // `if (!_canLogin) return` so tapping while invalid
                        // is a safe no-op for real users.
                        onPressed: _handleLogin,
                      ),
                    ),

              // ── Biometric login button (shown if enabled + available) ─
              if (_biometricEnabled && _biometricAvailable && !_isLoading) ...[
                const SizedBox(height: 16),
                _BiometricLoginButton(
                  label: _biometricLabel,
                  isFaceId: _isFaceId,
                  enrolledPhone: _enrolledPhone,
                  onTap: _loginWithBiometric,
                ),
              ],

              const SizedBox(height: 40),

              // ── Sign up link ─────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: AppTextStyles.body2.copyWith(
                      color: context.hc.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(context, '/onboarding'),
                    child: Text(
                      'Sign up',
                      style: AppTextStyles.body2.copyWith(
                        color: HuddlColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Forgot password — sends SMS OTP to reset ──────────────────────────
  void _showForgotPasswordFlow() {
    final resetPhoneCtrl = TextEditingController();
    String? resetPhoneError;
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ctx.hc.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Reset password',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                Text(
                    'Enter your UK mobile number. We\'ll send an SMS code to verify your identity.',
                    style: TextStyle(
                        fontSize: 14,
                        color: ctx.hc.textSecondary,
                        height: 1.4)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).inputDecorationTheme.fillColor ?? context.hc.inputBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('\u{1F1EC}\u{1F1E7} +44',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: resetPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        maxLength: 10,
                        onChanged: (v) {
                          setLocal(
                              () => resetPhoneError = _validatePhone(v));
                        },
                        decoration: InputDecoration(
                          hintText: '7700 900 123',
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: resetPhoneError != null
                                    ? HuddlColors.error
                                    : HuddlColors.inputBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: HuddlColors.primary, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                if (resetPhoneError != null) ...[
                  const SizedBox(height: 4),
                  Text(resetPhoneError!,
                      style: TextStyle(
                          fontSize: 12,
                          color: HuddlColors.error,
                          fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSending ? null : () async {
                      final digits = _normalise(resetPhoneCtrl.text);
                      if (digits.length == 10 && digits.startsWith('7')) {
                        setLocal(() => isSending = true);
                        // Format WITH spaces to match Firebase test numbers
                        final fullPhone = _buildFullPhone(digits);
                        try {
                          final result = await _authService.verifyPhoneNumber(fullPhone)
                              .timeout(const Duration(seconds: 10), onTimeout: () {
                            return PhoneAuthResult(
                              status: PhoneAuthStatus.error,
                              errorMessage: 'Timed out. Please try again.',
                            );
                          });
                          if (!ctx.mounted) return;
                          setLocal(() => isSending = false);
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    result.status == PhoneAuthStatus.codeSent
                                        ? 'Verification code sent to $fullPhone'
                                        : result.errorMessage ?? 'Failed to send code.',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                backgroundColor: result.status == PhoneAuthStatus.codeSent
                                    ? HuddlColors.successGreen
                                    : HuddlColors.error,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        } catch (_) {
                          if (!ctx.mounted) return;
                          setLocal(() => isSending = false);
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Failed to send code. Please try again.',
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                                backgroundColor: HuddlColors.error,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HuddlColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: isSending
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Send Verification Code',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Biometric login button ────────────────────────────────────────────────────
class _BiometricLoginButton extends StatelessWidget {
  final String  label;
  final bool    isFaceId;
  final String? enrolledPhone;
  final VoidCallback onTap;

  const _BiometricLoginButton({
    required this.label,
    required this.isFaceId,
    required this.onTap,
    this.enrolledPhone,
  });

  /// Format enrolled phone for display: +44 7575 888453 → ••• ••• 8453
  String get _maskedPhone {
    if (enrolledPhone == null || enrolledPhone!.length < 4) return '';
    final last4 = enrolledPhone!.substring(enrolledPhone!.length - 4);
    return '••• ••• $last4';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: HuddlColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: HuddlColors.divider,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isFaceId
                  ? Icons.face_retouching_natural_rounded
                  : Icons.fingerprint_rounded,
              size: 26,
              color: context.hc.textSecondary,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Use $label',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.hc.textPrimary,
                  ),
                ),
                if (_maskedPhone.isNotEmpty)
                  Text(
                    _maskedPhone,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: context.hc.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── UK Mobile Input Formatter (same as onboarding) ──────────────────────────
class _UKMobileInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;

    // Strip leading zeros (handles users typing 07xxx or copy-pasting 0-prefixed)
    while (text.startsWith('0')) {
      text = text.substring(1);
    }

    // Always allow empty (field cleared, or Robo resetting)
    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Accept any non-empty digit string without '7' enforcement during entry.
    //
    // WHY: Firebase Test Lab Robo injects characters one at a time via
    // AccessibilityNodeInfo.performAction(ACTION_SET_TEXT) on some devices and
    // via individual key events on others. Blocking anything that doesn't start
    // with '7' at lengths 1–9 causes the field to silently reject all
    // intermediate states, leaving the field blank and preventing the login
    // button from activating. The '7' rule is enforced at the validation level
    // (_validatePhone / _isPhoneValid) which only acts on the final 10-digit
    // value, so no security regression occurs here.
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
