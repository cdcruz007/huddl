import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';
import '../../services/huddl_user_service.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_button.dart';
import '../../widgets/onboarding_progress_bar.dart';

// large textarea filling most of screen, orange "Continue" button at bottom.

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
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
      final assigned =
          await groupService.assignUserToDefaultGroups(userId);
      if (kDebugMode) {
        debugPrint('Assigned ${assigned.length} default group(s) at onboarding completion');
      }
    } catch (e) {
      // Non-fatal — groups will be assigned lazily when the Messages tab loads
      if (kDebugMode) {
        debugPrint('Could not assign default groups at onboarding: $e');
      }
    }

    if (!mounted) return;

    // ── SYNC profile to Firestore and mark onboarding complete ───────────
    // This writes name, postcode, parentType, etc. to Firestore and clears
    // the isOnboarding flag so subsequent cold starts go straight to /home.
    try {
      await HuddlUserService().syncCurrentUserProfile();
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('Could not sync profile at onboarding end: $e');
      }
    }

    if (!mounted) return;

    // Navigate to email verification gate — user must confirm email before
    // entering the app. The welcome email (with Verify button) was already
    // sent earlier in the onboarding flow when "Let's go!" was tapped.
    Navigator.pushNamedAndRemoveUntil(
        context, '/email_pending_verification', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OnboardingProgressBar(step: OnboardingStep.aboutYou),
            // ── Back arrow only (no logo on this screen per design) ────
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Title (left-aligned, large) ────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'One last thing',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.2,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Subtitle ───────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'A line about you helps nearby parents find their people. You can always add this later.',
                style: TextStyle(
                  fontSize: 14,
                  color: HuddlColors.disabledText,
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
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _bioController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    textInputAction: TextInputAction.done,
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.55,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'E.g. tell other about your children or interests',
                      hintStyle: const TextStyle(
                        fontSize: 15,
                        color: HuddlColors.disabledText,
                      ),
                      filled: true,
                      fillColor: Colors.transparent,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: HuddlColors.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
              child: HuddlButton(
                label: 'Continue',
                onPressed: _finish,
              ),
            ),

            // ── Skip button ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: HuddlButton(
                label: 'Skip',
                onPressed: _finish,
                variant: HuddlButtonVariant.ghost,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
