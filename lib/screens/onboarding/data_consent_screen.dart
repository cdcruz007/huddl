import 'package:flutter/gestures.dart';
import '../../theme/huddl_icons.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/huddl_colors.dart';
import '../../services/browser_storage.dart';
import '../../services/onboarding_data_service.dart';

// =============================================================================
// DATA CONSENT SCREEN — GDPR / COPPA
//
// Shown ONCE in the onboarding flow, after name_input and before parent_type.
// The user must tick both mandatory checkboxes before continuing.
//
// What it covers:
//   1. Mandatory — General privacy/data processing consent (GDPR Art. 6(a))
//   2. Mandatory — Acknowledgement that the app may collect children's data
//                  (COPPA / UK Children's Code compliance)
//   3. Optional  — Marketing / newsletter consent
//
// Consent is persisted to BrowserStorage under key 'data_consent_v1' so the
// screen is never shown again after first completion.  The router does NOT
// need to check this — it is driven by name_input's navigation target.
// =============================================================================

class DataConsentScreen extends StatefulWidget {
  const DataConsentScreen({super.key});

  @override
  State<DataConsentScreen> createState() => _DataConsentScreenState();
}

class _DataConsentScreenState extends State<DataConsentScreen> {
  bool _privacyAccepted    = false;
  bool _childsDataAccepted = false;
  bool _marketingAccepted  = false;

  bool get _canContinue => _privacyAccepted && _childsDataAccepted;

  Future<void> _continue() async {
    if (!_canContinue) return;

    // Persist consent so the screen is never shown again (gates re-show on resume)
    await BrowserStorage.setString('data_consent_v1', 'granted');
    await BrowserStorage.setString(
        'data_consent_marketing_v1', _marketingAccepted ? 'true' : 'false');

    // LAYER-15: capture consent into OnboardingDataService so _createUserProfile
    // can write a durable user_consents/{uid} record atomically with the account.
    // Called AFTER BrowserStorage writes so the gate is set before we proceed.
    OnboardingDataService().setConsent(
      dataProcessing: true,               // mandatory — _canContinue enforces it
      marketing: _marketingAccepted,
      policyVersion: 'v1',                // BUMP when privacy policy text changes
      consentedAt: DateTime.now().toUtc(),
    );

    if (mounted) {
      Navigator.pushNamed(context, '/parent_type');
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingAppBar(onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 36),

                    // ── Shield icon + title ──────────────────────────────
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: HuddlColors.neutral50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          HuddlIcons.shield,
                          size: 40,
                          color: HuddlColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Center(
                      child: Text(
                        'Your privacy matters',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.25,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Center(
                      child: Text(
                        'Before you join Huddl, please review how we use your data and give your consent below.',
                        style: TextStyle(
                          fontSize: 14,
                          color: HuddlColors.disabledText,
                          height: 1.55,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Summary card ─────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SummaryRow(
                            icon: HuddlIcons.user,
                            title: 'Account data',
                            detail: 'Name, email, postcode — used to connect you with your local parenting community.',
                          ),
                          const SizedBox(height: 12),
                          _SummaryRow(
                            icon: HuddlIcons.childCare,
                            title: 'Children\'s data',
                            detail: 'If you add a child\'s age or due date, this data is stored to personalise your experience.',
                          ),
                          const SizedBox(height: 12),
                          _SummaryRow(
                            icon: HuddlIcons.lock,
                            title: 'How we protect it',
                            detail: 'Data is encrypted in transit and at rest. We never sell personal data to third parties.',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Consent checkboxes ───────────────────────────────
                    _ConsentCheckbox(
                      value: _privacyAccepted,
                      onChanged: (v) => setState(() => _privacyAccepted = v ?? false),
                      isMandatory: true,
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                            height: 1.5,
                          ),
                          children: [
                            const TextSpan(
                              text: 'I have read and agree to the ',
                            ),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: const TextStyle(
                                color: HuddlColors.textTertiary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => Navigator.pushNamed(context, '/privacy'),
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Terms of Service',
                              style: const TextStyle(
                                color: HuddlColors.textTertiary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => Navigator.pushNamed(context, '/terms'),
                            ),
                            const TextSpan(
                              text: '. I consent to Huddl processing my personal data as described.',
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    _ConsentCheckbox(
                      value: _childsDataAccepted,
                      onChanged: (v) => setState(() => _childsDataAccepted = v ?? false),
                      isMandatory: true,
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                            height: 1.5,
                          ),
                          children: [
                            const TextSpan(
                              text: 'I understand that if I add information about my child (age, due date, name), '
                                  'this data will be stored and used to personalise my Huddl experience. '
                                  'I confirm I am the parent or legal guardian and consent to this under the ',
                            ),
                            TextSpan(
                              text: 'UK Children\'s Code',
                              style: const TextStyle(
                                color: HuddlColors.textTertiary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => _launchUrl(
                                    'https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/'),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    _ConsentCheckbox(
                      value: _marketingAccepted,
                      onChanged: (v) => setState(() => _marketingAccepted = v ?? false),
                      isMandatory: false,
                      child: const Text(
                        'I\'d like to receive helpful parenting tips, local event updates, and product news from Huddl. '
                        'I can unsubscribe at any time. (Optional)',
                        style: TextStyle(
                          fontSize: 14,
                          color: HuddlColors.disabledText,
                          height: 1.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Continue button ──────────────────────────────────
                    _OrangeButton(
                      label: 'I agree — continue',
                      enabled: _canContinue,
                      onTap: _continue,
                    ),

                    const SizedBox(height: 16),

                    // ── Decline / more info ──────────────────────────────
                    Center(
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 12,
                            color: HuddlColors.disabledText,
                            height: 1.6,
                          ),
                          children: [
                            const TextSpan(
                              text: 'You must agree to both required items to use Huddl.\n',
                            ),
                            TextSpan(
                              text: 'Read our full Privacy Policy',
                              style: const TextStyle(
                                color: HuddlColors.textTertiary,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => Navigator.pushNamed(context, '/privacy'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
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

// ── Private helper widgets ─────────────────────────────────────────────────────

class _OnboardingAppBar extends StatelessWidget {
  final VoidCallback onBack;
  const _OnboardingAppBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          tooltip: 'Back',
          icon: const Icon(
            HuddlIcons.arrowBack,
            size: 18,
            color: Colors.white,
          ),
          onPressed: onBack,
        ),
      ),
    );
  }
}

class _OrangeButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _OrangeButton({required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: enabled ? HuddlColors.onboardingOrange : HuddlColors.disabled,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: enabled ? Colors.white : HuddlColors.disabledText,
          ),
        ),
      ),
    );
  }
}

/// Row with icon + title + detail text, used in the summary card.
class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  const _SummaryRow({required this.icon, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: HuddlColors.neutral50,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: HuddlColors.textDark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  fontSize: 12,
                  color: HuddlColors.disabledText,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Checkbox with label; mandatory items show a red asterisk.
class _ConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final bool isMandatory;
  final Widget child;
  const _ConsentCheckbox({
    required this.value,
    required this.onChanged,
    required this.isMandatory,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: HuddlColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Expanded(child: child),
            if (isMandatory) ...[
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(
                  color: HuddlColors.error,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
