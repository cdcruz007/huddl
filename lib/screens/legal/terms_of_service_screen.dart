import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../constants/app_text_styles.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          'Terms of Service',
          style: AppTextStyles.h2.copyWith(color: Colors.white),
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
• Connect with other parents in their local area
• Join and create local parenting groups
• Organize and attend meetups and events
• Share advice, tips, and experiences
• Access local childcare services and service providers
• Buy and sell children's items through the marketplace
• Communicate via direct messaging

The Service is provided "as is" without warranties of any kind. We reserve the right to modify, suspend, or discontinue any aspect of the Service at any time.''',
            ),
            _buildSection(
              '3. User Eligibility',
              '''You must:
• Be at least 18 years of age
• Have the legal capacity to enter into binding contracts
• Provide accurate and complete registration information
• Maintain the security of your account credentials
• Be a parent, guardian, or caregiver to use the Service

Users who violate these eligibility requirements will have their accounts terminated immediately.''',
            ),
            _buildSection(
              '4. User Responsibilities and Conduct',
              '''You agree to:

a) Respectful Behavior:
• Treat all users with respect and courtesy
• Refrain from harassment, bullying, or abusive behavior
• Report inappropriate conduct to our moderation team
• Foster a safe, inclusive community environment

b) Prohibited Activities:
You must NOT:
• Post false, misleading, or defamatory content
• Share inappropriate, explicit, or harmful content
• Harass, threaten, or intimidate other users
• Impersonate others or create fake accounts
• Spam or engage in commercial solicitation
• Share personal contact information of minors publicly
• Violate any applicable laws or regulations
• Attempt to hack, disrupt, or compromise the Service
• Use automated systems to access the Service
• Collect user data without consent

c) Content Responsibility:
• You are solely responsible for all content you post
• You must have rights to any content you share
• You grant us license to use, display, and distribute your content
• You must not post copyrighted material without permission

Violation of these terms may result in immediate account suspension or termination without refund.''',
            ),
            _buildSection(
              '5. Limitation of Liability',
              '''TO THE MAXIMUM EXTENT PERMITTED BY LAW:

a) Cruzen Ltd, its directors, officers, employees, and agents SHALL NOT BE LIABLE FOR:
• Any direct, indirect, incidental, special, or consequential damages
• Loss of profits, data, or business opportunities
• Personal injury or property damage arising from use of the Service
• User-generated content or interactions between users
• Third-party services, links, or integrations
• Service interruptions, errors, or security breaches
• Decisions made based on information found on the Service

b) Disclaimer of Warranties:
THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT ANY WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO:
• Warranties of merchantability
• Fitness for a particular purpose
• Non-infringement
• Accuracy or reliability of content
• Uninterrupted or error-free service

c) Maximum Liability:
In no event shall our total liability exceed the amount you paid for the Service in the 12 months preceding the claim, or £100, whichever is less.

d) User Interactions:
• You use the Service at your own risk
• We are not responsible for user conduct or safety
• You are responsible for verifying information and identities
• Meet other users in public places and exercise caution
• Report suspicious behavior to our support team''',
            ),
            _buildSection(
              '6. Indemnification',
              '''You agree to indemnify, defend, and hold harmless Cruzen Ltd, its affiliates, officers, directors, employees, agents, and partners from any claims, damages, losses, liabilities, and expenses (including legal fees) arising from:

• Your use or misuse of the Service
• Your violation of these Terms
• Your violation of any rights of another person or entity
• Your content or conduct on the Service
• Any dispute between you and other users

This indemnification obligation survives termination of your account and these Terms.''',
            ),
            _buildSection(
              '7. Payment Terms',
              '''a) Subscription Plans:
• Free tier: Basic access to community features
• Premium tier: Full access to all features (pricing displayed in-app)

b) Payment Processing:
• Payments are processed securely via Stripe
• All prices are in GBP and include applicable VAT
• Subscription automatically renews unless cancelled

c) Billing Cycle:
• Monthly subscriptions: Billed every 30 days
• Annual subscriptions: Billed every 365 days
• Billing occurs on the same day of each period
• You authorize automatic charges to your payment method

d) Price Changes:
• We reserve the right to change subscription prices
• Price changes apply from the next billing cycle
• You will be notified 30 days before any price increase
• Continued use after price change constitutes acceptance

e) Payment Failures:
• Failed payments may result in service suspension
• We will attempt to process payment multiple times
• Update payment information to restore access
• Unpaid accounts may be permanently deleted after 60 days''',
            ),
            _buildSection(
              '8. Cancellation and Refunds',
              '''a) Cancellation Policy:
• You may cancel your subscription at any time
• Cancel through: Profile → Settings → Subscription Management
• Cancellation takes effect at the end of the current billing period
• You retain access until the end of the paid period
• No partial refunds for unused time

b) NO REFUND POLICY:
• All subscription fees are NON-REFUNDABLE
• No refunds for unused portion of subscription period
• No refunds for accounts terminated for Terms violations
• No refunds for dissatisfaction with the Service
• Payment disputes must be submitted within 7 days

c) Free Trial:
• New users may receive a free trial period
• Trial period ends automatically and converts to paid subscription
• Cancel before trial ends to avoid charges
• One free trial per user/payment method

d) Account Deletion:
• Deleting your account does NOT cancel active subscriptions
• You must cancel subscription separately before deleting account
• Deleted accounts cannot be recovered
• Unpaid balances remain due after account deletion''',
            ),
            _buildSection(
              '9. Intellectual Property',
              '''a) Our Rights:
• The Huddl name, logo, and branding are trademarks of Cruzen Ltd
• All Service content, features, and functionality are owned by us
• Protected by copyright, trademark, and other intellectual property laws
• You may not copy, modify, or distribute our intellectual property

b) User Content License:
By posting content, you grant us:
• Worldwide, non-exclusive, royalty-free license
• Right to use, reproduce, modify, and distribute your content
• Right to sublicense your content to third parties
• License survives termination of your account

c) Content Removal:
• We reserve the right to remove any content without notice
• Content that violates Terms or community guidelines will be removed
• Repeated violations may result in account termination''',
            ),
            _buildSection(
              '10. Privacy and Data Protection',
              '''a) GDPR Compliance:
• We comply with UK GDPR and Data Protection Act 2018
• Read our Privacy Policy for detailed data practices
• You have rights to access, correct, and delete your data
• Contact privacy@huddl.app for data requests

b) Data Collection:
• We collect data as described in our Privacy Policy
• Location data is used to connect you with local parents
• Communications may be monitored for safety and quality
• We may share data as required by law

c) Child Safety:
• Do NOT share personal information about children publicly
• Do NOT post photos of other people's children without consent
• Report any child safety concerns immediately''',
            ),
            _buildSection(
              '11. Termination',
              '''a) By You:
• You may delete your account at any time
• Must cancel subscription separately
• Account deletion is permanent and irreversible

b) By Us:
We may suspend or terminate your account immediately if you:
• Violate these Terms or community guidelines
• Engage in fraudulent or illegal activity
• Pose a safety risk to other users
• Fail to pay subscription fees
• Are subject to legal proceedings

c) Effect of Termination:
• Access to Service is immediately revoked
• No refunds for paid subscriptions
• All user data may be deleted
• Indemnification obligations survive termination''',
            ),
            _buildSection(
              '12. Dispute Resolution',
              '''a) Governing Law:
• These Terms are governed by the laws of England and Wales
• Disputes subject to exclusive jurisdiction of English courts

b) Informal Resolution:
• Contact support@huddl.app to resolve disputes informally
• We will attempt good faith resolution before legal proceedings

c) Arbitration:
• Disputes may be resolved through binding arbitration
• Arbitration conducted under rules of London Court of International Arbitration
• Each party bears own costs unless arbitrator orders otherwise

d) Class Action Waiver:
• You agree to resolve disputes individually, not as class actions
• You waive right to participate in class action lawsuits''',
            ),
            _buildSection(
              '13. Changes to Terms',
              '''• We may modify these Terms at any time
• Material changes will be notified via email and in-app notification
• Continued use after changes constitutes acceptance
• Your only remedy for disagreement is to stop using the Service
• Review Terms periodically for updates''',
            ),
            _buildSection(
              '14. Miscellaneous',
              '''a) Entire Agreement:
These Terms constitute the entire agreement between you and Cruzen Ltd.

b) Severability:
If any provision is found unenforceable, remaining provisions remain in effect.

c) No Waiver:
Failure to enforce any provision does not constitute waiver of that provision.

d) Assignment:
You may not assign these Terms. We may assign without restriction.

e) Force Majeure:
We are not liable for delays caused by circumstances beyond our control.

f) Contact Information:
Cruzen Ltd
Email: legal@huddl.app
Support: support@huddl.app
Address: [Company Registered Address]''',
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
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.update, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last Updated: January 2025',
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  'Version 1.0',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.text2,
                  ),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Important Notice',
                  style: AppTextStyles.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Please read these Terms of Service carefully before using Huddl. By creating an account or using our Service, you acknowledge that you have read, understood, and agree to be bound by these Terms.',
            style: AppTextStyles.body2.copyWith(
              color: AppColors.text2,
              height: 1.5,
            ),
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
          style: AppTextStyles.h3.copyWith(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          content,
          style: AppTextStyles.body2.copyWith(
            color: AppColors.text2,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildAcceptanceNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: AppColors.error, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'By using Huddl, you agree to:',
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '• All limitations of liability\n'
                  '• No refund policy\n'
                  '• Binding arbitration for disputes\n'
                  '• All other terms stated above',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.text2,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
