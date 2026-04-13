import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

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
          'Terms of Service',
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
            _buildIntroduction(),
            const SizedBox(height: 24),
            _buildSection(
              '1. Acceptance of Terms',
              '''By accessing, downloading, installing, or using the Huddl mobile application and all related services ("Service", "App", "Platform"), you unconditionally agree to be bound by these Terms of Service ("Terms", "Agreement"). If you do not agree to these Terms in their entirety, you must immediately cease all use of the Service and uninstall the application.

These Terms constitute a legally binding agreement between you ("User", "you", "your") and Cruzen Ltd ("Company", "we", "us", "our"), a company registered in England and Wales. Your continued use of the Service, even after modifications to these Terms, constitutes your complete acceptance and agreement to comply with all provisions herein.

By using this Service, you acknowledge that you have read, understood, and agree to be bound by these Terms and our Privacy Policy, which is incorporated herein by reference.''',
            ),
            _buildSection(
              '2. Description of Service',
              '''Huddl is a community-based platform that provides various features including but not limited to:
• Social networking for parents and families
• Local community groups and connections (borough-specific)
• Direct messaging and group communications
• Event organization and meetup coordination
• Marketplace for buying and selling children's items
• AI-powered recommendations and matching
• Subscription management and premium features
• Third-party offers and deals integration
• User-generated content sharing (posts, photos, videos)
• Location-based services and borough filtering

THE SERVICE IS PROVIDED STRICTLY "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, OR AVAILABILITY.

We reserve the absolute right to modify, suspend, restrict, or discontinue any aspect, feature, or functionality of the Service at any time, with or without notice, for any reason or no reason, without liability to you or any third party.''',
            ),
            _buildSection(
              '3. User Eligibility and Account Security',
              '''You represent and warrant that you:
• Are at least 18 years of age
• Have the legal capacity and authority to enter into binding contracts under applicable law
• Are a parent, guardian, or caregiver (as the Service is designed for parenting communities)
• Will provide accurate, current, and complete registration information
• Will maintain the accuracy of such information
• Will not create multiple accounts or allow others to use your account
• Will maintain the security and confidentiality of your login credentials
• Will immediately notify us of any unauthorized use of your account

Account Security: You are solely and exclusively responsible for all activities conducted through your account, regardless of whether such activities were authorized by you. We are not liable for any loss or damage arising from unauthorized account access due to your failure to maintain account security.

Users who provide false information, violate eligibility requirements, or breach account security obligations will have their accounts immediately terminated without refund or recourse.''',
            ),
            _buildSection(
              '4. User Responsibilities, Conduct, and Prohibited Activities',
              '''a) General Conduct Requirements:
You agree to:
• Treat all users with respect, courtesy, and dignity
• Comply with all applicable local, national, and international laws
• Respect intellectual property rights of others
• Report violations of these Terms to our moderation team
• Use the Service only for lawful purposes
• Accept full responsibility for all content you create, share, or transmit

b) Strictly Prohibited Activities:
You must NOT:
• Post false, misleading, defamatory, or fraudulent content
• Share explicit, pornographic, violent, or otherwise inappropriate content
• Harass, threaten, stalk, intimidate, abuse, or harm other users
• Impersonate any person or entity, or misrepresent affiliation
• Create fake accounts, bot accounts, or multiple accounts
• Engage in spam, unsolicited advertising, or commercial solicitation
• Share, collect, or solicit personal information of minors (including full names, addresses, schools, or identifying photos)
• Post contact information of minors publicly
• Violate any applicable privacy laws or regulations
• Attempt to gain unauthorized access to the Service or other users' accounts
• Use automated systems, scripts, bots, or web scrapers to access the Service
• Reverse engineer, decompile, or attempt to extract source code
• Introduce viruses, malware, or harmful code
• Interfere with or disrupt the Service or servers
• Collect user data without explicit consent
• Sell, trade, or transfer your account to another party
• Use the Service for any illegal, fraudulent, or malicious purpose
• Post or promote hate speech, discrimination, or violence
• Engage in any activity that could harm the reputation of Cruzen Ltd

c) Content Ownership and Licensing:
• You retain ownership of content you create
• You grant Cruzen Ltd a worldwide, non-exclusive, royalty-free, perpetual, irrevocable, transferable, sublicensable license to use, reproduce, modify, adapt, publish, translate, create derivative works from, distribute, perform, and display your content in any media formats and channels
• You represent and warrant that you have all necessary rights to grant this license
• You must not post copyrighted material without proper authorization
• You waive all moral rights in your content to the maximum extent permitted by law

d) Consequences of Violation:
Violation of these terms may result in:
• Immediate account suspension or permanent termination
• Forfeiture of all paid subscriptions without refund
• Removal of all user-generated content
• Reporting to relevant authorities for illegal activity
• Legal action including claims for damages
• Permanent ban from creating new accounts''',
            ),
            _buildSection(
              '5. Comprehensive Limitation of Liability',
              '''TO THE MAXIMUM EXTENT PERMITTED UNDER APPLICABLE LAW:

a) NO LIABILITY FOR DAMAGES:
CRUZEN LTD, ITS PARENT COMPANIES, SUBSIDIARIES, AFFILIATES, DIRECTORS, OFFICERS, EMPLOYEES, AGENTS, CONTRACTORS, PARTNERS, LICENSORS, AND SERVICE PROVIDERS (COLLECTIVELY, "COMPANY PARTIES") SHALL NOT BE LIABLE UNDER ANY CIRCUMSTANCES FOR:

• Any direct, indirect, incidental, special, consequential, punitive, or exemplary damages of any kind whatsoever
• Loss of profits, revenue, business opportunities, goodwill, or reputation
• Loss or corruption of data or information
• Cost of procurement of substitute services
• Personal injury, emotional distress, or psychological harm
• Property damage of any nature
• Bodily injury or death arising from use of the Service
• Defamation, libel, or slander arising from user-generated content
• Financial losses from marketplace transactions
• Losses arising from unauthorized account access
• Damages resulting from reliance on information obtained through the Service
• Service interruptions, errors, bugs, or technical failures
• Security breaches, data breaches, or hacking incidents
• Third-party actions, services, content, or links
• Decisions or actions taken based on Service content
• Loss of use, data, or other intangibles
• Any matter beyond our reasonable control

b) DISCLAIMER OF ALL WARRANTIES:
THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT ANY WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED, OR STATUTORY, INCLUDING BUT NOT LIMITED TO:
• Warranties of merchantability, fitness for a particular purpose, or non-infringement
• Warranties that the Service will be uninterrupted, error-free, secure, or virus-free
• Warranties regarding accuracy, reliability, or completeness of content
• Warranties that defects will be corrected
• Warranties regarding results from Service use

c) USER INTERACTIONS AND SAFETY:
• You acknowledge and accept that you use the Service entirely at your own risk
• We are NOT responsible for the conduct, actions, or safety of any user
• We do NOT verify user identities, backgrounds, or credentials
• We do NOT guarantee the accuracy of user-provided information
• You are solely responsible for verifying information and identities
• You must exercise appropriate caution when meeting other users
• Always meet in public places and inform others of your whereabouts
• We are NOT liable for harm arising from interactions between users
• Report suspicious behavior, but understand we cannot guarantee timely response or action

d) AI AND ALGORITHMIC RECOMMENDATIONS:
• AI-generated content, recommendations, and matches are provided without warranty
• We are NOT liable for inaccurate, inappropriate, or harmful AI outputs
• AI features are experimental and may produce unexpected results
• You must independently verify all AI-generated information

e) MARKETPLACE AND TRANSACTIONS:
• We are NOT a party to transactions between users
• We do NOT verify item condition, authenticity, or legality
• We are NOT liable for fraud, disputes, or transaction failures
• Users bear all risks of marketplace transactions
• We do NOT provide buyer or seller protections

f) THIRD-PARTY CONTENT AND SERVICES:
• We are NOT responsible for third-party offers, deals, stores, or websites
• We do NOT endorse or guarantee third-party products or services
• Third-party content is provided "as is" without verification
• You access third-party services at your own risk

g) MAXIMUM LIABILITY CAP:
TO THE EXTENT LIABILITY CANNOT BE EXCLUDED BY LAW, OUR TOTAL AGGREGATE LIABILITY FOR ALL CLAIMS ARISING FROM OR RELATED TO THE SERVICE SHALL NOT EXCEED THE LESSER OF:
(i) The total amount you paid to Cruzen Ltd for the Service in the 12 months immediately preceding the claim; OR
(ii) £100 (one hundred British pounds sterling)

h) EXCLUSIONS AND LIMITATIONS APPLY TO ALL CLAIMS:
These limitations apply regardless of:
• The legal theory of liability (contract, tort, negligence, strict liability, or otherwise)
• Whether we were advised of the possibility of such damages
• Whether the limited remedy fails of its essential purpose
• Any failure of any agreed or other remedy

i) ACKNOWLEDGMENT:
BY USING THIS SERVICE, YOU EXPRESSLY ACKNOWLEDGE AND AGREE THAT:
• You have carefully read and understood this limitation of liability
• You voluntarily and knowingly assume all risks associated with using the Service
• These limitations are reasonable and fair given the free or low-cost nature of the Service
• You waive any rights you may have to bring claims against Company Parties
• This section shall survive termination of your account and these Terms''',
            ),
            _buildSection(
              '6. Comprehensive Indemnification',
              '''You agree to indemnify, defend, and hold harmless Cruzen Ltd and all Company Parties from and against any and all claims, damages, obligations, losses, liabilities, costs, debts, expenses (including but not limited to attorney's fees and legal costs), fines, penalties, and judgments arising from or related to:

• Your access to or use of the Service
• Your breach or violation of these Terms or any applicable law
• Your violation of any rights of any third party, including intellectual property rights, privacy rights, or contractual rights
• Any content you create, post, transmit, or make available through the Service
• Your conduct or interactions with other users, whether online or offline
• Any transaction or dispute in the marketplace
• Any event or meetup you organize or attend
• Any claim that your content caused damage to a third party
• Your failure to maintain account security
• Any negligent or wrongful conduct by you or anyone using your account
• Any misrepresentation made by you
• Any harm to minors arising from your actions
• Any defamatory, libelous, or slanderous statements you make
• Your use of AI features or reliance on AI recommendations

This indemnification obligation is unlimited in amount and duration, and survives termination of your account, termination of these Terms, and discontinuation of the Service. You agree to cooperate fully in the defense of any claim. We reserve the right to assume exclusive defense and control of any matter subject to indemnification, in which case you agree to cooperate with our defense of such claim.''',
            ),
            _buildSection(
              '7. Payment Terms and Subscription Management',
              '''a) Subscription Tiers:
• Welcome Tier (Free): Basic access with limited features
• Neighbour Tier (Paid): Full community access with AI tools
• Circle Tier (Paid): Unlimited access with exclusive AI features

Exact pricing, features, and limitations are displayed in-app and may be modified at our discretion.

b) Payment Processing:
• All payments are processed securely through Stripe or other third-party payment processors
• You authorize us to charge your payment method for all fees
• All prices are in British Pounds Sterling (GBP) and include applicable VAT where required
• Prices may change at any time; changes apply to subsequent billing periods

c) Auto-Renewal and Billing:
• Subscriptions automatically renew at the end of each billing period unless cancelled
• Monthly subscriptions renew every 30 days; annual subscriptions renew every 365 days
• You will be charged the then-current subscription price upon renewal
• You are responsible for all charges until cancellation takes effect

d) Cancellation and Refunds:
• You may cancel your subscription at any time via Profile → Settings → Subscription Management
• Cancellation takes effect at the end of the current billing period
• NO REFUNDS OR CREDITS will be provided for:
  - Partial subscription periods
  - Unused time on subscriptions
  - Account termination for Terms violations
  - Dissatisfaction with the Service
  - Service changes or discontinuation
  - Any other reason
• All sales are final and non-refundable
• You remain liable for all charges incurred prior to cancellation

e) Failed Payments:
• If payment fails, we may suspend or terminate your account
• You remain liable for all outstanding amounts plus collection costs
• We may use debt collection services for unpaid amounts

f) In-App Purchases:
• Purchases made through app stores (Apple App Store, Google Play Store) are subject to the respective store's terms and refund policies
• We have no control over app store billing or refunds
• Contact the respective app store for billing disputes

g) Taxes:
• You are responsible for all applicable taxes, duties, and assessments
• If we are required to collect or pay taxes, they will be added to your subscription fee''',
            ),
            _buildSection(
              '8. Privacy, Data Protection, and Security',
              '''a) Privacy Policy:
• Our Privacy Policy is incorporated into these Terms by reference
• By using the Service, you consent to all data practices described in our Privacy Policy
• You acknowledge that we collect, process, and share data as described
• Read our full Privacy Policy for detailed information

b) Data Collection and Use:
• We collect personal information, location data, usage data, and content you create
• We use data to provide, improve, and secure the Service
• We may share data with service providers, law enforcement, or as required by law
• You grant us broad rights to use and share your data as described in the Privacy Policy

c) GDPR and Data Protection Compliance:
• We comply with UK GDPR, EU GDPR, and Data Protection Act 2018
• You have rights to access, rectify, erase, and port your data
• Exercise rights via privacy@huddl.app or in-app settings
• We respond to valid requests within 30 days

d) No Guarantee of Security:
• While we implement security measures, we CANNOT GUARANTEE absolute security
• You acknowledge that no system is completely secure
• We are NOT LIABLE for security breaches, unauthorized access, or data loss
• You use the Service at your own risk regarding data security

e) Communications Monitoring:
• We reserve the right to monitor, record, and review all communications on the Service
• This includes messages, posts, and other content
• Monitoring may be used for safety, compliance, and quality purposes
• You consent to such monitoring by using the Service

f) Child Safety and COPPA Compliance:
• The Service is NOT intended for children under 18
• We do NOT knowingly collect data from children under 18
• Do NOT share personal information of minors (full names, addresses, schools, photos that identify them)
• You must obtain consent before posting photos or information about other people's children
• Report any child safety concerns immediately
• We may report suspected child abuse to authorities''',
            ),
            _buildSection(
              '9. Termination Rights and Effects',
              '''a) Termination by You:
• You may delete your account at any time via Profile → Settings → Delete Account
• Subscription cancellation must be done separately
• Account deletion is permanent and irreversible
• No refunds will be provided upon voluntary termination

b) Termination by Us:
We reserve the right to suspend, restrict, or permanently terminate your account immediately, without prior notice, without refund, and without liability, if:
• You breach any provision of these Terms
• You violate our Community Guidelines or policies
• You engage in fraudulent, illegal, or harmful activity
• You pose a safety or security risk to other users
• You fail to pay subscription fees
• We suspect unauthorized account access
• We are required to do so by law or court order
• We decide to discontinue the Service
• For any reason or no reason at our sole discretion

c) Effects of Termination:
Upon termination, immediately and automatically:
• Your right to access and use the Service ceases permanently
• Your account and all associated data may be deleted
• All subscriptions and purchases are forfeited without refund
• All content you created may be removed (subject to our license rights)
• You must immediately cease all use of the Service and uninstall the application
• You remain liable for all obligations incurred prior to termination

d) Survival of Terms:
The following provisions survive termination:
• Limitation of Liability
• Indemnification
• Intellectual Property Rights
• Dispute Resolution
• Governing Law
• Any other provisions that by their nature should survive

e) No Obligation to Retain Data:
• We have NO OBLIGATION to retain, provide, or restore your data after termination
• Back up any important data before account deletion
• We may delete all data immediately upon termination or retain it as described in our Privacy Policy''',
            ),
            _buildSection(
              '10. Intellectual Property Rights',
              '''a) Company Intellectual Property:
All content, features, functionality, software, code, designs, graphics, logos, trademarks, service marks, and other materials provided as part of the Service (excluding user-generated content) are owned exclusively by Cruzen Ltd or our licensors and are protected by:
• Copyright laws (UK, EU, US, and international)
• Trademark laws
• Patent laws
• Trade secret laws
• Other intellectual property rights and laws

You are granted only a limited, non-exclusive, non-transferable, revocable license to access and use the Service for personal, non-commercial purposes, strictly in accordance with these Terms. You have NO OTHER RIGHTS in the Service or Company intellectual property.

b) Restrictions on Use:
You must NOT:
• Copy, modify, reproduce, or create derivative works of the Service
• Distribute, sell, lease, license, or sublicense the Service
• Reverse engineer, decompile, disassemble, or attempt to extract source code
• Remove, alter, or obscure any copyright, trademark, or proprietary notices
• Use the Service or Company intellectual property for commercial purposes
• Frame, mirror, or inline link to the Service without written permission
• Use automated tools to access, scrape, or index the Service
• Build a competitive product or service
• Access the Service to build a similar or competing service

c) User-Generated Content License:
By posting, uploading, or submitting content to the Service, you grant Cruzen Ltd and our affiliates:
• A worldwide, non-exclusive, royalty-free, fully paid, transferable, sublicensable, perpetual, irrevocable license
• To use, reproduce, modify, adapt, publish, translate, create derivative works from, distribute, publicly perform, publicly display, and incorporate your content into other works in any format or medium now known or later developed
• This license survives termination of your account

d) Trademark Notice:
"Huddl" and associated logos are trademarks or registered trademarks of Cruzen Ltd. Unauthorized use is strictly prohibited and may result in legal action.

e) DMCA and Copyright Infringement:
• We respect intellectual property rights
• Report copyright infringement to legal@huddl.app
• We will respond to valid DMCA notices
• Repeat infringers will have accounts terminated
• False DMCA claims may result in liability under applicable law''',
            ),
            _buildSection(
              '11. Dispute Resolution, Governing Law, and Jurisdiction',
              '''a) Governing Law:
These Terms and any disputes arising from or relating to the Service shall be governed by and construed in accordance with the laws of England and Wales, without regard to conflict of law principles. The United Nations Convention on Contracts for the International Sale of Goods does not apply.

b) Exclusive Jurisdiction:
You irrevocably agree that the courts of England and Wales shall have exclusive jurisdiction to settle any dispute or claim arising out of or in connection with these Terms, the Service, or your use thereof. You waive any objection to venue or jurisdiction in these courts.

c) Mandatory Informal Dispute Resolution:
Before initiating any legal proceedings, you agree to first attempt to resolve the dispute informally by contacting legal@huddl.app with:
• A detailed description of the dispute
• Your account information
• The resolution you seek
• Supporting documentation

We will attempt good faith resolution for 60 days. Only after this period may you initiate formal proceedings.

d) Class Action and Jury Trial Waiver:
TO THE MAXIMUM EXTENT PERMITTED BY LAW, YOU AGREE THAT:
• All disputes must be brought individually, not as a class action, collective action, or representative proceeding
• You waive any right to participate in a class action or class-wide arbitration
• You waive any right to a jury trial
• You may only seek individualized relief

e) Limitation on Time to Bring Claims:
Any claim or cause of action arising from or related to the Service or these Terms must be filed within ONE (1) YEAR after the claim arose. After this period, such claims are permanently barred.

f) Legal Fees:
If we prevail in any legal proceeding related to these Terms, you agree to reimburse us for all legal fees, costs, and expenses incurred, including attorney's fees.

g) Equitable Relief:
You acknowledge that breach of these Terms may cause irreparable harm to Cruzen Ltd for which monetary damages would be inadequate. Therefore, we are entitled to seek equitable relief, including injunctive relief, without the need to post bond, in addition to all other remedies available at law or in equity.''',
            ),
            _buildSection(
              '12. AI Features and Algorithmic Content',
              '''a) AI-Powered Features:
The Service includes AI-powered features such as:
• Matchmaking and user recommendations
• Content recommendations (groups, events, marketplace items)
• Event and listing generation
• Offer and deal personalization
• Automated moderation and content filtering
• Predictive suggestions and insights

b) No Warranty for AI Accuracy:
• AI-generated content and recommendations are provided "as is" without warranty of accuracy, reliability, or completeness
• AI features may produce unexpected, inappropriate, or incorrect results
• We are NOT LIABLE for any reliance on AI-generated content
• You must independently verify all AI recommendations and outputs
• AI models are constantly evolving and results may change

c) Data Used for AI Training:
• Your content and usage data may be used to train and improve AI models
• By using the Service, you consent to this use
• You cannot opt out of AI data usage while using AI features

d) No Human Review Guarantee:
• AI moderation is automated; human review is not guaranteed
• We may not detect all prohibited content
• We are NOT LIABLE for harm from content that AI moderation fails to detect''',
            ),
            _buildSection(
              '13. Marketplace Terms and Transactions',
              '''a) Marketplace Function:
• The marketplace allows users to list, buy, and sell children's items
• Cruzen Ltd is NOT a party to transactions; we merely provide the platform
• We do NOT verify sellers, buyers, items, or information
• We do NOT handle payments for marketplace transactions

b) User Responsibilities:
• Sellers are solely responsible for item descriptions, condition, legality, and delivery
• Buyers are solely responsible for verifying items, meeting sellers, and payment
• You must comply with all applicable laws regarding sales and taxes

c) Prohibited Items:
You must NOT list:
• Illegal items or items that violate laws
• Stolen or counterfeit goods
• Items that infringe intellectual property rights
• Unsafe or recalled products
• Weapons, drugs, or controlled substances

d) No Liability for Transactions:
• We are NOT LIABLE for fraud, disputes, non-delivery, item condition, or any transaction issues
• We do NOT provide buyer or seller protections
• We do NOT mediate disputes between users
• We do NOT offer refunds or compensation for marketplace transactions
• All marketplace transactions are conducted AT YOUR OWN RISK

e) Safety Recommendations:
• Meet in public places
• Inspect items before payment
• Use secure payment methods
• Report suspicious activity''',
            ),
            _buildSection(
              '14. Events, Meetups, and In-Person Interactions',
              '''a) Event Organization:
• Users may create and organize events and meetups
• Event organizers are solely responsible for event planning, safety, and execution
• We are NOT responsible for events organized through the Service

b) Event Attendance:
• Attendees participate in events at their own risk
• Verify event details and organizer information independently
• Use caution when attending events with strangers

c) No Liability for Events:
• We are NOT LIABLE for any harm, injury, loss, or damage occurring at events
• This includes but is not limited to personal injury, property damage, emotional distress, or financial loss
• We do NOT verify event organizers, venues, or activities
• We do NOT provide insurance for events

d) Assumption of Risk:
• By attending events, you voluntarily assume all risks
• You waive all claims against Cruzen Ltd related to event attendance
• Event organizers and attendees are responsible for their own conduct and safety''',
            ),
            _buildSection(
              '15. Third-Party Services, Offers, and Links',
              '''a) Third-Party Integrations:
The Service may integrate with third-party services including:
• Stripe (payment processing)
• Firebase (data hosting and authentication)
• RevGlue (offers and deals)
• Google Maps (location services)
• Other service providers

b) Third-Party Offers and Deals:
• Third-party stores, offers, coupons, and deals are provided by external companies
• We do NOT endorse, verify, or guarantee these offers
• We are NOT LIABLE for third-party products, services, pricing, or availability
• Third-party offers are subject to their own terms and conditions

c) External Links:
• The Service may contain links to external websites
• We do NOT control or endorse linked websites
• We are NOT LIABLE for content, products, or services on external sites
• Access external links at your own risk

d) Service Provider Liability:
• We are NOT LIABLE for actions, errors, or failures of third-party service providers
• You acknowledge that third-party services may have their own terms and privacy policies
• Disputes with third parties must be resolved directly with them''',
            ),
            _buildSection(
              '16. Modifications to Terms and Service',
              '''a) Right to Modify Terms:
We reserve the right to modify, amend, or update these Terms at any time, for any reason or no reason, at our sole discretion, with or without notice. Changes may include:
• Adding new restrictions or obligations
• Removing features or rights
• Changing liability provisions
• Modifying pricing or subscription terms
• Any other modifications whatsoever

b) Notification of Changes:
• We may notify you of changes via email, in-app notification, or by posting updated Terms
• However, we have NO OBLIGATION to provide notice
• It is your responsibility to regularly review these Terms

c) Effective Date of Changes:
• Changes become effective immediately upon posting or at the date specified
• Continued use of the Service after changes constitutes your acceptance
• If you do not agree to changes, you must immediately stop using the Service and delete your account

d) No Refunds for Changes:
• No refunds will be provided if you disagree with Terms changes
• Paid subscriptions remain non-refundable regardless of modifications

e) Service Modifications:
We may at any time:
• Add, modify, or remove features
• Change pricing or subscription terms
• Restrict access to certain features or users
• Discontinue the Service entirely
• Without notice, liability, or refund obligation''',
            ),
            _buildSection(
              '17. Miscellaneous Legal Provisions',
              '''a) Entire Agreement:
These Terms, together with our Privacy Policy and any other legal notices or policies published by us, constitute the entire agreement between you and Cruzen Ltd regarding the Service and supersede all prior or contemporaneous communications, agreements, and understandings, whether written or oral.

b) Severability:
If any provision of these Terms is found to be invalid, illegal, or unenforceable by a court of competent jurisdiction, such provision shall be modified to the minimum extent necessary to make it valid and enforceable. If modification is not possible, the provision shall be severed, and the remaining provisions shall remain in full force and effect.

c) No Waiver:
Our failure to enforce any right or provision of these Terms shall not constitute a waiver of such right or provision. Any waiver must be in writing and signed by an authorized representative of Cruzen Ltd. No waiver of any term shall be deemed a further or continuing waiver of such term or any other term.

d) Assignment:
You may NOT assign, transfer, or delegate these Terms or your rights hereunder without our prior written consent. We may freely assign or transfer these Terms and all rights hereunder to any third party without your consent or notice. Any attempted assignment by you in violation of this provision is void.

e) Force Majeure:
We are NOT LIABLE for any failure or delay in performance due to causes beyond our reasonable control, including but not limited to acts of God, war, terrorism, riots, embargoes, acts of civil or military authorities, fire, floods, accidents, pandemics, strikes, shortages of transportation, fuel, energy, labor, or materials, or failures of telecommunications or internet infrastructure.

f) Relationship of Parties:
Nothing in these Terms creates any partnership, joint venture, agency, franchise, employment, or fiduciary relationship between you and Cruzen Ltd. You have no authority to bind Cruzen Ltd in any manner.

g) Third-Party Beneficiaries:
These Terms do not confer any third-party beneficiary rights. No third party may enforce any provision of these Terms.

h) Headings:
Section headings are for convenience only and shall not affect the interpretation of these Terms.

i) Language:
These Terms are drafted in English. Any translation is provided for convenience only. In the event of conflict between English and translated versions, the English version prevails.

j) Independent Investigation:
You acknowledge that you have independently evaluated the desirability of using the Service and are not relying on any representation, warranty, or statement other than as expressly set forth in these Terms.

k) Contact Information for Legal Matters:
Cruzen Ltd  
Legal Department  
Email: legal@huddl.app  
Support: support@huddl.app

For legal notices, service of process, or formal communications, contact legal@huddl.app.

l) Acknowledgment of Understanding:
BY USING THE SERVICE, YOU ACKNOWLEDGE THAT YOU HAVE READ THESE TERMS IN THEIR ENTIRETY, UNDERSTAND THEM, AND AGREE TO BE BOUND BY THEM. YOU FURTHER ACKNOWLEDGE THAT THESE TERMS CONSTITUTE A BINDING LEGAL AGREEMENT BETWEEN YOU AND CRUZEN LTD.

If you do not agree to these Terms, do not use the Service.''',
            ),
            const SizedBox(height: 8),
            _buildAcceptanceNotice(),
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
                  'Last Updated: April 2026',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primaryDark,
                  ),
                ),
                Text(
                  'Version 2.0 - Comprehensive Legal Protection',
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
              const Icon(Icons.description, color: HuddlColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Important Legal Notice',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'PLEASE READ THESE TERMS OF SERVICE CAREFULLY. BY ACCESSING, DOWNLOADING, INSTALLING, OR USING HUDDL, YOU ACKNOWLEDGE THAT YOU HAVE READ, UNDERSTOOD, AND AGREE TO BE LEGALLY BOUND BY THESE TERMS. IF YOU DO NOT AGREE, YOU MUST NOT USE THE SERVICE.',
            style: GoogleFonts.poppins(
                fontSize: 13, color: HuddlColors.textSecondary, height: 1.55, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Text(
            'These Terms include comprehensive limitations of liability, disclaimers of warranties, indemnification obligations, dispute resolution provisions, and other important legal terms that affect your rights.',
            style: GoogleFonts.poppins(
                fontSize: 12, color: HuddlColors.textSecondary, height: 1.5, fontStyle: FontStyle.italic),
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

  Widget _buildAcceptanceNotice() {
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
              const Icon(Icons.warning_rounded, color: HuddlColors.warning, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'By using Huddl, you agree to:',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildAcceptanceItem('• ALL comprehensive limitations of liability'),
          _buildAcceptanceItem('• Complete disclaimer of all warranties'),
          _buildAcceptanceItem('• Full indemnification of Cruzen Ltd'),
          _buildAcceptanceItem('• Strict no refund policy'),
          _buildAcceptanceItem('• Exclusive jurisdiction in England & Wales'),
          _buildAcceptanceItem('• Individual dispute resolution (no class actions)'),
          _buildAcceptanceItem('• All other terms and conditions stated above'),
          const SizedBox(height: 10),
          Text(
            'These Terms provide maximum legal protection to Cruzen Ltd. You use the Service entirely at your own risk.',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: HuddlColors.textSecondary,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptanceItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
