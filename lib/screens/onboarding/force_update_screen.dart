import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/huddl_colors.dart';
import '../../services/version_gate_service.dart';

// =============================================================================
// LAYER-19-NO-VERSION-GATE-1
//
// ForceUpdateScreen — blocking screen shown when VersionGateService.check()
// returns updateRequired=true.
//
// Design constraints:
//   • PopScope(canPop: false) — no back-nav escape. User MUST update.
//   • No dismiss button, no "skip", no timer-based bypass.
//   • "Update now" launches the platform-appropriate store URL.
//   • If no URL is configured for the current platform, the button is hidden
//     (edge case; operator should always configure both URLs).
//   • Huddl brand colours: white background, primary orange CTA.
// =============================================================================

class ForceUpdateScreen extends StatelessWidget {
  final VersionGateResult gate;

  const ForceUpdateScreen({super.key, required this.gate});

  // ── Resolve the store URL for the current platform ───────────────────────
  String? get _storeUrl {
    if (kIsWeb) return null;
    if (Platform.isIOS)     return gate.updateUrlIos;
    if (Platform.isAndroid) return gate.updateUrlAndroid;
    return null;
  }

  Future<void> _openStore(BuildContext context) async {
    final url = _storeUrl;
    if (url == null || url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the store. Please update manually.'),
          backgroundColor: HuddlColors.nearBlack,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Force status bar to dark icons on white background (same as splash).
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness:     Brightness.light,
    ));

    final hasStoreUrl = (_storeUrl ?? '').isNotEmpty;
    final message = gate.message.isNotEmpty
        ? gate.message
        : 'A new version of Huddl is required to continue.';

    return PopScope(
      // BLOCKING: back navigation is categorically disabled.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // ── Huddl lockup (same as splash, smaller) ──────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/huddl_logomark.svg',
                      height: 40,
                      placeholderBuilder: (_) =>
                          const SizedBox(width: 28, height: 40),
                    ),
                    const SizedBox(width: 10),
                    SvgPicture.asset(
                      'assets/icons/huddl_wordmark.svg',
                      height: 28,
                      colorFilter: const ColorFilter.mode(
                          HuddlColors.nearBlack, BlendMode.srcIn),
                      placeholderBuilder: (_) =>
                          const SizedBox(width: 124, height: 28),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // ── Update icon ─────────────────────────────────────────
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: HuddlColors.peachSurface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: HuddlColors.primary,
                    size: 40,
                  ),
                ),

                const SizedBox(height: 28),

                // ── Headline ────────────────────────────────────────────
                Text(
                  'Update required',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.nearBlack,
                    letterSpacing: -0.3,
                  ),
                ),

                const SizedBox(height: 12),

                // ── Body message from Firestore ─────────────────────────
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: HuddlColors.nearBlack.withValues(alpha: 0.55),
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 40),

                // ── CTA button — only shown if store URL is configured ──
                if (hasStoreUrl)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _openStore(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Update now',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),

                // ── Fallback copy when URL is missing ──────────────────
                if (!hasStoreUrl)
                  Text(
                    'Please update the app from your device\'s app store.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: HuddlColors.nearBlack.withValues(alpha: 0.45),
                    ),
                  ),

                const Spacer(flex: 3),

                // ── Footer note ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    'This version is no longer supported.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.nearBlack.withValues(alpha: 0.30),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
