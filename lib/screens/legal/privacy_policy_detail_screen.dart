import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';

class PrivacyPolicyDetailScreen extends StatelessWidget {
  const PrivacyPolicyDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.white,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        surfaceTintColor: HuddlColors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              size: 30, color: HuddlColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Privacy Policy',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: context.hc.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLastUpdated(),
            const SizedBox(height: 20),
            _buildGDPRNotice(),
            const SizedBox(height: 20),
            _buildIntroduction(),
            const SizedBox(height: 24),
            _buildSection(
              '1. Information We Collect',
              '''a) Information You Provide:

Account Information:
\u2022 Name, email address, phone number
\u2022 Password (encrypted)
\u2022 Profile photo
\u2022 Date of birth (for age verification)
\u2022 Postcode/location (for local connections)
\u2022 Parenting stage and preferences

Content You Create:
\u2022 Posts, comments, and messages
\u2022 Photos and videos you upload
\u2022 Marketplace listings
\u2022 Reviews and ratings
\u2022 Event and group creations

b) Information Collected Automatically:
\u2022 Device type, operating system, and version
\u2022 IP address and mobile network information
\u2022 Pages and features accessed
\u2022 Location data (with your permission)''',
            ),
            _buildSection(
              '2. How We Use Your Information',
              '''We use your information to:

a) Provide and Improve Service:
\u2022 Create and manage your account
\u2022 Connect you with local parents
\u2022 Show relevant groups, meetups, and content
\u2022 Process transactions and subscriptions
\u2022 Provide customer support

b) Safety and Security:
\u2022 Verify user identity
\u2022 Prevent fraud and abuse
\u2022 Monitor for prohibited content
\u2022 Enforce our Terms of Service

c) Communications:
\u2022 Send account-related emails
\u2022 Notify you of new messages and activity
\u2022 Send marketing communications (with consent)

d) Analytics and Research:
\u2022 Analyze usage patterns
\u2022 Measure effectiveness of features
\u2022 Create aggregated statistics''',
            ),
            _buildSection(
              '3. Legal Basis for Processing (GDPR)',
              '''Under GDPR, we process your data based on:

a) Contractual Necessity:
\u2022 Processing required to provide the Service
\u2022 Account creation and management

b) Legitimate Interests:
\u2022 Improving and developing the Service
\u2022 Fraud prevention and security

c) Legal Obligation:
\u2022 Compliance with UK and EU laws
\u2022 Responding to legal requests

d) Consent:
\u2022 Marketing communications
\u2022 Precise location tracking
\u2022 You may withdraw consent at any time''',
            ),
            _buildSection(
              '4. Data Sharing and Disclosure',
              '''a) Other Users:
Your profile information is visible to other users:
\u2022 Name, photo, and bio
\u2022 Location (postcode area only)
\u2022 Groups and events you join

Private information NOT shared:
\u2022 Email address
\u2022 Phone number
\u2022 Full postcode
\u2022 Payment information
\u2022 Private messages

b) Service Providers:
\u2022 Stripe: Payment processing
\u2022 Firebase/Google Cloud: Data hosting
\u2022 Analytics providers

All providers bound by confidentiality agreements and GDPR compliance.''',
            ),
            _buildSection(
              '5. Data Retention',
              '''\u2022 Data retained while your account is active
\u2022 Most data deleted within 90 days of account deletion
\u2022 Transaction records retained 7 years (tax law)
\u2022 Fraud prevention records retained as needed
\u2022 Data in backups deleted per backup schedule (max 90 days)''',
            ),
            _buildSection(
              '6. Your Rights Under GDPR',
              '''You have the following rights:

a) Right to Access \u2013 Request a copy of your personal data
b) Right to Rectification \u2013 Correct inaccurate data
c) Right to Erasure \u2013 Request deletion of your data
d) Right to Restrict Processing \u2013 Limit how we use your data
e) Right to Data Portability \u2013 Receive data in portable format
f) Right to Object \u2013 Object to processing
g) Right to Withdraw Consent \u2013 Withdraw consent anytime
h) Right to Lodge Complaint \u2013 Complain to UK ICO

To exercise rights:
\u2022 Email: privacy@huddl.app
\u2022 In-app: Profile \u2192 Privacy & Security \u2192 Data Rights
\u2022 Response within 30 days''',
            ),
            _buildSection(
              '7. Data Security',
              '''\u2022 Industry-standard encryption (TLS/SSL)
\u2022 Encrypted data storage
\u2022 Secure authentication (Firebase Auth)
\u2022 Regular security audits
\u2022 PCI DSS compliant payment processing
\u2022 Data breach notification within 72 hours''',
            ),
            _buildSection(
              '8. Children\u2019s Privacy',
              '''\u2022 Service is for users 18 years and older
\u2022 We do not knowingly collect data from children under 18
\u2022 Do NOT post full names or identifying information of children
\u2022 Only share children\u2019s ages for matching purposes''',
            ),
            _buildSection(
              '9. Contact Information',
              '''For privacy questions or to exercise your rights:

Email: privacy@huddl.app
Support: support@huddl.app
Data Protection Officer: dpo@huddl.app

Cruzen Ltd
[Company Registered Address]

UK Information Commissioner\u2019s Office:
Website: https://ico.org.uk
Phone: 0303 123 1113''',
            ),
            const SizedBox(height: 8),
            _buildDataProtectionSummary(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdated() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.peachLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.2)),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primaryDark,
                  ),
                ),
                Text(
                  'Version 1.0 \u2013 GDPR Compliant',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: HuddlColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGDPRNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user, color: HuddlColors.teal, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GDPR Compliant',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.teal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This policy complies with UK GDPR, EU GDPR, Data Protection Act 2018, and CCPA. Your privacy rights are protected.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: HuddlColors.textSecondary, height: 1.5),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.privacy_tip, color: HuddlColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your Privacy Matters',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Huddl (\u201cwe\u201d, \u201cus\u201d, \u201cour\u201d) operated by Cruzen Ltd is committed to protecting your privacy. This Privacy Policy explains how we collect, use, share, and protect your personal information when you use our Service.',
            style: GoogleFonts.poppins(
                fontSize: 13, color: HuddlColors.textSecondary, height: 1.55),
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
        const SizedBox(height: 10),
        Text(
          content,
          style: GoogleFonts.poppins(
              fontSize: 13, color: HuddlColors.textSecondary, height: 1.6),
        ),
        const SizedBox(height: 20),
        Divider(color: HuddlColors.divider, height: 1),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDataProtectionSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.peachVeryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield, color: HuddlColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Quick Summary \u2013 Your Rights',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRightItem('\u2713 Access your data anytime'),
          _buildRightItem('\u2713 Correct inaccurate information'),
          _buildRightItem('\u2713 Delete your account and data'),
          _buildRightItem('\u2713 Export your data (portability)'),
          _buildRightItem('\u2713 Opt out of marketing'),
          _buildRightItem('\u2713 Withdraw consent anytime'),
          _buildRightItem('\u2713 Lodge complaint with ICO'),
          const SizedBox(height: 12),
          Text(
            'Exercise your rights: Profile \u2192 Privacy \u2192 Export / Delete\nOr email: privacy@huddl.app',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: HuddlColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: HuddlColors.textDark,
        ),
      ),
    );
  }
}
