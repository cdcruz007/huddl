import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/logo_widget.dart';
import '../../services/onboarding_data_service.dart';
import 'login_otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading       = false;
  String? _errorMessage;

  // Country code — defaulting to UK (+44) matching onboarding
  String _countryCode = '+44';

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canLogin =>
      _phoneController.text.trim().length >= 7 &&
      _passwordController.text.length >= 6;

  // ── Generate a 6-digit OTP ────────────────────────────────────────────────
  String _generateOtp() {
    final rng = math.Random();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  Future<void> _handleLogin() async {
    if (!_canLogin) return;
    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;

    // Validate against stored onboarding credentials
    final svc          = OnboardingDataService();
    final storedPhone  = svc.fullPhoneNumber ?? '';
    final storedPass   = svc.password        ?? '';
    final enteredPhone = '$_countryCode${_phoneController.text.trim()}';

    final credentialsValid = storedPhone.isNotEmpty &&
        storedPass.isNotEmpty &&
        enteredPhone == storedPhone &&
        _passwordController.text == storedPass;

    if (credentialsValid) {
      // Generate OTP and navigate to OTP verification screen
      final otp           = _generateOtp();
      final displayPhone  = '$_countryCode ${_phoneController.text.trim()}';

      setState(() => _isLoading = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LoginOtpScreen(
            phoneNumber:  displayPhone,
            generatedOtp: otp,
          ),
        ),
      );
    } else {
      setState(() {
        _isLoading    = false;
        _errorMessage = 'Incorrect phone number or password.\nPlease try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.primary, size: 20),
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

              // ── Logo (real PNG) ──────────────────────────────────────
              const LogoWidget(height: 44),

              const SizedBox(height: 44),

              // ── Title ────────────────────────────────────────────────
              Text(
                'Welcome back!',
                style: AppTextStyles.h1.copyWith(color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 10),

              Text(
                'Log in with your phone number',
                style: AppTextStyles.body1.copyWith(color: AppColors.textMedium),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 44),

              // ── Phone number field ───────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phone number',
                    style: AppTextStyles.inputLabel.copyWith(
                      color: AppColors.textMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Country code picker
                      GestureDetector(
                        onTap: _showCountryPicker,
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFCCCCCC)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                _countryCode,
                                style: AppTextStyles.body1.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down,
                                  size: 18, color: AppColors.textMedium),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: AppTextStyles.body1,
                          decoration: InputDecoration(
                            hintText: '7911 123456',
                            hintStyle: AppTextStyles.inputHint,
                            border: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFCCCCCC)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: AppColors.primary, width: 2),
                            ),
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFCCCCCC)),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ── Password field ───────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Password',
                    style: AppTextStyles.inputLabel.copyWith(
                      color: AppColors.textMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: AppTextStyles.body1,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      hintStyle: AppTextStyles.inputHint,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.textMedium,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      border: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFCCCCCC)),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: AppColors.primary, width: 2),
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFCCCCCC)),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _handleLogin(),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Forgot password ──────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _showForgotPasswordDialog,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Forgot password?',
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── Error message ────────────────────────────────────────
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 16),

              // ── Log in button ────────────────────────────────────────
              _isLoading
                  ? SizedBox(
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : PrimaryButton(
                      text: 'Log in',
                      onPressed: _canLogin ? _handleLogin : null,
                    ),

              const SizedBox(height: 40),

              // ── Sign up link ─────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.textMedium,
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(context, '/onboarding'),
                    child: Text(
                      'Sign up',
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.primary,
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

  // ── Country picker ────────────────────────────────────────────────────────
  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CountryPickerSheet(
        selected: _countryCode,
        onSelected: (code) {
          setState(() => _countryCode = code);
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── Forgot password dialog ────────────────────────────────────────────────
  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Forgot password?'),
        content: Text(
          'To reset your password, please complete the sign-up process again '
          'with your phone number. Your existing account data will be preserved.',
          style: AppTextStyles.body2.copyWith(color: AppColors.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textMedium)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/onboarding');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Go to Sign up',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Country picker bottom sheet ───────────────────────────────────────────────
class _CountryPickerSheet extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  static const _countries = [
    ('+44', '🇬🇧', 'United Kingdom'),
    ('+1',  '🇺🇸', 'United States'),
    ('+1',  '🇨🇦', 'Canada'),
    ('+61', '🇦🇺', 'Australia'),
    ('+64', '🇳🇿', 'New Zealand'),
    ('+353','🇮🇪', 'Ireland'),
    ('+49', '🇩🇪', 'Germany'),
    ('+33', '🇫🇷', 'France'),
    ('+34', '🇪🇸', 'Spain'),
    ('+39', '🇮🇹', 'Italy'),
    ('+31', '🇳🇱', 'Netherlands'),
    ('+46', '🇸🇪', 'Sweden'),
    ('+47', '🇳🇴', 'Norway'),
    ('+45', '🇩🇰', 'Denmark'),
    ('+41', '🇨🇭', 'Switzerland'),
    ('+27', '🇿🇦', 'South Africa'),
    ('+91', '🇮🇳', 'India'),
    ('+65', '🇸🇬', 'Singapore'),
    ('+852','🇭🇰', 'Hong Kong'),
    ('+971','🇦🇪', 'UAE'),
  ];

  const _CountryPickerSheet({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Text('Select country code',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.grey[800])),
        const SizedBox(height: 8),
        const Divider(height: 1),
        SizedBox(
          height: 320,
          child: ListView.builder(
            itemCount: _countries.length,
            itemBuilder: (_, i) {
              final (code, flag, name) = _countries[i];
              final isSelected = code == selected;
              return ListTile(
                leading: Text(flag, style: const TextStyle(fontSize: 24)),
                title: Text(name),
                trailing: Text(code,
                    style: TextStyle(
                        color: Colors.grey[600], fontWeight: FontWeight.w500)),
                selected: isSelected,
                selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                onTap: () => onSelected(code),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
