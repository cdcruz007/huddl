import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import '../../theme/huddl_colors.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/firebase_auth_service.dart';

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
              Image.asset(
                'assets/images/logo_huddl_splash.png',
                height: 48,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 56),

              // ── Biometric icon ─────────────────────────────────────────
              _BiometricIcon(
                isFaceId: _isFaceId,
                isAnimating: _isAuthenticating,
                hasFailed: _hasFailed,
              ),

              const SizedBox(height: 32),

              // ── Title ──────────────────────────────────────────────────
              Text(
                _hasFailed ? 'Try again' : 'Welcome back',
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // ── Subtitle ───────────────────────────────────────────────
              Text(
                _hasFailed
                    ? 'Authentication failed. Tap the icon to try again.'
                    : 'Use $_biometricLabel to log in to Huddl',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: HuddlColors.textSecondary,
                  height: 1.5,
                ),
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
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _hasFailed
                              ? HuddlColors.error
                              : HuddlColors.primary,
                        ),
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
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: HuddlColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
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

// ── Animated biometric icon widget ───────────────────────────────────────────
class _BiometricIcon extends StatefulWidget {
  final bool isFaceId;
  final bool isAnimating;
  final bool hasFailed;

  const _BiometricIcon({
    required this.isFaceId,
    required this.isAnimating,
    required this.hasFailed,
  });

  @override
  State<_BiometricIcon> createState() => _BiometricIconState();
}

class _BiometricIconState extends State<_BiometricIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.0).animate(
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
    final color = widget.hasFailed
        ? HuddlColors.error
        : HuddlColors.primary;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(
        scale: widget.isAnimating ? _pulse.value : 1.0,
        child: child,
      ),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.10),
          border: Border.all(
            color: color.withValues(alpha: widget.isAnimating ? 0.5 : 0.25),
            width: 2,
          ),
        ),
        child: Icon(
          widget.isFaceId
              ? Icons.face_retouching_natural_rounded
              : Icons.fingerprint_rounded,
          size: 52,
          color: color,
        ),
      ),
    );
  }
}
