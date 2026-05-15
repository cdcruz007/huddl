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
              '''We collect various types of information to provide and improve our Service:

a) Information You Provide Directly:

Account Registration:
• Full name
• Email address
• Phone number (for authentication and account recovery)
• Password (encrypted and securely stored)
• Date of birth (for age verification - must be 18+)
• Postcode/location (for borough-based community matching)
• Profile photo (optional)
• Bio and profile information

Parenting Information:
• Parenting stage (expecting, new parent, toddler, etc.)
• Children's age ranges (not specific birthdates)
• Parenting preferences and interests

Content You Create:
• Posts, comments, and messages in groups and direct messages
• Photos, videos, and other media you upload
• Marketplace listings (items for sale, descriptions, prices, photos)
• Event and meetup creations (titles, descriptions, locations, dates)
• Reviews and ratings of other users or listings
• Saved messages and bookmarks
• Group creations and memberships

Payment Information:
• Payment card details (processed and stored by Stripe; we do NOT store full card numbers)
• Billing address
• Transaction history
• Subscription status and payment history

Communications:
• Support requests and correspondence
• Feedback and survey responses
• In-app communications and messages

b) Information Collected Automatically:

Device and Technical Information:
• Device type, model, and manufacturer
• Operating system and version (iOS, Android, Web)
• Unique device identifiers (IDFA, advertising ID, device ID)
• IP address and approximate location
• Browser type and version
• Mobile network information
• Screen resolution and device settings

Usage Data:
• Pages and features accessed
• Time spent on different screens
• Actions taken (clicks, taps, scrolls)
• Search queries and filters applied
• AI feature interactions
• Marketplace browsing behavior
• Events attended or created
• Groups joined or created
• Content views and engagement metrics
• App performance data and crash reports

Location Information:
• Precise GPS location (only with your explicit permission)
• Approximate location based on IP address
• Borough and postcode area
• Location shared in posts or events

c) Information from Third Parties:

• Authentication information from sign-in providers (if using social login)
• Payment verification from Stripe
• Analytics data from service providers
• Public information from linked social media profiles (if you choose to connect them)

d) Information from Cookies and Tracking Technologies:
• Cookies, local storage, and session storage
• Analytics and performance cookies
• Advertising identifiers
• Usage tracking pixels''',
            ),
            _buildSection(
              '2. How We Use Your Information',
              '''We use collected information for the following purposes:

a) Service Provision and Account Management:
• Create and manage your account
• Authenticate your identity and secure your account
• Process registrations and login requests
• Provide core Service features and functionality
• Enable communication between users (messaging, groups)
• Connect you with local parents in your borough
• Match you with relevant groups, events, and content
• Process and display marketplace listings
• Coordinate event attendance and organization

b) Personalization and Recommendations:
• AI-powered user matching and recommendations
• Personalized group suggestions based on your parenting stage
• Customized event recommendations based on location and interests
• Marketplace item recommendations using AI
• Tailored local event and meetup recommendations
• Borough-specific content filtering
• Customized in-app experiences

c) Payment Processing and Subscriptions:
• Process subscription payments and upgrades
• Manage billing and invoicing
• Detect and prevent payment fraud
• Provide payment-related customer support
• Issue refunds where applicable (as per our Terms)

d) Safety, Security, and Compliance:
• Verify user eligibility (age 18+)
• Detect and prevent fraud, spam, and abuse
• Monitor for prohibited content and behavior
• Enforce our Terms of Service and Community Guidelines
• Protect against security threats and unauthorized access
• Investigate violations and take appropriate action
• Respond to legal requests and comply with legal obligations
• Protect the rights, property, and safety of Cruzen Ltd, users, and the public

e) Communications:
• Send transactional emails (account verification, password resets, receipts)
• Notify you of new messages, comments, and activity
• Send updates about events you're attending or groups you've joined
• Provide customer support and respond to inquiries
• Send service announcements and important notices
• Send marketing communications (only with your consent; you may opt out)
• Conduct surveys and request feedback

f) Analytics, Research, and Improvement:
• Analyze usage patterns and user behavior
• Measure effectiveness of features and content
• Conduct A/B testing and experiments
• Identify bugs, errors, and performance issues
• Develop new features and services
• Create aggregated, anonymized statistics and reports
• Train and improve AI models and algorithms
• Understand user demographics and preferences

g) AI and Machine Learning:
• Train AI models using your content and usage data
• Improve recommendation algorithms
• Enhance content moderation and safety features
• Develop predictive features and insights
• Optimize user experience through machine learning

h) Legal and Business Operations:
• Comply with legal obligations and regulatory requirements
• Exercise or defend legal rights and claims
• Facilitate business transactions (mergers, acquisitions, asset sales)
• Maintain business records and documentation''',
            ),
            _buildSection(
              '3. Legal Basis for Processing (GDPR Compliance)',
              '''Under the UK GDPR, EU GDPR, and Data Protection Act 2018, we process your personal data based on the following legal grounds:

a) Contractual Necessity (Article 6(1)(b) GDPR):
Processing is necessary to perform our contract with you (Terms of Service):
• Account creation and authentication
• Providing Service features and functionality
• Processing payments and subscriptions
• Delivering content and communications
• Enabling user interactions

Without this processing, we cannot provide the Service to you.

b) Legitimate Interests (Article 6(1)(f) GDPR):
Processing is necessary for our legitimate business interests, which are not overridden by your rights and freedoms:
• Improving and developing the Service
• Personalizing user experience
• Conducting analytics and research
• Fraud prevention and security
• Network and information security
• Business administration and record-keeping
• Marketing to existing users about similar services

You have the right to object to processing based on legitimate interests.

c) Legal Obligation (Article 6(1)(c) GDPR):
Processing is necessary to comply with legal obligations:
• Responding to law enforcement requests
• Complying with court orders and legal processes
• Meeting tax and accounting requirements
• Fulfilling regulatory obligations

d) Consent (Article 6(1)(a) GDPR):
We obtain your explicit consent for:
• Precise GPS location tracking
• Marketing communications (newsletters, promotional emails)
• Non-essential cookies and tracking
• Sharing data with specific third parties beyond what is necessary for the Service
• Processing special categories of data (if applicable)

You may withdraw consent at any time via in-app settings or by contacting privacy@huddl.app. Withdrawal does not affect the lawfulness of processing before withdrawal.

e) Vital Interests (Article 6(1)(d) GDPR):
In rare cases, processing may be necessary to protect vital interests:
• Emergency situations requiring user contact
• Child safety concerns requiring immediate action

f) Special Categories of Data:
We do NOT intentionally collect special categories of personal data (racial or ethnic origin, political opinions, religious beliefs, health data, sexual orientation). If such data is inadvertently collected through user-generated content, processing is based on your explicit consent (Article 9(2)(a) GDPR) or another applicable legal basis.''',
            ),
            _buildSection(
              '4. Data Sharing, Disclosure, and Third-Party Access',
              '''a) Information Visible to Other Users:

Public Profile Information:
• Name and profile photo
• Bio and parenting stage
• Approximate location (borough/postcode area, NOT full address)
• Groups you have joined (group memberships are visible to other group members)
• Events you are attending
• Marketplace listings you create
• Public posts and comments

Private Information NOT Shared with Other Users:
• Email address
• Phone number
• Precise GPS location or full postcode
• Payment information
• Private messages (only visible to message participants)
• Personal data you do not choose to share publicly

b) Service Providers and Processors:

We share data with trusted third-party service providers who process data on our behalf under strict confidentiality and data protection agreements:

• Stripe: Payment processing, subscription billing, fraud detection
• Google Firebase / Google Cloud: Data hosting, cloud storage, authentication, push notifications
• Analytics Providers: Usage analytics, performance monitoring, crash reporting
• Customer Support Tools: Support ticket management
• Email Service Providers: Transactional and marketing emails
• Security Services: Fraud prevention, threat detection

All service providers are required to:
• Process data only as instructed by Cruzen Ltd
• Implement appropriate security measures
• Comply with GDPR and other applicable data protection laws
• Not use data for their own purposes

c) Third-Party Offers and Advertising Partners:
• We may share anonymized or aggregated data with offer and advertising partners
• We do NOT share personal identifiers without consent
• Third-party offers are governed by third-party privacy policies

d) Business Transfers:
In the event of a merger, acquisition, reorganization, asset sale, or bankruptcy:
• Your data may be transferred to the acquiring entity
• You will be notified via email or prominent notice on the Service
• The acquiring entity will be bound by this Privacy Policy unless you consent to a new policy

e) Legal Obligations and Safety:
We may disclose data when required or permitted by law:
• To comply with legal processes (subpoenas, court orders, warrants)
• To respond to law enforcement requests
• To protect our rights, property, or safety
• To protect the rights, property, or safety of users or the public
• To investigate or prevent fraud, security threats, or illegal activity
• To enforce our Terms of Service
• In child safety emergencies
• To comply with regulatory requirements

f) With Your Consent:
• We may share data with third parties if you provide explicit consent
• You may revoke consent at any time

g) Aggregated and Anonymized Data:
• We may share aggregated, anonymized data that does not identify you personally
• Such data may be used for research, analytics, marketing, or public reporting
• Anonymized data is not subject to this Privacy Policy''',
            ),
            _buildSection(
              '5. International Data Transfers',
              '''a) Data Storage Locations:
Your data is primarily stored and processed in:
• European Economic Area (EEA)
• United Kingdom
• United States (via Google Cloud and Firebase)

b) Transfer Safeguards:
When data is transferred outside the UK or EEA, we ensure adequate protection through:
• Standard Contractual Clauses (SCCs) approved by the European Commission
• Adequacy decisions by the UK or EU recognizing equivalent data protection
• Binding Corporate Rules
• Other lawful transfer mechanisms under GDPR

c) US Data Transfers:
Data transferred to the United States is protected by:
• Standard Contractual Clauses with service providers
• Service providers' compliance with recognized data protection frameworks
• Additional technical and organizational measures

d) Your Rights:
You have the right to obtain information about international transfers and the safeguards in place by contacting privacy@huddl.app.''',
            ),
            _buildSection(
              '6. Data Retention and Deletion',
              '''a) Active Account Data:
• Data is retained while your account is active and for as long as necessary to provide the Service
• You can update or delete certain data through in-app settings

b) Account Deletion:
When you delete your account:
• Most personal data is deleted within 30 days
• Some data may be retained for up to 90 days to allow for account recovery or dispute resolution
• Certain data is retained for longer periods as required by law or legitimate business needs

c) Data Retained After Account Deletion:

Transaction Records:
• Financial transaction data retained for 7 years (tax and accounting law requirements)
• Payment disputes and fraud prevention records

Legal and Compliance Records:
• Records related to legal claims, investigations, or regulatory requirements
• Data necessary to comply with legal obligations

Aggregated and Anonymized Data:
• Aggregated, anonymized data that does not identify you personally may be retained indefinitely for analytics and research

Content in Backups:
• Data in backups is deleted according to backup schedules (typically within 90 days)
• Backup deletion may take longer depending on technical constraints

d) Fraud Prevention:
• If your account was terminated for fraud or Terms violations, certain data may be retained indefinitely to prevent future abuse

e) User-Generated Content:
• Content you shared in public groups may remain visible to other users even after account deletion (but will no longer be attributed to you)
• Private messages may be retained for the other party's access unless both parties delete them

f) Retention Period Summary:
• Active accounts: Duration of Service use
• Deleted accounts: 30-90 days (most data)
• Transaction records: 7 years
• Legal/compliance records: As required by law
• Anonymized data: Indefinitely

g) Your Right to Erasure:
• You may request deletion of your data at any time (subject to legal retention requirements)
• Contact privacy@huddl.app to exercise this right''',
            ),
            _buildSection(
              '7. Your Rights Under Data Protection Laws',
              '''Under UK GDPR, EU GDPR, Data Protection Act 2018, and CCPA, you have the following rights:

a) Right to Access (GDPR Article 15, CCPA):
• Request a copy of all personal data we hold about you
• Receive information about how your data is processed
• Obtain data in a structured, commonly used, machine-readable format
• Exercise via: Profile → Privacy & Security → Download My Data or email privacy@huddl.app

b) Right to Rectification (GDPR Article 16):
• Correct inaccurate or incomplete personal data
• Update your profile information directly in-app or request corrections via privacy@huddl.app

c) Right to Erasure / Right to Delete (GDPR Article 17, CCPA):
• Request deletion of your personal data
• Note: Some data may be retained as described in Section 6 (legal obligations, legitimate interests)
• Exercise via: Profile → Settings → Delete Account or email privacy@huddl.app

d) Right to Restrict Processing (GDPR Article 18):
• Request limitation of how we process your data in certain circumstances:
  - You contest the accuracy of data
  - Processing is unlawful but you oppose erasure
  - We no longer need the data but you need it for legal claims
  - You have objected to processing pending verification of legitimate grounds

e) Right to Data Portability (GDPR Article 20):
• Receive your data in a portable format (JSON or CSV)
• Transmit your data to another service provider
• Applies to data you provided based on consent or contract

f) Right to Object (GDPR Article 21):
• Object to processing based on legitimate interests
• Object to direct marketing at any time (we will stop immediately)
• Object to profiling and automated decision-making
• Exercise via: Profile → Privacy & Security → Marketing Preferences or email privacy@huddl.app

g) Right to Withdraw Consent (GDPR Article 7(3)):
• Withdraw consent for processing based on consent at any time
• Withdrawal does not affect lawfulness of processing before withdrawal
• Exercise via: in-app settings or email privacy@huddl.app

h) Right to Lodge a Complaint (GDPR Article 77):
• File a complaint with a supervisory authority if you believe your rights have been violated
• UK: Information Commissioner's Office (ICO) - https://ico.org.uk or call 0303 123 1113
• EU: Contact your local data protection authority

i) Rights Regarding Automated Decision-Making (GDPR Article 22):
• Right not to be subject to solely automated decisions with legal or significant effects
• Right to human review of AI-generated recommendations
• Currently, our AI features provide recommendations but do not make decisions with legal effects

j) California Residents (CCPA Rights):
If you are a California resident, you have additional rights:
• Right to know what personal information is collected, used, shared, or sold
• Right to delete personal information
• Right to opt out of the "sale" of personal information (we do NOT sell personal information)
• Right to non-discrimination for exercising CCPA rights

k) How to Exercise Your Rights:
• Email: privacy@huddl.app with your request and account information
• In-App: Profile → Privacy & Security → Data Rights
• Response Time: We will respond within 30 days (may be extended by 60 days for complex requests)
• Verification: We may request additional information to verify your identity before processing requests
• No Fee: Rights requests are free unless requests are manifestly unfounded or excessive

l) Limitations on Rights:
Certain rights may be limited or refused if:
• Necessary to comply with legal obligations
• Required to establish, exercise, or defend legal claims
• Necessary for reasons of public interest
• Processing is necessary for the performance of a contract''',
            ),
            _buildSection(
              '8. Data Security and Protection Measures',
              '''a) Technical Security Measures:
• Industry-standard TLS/SSL encryption for data in transit
• AES-256 encryption for data at rest
• Secure authentication via Firebase Auth with password hashing (bcrypt)
• Regular security audits and vulnerability assessments
• Intrusion detection and prevention systems
• Secure API endpoints with authentication and authorization
• Regular security updates and patches

b) Organizational Security Measures:
• Access controls and role-based permissions (principle of least privilege)
• Employee security training and confidentiality agreements
• Background checks for employees with data access
• Incident response and data breach procedures
• Regular security policy reviews and updates
• Data minimization and privacy by design principles

c) Payment Security:
• PCI DSS Level 1 compliant payment processing via Stripe
• We do NOT store full credit card numbers or CVV codes
• Tokenized payment information only
• Secure payment forms with encryption

d) Data Breach Notification:
In the event of a data breach affecting personal data:
• We will notify affected users via email within 72 hours of discovery (as required by GDPR)
• We will notify the Information Commissioner's Office (ICO) within 72 hours where required
• Notification will include:
  - Nature of the breach
  - Categories and approximate number of affected users
  - Likely consequences
  - Measures taken or proposed to address the breach
  - Contact information for further inquiries

e) Limitations of Security:
While we implement robust security measures, please understand:
• NO system is 100% secure
• We CANNOT GUARANTEE absolute security of your data
• You transmit data at your own risk
• You are responsible for maintaining the security of your account credentials
• We are NOT LIABLE for unauthorized access resulting from your failure to secure your account

f) Your Security Responsibilities:
• Use a strong, unique password
• Enable two-factor authentication if available
• Do not share your password with others
• Log out of shared devices
• Report suspicious activity immediately
• Keep your device and apps updated''',
            ),
            _buildSection(
              '9. Children\'s Privacy and Child Safety',
              '''a) Age Restriction:
• The Service is ONLY for users aged 18 years and older
• We do NOT knowingly collect personal data from individuals under 18
• By using the Service, you represent and warrant that you are at least 18 years old

b) Parental Responsibility:
• This is a parenting community; we understand users will discuss their children
• You are responsible for what information you share about your children
• You must have authority to share information and photos of children in your care

c) Prohibited Sharing of Children's Information:
You must NOT share publicly:
• Children's full names (first and last name together)
• Children's specific birthdates (year of birth or age ranges are acceptable)
• Children's home addresses, school names, or precise locations
• Photos that could be used to identify or locate children
• Any information that could pose a safety risk to children

d) Photos of Other People's Children:
• You must NOT post photos of other people's children without explicit permission from their parents/guardians
• Violation of this policy will result in immediate account termination

e) Child Safety Concerns:
If you suspect child abuse, exploitation, or safety concerns:
• Report immediately to: safety@huddl.app
• We will investigate and take appropriate action
• We may report suspected child abuse to relevant authorities as required by law
• We cooperate fully with law enforcement in child safety investigations

f) Underage User Detection:
If we discover a user is under 18:
• Account will be immediately terminated
• Personal data will be deleted as soon as reasonably possible
• We may retain records as necessary for legal compliance

g) COPPA Compliance:
• Our Service is not directed at children under 13
• We do not knowingly collect data from children under 13
• If you believe we have inadvertently collected data from a child under 13, contact privacy@huddl.app immediately''',
            ),
            _buildSection(
              '10. Cookies, Tracking Technologies, and Analytics',
              '''a) Types of Technologies Used:

Essential Cookies:
• Session management and authentication
• Security and fraud prevention
• Load balancing and performance optimization
• Cannot be disabled as they are necessary for Service functionality

Analytics Cookies:
• Usage analytics and performance metrics
• User behavior tracking and heatmaps
• A/B testing and feature experimentation
• Crash reporting and error tracking

Advertising and Marketing Cookies:
• Third-party offer personalization
• Marketing campaign effectiveness measurement
• Retargeting and remarketing (with consent)

b) Specific Technologies:
• Firebase Analytics: Usage and performance data
• Google Analytics: Web analytics (if applicable)
• Crashlytics: Crash and error reporting
• Local Storage: App preferences and session data
• Advertising Identifiers: IDFA (iOS), AAID (Android)

c) Cookie Management:
• You can manage cookie preferences via: Profile → Privacy & Security → Cookie Settings
• Disabling certain cookies may affect Service functionality
• Essential cookies cannot be disabled

d) Do Not Track (DNT):
• Currently, we do not respond to browser Do Not Track signals
• You can control tracking through in-app settings

e) Third-Party Analytics:
• Third-party analytics providers may collect data across multiple services
• Review their privacy policies for more information on their data practices

f) Mobile Device Identifiers:
• You can reset your device's advertising identifier in device settings:
  - iOS: Settings → Privacy → Advertising → Reset Advertising Identifier
  - Android: Settings → Google → Ads → Reset Advertising ID''',
            ),
            _buildSection(
              '11. AI, Machine Learning, and Automated Decision-Making',
              '''a) AI Features and Use Cases:
The Service uses AI and machine learning for:
• User matching and friend recommendations
• Group recommendations based on parenting stage and interests
• Event recommendations based on location and preferences
• Marketplace item recommendations
• Offer and deal personalization
• Content moderation and safety filtering
• Search result ranking
• Spam and abuse detection
• Predictive text and autocomplete

b) Data Used for AI:
AI models are trained and improved using:
• Your profile information and preferences
• Your interactions (clicks, likes, joins, saves)
• Content you create and share
• Search queries and browsing behavior
• Location and borough data
• Aggregated usage patterns across all users

c) AI Training Consent:
• By using the Service, you consent to your data being used to train AI models
• You cannot opt out of AI data usage while using AI-powered features
• AI training data is anonymized where possible

d) Transparency and Explainability:
• AI recommendations are based on similarity algorithms and behavioral patterns
• You can view why content was recommended (when technically feasible)
• You can provide feedback on recommendations to improve AI

e) Right to Object to Automated Decisions:
• You have the right to object to automated decision-making with legal or significant effects
• Currently, AI features provide recommendations but do not make decisions with legal effects (e.g., automated account suspensions are reviewed by humans)
• You can request human review of AI-generated content moderation decisions

f) AI Limitations and Risks:
• AI may produce inaccurate, biased, or inappropriate results
• AI cannot guarantee perfect content moderation
• We are NOT LIABLE for harm from AI errors or limitations
• You must independently verify AI recommendations

g) AI Model Updates:
• AI models are continuously updated and improved
• Model updates may change recommendation behavior
• We do not notify users of AI model changes''',
            ),
            _buildSection(
              '12. Marketing Communications and Opt-Out',
              '''a) Types of Communications:

Transactional Communications (Cannot Opt Out):
• Account verification and password reset emails
• Payment receipts and subscription confirmations
• Important Service updates and security alerts
• Responses to support requests
• Legal notices and Terms updates

Promotional Communications (Can Opt Out):
• Marketing emails about new features
• Newsletters and community highlights
• Local events and meetup recommendations
• Surveys and feedback requests
• Event recommendations and invitations

b) How We Obtain Consent:
• During account registration (opt-in checkbox)
• Via in-app prompts and banners
• Through explicit consent requests

c) How to Opt Out of Marketing:
• Click "Unsubscribe" link in any marketing email
• Via: Profile → Settings → Notifications → Marketing Preferences
• Email: privacy@huddl.app with subject "Unsubscribe"
• We will process opt-out requests within 10 business days

d) Re-Consent:
• You can opt back in to marketing at any time via in-app settings

e) Third-Party Marketing:
• We do NOT share your email with third parties for their direct marketing without explicit consent
• Third-party offers shown in-app are not direct email marketing''',
            ),
            _buildSection(
              '13. Changes to This Privacy Policy',
              '''a) Right to Modify:
We reserve the right to modify this Privacy Policy at any time for any reason, including to:
• Reflect changes in data practices
• Comply with new legal requirements
• Improve clarity and transparency
• Add new features or services

b) Notification of Changes:
• We will notify you of material changes via email or prominent in-app notice
• Non-material changes may be posted without individual notification
• Effective date of changes will be clearly indicated

c) Review Responsibility:
• It is your responsibility to periodically review this Privacy Policy
• Check the "Last Updated" date at the top

d) Continued Use:
• Continued use of the Service after changes constitutes acceptance of the updated Privacy Policy
• If you do not agree to changes, you must stop using the Service and delete your account

e) No Refunds:
• No refunds will be provided for Privacy Policy changes you disagree with''',
            ),
            _buildSection(
              '14. Contact Information and Data Protection Officer',
              '''For privacy questions, to exercise your rights, or to contact our Data Protection Officer:

Email Contacts:
• General Privacy Inquiries: privacy@huddl.app
• Data Protection Officer: dpo@huddl.app
• Data Rights Requests: privacy@huddl.app
• Security Concerns: security@huddl.app
• Child Safety Reports: safety@huddl.app
• General Support: support@huddl.app

Postal Address:
Cruzen Ltd  
Data Protection / Privacy Team  
[Company Registered Address to be provided]  
United Kingdom

Response Time:
• We aim to respond to all privacy inquiries within 30 days
• Complex requests may require up to 60 additional days (we will notify you if extension is needed)

UK Supervisory Authority:
Information Commissioner's Office (ICO)  
Website: https://ico.org.uk  
Telephone: 0303 123 1113  
Email: casework@ico.org.uk

You have the right to lodge a complaint with the ICO if you believe we have violated your data protection rights.''',
            ),
            _buildSection(
              '15. Additional Legal Disclosures',
              '''a) Data Controller:
Cruzen Ltd is the data controller responsible for your personal data under UK GDPR and EU GDPR.

b) Legal Basis Summary:
Processing is primarily based on:
• Contract performance (Terms of Service)
• Legitimate interests (Service improvement, security)
• Legal obligations (compliance, law enforcement)
• Consent (marketing, precise location, non-essential processing)

c) No Sale of Personal Data:
• We do NOT sell personal data to third parties
• We do NOT rent or trade personal data
• We may share anonymized, aggregated data for research or business purposes

d) Cross-Border Data Transfers:
• Data is transferred internationally with appropriate safeguards (Standard Contractual Clauses)
• Primary storage locations: UK, EEA, United States

e) Data Processor Agreements:
• All third-party processors are bound by data processing agreements (DPAs)
• Processors must comply with GDPR and equivalent data protection standards

f) Privacy by Design:
• We implement privacy by design and default principles
• Data minimization: We collect only necessary data
• Purpose limitation: Data used only for specified purposes
• Storage limitation: Data retained only as long as necessary

g) Accountability:
• We maintain records of processing activities
• We conduct Data Protection Impact Assessments (DPIAs) for high-risk processing
• We regularly review and update data protection practices

h) Data Breach Response:
• Documented incident response plan
• 72-hour notification to ICO (where required)
• User notification for high-risk breaches

i) Limitation of Liability:
• While we take data protection seriously, we are NOT LIABLE for:
  - Data breaches caused by factors outside our reasonable control
  - Unauthorized access due to your failure to secure your account
  - Third-party data breaches
• See Terms of Service for complete limitation of liability

j) Governing Law:
• This Privacy Policy is governed by the laws of England and Wales
• Disputes subject to exclusive jurisdiction of English courts

k) Language:
• This Privacy Policy is drafted in English
• Translations provided for convenience only; English version prevails in case of conflict''',
            ),
            _buildSection(
              '16. Voice Messages & Microphone Access',
              '''a) Overview:
Huddl provides a voice message feature that allows you to record and send short audio messages within group chats and direct messages. This section explains specifically how we handle microphone access and voice message data.

b) Microphone Permission:
• We request access to your device microphone solely to enable voice message recording
• The android.permission.RECORD_AUDIO (Android) and NSMicrophoneUsageDescription (iOS) permissions are used exclusively for this feature
• Microphone access is only active during the brief period you are actively recording a voice message
• We do NOT listen to, record, or access your microphone at any other time
• You may deny or revoke microphone permission at any time in your device settings — this will disable voice message recording but will not affect any other feature

c) Data Collected:
• Audio recordings: Temporary audio files (M4A/AAC format on mobile, WebM on web) created during recording
• Recording metadata: Duration (in seconds) and timestamp of recording
• Conversation context: The group or direct message conversation the voice message was sent in
• Sender identity: Your user ID is associated with each voice message you send

d) How Voice Message Data Is Processed:
• Temporary local file: A short-lived audio file is created in your device's temporary directory during recording
• Upload to Firebase Storage: Upon sending, the audio file is uploaded to Firebase Cloud Storage under a path scoped to the conversation (e.g. voice_notes/{conversationId}/{userId}_{timestamp}.m4a)
• Transmission: Audio data is transmitted over an encrypted HTTPS connection
• Local file deletion: The temporary file on your device is deleted immediately after successful upload
• Playback: Stored voice messages are retrieved from Firebase Storage via a secure download URL for playback within the app

e) Legal Basis for Processing (UK GDPR Article 6):
• Consent (Article 6(1)(a)): Voice message recording and sending is based on your freely given, specific, informed, and unambiguous consent — granted when you explicitly enable voice messages in your Profile settings. You may withdraw consent at any time.
• Contract performance (Article 6(1)(b)): Transmission and storage of sent voice messages is necessary to deliver the messaging service you have contracted for.

f) Your Consent Controls:
• You must actively enable voice messages in Profile → Privacy & Security → Voice Messages before you can record or send audio
• You may withdraw consent at any time by toggling this setting off — this will prevent future recordings; it will not automatically delete previously sent voice messages already received by other participants
• To delete voice messages you have already sent, contact us at privacy@huddl.app

g) Data Retention:
• Voice messages are retained for as long as the conversation they belong to exists, or until you delete your account
• When you delete your Huddl account (Profile → Privacy & Security → Delete my account & data), all voice messages stored in Firebase Storage under your user ID are permanently deleted
• Temporary recording files on your device are deleted immediately after upload (or immediately if you cancel the recording)

h) Data Sharing:
• Voice messages are accessible to all participants in the group or direct message conversation they were sent in
• Firebase Storage (Google LLC) acts as our data processor for audio file storage. Firebase complies with GDPR through Standard Contractual Clauses. See Google's privacy policy at https://policies.google.com/privacy
• Voice message audio is NOT shared with any other third parties, used for advertising, or used to train AI models

i) Children and Sensitive Data:
• Huddl is restricted to users aged 18 and over. Voice messages are never collected from minors.
• Audio recordings are not considered special category data under UK GDPR Article 9; however, we apply equivalent care to their handling

j) Your Rights Regarding Voice Messages:
• Right of access (Article 15): You may request a list of voice messages associated with your account
• Right to erasure (Article 17): Contact privacy@huddl.app to request deletion of specific voice messages
• Right to withdraw consent (Article 7(3)): Toggle off voice messages in Profile → Privacy & Security at any time; withdrawal does not affect the lawfulness of processing carried out before withdrawal
• Right to object (Article 21): You may object to voice message processing by disabling the feature and contacting dpo@huddl.app

k) Security Measures:
• All audio data in transit is encrypted using TLS 1.2+
• Firebase Storage enforces access control rules limiting read/write access to authenticated participants of the relevant conversation
• Temporary local audio files are stored in the operating system's sandboxed temporary directory and are not accessible to other apps

l) Contact:
For any questions about voice message data processing, contact our Data Protection Officer at dpo@huddl.app.''',
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
        color: HuddlColors.primary.withValues(alpha: 0.08),
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
                  'Last Updated: May 2026',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primaryDark,
                  ),
                ),
                Text(
                  'Version 2.1 - Voice Message & Microphone Data Added',
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
                  'Fully GDPR & CCPA Compliant',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.teal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This Privacy Policy complies with UK GDPR, EU GDPR, Data Protection Act 2018, CCPA, and international data protection standards. Your privacy rights are fully protected.',
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
            'Huddl ("we", "us", "our"), operated by Cruzen Ltd, is committed to protecting your privacy and personal data. This Privacy Policy explains in detail how we collect, use, share, protect, and retain your information when you use our Service.',
            style: GoogleFonts.poppins(
                fontSize: 13, color: HuddlColors.textSecondary, height: 1.55),
          ),
          const SizedBox(height: 8),
          Text(
            'By using Huddl, you acknowledge that you have read, understood, and agree to the data practices described in this Privacy Policy.',
            style: GoogleFonts.poppins(
                fontSize: 12, color: HuddlColors.textSecondary, height: 1.5, fontWeight: FontWeight.w500),
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
        color: HuddlColors.white,
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
                  'Your Data Protection Rights Summary',
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
          _buildRightItem('✓ Access your data anytime (download full copy)'),
          _buildRightItem('✓ Correct inaccurate or incomplete data'),
          _buildRightItem('✓ Delete your account and data'),
          _buildRightItem('✓ Export your data in portable format'),
          _buildRightItem('✓ Restrict or object to certain processing'),
          _buildRightItem('✓ Opt out of marketing communications'),
          _buildRightItem('✓ Withdraw consent for consent-based processing'),
          _buildRightItem('✓ Lodge complaint with ICO or data protection authority'),
          const SizedBox(height: 12),
          Text(
            'Exercise your rights:\n• In-App: Profile → Privacy & Security → Data Rights\n• Email: privacy@huddl.app\n• Response within 30 days',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: HuddlColors.textSecondary,
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We take your privacy seriously and are committed to transparency, accountability, and compliance with all applicable data protection laws.',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: HuddlColors.textSecondary,
              fontWeight: FontWeight.w500,
              height: 1.4,
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
