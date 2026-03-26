import 'package:flutter/material.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';

// Design tokens from screenshot 16
// Note: Screen 16 has NO huddl logo — just back arrow, left-aligned title,
// large textarea filling most of screen, orange "Continue" button at bottom.
const _kOrange = Color(0xFFFCA878);
const _kTextDark = Color(0xFF1C1C1C);
const _kTextGray = Color(0xFF9E9E9E);
const _kInputBg = Color(0xFFF5F5F5);
const _kInputBorder = Color(0xFFDDDDDD);

class AboutYouScreen extends StatefulWidget {
  const AboutYouScreen({super.key});

  @override
  State<AboutYouScreen> createState() => _AboutYouScreenState();
}

class _AboutYouScreenState extends State<AboutYouScreen> {
  final _bioController = TextEditingController();
  final _onboarding = OnboardingDataService();

  @override
  void initState() {
    super.initState();
    // Pre-fill with any previously saved bio
    _onboarding.initialize().then((_) {
      if (_onboarding.bio != null && _onboarding.bio!.isNotEmpty && mounted) {
        _bioController.text = _onboarding.bio!;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  void _finish() async {
    // ── SAVE bio to OnboardingDataService before navigating ──
    final bio = _bioController.text.trim();
    if (bio.isNotEmpty) {
      _onboarding.setBio(bio);
    }

    // ── ASSIGN DEFAULT GROUPS based on onboarding data ──────────────────
    // This must happen BEFORE navigating to /home so the Groups tab
    // immediately shows the correct borough-based community groups.
    try {
      final groupService = DefaultGroupService();
      await groupService.initialize();
      final assigned =
          await groupService.assignUserToDefaultGroups('current_user');
      // ignore: avoid_print
      print('✅ Assigned ${assigned.length} default group(s) at onboarding completion');
      groupService.printGroupAssignmentSummary();
    } catch (e) {
      // Non-fatal — groups will be assigned lazily when the Messages tab loads
      // ignore: avoid_print
      print('⚠️ Could not assign default groups at onboarding: $e');
    }

    if (!mounted) return;

    // Provider path → show the "You're Live!" success screen
    if (_onboarding.isProvider) {
      Navigator.pushNamedAndRemoveUntil(
          context, '/provider_complete', (route) => false);
    } else {
      // Parent path → go straight home
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Back arrow only (no logo on this screen per design) ────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
              child: IconButton(
                icon: const Icon(Icons.chevron_left,
                    size: 30, color: _kOrange),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
              ),
            ),

            const SizedBox(height: 16),

            // ── Title (left-aligned, large) ────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'About you',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: _kTextDark,
                  height: 1.2,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Subtitle ───────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Adding a short bio will make it easier for you to connect\nwith other parents.',
                style: TextStyle(
                  fontSize: 14,
                  color: _kTextGray,
                  height: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Large textarea (fills available vertical space) ────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  decoration: const BoxDecoration(
                    color: _kInputBg,
                    border: Border(
                      bottom: BorderSide(color: _kInputBorder, width: 1.2),
                    ),
                  ),
                  child: TextField(
                    controller: _bioController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontSize: 15,
                      color: _kTextDark,
                      height: 1.55,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'About',
                      labelStyle: TextStyle(
                        fontSize: 13,
                        color: _kTextGray,
                      ),
                      hintText:
                          'E.g. tell other about your children or interests',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: _kTextGray,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                      alignLabelWithHint: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ),

            // ── Continue button at bottom ────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            // ── Skip button ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(
                    foregroundColor: _kTextGray,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _kTextGray,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
