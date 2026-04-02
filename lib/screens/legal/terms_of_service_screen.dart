import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.primary,
        title: Text(
          'Terms of Service',
          style: GoogleFonts.poppins(
              fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLastUpdated(),
            const SizedBox(height: 24),
            _buildIntroduction(),
            const SizedBox(height: 24),
            _buildSection(
              '1. Acceptance of Terms',
              '''By accessing or using the Huddl mobile application and services ("Service"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, do not use the Service.

These Terms constitute a legally binding agreement between you and Cruzen Ltd ("Company", "we", "us", or "our"). Your continued use of the Service constitutes acceptance of these Terms and any modifications thereto.''',
            ),
            _buildSection(
              '2. Description of Service',
              '''Huddl is a community platform that enables parents and families to:
\u2022 Connect with other parents in their local area
\u2022 Join and create local parenting groups
\u2022 Organize and attend meetups and events
\u2022 Share advice, tips, and experiences
\u2022 Access local childcare services and service providers
\u2022 Buy and sell children\u2019s items through the marketplace
\u2022 Communicate via direct messaging

The Service is provided "as is" without warranties of any kind. We reserve the right to modify, suspend, or discontinue any aspect of the Service at any time.''',
            ),
            _buildSection(
              '3. User Eligibility',
              '''You must:
\u2022 Be at least 18 years of age
\u2022 Have the legal capacity to enter into binding contracts
\u2022 Provide accurate and complete registration information
\u2022 Maintain the security of your account credentials
\u2022 Be a parent, guardian, or caregiver to use the Service

Users who violate these eligibility requirements will have their accounts terminated immediately.''',
            ),
            _buildSection(
              '4. User Responsibilities and Conduct',
              '''You agree to:

a) Respectful Behavior:
\u2022 Treat all users with respect and courtesy
\u2022 Refrain from harassment, bullying, or abusive behavior
\u2022 Report inappropriate conduct to our moderation team
\u2022 Foster a safe, inclusive community environment

b) Prohibited Activities:
You must NOT:
\u2022 Post false, misleading, or defamatory content
\u2022 Share inappropriate, explicit, or harmful content
\u2022 Harass, threaten, or intimidate other users
\u2022 Impersonate others or create fake accounts
\u2022 Spam or engage in commercial solicitation
\u2022 Share personal contact information of minors publicly
\u2022 Violate any applicable laws or regulations
\u2022 Attempt to hack, disrupt, or compromise the Service
\u2022 Use automated systems to access the Service
\u2022 Collect user data without consent

c) Content Responsibility:
\u2022 You are solely responsible for all content you post
\u2022 You must have rights to any content you share
\u2022 You grant us license to use, display, and distribute your content
\u2022 You must not post copyrighted material without permission

Violation of these terms may result in immediate account suspension or termination without refund.''',
            ),
            _buildSection(
              '5. Limitation of Liability',
              '''TO THE MAXIMUM EXTENT PERMITTED BY LAW:

a) Cruzen Ltd, its directors, officers, employees, and agents SHALL NOT BE LIABLE FOR:
\u2022 Any direct, indirect, incidental, special, or consequential damages
\u2022 Loss of profits, data, or business opportunities
\u2022 Personal injury or property damage arising from use of the Service
\u2022 User-generated content or interactions between users
\u2022 Third-party services, links, or integrations
\u2022 Service interruptions, errors, or security breaches
\u2022 Decisions made based on information found on the Service

b) Disclaimer of Warranties:
THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT ANY WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED.

c) Maximum Liability:
In no event shall our total liability exceed the amount you paid for the Service in the 12 months preceding the claim, or \u00a3100, whichever is less.

d) User Interactions:
\u2022 You use the Service at your own risk
\u2022 We are not responsible for user conduct or safety
\u2022 You are responsible for verifying information and identities
\u2022 Meet other users in public places and exercise caution
\u2022 Report suspicious behavior to our support team''',
            ),
            _buildSection(
              '6. Indemnification',
              '''You agree to indemnify, defend, and hold harmless Cruzen Ltd, its affiliates, officers, directors, employees, agents, and partners from any claims, damages, losses, liabilities, and expenses (including legal fees) arising from:

\u2022 Your use or misuse of the Service
\u2022 Your violation of these Terms
\u2022 Your violation of any rights of another person or entity
\u2022 Your content or conduct on the Service
\u2022 Any dispute between you and other users

This indemnification obligation survives termination of your account and these Terms.''',
            ),
            _buildSection(
              '7. Payment Terms',
              '''a) Subscription Plans:
\u2022 Free tier: Basic access to community features
\u2022 Premium tier: Full access to all features (pricing displayed in-app)

b) Payment Processing:
\u2022 Payments are processed securely via Stripe
\u2022 All prices are in GBP and include applicable VAT
\u2022 Subscription automatically renews unless cancelled

c) Billing Cycle:
\u2022 Monthly subscriptions: Billed every 30 days
\u2022 Annual subscriptions: Billed every 365 days

d) Cancellation Policy:
\u2022 You may cancel your subscription at any time
\u2022 Cancel through: Profile \u2192 Settings \u2192 Subscription Management
\u2022 Cancellation takes effect at the end of the current billing period
\u2022 No partial refunds for unused time''',
            ),
            _buildSection(
              '8. Privacy and Data Protection',
              '''a) GDPR Compliance:
\u2022 We comply with UK GDPR and Data Protection Act 2018
\u2022 Read our Privacy Policy for detailed data practices
\u2022 You have rights to access, correct, and delete your data
\u2022 Contact privacy@huddl.app for data requests

b) Data Collection:
\u2022 We collect data as described in our Privacy Policy
\u2022 Location data is used to connect you with local parents
\u2022 Communications may be monitored for safety and quality
\u2022 We may share data as required by law

c) Child Safety:
\u2022 Do NOT share personal information about children publicly
\u2022 Do NOT post photos of other people\u2019s children without consent
\u2022 Report any child safety concerns immediately''',
            ),
            _buildSection(
              '9. Termination',
              '''a) By You:
\u2022 You may delete your account at any time
\u2022 Must cancel subscription separately
\u2022 Account deletion is permanent and irreversible

b) By Us:
We may suspend or terminate your account immediately if you:
\u2022 Violate these Terms or community guidelines
\u2022 Engage in fraudulent or illegal activity
\u2022 Pose a safety risk to other users
\u2022 Fail to pay subscription fees

c) Effect of Termination:
\u2022 Access to Service is immediately revoked
\u2022 No refunds for paid subscriptions
\u2022 All user data may be deleted
\u2022 Indemnification obligations survive termination''',
            ),
            _buildSection(
              '10. Dispute Resolution',
              '''a) Governing Law:
\u2022 These Terms are governed by the laws of England and Wales
\u2022 Disputes subject to exclusive jurisdiction of English courts

b) Informal Resolution:
\u2022 Contact support@huddl.app to resolve disputes informally
\u2022 We will attempt good faith resolution before legal proceedings

c) Class Action Waiver:
\u2022 You agree to resolve disputes individually, not as class actions''',
            ),
            _buildSection(
              '11. Miscellaneous',
              '''a) Entire Agreement:
These Terms constitute the entire agreement between you and Cruzen Ltd.

b) Severability:
If any provision is found unenforceable, remaining provisions remain in effect.

c) Contact Information:
Cruzen Ltd
Email: legal@huddl.app
Support: support@huddl.app''',
            ),
            const SizedBox(height: 32),
            _buildAcceptanceNotice(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdated() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.update, color: HuddlColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last Updated: January 2025',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primary,
                  ),
                ),
                Text(
                  'Version 1.0',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: HuddlColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroduction() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description, color: HuddlColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Important Notice',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Please read these Terms of Service carefully before using Huddl. By creating an account or using our Service, you acknowledge that you have read, understood, and agree to be bound by these Terms.',
            style: GoogleFonts.poppins(
                fontSize: 13, color: HuddlColors.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: HuddlColors.textDark,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          content,
          style: GoogleFonts.poppins(
              fontSize: 13, color: HuddlColors.textSecondary, height: 1.6),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildAcceptanceNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: HuddlColors.error, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'By using Huddl, you agree to:',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.error),
                ),
                const SizedBox(height: 8),
                Text(
                  '\u2022 All limitations of liability\n'
                  '\u2022 No refund policy\n'
                  '\u2022 Binding arbitration for disputes\n'
                  '\u2022 All other terms stated above',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: HuddlColors.textSecondary, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
