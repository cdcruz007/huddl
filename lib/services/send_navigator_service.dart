import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'ai_api_helper.dart';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

// ─── Typed AI error ───────────────────────────────────────────────────────────

/// Thrown when the Gemini / Vertex AI call fails.
/// [isConfigError] = true means the API key is blocked or missing (403/401)
///   — the user cannot retry; a developer action is required.
/// [isConfigError] = false means a transient network or timeout failure —
///   the user can try again.
class SendAiException implements Exception {
  final String message;
  final bool isConfigError;
  const SendAiException(this.message, {this.isConfigError = false});
  @override
  String toString() => 'SendAiException($message, configError=$isConfigError)';
}

// =============================================================================
// SEND NAVIGATOR SERVICE
//
// Powers Huddl's SEND / Complex Needs hub — a structured, AI-assisted
// navigation layer for parents of children with Special Educational Needs
// and Disabilities.
//
// This is NOT a general parenting feature. It is a high-urgency, premium
// feature targeting a deeply underserved group: parents navigating the UK
// SEND system (EHCP, school placements, tribunal appeals, funding).
//
// Five capability areas:
//
//  1. EhcpJourney           — Stateful EHCP process tracker. Stores which
//                             stage the parent is at, surfaces step-by-step
//                             guidance, timelines, template letters.
//
//  2. DeadlineTracker       — Borough-aware deadline list. School application
//                             windows, EHCP review dates, appeal deadlines,
//                             tribunal windows. Stored in BrowserStorage.
//
//  3. AiEhcpAdvisor         — Gemini-powered Q&A grounded in UK SEND law,
//                             IPSEA guidance, and SEND Code of Practice 2015.
//                             Conversational, warm, legally-aware.
//
//  4. AnonQaSession         — Anonymous Q&A: parent submits a question,
//                             AI answers. No name, no UID attached.
//                             Stored ephemerally (session only — not Firestore).
//
//  5. SendResourceDirectory — Curated, structured resource list by need type
//                             (autism, ADHD, speech, SpLD, physical, complex).
//
// Moat: Structured + AI-assisted vs. chaotic Facebook groups.
//       Contact, Sibs, Family Fund already in KB — this surfaces them at the
//       right moment in the EHCP journey, not buried in general articles.
// =============================================================================

// ─── EHCP Stage enum ──────────────────────────────────────────────────────────

/// The 8 major stages of the UK EHCP process.
/// Parents pick where they are → get stage-appropriate guidance.
enum EhcpStage {
  notStarted,        // "I think my child might need support"
  requestingAssessment, // Submitted EHC needs assessment request
  awaitingDecision,  // LA deciding whether to assess (6-week window)
  beingAssessed,     // Assessment underway (EPs, SALTs, OTs, etc.)
  draftReceived,     // Draft EHCP received — 15-day consultation window
  finalIssued,       // Final EHCP issued — school named, provision detailed
  annualReview,      // Annual review meeting scheduled / in progress
  appealing,         // SENDIST / First-tier Tribunal appeal lodged
}

extension EhcpStageX on EhcpStage {
  String get displayTitle => switch (this) {
        EhcpStage.notStarted           => 'Starting out',
        EhcpStage.requestingAssessment => 'Requesting assessment',
        EhcpStage.awaitingDecision     => 'Awaiting LA decision',
        EhcpStage.beingAssessed        => 'Assessment underway',
        EhcpStage.draftReceived        => 'Draft EHCP received',
        EhcpStage.finalIssued          => 'Final EHCP issued',
        EhcpStage.annualReview         => 'Annual review',
        EhcpStage.appealing            => 'Tribunal / appeal',
      };

  String get subtitle => switch (this) {
        EhcpStage.notStarted           => 'I think my child needs more support',
        EhcpStage.requestingAssessment => 'I\'ve submitted a request to the local authority',
        EhcpStage.awaitingDecision     => 'Waiting to hear if they\'ll assess',
        EhcpStage.beingAssessed        => 'Professionals are assessing my child',
        EhcpStage.draftReceived        => 'I\'ve received a draft plan to review',
        EhcpStage.finalIssued          => 'We have a final plan — checking provision',
        EhcpStage.annualReview         => 'Plan is being reviewed this year',
        EhcpStage.appealing            => 'Challenging the LA\'s decision',
      };

  String get storageValue => name;

  static EhcpStage fromString(String v) {
    try {
      return EhcpStage.values.firstWhere((e) => e.name == v);
    } catch (_) {
      return EhcpStage.notStarted;
    }
  }
}

// ─── EHCP Guidance ────────────────────────────────────────────────────────────

/// Structured guidance for one EHCP stage.
class EhcpStageGuidance {
  final EhcpStage stage;
  final String headline;
  final String timelineNote; // Key statutory deadline or window
  final List<String> nextSteps;
  final List<String> yourRights;
  final List<SendResource> resources;
  final String? templateLetterHint; // What template letter to request

  const EhcpStageGuidance({
    required this.stage,
    required this.headline,
    required this.timelineNote,
    required this.nextSteps,
    required this.yourRights,
    required this.resources,
    this.templateLetterHint,
  });
}

// ─── SEND Resource ────────────────────────────────────────────────────────────

enum SendNeedType {
  autism,
  adhd,
  speechLanguage,
  physicalDisability,
  sensoryImpairment,
  learningDifficulty, // SpLD: dyslexia, dyscalculia, dyspraxia
  mentalHealth,
  complexNeeds,       // Multiple / profound and multiple learning difficulties
  general,            // Any SEND
}

extension SendNeedTypeX on SendNeedType {
  String get displayLabel => switch (this) {
        SendNeedType.autism            => 'Autism / ASD',
        SendNeedType.adhd              => 'ADHD',
        SendNeedType.speechLanguage    => 'Speech & Language',
        SendNeedType.physicalDisability => 'Physical / Medical',
        SendNeedType.sensoryImpairment => 'Sensory (HI/VI)',
        SendNeedType.learningDifficulty => 'Dyslexia / SpLD',
        SendNeedType.mentalHealth      => 'Mental Health',
        SendNeedType.complexNeeds      => 'Complex / PMLD',
        SendNeedType.general           => 'General SEND',
      };
}

class SendResource {
  final String name;
  final String description;
  final String url;
  final String? phone;
  final SendNeedType needType;
  final bool isCharity;

  const SendResource({
    required this.name,
    required this.description,
    required this.url,
    required this.needType,
    this.phone,
    this.isCharity = true,
  });
}

// ─── Deadline ─────────────────────────────────────────────────────────────────

enum DeadlineCategory {
  schoolApplication,
  ehcpReview,
  appealWindow,
  tribunalHearing,
  fundingApplication,
  other,
}

extension DeadlineCategoryX on DeadlineCategory {
  String get displayLabel => switch (this) {
        DeadlineCategory.schoolApplication => 'School Application',
        DeadlineCategory.ehcpReview        => 'EHCP Review',
        DeadlineCategory.appealWindow      => 'Appeal Window',
        DeadlineCategory.tribunalHearing   => 'Tribunal',
        DeadlineCategory.fundingApplication => 'Funding',
        DeadlineCategory.other             => 'Other',
      };
}

class SendDeadline {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final DeadlineCategory category;
  final bool isCompleted;

  const SendDeadline({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.category,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
        'id':          id,
        'title':       title,
        'description': description,
        'date':        date.millisecondsSinceEpoch,
        'category':    category.name,
        'isCompleted': isCompleted,
      };

  factory SendDeadline.fromJson(Map<String, dynamic> j) => SendDeadline(
        id:          j['id'] as String,
        title:       j['title'] as String,
        description: j['description'] as String,
        date:        DateTime.fromMillisecondsSinceEpoch(j['date'] as int),
        category:    DeadlineCategory.values.firstWhere(
          (e) => e.name == (j['category'] as String? ?? ''),
          orElse: () => DeadlineCategory.other,
        ),
        isCompleted: j['isCompleted'] as bool? ?? false,
      );

  SendDeadline copyWith({bool? isCompleted}) => SendDeadline(
        id:          id,
        title:       title,
        description: description,
        date:        date,
        category:    category,
        isCompleted: isCompleted ?? this.isCompleted,
      );

  int get daysUntil => date.difference(DateTime.now()).inDays;
  bool get isOverdue => daysUntil < 0 && !isCompleted;
  bool get isUrgent => daysUntil >= 0 && daysUntil <= 14 && !isCompleted;
}

// ─── Anonymous Q&A message ────────────────────────────────────────────────────

class AnonMessage {
  final String text;
  final bool isUser;
  final DateTime createdAt;

  const AnonMessage({
    required this.text,
    required this.isUser,
    required this.createdAt,
  });
}

// ─── Service ──────────────────────────────────────────────────────────────────

class SendNavigatorService {
  static final SendNavigatorService _instance =
      SendNavigatorService._internal();
  factory SendNavigatorService() => _instance;
  SendNavigatorService._internal();

  static const String _stageKey     = 'send_ehcp_stage_v1';
  static const String _deadlinesKey = 'send_deadlines_v1';

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();

  // ── In-memory cache ────────────────────────────────────────────────────────
  EhcpStage? _cachedStage;
  List<SendDeadline> _deadlines = [];
  bool _deadlinesLoaded = false;

  // ── Borough helper ─────────────────────────────────────────────────────────

  String get userBorough {
    final pc = _onboarding.postcode;
    if (pc == null || pc.isEmpty) return 'your area';
    return _postcode.getBoroughFromPostcode(pc) ?? 'your area';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. EHCP JOURNEY — stage persistence + guidance
  // ═══════════════════════════════════════════════════════════════════════════

  Future<EhcpStage> loadStage() async {
    if (_cachedStage != null) return _cachedStage!;
    // Try Firestore first (authoritative source), fall back to BrowserStorage
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final firestoreVal = doc.data()?['ehcpStage'] as String?;
        if (firestoreVal != null) {
          _cachedStage = EhcpStageX.fromString(firestoreVal);
          // Keep BrowserStorage in sync
          await BrowserStorage.setString(_stageKey, firestoreVal);
          return _cachedStage!;
        }
      }
    } catch (e) {
      debugPrint('[SEND] loadStage Firestore error (using local fallback): $e');
    }
    // BrowserStorage fallback
    final raw = await BrowserStorage.getString(_stageKey);
    _cachedStage = raw != null
        ? EhcpStageX.fromString(raw)
        : EhcpStage.notStarted;
    return _cachedStage!;
  }

  Future<void> saveStage(EhcpStage stage) async {
    _cachedStage = stage;
    // Dual-write: BrowserStorage (sync) + Firestore (async, best-effort)
    await BrowserStorage.setString(_stageKey, stage.storageValue);
    _writeStageToFirestore(stage);
    debugPrint('[SEND] Stage saved: ${stage.storageValue}');
  }

  /// Writes EHCP stage to Firestore `users/{uid}.ehcpStage` — best-effort,
  /// never throws (errors are logged and silently swallowed).
  void _writeStageToFirestore(EhcpStage stage) {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'ehcpStage': stage.storageValue}, SetOptions(merge: true))
          .catchError((Object e) {
        debugPrint('[SEND] _writeStageToFirestore error: $e');
      });
    } catch (e) {
      debugPrint('[SEND] _writeStageToFirestore sync error: $e');
    }
  }

  // ── Static guidance library ────────────────────────────────────────────────

  static EhcpStageGuidance guidanceFor(EhcpStage stage) {
    return switch (stage) {
      EhcpStage.notStarted => EhcpStageGuidance(
          stage: stage,
          headline: 'Getting started with SEND support',
          timelineNote:
              'No deadline yet — but early action strengthens your case. '
              'Schools should have a SEND policy and SENCO.',
          nextSteps: [
            'Talk to your child\'s teacher or SENCO (Special Educational Needs Coordinator) first.',
            'Ask for a meeting to discuss your concerns in writing.',
            'Keep a written record of all conversations with dates.',
            'Request copies of any assessments or reports already done.',
            'Visit IPSEA (ipsea.org.uk) or Contact (contact.org.uk) for free advice.',
          ],
          yourRights: [
            'You have the right to request an EHC Needs Assessment at any time.',
            'Schools must make "reasonable adjustments" under the Equality Act 2010.',
            'The LA must respond to an assessment request within 6 weeks.',
            'You can request an assessment even if the school disagrees.',
          ],
          resources: [
            SendResource(
              name: 'IPSEA — Free legal advice',
              description: 'Independent advice on SEND law. Template letters, tribunal support.',
              url: 'https://www.ipsea.org.uk/',
              needType: SendNeedType.general,
            ),
            SendResource(
              name: 'Contact — Families with disabled children',
              description: '381,000 parent carers helped annually. Education, benefits, local services.',
              url: 'https://contact.org.uk/',
              phone: '0808 808 3555',
              needType: SendNeedType.general,
            ),
            SendResource(
              name: 'SEND Code of Practice 2015',
              description: 'The statutory guidance schools and LAs must follow.',
              url: 'https://www.gov.uk/government/publications/send-code-of-practice-0-to-25',
              needType: SendNeedType.general,
              isCharity: false,
            ),
          ],
          templateLetterHint:
              'Ask IPSEA for their "Request reasonable adjustments" template letter.',
        ),

      EhcpStage.requestingAssessment => EhcpStageGuidance(
          stage: stage,
          headline: 'How to request an EHC Needs Assessment',
          timelineNote:
              'The LA has 6 weeks to decide whether to assess. Clock starts when they receive your written request.',
          nextSteps: [
            'Write to the LA\'s SEND team (not the school) requesting an EHC Needs Assessment.',
            'Include your child\'s name, date of birth, school, and a clear description of their needs.',
            'Attach any existing reports (educational psychology, speech therapy, medical).',
            'Send by recorded post or email with read receipt — you need proof of date.',
            'Ask school for their evidence too (they can support your request).',
            'The LA must respond within 6 weeks — if they refuse, you can appeal.',
          ],
          yourRights: [
            'Any parent can request an EHC Needs Assessment — school agreement not required.',
            'The LA cannot refuse simply because the child is managing at school.',
            'If refused, you have 2 months to appeal to the First-tier Tribunal (SENDIST).',
            'Contact or IPSEA can help you write the request letter for free.',
          ],
          resources: [
            SendResource(
              name: 'IPSEA request letter template',
              description: 'Free template for requesting an EHC Needs Assessment from your LA.',
              url: 'https://www.ipsea.org.uk/request-an-ehc-needs-assessment',
              needType: SendNeedType.general,
            ),
            SendResource(
              name: 'SOS!SEN — Free helpline',
              description: 'Free helpline and workshops. Over 40 years supporting SEND parents.',
              url: 'https://www.sossen.org.uk/',
              phone: '0800 121 4275',
              needType: SendNeedType.general,
            ),
          ],
          templateLetterHint:
              'IPSEA has a free "Request for EHC Needs Assessment" letter template.',
        ),

      EhcpStage.awaitingDecision => EhcpStageGuidance(
          stage: stage,
          headline: 'Waiting for the LA\'s decision — know your deadlines',
          timelineNote:
              '6-week statutory deadline from receipt. Chase in writing at week 5 if no response.',
          nextSteps: [
            'Note the exact date you sent the request — the 6-week clock starts then.',
            'Chase in writing at 5 weeks if you\'ve heard nothing.',
            'Continue gathering professional reports in the meantime.',
            'If refused: request the reasons in writing and contact IPSEA immediately.',
            'You have 2 months from refusal to register your appeal with the Tribunal.',
          ],
          yourRights: [
            'The LA must give written reasons if they refuse to assess.',
            'You can appeal any refusal — most appeals succeed when parents are prepared.',
            'The SEND Tribunal is free to use and legally binding.',
          ],
          resources: [
            SendResource(
              name: 'Council for Disabled Children',
              description: 'Policy, practice guides, and the "Preparing for Adulthood" programme.',
              url: 'https://councilfordisabledchildren.org.uk/',
              needType: SendNeedType.general,
            ),
            SendResource(
              name: 'First-tier Tribunal (SEND)',
              description: 'The independent tribunal that hears SEND appeals. Free to use.',
              url: 'https://www.gov.uk/courts-tribunals/first-tier-tribunal-special-educational-needs-and-disability',
              needType: SendNeedType.general,
              isCharity: false,
            ),
          ],
        ),

      EhcpStage.beingAssessed => EhcpStageGuidance(
          stage: stage,
          headline: 'Your child is being assessed — 20-week clock running',
          timelineNote:
              'LA has 20 weeks from the assessment request to issue a final EHCP. '
              'Assessment itself takes ~12 weeks.',
          nextSteps: [
            'The LA will commission reports: educational psychology (EP), speech & language (SALT), '
                'occupational therapy (OT), and sometimes a medical assessment.',
            'You will be asked to contribute your own views — write them down carefully.',
            'Get copies of ALL reports as soon as they are produced (you are entitled to these).',
            'Consider getting an independent EP report if you feel the LA\'s report undersells your child\'s needs.',
            'Keep a "parent evidence" document: daily observations, what support helps, what doesn\'t.',
          ],
          yourRights: [
            'You must be consulted and can attend meetings.',
            'You are entitled to copies of all professional advice received.',
            'If you disagree with an LA-commissioned report, you can get an independent one.',
            'Independent reports carry the same legal weight at Tribunal.',
          ],
          resources: [
            SendResource(
              name: 'Cerebra — Independent reports & parent guides',
              description: 'Free legal guides and help navigating complex SEND processes.',
              url: 'https://cerebra.org.uk/get-advice-support/our-legal-rights-service/',
              needType: SendNeedType.complexNeeds,
            ),
            SendResource(
              name: 'National Autistic Society — EHCP guide',
              description: 'Step-by-step EHCP guidance for autistic children and families.',
              url: 'https://www.autism.org.uk/advice-and-guidance/topics/education/ehc-plans',
              needType: SendNeedType.autism,
            ),
          ],
          templateLetterHint:
              'Ask IPSEA for their "Request copies of evidence" template letter.',
        ),

      EhcpStage.draftReceived => EhcpStageGuidance(
          stage: stage,
          headline: 'Draft EHCP received — your 15 days start now',
          timelineNote:
              'You have 15 calendar days to respond to the draft. '
              'This is your most important window — the final plan reflects your response.',
          nextSteps: [
            'Read the draft carefully: Sections B (needs), F (provision), and I (school) are most critical.',
            'Section F must describe provision specifically — not vaguely ("some speech therapy"). '
                'It must say: who, how often, how long, by whom.',
            'If you disagree with school placement (Section I), say so now in writing.',
            'Write a detailed response to the LA pointing out everything that needs changing.',
            'Contact IPSEA, SOS!SEN, or Contact helpline for a free review of the draft.',
            'You can request a meeting with the LA to discuss — always follow up in writing.',
          ],
          yourRights: [
            'Section F provision must be specific and quantified — "as recommended by SALT" is not enough.',
            'You can name any school — maintained, academy, or specialist — in Section I.',
            'If the LA refuses your chosen school, they must demonstrate it is unsuitable or inefficient.',
            'If not happy with the final plan, you have 2 months to appeal.',
          ],
          resources: [
            SendResource(
              name: 'IPSEA — Check my draft EHCP',
              description: 'Guidance on what Sections B, F, and I must contain under the law.',
              url: 'https://www.ipsea.org.uk/check-the-draft-ehc-plan',
              needType: SendNeedType.general,
            ),
            SendResource(
              name: 'SEND Action — Parent carer forums',
              description: 'Local parent carer forums with EHCP workshops and peer support.',
              url: 'https://www.sendaction.org/',
              needType: SendNeedType.general,
            ),
          ],
          templateLetterHint:
              'IPSEA has a "Response to draft EHCP" letter template — use it.',
        ),

      EhcpStage.finalIssued => EhcpStageGuidance(
          stage: stage,
          headline: 'Final EHCP issued — check every detail carefully',
          timelineNote:
              '2-month appeal window from issue date. After that: the plan must be reviewed annually.',
          nextSteps: [
            'Check the final plan matches what you agreed in the draft stage.',
            'Note the date of issue — your 2-month appeal window starts now.',
            'If provision has been watered down from the draft, challenge it immediately.',
            'Confirm the named school has received the plan and knows the start date.',
            'Set a reminder for the Annual Review date (usually within 12 months).',
            'Keep a copy of the plan somewhere accessible — you\'ll need it at every school meeting.',
          ],
          yourRights: [
            '2 months to appeal any part of the final plan (Sections B, F, or I) to the Tribunal.',
            'The LA must arrange provision in the EHCP from the date it is issued.',
            'If provision is not being delivered, write to the LA and copy in the school.',
            'Annual Review must happen within 12 months — you can request an early review.',
          ],
          resources: [
            SendResource(
              name: 'Family Fund — Grants for disabled children',
              description: 'Grants for essentials: equipment, holidays, clothing, vehicles.',
              url: 'https://www.familyfund.org.uk/',
              phone: '01904 550055',
              needType: SendNeedType.general,
            ),
            SendResource(
              name: 'Disability Rights UK',
              description: 'Benefits, Access to Work, and rights guides for disabled children and adults.',
              url: 'https://www.disabilityrightsuk.org/',
              needType: SendNeedType.general,
            ),
          ],
        ),

      EhcpStage.annualReview => EhcpStageGuidance(
          stage: stage,
          headline: 'Annual Review — your chance to update the plan',
          timelineNote:
              'Review must be completed within 12 months of the last review or issue date. '
              'For Year 9+, the review must address transition to adulthood.',
          nextSteps: [
            'The school is responsible for organising the Annual Review meeting.',
            'Prepare your own written views before the meeting — submit them in advance.',
            'Invite all professionals involved (EP, SALT, OT) to contribute updated advice.',
            'Focus on what has changed: needs, provision, and any new targets.',
            'If your child is in Year 9 or above, the review must include "preparing for adulthood" outcomes.',
            'After the meeting: the school sends a report to the LA, who then issues an amended EHCP.',
          ],
          yourRights: [
            'You can request an early review at any time — send a written request to the LA.',
            'The LA must issue any amended EHCP within 8 weeks of the review.',
            'If you disagree with amendments, you have a 2-month appeal window.',
            'Year 9+ reviews must include vocational assessments and transition planning.',
          ],
          resources: [
            SendResource(
              name: 'Council for Disabled Children — Annual Review guide',
              description: 'Template agendas and guidance for Annual Reviews.',
              url: 'https://councilfordisabledchildren.org.uk/resources/all-resources/filter/send/annual-review',
              needType: SendNeedType.general,
            ),
            SendResource(
              name: 'Preparing for Adulthood',
              description: 'Specialist advice on EHCP transition planning for 14–25 year olds.',
              url: 'https://www.preparingforadulthood.org.uk/',
              needType: SendNeedType.general,
            ),
          ],
        ),

      EhcpStage.appealing => EhcpStageGuidance(
          stage: stage,
          headline: 'Appealing to the SEND Tribunal — you can do this',
          timelineNote:
              '2-month window to register appeal from LA decision date. '
              'Most hearings are scheduled 22–26 weeks after registration.',
          nextSteps: [
            'Register your appeal at: appeals.justice.gov.uk/optics/appeals/new-appeal',
            'You must first request "disagreement resolution" or "mediation" — or formally decline it.',
            'You can decline mediation and still appeal — this does not weaken your case.',
            'Gather all professional reports. Consider an independent EP report if needed.',
            'Contact IPSEA or SOS!SEN immediately — both provide free tribunal support.',
            'The Tribunal is an evidence-based process. Document everything.',
          ],
          yourRights: [
            'The SEND Tribunal is free, independent, and legally binding on the LA.',
            'Approximately 89% of SEND Tribunal cases that reach a full hearing are decided in favour of parents — though many more are resolved before hearing through LA concession. This figure applies to England only and reflects published SENDIST statistics; individual outcomes vary significantly by case.',
            'You can appeal: refusal to assess, refusal to issue, or contents of Sections B/F/I.',
            'The LA cannot withdraw provision during a live appeal.',
            'Legal Aid may be available through IPSEA for the most complex cases.',
          ],
          resources: [
            SendResource(
              name: 'IPSEA — Tribunal support',
              description: 'Free training, template documents, and expert guidance for SEND tribunals.',
              url: 'https://www.ipsea.org.uk/going-to-tribunal',
              phone: '01799 582030',
              needType: SendNeedType.general,
            ),
            SendResource(
              name: 'SOS!SEN — Tribunal workshops',
              description: 'Free parent workshops and a helpline staffed by experienced volunteers.',
              url: 'https://www.sossen.org.uk/',
              phone: '0800 121 4275',
              needType: SendNeedType.general,
            ),
            SendResource(
              name: 'SEND Tribunal registration',
              description: 'Government portal to register your appeal online.',
              url: 'https://appeals.justice.gov.uk/optics/appeals/new-appeal',
              needType: SendNeedType.general,
              isCharity: false,
            ),
          ],
          templateLetterHint:
              'IPSEA provides free "Notice of Appeal" guidance and templates.',
        ),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. DEADLINE TRACKER
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<SendDeadline>> loadDeadlines() async {
    if (_deadlinesLoaded) return List.unmodifiable(_deadlines);

    // Try Firestore first — merge with BrowserStorage (Firestore is authoritative)
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('deadlines')
            .get();
        if (snap.docs.isNotEmpty) {
          _deadlines = snap.docs
              .map((d) => SendDeadline.fromJson(
                    Map<String, dynamic>.from(d.data()),
                  ))
              .toList();
          _deadlinesLoaded = true;
          return List.unmodifiable(_deadlines);
        }
      }
    } catch (e) {
      debugPrint('[SEND] loadDeadlines Firestore error (using local fallback): $e');
    }

    // BrowserStorage fallback
    final raw = await BrowserStorage.getString(_deadlinesKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _deadlines = list
            .map((j) => SendDeadline.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[SEND] loadDeadlines parse error: $e');
        _deadlines = [];
      }
    }
    _deadlinesLoaded = true;
    return List.unmodifiable(_deadlines);
  }

  Future<void> addDeadline(SendDeadline deadline) async {
    _deadlines.add(deadline);
    await _persistDeadlines();
  }

  Future<void> toggleDeadlineComplete(String id) async {
    final i = _deadlines.indexWhere((d) => d.id == id);
    if (i == -1) return;
    _deadlines[i] = _deadlines[i].copyWith(isCompleted: !_deadlines[i].isCompleted);
    await _persistDeadlines();
  }

  Future<void> removeDeadline(String id) async {
    _deadlines.removeWhere((d) => d.id == id);
    await _persistDeadlines();
  }

  Future<void> _persistDeadlines() async {
    // Dual-write: BrowserStorage (sync) + Firestore (async, best-effort)
    final json = jsonEncode(_deadlines.map((d) => d.toJson()).toList());
    await BrowserStorage.setString(_deadlinesKey, json);
    _persistDeadlinesToFirestore();
  }

  /// Writes all in-memory deadlines to Firestore `users/{uid}/deadlines/{id}`.
  /// Best-effort: errors are logged and silently swallowed.
  void _persistDeadlinesToFirestore() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('deadlines');
      for (final d in _deadlines) {
        batch.set(col.doc(d.id), d.toJson());
      }
      batch.commit().catchError((Object e) {
        debugPrint('[SEND] _persistDeadlinesToFirestore batch error: $e');
      });
    } catch (e) {
      debugPrint('[SEND] _persistDeadlinesToFirestore sync error: $e');
    }
  }

  /// Seeded borough-aware deadlines — called once on first load.
  List<SendDeadline> boroughSuggestedDeadlines(String borough) {
    final now = DateTime.now();
    final year = now.year;

    // National SEND deadlines (statutory)
    return [
      SendDeadline(
        id: 'national_primary_$year',
        title: 'Primary school SEND applications',
        description:
            'National Offer Day for primary school places — 16 April ${year + 1}. '
            'Applications in $borough due 15 January ${year + 1}.',
        date: DateTime(year + 1, 1, 15),
        category: DeadlineCategory.schoolApplication,
      ),
      SendDeadline(
        id: 'national_secondary_$year',
        title: 'Secondary school SEND applications',
        description:
            'National Offer Day for secondary school places — 1 March ${year + 1}. '
            'Applications in $borough due 31 October $year.',
        date: DateTime(year, 10, 31),
        category: DeadlineCategory.schoolApplication,
      ),
      SendDeadline(
        id: 'ehcp_review_reminder',
        title: 'Annual EHCP Review due',
        description:
            'Annual Reviews must happen within 12 months. '
            'Contact your school\'s SENCO to schedule.',
        date: now.add(const Duration(days: 180)),
        category: DeadlineCategory.ehcpReview,
      ),
      SendDeadline(
        id: 'dla_renewal',
        title: 'Disability Living Allowance renewal',
        description:
            'DLA for children under 16 needs renewing periodically. '
            'Check your renewal letter for the exact date.',
        date: now.add(const Duration(days: 365)),
        category: DeadlineCategory.fundingApplication,
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. AI EHCP ADVISOR — Gemini-powered, grounded in UK SEND law
  //    Multi-turn: full conversation history is sent with every request so
  //    the model can refer back to earlier messages in the session.
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Rec 4: Removed false "grounded in IPSEA" claim. Gemini has no live
  // access to IPSEA's current guidance database — claiming it does is
  // misleading. Replaced with accurate "informed by publicly available
  // UK SEND law and guidance" framing.
  static const String _ehcpSystemPrompt =
      'You are Huddl\'s SEND Navigator — a warm, knowledgeable AI assistant '
      'for parents of children with Special Educational Needs and Disabilities '
      '(SEND) in the UK.\n\n'
      'Your responses are informed by publicly available UK SEND law and '
      'guidance, including:\n'
      '- The Children and Families Act 2014\n'
      '- The SEND Code of Practice 0-25 (2015)\n'
      '- Published guidance from IPSEA, Contact charity, and SOS!SEN\n'
      '- The First-tier Tribunal (SEND) appeal process\n\n'
      'IMPORTANT LIMITATIONS you must acknowledge when relevant:\n'
      '- Your knowledge has a training cutoff and may not reflect the most '
      'recent changes to LA policies, case law, or statutory guidance.\n'
      '- Always direct parents to IPSEA (ipsea.org.uk) or Contact '
      '(contact.org.uk) to verify any specific legal position.\n'
      '- This applies to England only. Scotland, Wales, and Northern Ireland '
      'have different SEND systems — always clarify jurisdiction.\n\n'
      'Tone rules:\n'
      '- Warm, compassionate, and direct. These parents are under enormous stress.\n'
      '- Never minimise their concerns or suggest they are overreacting.\n'
      '- Always validate the difficulty of navigating the SEND system.\n'
      '- Give clear, actionable answers — not vague reassurances.\n'
      '- When relevant, cite statutory deadlines and parents\' legal rights.\n'
      '- Always recommend professional support (IPSEA, Contact, SOS!SEN) for '
      'complex decisions.\n\n'
      'Safety guardrails:\n'
      '- You are NOT a solicitor. Say "I\'d recommend verifying this with '
      'IPSEA" whenever legal advice is sought.\n'
      '- Never give medical diagnoses or clinical opinions.\n'
      '- If a parent expresses severe distress, signpost: '
      'Contact helpline 0808 808 3555.\n'
      '- Do not make promises about LA behaviour or tribunal outcomes.\n'
      '- Do not cite specific case names or precedents unless you are '
      'certain they exist — acknowledge uncertainty instead.\n\n'
      'Format:\n'
      '- Use short paragraphs. Maximum 4 sentences per paragraph.\n'
      '- Use numbered lists for steps.\n'
      '- Keep responses under 300 words unless the question is complex.';

  /// Send a message to the EHCP Advisor with full multi-turn history.
  ///
  /// [history] is the list of previous [AnonMessage]s (both user and model)
  /// so Gemini can refer back to the conversation context.
  Future<String?> askEhcpAdvisor({
    required String question,
    required EhcpStage currentStage,
    String? borough,
    List<AnonMessage> history = const [],
  }) async {
    final stageContext =
        'Current parent stage: ${currentStage.displayTitle} — ${currentStage.subtitle}.';
    final boroughContext =
        borough != null && borough != 'your area'
            ? ' Local authority: $borough.'
            : '';
    // System turn injected as the very first user turn (Gemini doesn't have
    // a dedicated system role in the REST API — we prepend it to turn 1).
    final systemPreamble =
        '$_ehcpSystemPrompt\n\n$stageContext$boroughContext';

    // Build the contents array: system preamble in the first user turn,
    // then alternating user/model turns from history, then the new question.
    final List<Map<String, dynamic>> contents = [];

    if (history.isEmpty) {
      // First message — combine system + question in one user turn
      contents.add({
        'role': 'user',
        'parts': [{'text': '$systemPreamble\n\nParent\'s question:\n"$question"'}],
      });
    } else {
      // System preamble as the first user turn
      contents.add({
        'role': 'user',
        'parts': [{'text': systemPreamble}],
      });
      // Dummy model ack so Gemini sees a valid alternating pattern
      contents.add({
        'role': 'model',
        'parts': [{'text': 'Understood. I\'m ready to help you navigate the SEND system.'}],
      });
      // Replay conversation history
      for (final msg in history) {
        contents.add({
          'role': msg.isUser ? 'user' : 'model',
          'parts': [{'text': msg.text}],
        });
      }
      // New user message
      contents.add({
        'role': 'user',
        'parts': [{'text': question}],
      });
    }

    try {
      return await AiApiHelper.generateText(
        {
          'contents': contents,
          'generationConfig': {
            'temperature': 0.3,
            'maxOutputTokens': 600,
            'topP': 0.95,
          },
        },
        timeout: const Duration(seconds: 25),
      );
    } catch (e) {
      debugPrint('[SEND] askEhcpAdvisor error: $e');
      final msg = e.toString();
      // 403 API_KEY_SERVICE_BLOCKED means the Generative Language API is not
      // enabled for this project's key — a config error, not a network error.
      final isConfig = msg.contains('403') ||
          msg.contains('PERMISSION_DENIED') ||
          msg.contains('API_KEY_SERVICE_BLOCKED') ||
          msg.contains('API key');
      throw SendAiException(msg, isConfigError: isConfig);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. ANONYMOUS Q&A — session-only, no Firestore, no UID
  //    Multi-turn: history passed so the AI can follow the thread.
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Rec 4: Removed false grounding claims. Updated safety guardrails to
  // be explicit about AI limitations and crisis escalation.
  static const String _anonSystemPrompt =
      'You are a compassionate, anonymous SEND support assistant for a UK parenting platform.\n\n'
      'This service is ANONYMOUS. The parent has chosen not to share their identity. '
      'Treat every question with complete non-judgement.\n\n'
      'IMPORTANT: You are an AI assistant, not a therapist, counsellor, or '
      'legal professional. Your role is to listen, offer general information, '
      'and signpost to the right human support. Be honest about your limitations.\n\n'
      'You may receive questions about:\n'
      '- Challenging behaviour at home\n'
      '- Suspected undiagnosed conditions (autism, ADHD, sensory processing)\n'
      '- School exclusions and managed moves\n'
      '- Parental coping, burnout, or overwhelm\n'
      '- Stigma and shame around their child\'s diagnosis\n'
      '- Relationship strain due to a child\'s complex needs\n'
      '- Sibling impact (see Sibs.org.uk)\n\n'
      'Tone:\n'
      '- Lead with empathy. Acknowledge the difficulty before giving information.\n'
      '- Never say "have you tried..." without first validating feelings.\n'
      '- Short, warm responses. Not clinical. Not list-heavy unless they ask for steps.\n'
      '- If a parent sounds in crisis, gently signpost: Contact helpline 0808 808 3555.\n\n'
      'Safety:\n'
      '- If there is any suggestion of immediate risk to the child or parent, always say:\n'
      '  "Please contact your GP or call 999 if this is an emergency."\n'
      '- You are not a therapist. Gently name this and refer to professional '
      'support if deep mental health support is clearly needed.\n'
      '- Do not make specific diagnostic suggestions ("this sounds like autism") '
      '— only a qualified professional can diagnose.\n\n'
      'Format: conversational paragraphs. Maximum 200 words.';

  /// Send a message to the Anonymous Advisor with full multi-turn history.
  Future<String?> askAnonAdvisor(
    String question, {
    List<AnonMessage> history = const [],
  }) async {
    final List<Map<String, dynamic>> contents = [];

    if (history.isEmpty) {
      contents.add({
        'role': 'user',
        'parts': [{'text': '$_anonSystemPrompt\n\nQuestion:\n"$question"'}],
      });
    } else {
      contents.add({
        'role': 'user',
        'parts': [{'text': _anonSystemPrompt}],
      });
      contents.add({
        'role': 'model',
        'parts': [{'text': 'I\'m here for you. Please share whatever is on your mind.'}],
      });
      for (final msg in history) {
        contents.add({
          'role': msg.isUser ? 'user' : 'model',
          'parts': [{'text': msg.text}],
        });
      }
      contents.add({
        'role': 'user',
        'parts': [{'text': question}],
      });
    }

    try {
      return await AiApiHelper.generateText(
        {
          'contents': contents,
          'generationConfig': {
            'temperature': 0.4,
            'maxOutputTokens': 400,
            'topP': 0.95,
          },
        },
        timeout: const Duration(seconds: 25),
      );
    } catch (e) {
      debugPrint('[SEND] askAnonAdvisor error: $e');
      final msg = e.toString();
      final isConfig = msg.contains('403') ||
          msg.contains('PERMISSION_DENIED') ||
          msg.contains('API_KEY_SERVICE_BLOCKED') ||
          msg.contains('API key');
      throw SendAiException(msg, isConfigError: isConfig);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. SEND RESOURCE DIRECTORY — curated by need type
  // ═══════════════════════════════════════════════════════════════════════════

  static List<SendResource> resourcesForNeed(SendNeedType need) {
    final all = _allResources;
    if (need == SendNeedType.general) return all;
    return all
        .where((r) => r.needType == need || r.needType == SendNeedType.general)
        .toList();
  }

  static const List<SendResource> _allResources = [
    // ── General SEND ────────────────────────────────────────────────────────
    SendResource(
      name: 'Contact',
      description:
          'The leading charity for families with disabled children. '
          '381,000 parent carers helped annually. Free helpline, benefits advice, local groups.',
      url: 'https://contact.org.uk/',
      phone: '0808 808 3555',
      needType: SendNeedType.general,
    ),
    SendResource(
      name: 'IPSEA',
      description:
          'Independent Provider of Special Education Advice. '
          'Free legal advice, template letters, tribunal support. The gold standard for SEND law.',
      url: 'https://www.ipsea.org.uk/',
      phone: '01799 582030',
      needType: SendNeedType.general,
    ),
    SendResource(
      name: 'SOS!SEN',
      description:
          'Free helpline and workshops for SEND parents. '
          'Over 40 years supporting families through the EHCP process.',
      url: 'https://www.sossen.org.uk/',
      phone: '0800 121 4275',
      needType: SendNeedType.general,
    ),
    SendResource(
      name: 'Family Fund',
      description:
          'Grants for families raising disabled or seriously ill children. '
          'Funding for essentials: equipment, vehicles, holidays, sensory resources.',
      url: 'https://www.familyfund.org.uk/',
      phone: '01904 550055',
      needType: SendNeedType.general,
    ),
    SendResource(
      name: 'Sibs',
      description:
          'The only UK charity for brothers and sisters of disabled people. '
          'Supports young siblings (7–17) and adult siblings (18+). Sibs Groups in many areas.',
      url: 'https://www.sibs.org.uk/',
      needType: SendNeedType.general,
    ),
    // ── Autism ──────────────────────────────────────────────────────────────
    SendResource(
      name: 'National Autistic Society',
      description:
          'Largest autism charity in the UK. Helpline, schools, diagnosis, EHCP guides.',
      url: 'https://www.autism.org.uk/',
      phone: '0808 800 4104',
      needType: SendNeedType.autism,
    ),
    SendResource(
      name: 'Ambitious about Autism',
      description:
          'Education, employment, and wellbeing support for autistic children and young people.',
      url: 'https://www.ambitiousaboutautism.org.uk/',
      needType: SendNeedType.autism,
    ),
    SendResource(
      name: 'Autistica',
      description:
          'Research-led charity focused on improving autistic lives. '
          'Sensory research, employment, and community projects.',
      url: 'https://www.autistica.org.uk/',
      needType: SendNeedType.autism,
    ),
    // ── ADHD ────────────────────────────────────────────────────────────────
    SendResource(
      name: 'ADHD UK',
      description:
          'Parent and adult ADHD support. Free resources, online community, school guides.',
      url: 'https://adhduk.co.uk/',
      needType: SendNeedType.adhd,
    ),
    SendResource(
      name: 'YoungMinds — ADHD',
      description:
          'Mental health support for young people with ADHD. Parent helpline available.',
      url: 'https://www.youngminds.org.uk/find-help/conditions/adhd/',
      phone: '0808 802 5544',
      needType: SendNeedType.adhd,
    ),
    // ── Speech & Language ───────────────────────────────────────────────────
    SendResource(
      name: 'RCSLT — Find a speech therapist',
      description:
          'Royal College of Speech and Language Therapists. '
          'Directory of qualified SLTs and guidance on accessing SALT through the NHS.',
      url: 'https://www.rcslt.org/speech-and-language-therapy/for-families/',
      needType: SendNeedType.speechLanguage,
      isCharity: false,
    ),
    SendResource(
      name: 'I CAN — Communication charity',
      description:
          'UK charity for children with speech, language and communication needs. '
          'Talk Boost programme in schools and Early Talk Boost for under 5s.',
      url: 'https://www.ican.org.uk/',
      needType: SendNeedType.speechLanguage,
    ),
    // ── Physical / Medical ──────────────────────────────────────────────────
    SendResource(
      name: 'Scope',
      description:
          'Disability equality charity. Benefits guides, employment, independent living. '
          'Particularly strong for cerebral palsy and physical disabilities.',
      url: 'https://www.scope.org.uk/',
      phone: '0808 800 3333',
      needType: SendNeedType.physicalDisability,
    ),
    SendResource(
      name: 'Cerebra',
      description:
          'Supports children with brain conditions. '
          'Free legal rights service, product library, and sleep service for families.',
      url: 'https://cerebra.org.uk/',
      needType: SendNeedType.complexNeeds,
    ),
    // ── Learning Difficulties / SpLD ─────────────────────────────────────────
    SendResource(
      name: 'British Dyslexia Association',
      description:
          'Support for families navigating dyslexia diagnoses in schools. '
          'Assessment, teacher training, and school approval scheme.',
      url: 'https://www.bdadyslexia.org.uk/',
      phone: '0333 405 4567',
      needType: SendNeedType.learningDifficulty,
    ),
    SendResource(
      name: 'Dyspraxia Foundation',
      description:
          'Support for children and adults with developmental coordination disorder (DCD/Dyspraxia).',
      url: 'https://dyspraxiafoundation.org.uk/',
      needType: SendNeedType.learningDifficulty,
    ),
    // ── Mental Health ────────────────────────────────────────────────────────
    SendResource(
      name: 'YoungMinds',
      description:
          'UK\'s leading charity for young people\'s mental health. '
          'Parents helpline and crisis text line.',
      url: 'https://www.youngminds.org.uk/',
      phone: '0808 802 5544',
      needType: SendNeedType.mentalHealth,
    ),
    SendResource(
      name: 'Place2Be',
      description:
          'School-based mental health support. Counselling in 1,000+ schools across the UK.',
      url: 'https://www.place2be.org.uk/',
      needType: SendNeedType.mentalHealth,
    ),
  ];
}
