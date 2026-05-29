import 'package:flutter/material.dart';
import '../../widgets/common/huddl_logo.dart';
import 'package:local_auth/local_auth.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_character.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/firebase_auth_service.dart';
import '../../constants/app_text_styles.dart';

/// Shown on app launch when the user has biometric login enabled.
/// The user must authenticate with Face ID / fingerprint (or device PIN)
/// before the app home screen is revealed.
///
/// If they tap "Use password instead" the app routes to /login so they can
/// authenticate manually.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with WidgetsBindingObserver {
  final _biometric = BiometricAuthService();
  final _auth      = FirebaseAuthService();

  bool _isAuthenticating = false;
  bool _hasFailed        = false;
  String _biometricLabel = 'Biometrics';
  bool _isFaceId         = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBiometricInfo();
    // Auto-trigger prompt shortly after screen appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), _authenticate);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-trigger biometric prompt when app resumes from background
    if (state == AppLifecycleState.resumed && !_isAuthenticating) {
      Future.delayed(const Duration(milliseconds: 300), _authenticate);
    }
  }

  Future<void> _loadBiometricInfo() async {
    final label = await _biometric.biometricLabel;
    final types = await _biometric.availableBiometrics;
    if (!mounted) return;
    setState(() {
      _biometricLabel = label;
      _isFaceId = types.contains(BiometricType.face);
    });
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating || !mounted) return;
    setState(() {
      _isAuthenticating = true;
      _hasFailed        = false;
    });

    final success = await _biometric.authenticateForLogin();

    if (!mounted) return;

    if (success) {
      // Restore profile from Firestore in case local storage was cleared
      try {
        await _auth.restoreProfileFromFirestore()
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      if (!mounted) return;
      _auth.updateLastActive();
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      setState(() {
        _isAuthenticating = false;
        _hasFailed        = true;
      });
    }
  }

  void _usePasswordInstead() {
    // Sign out so the login screen starts fresh
    _auth.signOut();
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── App logo ───────────────────────────────────────────────
              const HuddlLogomark(size: 56),

              const SizedBox(height: 56),

              // ── Welcome illustration ───────────────────────────────────
              _WelcomeIllustration(
                isAnimating: _isAuthenticating,
                hasFailed: _hasFailed,
              ),

              const SizedBox(height: 32),

              // ── Title ──────────────────────────────────────────────────
              Text(
                _hasFailed ? 'Try again' : 'Welcome back',
                style: HuddlText.display(color: HuddlColors.nearBlack),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // ── Subtitle ───────────────────────────────────────────────
              Text(
                _hasFailed
                    ? 'Authentication failed. Tap the icon to try again.'
                    : 'Use $_biometricLabel to log in to Huddl',
                style: HuddlText.body(color: HuddlColors.textSecondary),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // ── Tap-to-retry biometric button ──────────────────────────
              GestureDetector(
                onTap: _isAuthenticating ? null : _authenticate,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _hasFailed
                        ? HuddlColors.error.withValues(alpha: 0.08)
                        : HuddlColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _hasFailed
                          ? HuddlColors.error.withValues(alpha: 0.3)
                          : HuddlColors.primary.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isFaceId
                            ? Icons.face_retouching_natural_rounded
                            : Icons.fingerprint_rounded,
                        size: 24,
                        color: _hasFailed
                            ? HuddlColors.error
                            : HuddlColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isAuthenticating
                            ? 'Verifying…'
                            : 'Use $_biometricLabel',
                        style: HuddlText.body(weight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Use password instead ──────────────────────────────────
              TextButton(
                onPressed: _usePasswordInstead,
                child: Text(
                  'Use password instead',
                  style: HuddlText.body(color: HuddlColors.textSecondary),
                ),
              ),

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Huddl welcome illustration with pulse animation ──────────────────────────
class _WelcomeIllustration extends StatefulWidget {
  final bool isAnimating;
  final bool hasFailed;

  const _WelcomeIllustration({
    required this.isAnimating,
    required this.hasFailed,
  });

  @override
  State<_WelcomeIllustration> createState() => _WelcomeIllustrationState();
}

class _WelcomeIllustrationState extends State<_WelcomeIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(
        scale: widget.isAnimating ? _pulse.value : 1.0,
        child: child,
      ),
      child: ColorFiltered(
        // Tint the illustration red on auth failure for clear visual feedback
        colorFilter: widget.hasFailed
            ? ColorFilter.mode(
                HuddlColors.error.withValues(alpha: 0.15),
                BlendMode.srcATop,
              )
            : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
        child: HuddlCharacter(
          mood: widget.hasFailed ? HuddlMood.curious : HuddlMood.supportive,
          size: 180,
        ),
      ),
    );
  }
}
