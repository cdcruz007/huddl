import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../constants/app_text_styles.dart';

class PrivacyPolicyDetailScreen extends StatelessWidget {
  const PrivacyPolicyDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          'Privacy Policy',
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
            _buildGDPRNotice(),
            const SizedBox(height: 24),
            _buildIntroduction(),
            const SizedBox(height: 24),
            _buildSection(
              '1. Information We Collect',
              '''a) Information You Provide:

Account Information:
• Name, email address, phone number
• Password (encrypted)
• Profile photo
• Date of birth (for age verification)
• Postcode/location (for local connections)
• Parenting stage and preferences

Profile Information:
• Bio and personal description
• Children's ages (not names or identifying information)
• Interests and hobbies
• Group memberships
• Event attendance

Content You Create:
• Posts, comments, and messages
• Photos and videos you upload
• Marketplace listings
• Reviews and ratings
• Event and group creations

b) Information Collected Automatically:

Device Information:
• Device type, operating system, and version
• Unique device identifiers
• Mobile network information
• IP address
• Browser type and language settings

Usage Information:
• Pages and features accessed
• Time spent on features
• Links clicked
• Search queries
• Actions taken (likes, joins, etc.)

Location Information:
• Precise location (with your permission)
• Approximate location from IP address
• Location entered in profile

c) Information From Third Parties:

Payment Information:
• Payment card details (processed by Stripe, not stored by us)
• Billing address
• Transaction history

Social Media:
• Information from connected social accounts (if you choose to link)
• Only data you authorize us to access

Service Providers:
• Analytics providers
• Cloud storage providers
• Security service providers''',
            ),
            _buildSection(
              '2. How We Use Your Information',
              '''We use your information for the following purposes:

a) Provide and Improve Service:
• Create and manage your account
• Connect you with local parents
• Show relevant groups, events, and content
• Process transactions and subscriptions
• Provide customer support
• Send service notifications
• Improve app features and user experience
• Develop new features

b) Safety and Security:
• Verify user identity
• Prevent fraud and abuse
• Monitor for prohibited content
• Enforce our Terms of Service
• Protect users from harm
• Investigate violations
• Comply with legal obligations

c) Communications:
• Send account-related emails
• Notify you of new messages and activity
• Send marketing communications (with consent)
• Respond to your inquiries
• Conduct surveys and research

d) Analytics and Research:
• Analyze usage patterns
• Understand user behavior
• Measure effectiveness of features
• Create aggregated statistics
• Research and development

e) Legal Compliance:
• Comply with legal obligations
• Respond to legal requests
• Enforce our rights
• Protect against legal claims''',
            ),
            _buildSection(
              '3. Legal Basis for Processing (GDPR)',
              '''Under GDPR, we process your data based on:

a) Contractual Necessity:
• Processing required to provide the Service
• Account creation and management
• Transaction processing
• Service delivery

b) Legitimate Interests:
• Improving and developing the Service
• Marketing and communications
• Fraud prevention and security
• Analytics and research
• Your interests are not overridden by these purposes

c) Legal Obligation:
• Compliance with UK and EU laws
• Responding to legal requests
• Tax and accounting requirements

d) Consent:
• Marketing communications
• Precise location tracking
• Optional data collection
• You may withdraw consent at any time

e) Vital Interests:
• Protecting safety of users
• Preventing harm
• Emergency situations''',
            ),
            _buildSection(
              '4. Data Sharing and Disclosure',
              '''a) Other Users:
Your profile information is visible to other users:
• Name, photo, and bio
• Location (postcode area only, not full address)
• Groups and events you join
• Public posts and comments
• Marketplace listings

Private information NOT shared:
• Email address
• Phone number
• Full postcode
• Payment information
• Private messages

b) Service Providers:
We share data with trusted third parties:
• Stripe: Payment processing
• Firebase/Google Cloud: Data hosting and authentication
• Analytics providers: Service improvement
• Customer support tools
• Email service providers

All providers bound by confidentiality agreements and GDPR compliance.

c) Business Transfers:
• In case of merger, acquisition, or sale of assets
• Your data may be transferred to successor entity
• You will be notified of any such transfer

d) Legal Requirements:
We may disclose information when required to:
• Comply with court orders or legal process
• Protect rights and safety of users
• Prevent fraud or security threats
• Enforce our Terms of Service
• Respond to government requests

e) Aggregated Data:
• We may share anonymized, aggregated statistics
• No personally identifiable information included
• Used for research, marketing, or public reports''',
            ),
            _buildSection(
              '5. Data Retention',
              '''a) Active Accounts:
• Data retained while your account is active
• Plus reasonable period to comply with legal obligations

b) Account Deletion:
• Most data deleted within 90 days of account deletion
• Some data retained for legal compliance:
  - Transaction records: 7 years (tax law)
  - Legal dispute records: Until resolved
  - Fraud prevention records: As needed

c) Backup Data:
• Data in backups deleted per backup schedule
• Maximum backup retention: 90 days

d) Marketing Data:
• Unsubscribe from marketing: data removed within 30 days
• Consent withdrawal: processing stops immediately

e) Legal Holds:
• Data preserved when subject to legal proceedings
• Retained until legal matter concluded''',
            ),
            _buildSection(
              '6. Your Rights Under GDPR',
              '''You have the following rights:

a) Right to Access:
• Request copy of your personal data
• Receive data in structured, machine-readable format
• Free of charge (first request)

b) Right to Rectification:
• Correct inaccurate data
• Complete incomplete data
• Update your profile anytime

c) Right to Erasure ("Right to be Forgotten"):
• Request deletion of your data
• Applies when:
  - Data no longer necessary
  - You withdraw consent
  - You object to processing
  - Data unlawfully processed
• Exceptions apply for legal obligations

d) Right to Restrict Processing:
• Limit how we use your data
• Data stored but not processed
• Applies when:
  - You contest data accuracy
  - Processing is unlawful
  - We no longer need data but you need it for legal claims

e) Right to Data Portability:
• Receive data in portable format
• Transfer data to another service
• Applies to data you provided

f) Right to Object:
• Object to processing based on legitimate interests
• Object to direct marketing anytime
• We must stop unless compelling legitimate grounds

g) Right to Withdraw Consent:
• Withdraw consent anytime
• Does not affect lawfulness of prior processing
• May limit Service availability

h) Right to Lodge Complaint:
• Complain to UK Information Commissioner's Office (ICO)
• Contact: https://ico.org.uk
• Email: casework@ico.org.uk
• Phone: 0303 123 1113

To exercise rights:
• Email: privacy@huddl.app
• In-app: Profile → Privacy & Security → Data Rights
• Response within 30 days''',
            ),
            _buildSection(
              '7. Data Security',
              '''a) Security Measures:
• Industry-standard encryption (TLS/SSL)
• Encrypted data storage
• Secure authentication (Firebase Auth)
• Regular security audits
• Access controls and monitoring
• Secure payment processing (PCI DSS compliant)

b) Your Responsibilities:
• Keep password secure
• Enable two-factor authentication
• Log out on shared devices
• Report suspicious activity
• Review privacy settings regularly

c) Data Breaches:
• We will notify you within 72 hours of discovery
• Notification includes:
  - Nature of breach
  - Data affected
  - Likely consequences
  - Measures taken
• Report to ICO as required by law

d) Limitations:
• No system is 100% secure
• You use Service at your own risk
• We cannot guarantee absolute security
• See Terms of Service for liability limitations''',
            ),
            _buildSection(
              '8. Children\'s Privacy',
              '''a) Age Requirement:
• Service is for users 18 years and older
• We do not knowingly collect data from children under 18
• If we learn of underage users, accounts are deleted

b) Children's Information:
• Do NOT post full names of children
• Do NOT share identifying information about children
• Only share children's ages for matching purposes
• Photos should not identify children by name publicly

c) Parental Responsibility:
• You are responsible for safeguarding children's information
• Obtain consent before sharing others' children's information
• Report any child safety concerns immediately''',
            ),
            _buildSection(
              '9. International Data Transfers',
              '''a) Data Location:
• Primary data stored in UK/EU data centers
• Service providers may be located outside UK/EU
• All transfers comply with GDPR requirements

b) Safeguards:
• Standard Contractual Clauses (SCCs)
• Adequacy decisions by UK/EU authorities
• Privacy Shield frameworks (where applicable)
• All providers meet GDPR standards

c) Your Rights:
• Rights apply regardless of data location
• You can request information about transfer safeguards''',
            ),
            _buildSection(
              '10. Cookies and Tracking',
              '''a) Cookies We Use:

Essential Cookies:
• Required for Service functionality
• Authentication and security
• Cannot be disabled

Performance Cookies:
• Analytics and usage tracking
• Service improvement
• Can be disabled in settings

Functional Cookies:
• Remember your preferences
• Enhance user experience
• Can be disabled in settings

Marketing Cookies:
• Track ad effectiveness (if applicable)
• Requires explicit consent
• Can opt out anytime

b) Third-Party Cookies:
• Analytics providers (Google Analytics)
• Payment processors (Stripe)
• Social media (if you use sharing features)
• Subject to third-party privacy policies

c) Cookie Control:
• Manage in app settings: Profile → Privacy → Cookie Preferences
• Browser settings to block cookies
• May affect Service functionality

d) Do Not Track:
• We honor Do Not Track signals where applicable
• May limit some features''',
            ),
            _buildSection(
              '11. Marketing Communications',
              '''a) Communications You Receive:

Service Communications (Cannot Opt Out):
• Account notifications
• Security alerts
• Transaction confirmations
• Important updates to Service or policies

Marketing Communications (Can Opt Out):
• Newsletter and tips
• New features announcements
• Special offers
• Community highlights

b) Opting Out:
• Click unsubscribe in any marketing email
• Profile → Notifications → Email Preferences
• Email: unsubscribe@huddl.app
• Opt-out processed within 48 hours

c) Re-subscribing:
• Update preferences anytime
• Opt back in through app settings''',
            ),
            _buildSection(
              '12. California Privacy Rights (CCPA)',
              '''If you are a California resident, you have additional rights:

a) Right to Know:
• Categories of data collected
• Sources of data
• Purpose of collection
• Third parties we share with

b) Right to Delete:
• Request deletion of your data
• Exceptions for legal obligations

c) Right to Opt Out of Sale:
• We do NOT sell your personal information
• No opt-out necessary

d) Right to Non-Discrimination:
• Equal service regardless of privacy choices
• No discrimination for exercising rights

e) Shine the Light:
• Request information about data sharing for marketing
• Contact: privacy@huddl.app''',
            ),
            _buildSection(
              '13. Changes to Privacy Policy',
              '''• We may update this policy periodically
• Material changes notified via:
  - Email to registered address
  - In-app notification
  - Notice on Service
• Changes effective upon posting
• Continued use constitutes acceptance
• Review policy regularly for updates
• Last updated date shown at top

Material changes include:
• New data collection practices
• Changes to data sharing
• Changes to your rights
• Changes to legal basis for processing''',
            ),
            _buildSection(
              '14. Contact Information',
              '''For privacy questions or to exercise your rights:

Email: privacy@huddl.app
Support: support@huddl.app

Data Protection Officer:
Email: dpo@huddl.app

Cruzen Ltd
[Company Registered Address]
Company Number: [Registration Number]

UK Information Commissioner's Office:
Website: https://ico.org.uk
Email: casework@ico.org.uk
Phone: 0303 123 1113

Response Time:
• Routine inquiries: 7 business days
• Rights requests: 30 days
• Urgent safety issues: 24 hours''',
            ),
            const SizedBox(height: 32),
            _buildDataProtectionSummary(),
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
                  'Version 1.0 - GDPR Compliant',
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

  Widget _buildGDPRNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user, color: AppColors.success, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GDPR Compliant',
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This policy complies with UK GDPR, EU GDPR, Data Protection Act 2018, and CCPA. Your privacy rights are protected.',
                  style: AppTextStyles.caption.copyWith(
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
              Icon(Icons.privacy_tip, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your Privacy Matters',
                  style: AppTextStyles.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Huddl ("we", "us", "our") operated by Cruzen Ltd is committed to protecting your privacy. This Privacy Policy explains how we collect, use, share, and protect your personal information when you use our Service.',
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

  Widget _buildDataProtectionSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Quick Summary - Your Rights',
                  style: AppTextStyles.h3.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRightItem('✓ Access your data anytime'),
          _buildRightItem('✓ Correct inaccurate information'),
          _buildRightItem('✓ Delete your account and data'),
          _buildRightItem('✓ Export your data (portability)'),
          _buildRightItem('✓ Opt out of marketing'),
          _buildRightItem('✓ Withdraw consent anytime'),
          _buildRightItem('✓ Lodge complaint with ICO'),
          const SizedBox(height: 12),
          Text(
            'Exercise your rights: Profile → Privacy & Security → Data Rights\nOr email: privacy@huddl.app',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.text2,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppTextStyles.body2.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
