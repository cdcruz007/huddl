import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/browser_storage.dart';
import '../../services/send_navigator_service.dart';
import '../../theme/huddl_colors.dart';
import 'package:intl/intl.dart';

// =============================================================================
// SEND HUB SCREEN — HUDDL SEND NAVIGATOR
//
// ── DESIGN COLOURS ────────────────────────────────────────────────────────────
// Tab bar: underline style using HuddlColors.primary (orange) — matches
//   Discover (events_screen.dart) and Connect (groups_screen.dart) exactly.
// Header badge: HuddlColors.primary — consistent brand primary.
// Teal (HuddlColors.teal) is retained for secondary/informational surfaces
//   (e.g. _kSendInfoBg card backgrounds, success indicators).
//   _kSendCrimson — escalation/appeal accent (urgency, legal challenge)
// ─────────────────────────────────────────────────────────────────────────────
const Color _kSendAccent  = HuddlColors.primary; // orange — matches Discover & Connect tabs
const Color _kSendCrimson = Color(0xFF9B2335);
const Color _kSendInfoBg  = Color(0xFFFFF3EC); // light peach-tinted bg — matches primary brand
// =============================================================================
// AI ADVISOR — SAFETY & COMPLIANCE CONSTANTS
// =============================================================================

/// Persistent storage key for AI Advisor consent.
/// Value is 'v1' when the user has accepted; absent/null = not yet consented.
const String _kAiConsentKey = 'send_ai_advisor_consent_v1';
const String _kAiConsentAccepted = 'accepted';

// Crisis-keyword set — checked client-side BEFORE the message reaches Gemini.
// Any match triggers the _CrisisInterceptSheet regardless of AI response.
// Words are lowercase; message is lowercased before comparison.
// Rec 3: Hard-coded so this check cannot be disabled by model behaviour.
const Set<String> _kCrisisKeywords = {
  // Self-harm / suicide signals
  'hurt myself', 'harm myself', 'end it', 'end my life', 'kill myself',
  'want to die', 'don\'t want to be here', 'don\'t want to live',
  'suicidal', 'suicide', 'self harm', 'self-harm', 'cutting myself',
  'overdose', 'take my life',
  // Child safeguarding signals
  'hurting my child', 'hurting him', 'hurting her', 'hurting them',
  'abuse', 'being abused', 'someone is abusing', 'being hurt',
  'scared of my partner', 'scared of my husband', 'scared of my wife',
  'domestic violence', 'domestic abuse',
  // Immediate danger
  'call the police', 'called 999', 'emergency',
};

// =============================================================================
// SEND HUB SCREEN — HUDDL SEND NAVIGATOR
//
// Four sections navigable via a top tab bar:
//
//   1. EHCP Navigator  — Stage picker → structured guidance, next steps,
//                        your rights, template letter hints, curated resources.
//                        Stage is persisted in BrowserStorage.
//
//   2. AI Advisor      — Gemini-powered conversational Q&A grounded in UK
//                        SEND law (Children & Families Act 2014, SCoP 2015,
//                        IPSEA guidance). Stage-contextualised.
//
//   3. Deadlines       — Borough-aware deadline tracker. Add/complete/remove.
//                        Seeded with national statutory windows on first use.
//
//   4. Find Support    — Curated resource directory filterable by need type
//                        (Autism, ADHD, Speech, Physical, SpLD, Mental Health,
//                        Complex, General). Charity + official bodies.
//
//   + Anonymous Q&A   — Accessible from the AI Advisor tab. Session-only,
//                        no UID attached, no Firestore write.
// =============================================================================

class SendHubScreen extends StatefulWidget {
  /// When [embedded] is true the back button in the header is hidden.
  /// Used when rendering inside InsightsScreen's SEND tab.
  final bool embedded;
  const SendHubScreen({super.key, this.embedded = false});

  @override
  State<SendHubScreen> createState() => _SendHubScreenState();
}

class _SendHubScreenState extends State<SendHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // resizeToAvoidBottomInset=true ensures the input bar rides above the
      // keyboard instead of being hidden behind it.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _SendHeader(
              tabController: _tabController,
              showBack: !widget.embedded,
            ),
            // ── Tab content ──────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _EhcpNavigatorTab(),
                  _AiAdvisorTab(),
                  _DeadlinesTab(),
                  _SupportDirectoryTab(),
                ],
              ),
            ),
            // ── Bottom disclaimer — inline so it moves with the keyboard ─────
            _Disclaimer(isDark: isDark),
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _SendHeader extends StatelessWidget {
  final TabController tabController;
  final bool showBack;
  const _SendHeader({required this.tabController, this.showBack = true});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                if (showBack) ...[  
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 10),
                ],
                // SEND badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _kSendAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.diversity_3,
                      color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SEND Navigator',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? HuddlColors.darkTextPrimary
                              : HuddlColors.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        'AI-assisted EHCP & complex needs support',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: HuddlColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tab bar — underline style, matching Discover and Connect tabs
          TabBar(
            controller: tabController,
            labelColor: HuddlColors.primary,
            unselectedLabelColor: HuddlColors.textHint,
            indicatorColor: HuddlColors.primary,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: isDark ? HuddlColors.darkDivider : HuddlColors.divider,
            labelStyle: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w400),
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: const [
              Tab(text: 'EHCP'),
              Tab(text: 'AI Advisor'),
              Tab(text: 'Deadlines'),
              Tab(text: 'Support'),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Disclaimer ───────────────────────────────────────────────────────────────

class _Disclaimer extends StatelessWidget {
  final bool isDark;
  const _Disclaimer({required this.isDark});

  @override
  Widget build(BuildContext context) {
    // Compact single-line footer — the full legal copy lives in the privacy
    // policy and the consent gate; this is a brief ambient reminder only.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Text(
        'Not legal advice. Verify important decisions with IPSEA · Crisis: 0808 808 3555',
        style: GoogleFonts.poppins(
          fontSize: 10,
          color: HuddlColors.textHint,
          height: 1.3,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// =============================================================================
// TAB 1 — EHCP NAVIGATOR
// =============================================================================

class _EhcpNavigatorTab extends StatefulWidget {
  const _EhcpNavigatorTab();

  @override
  State<_EhcpNavigatorTab> createState() => _EhcpNavigatorTabState();
}

class _EhcpNavigatorTabState extends State<_EhcpNavigatorTab> {
  EhcpStage? _stage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stage = await SendNavigatorService().loadStage();
    if (mounted) setState(() { _stage = stage; _loading = false; });
  }

  Future<void> _pickStage(EhcpStage s) async {
    await SendNavigatorService().saveStage(s);
    if (mounted) setState(() => _stage = s);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stage picker ─────────────────────────────────────────────────
          _SectionLabel(
            icon: Icons.map_outlined,
            label: 'Where are you in the EHCP process?',
          ),
          const SizedBox(height: 10),
          ...EhcpStage.values.map((s) => _StagePickerItem(
                stage: s,
                isSelected: _stage == s,
                onTap: () => _pickStage(s),
              )),
          const SizedBox(height: 20),
          // ── Guidance for selected stage ──────────────────────────────────
          if (_stage != null) ...[
            _EhcpGuidancePanel(stage: _stage!),
          ],
        ],
      ),
    );
  }
}

// Stage picker row
class _StagePickerItem extends StatelessWidget {
  final EhcpStage stage;
  final bool isSelected;
  final VoidCallback onTap;

  const _StagePickerItem({
    required this.stage,
    required this.isSelected,
    required this.onTap,
  });

  // All stages use HuddlColors.primary (orange) — consistent with brand.
  // Stage 8 (Appealing/Tribunal) retains _kSendCrimson as a semantic urgency
  // signal (legal escalation), which is an intentional exception in the palette.
  static const List<Color> _stageColors = [
    HuddlColors.primary,  // 1 — Starting out
    HuddlColors.primary,  // 2 — Requesting assessment
    HuddlColors.primary,  // 3 — Awaiting LA decision
    HuddlColors.primary,  // 4 — Assessment underway
    HuddlColors.primary,  // 5 — Draft EHCP received
    HuddlColors.primary,  // 6 — Final EHCP issued
    HuddlColors.primary,  // 7 — Annual review
    _kSendCrimson,        // 8 — Appealing / Tribunal (urgency exception)
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _stageColors[stage.index];
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.25 : 0.10)
              : (isDark ? HuddlColors.darkSurface : HuddlColors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : HuddlColors.inputBorderLight,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // Stage number bubble
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected ? color : color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${stage.index + 1}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.displayTitle,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? HuddlColors.darkTextPrimary
                          : HuddlColors.textPrimary,
                    ),
                  ),
                  Text(
                    stage.subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: HuddlColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: isSelected ? color : HuddlColors.textHint,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// Guidance panel
class _EhcpGuidancePanel extends StatelessWidget {
  final EhcpStage stage;
  const _EhcpGuidancePanel({required this.stage});

  @override
  Widget build(BuildContext context) {
    final g = SendNavigatorService.guidanceFor(stage);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Headline ──────────────────────────────────────────────────────
        _SectionLabel(icon: Icons.lightbulb_outline, label: g.headline),
        const SizedBox(height: 10),

        // ── Timeline note ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: HuddlColors.warningBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: HuddlColors.warning.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.access_time,
                  size: 16, color: HuddlColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  g.timelineNote,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.warningDark,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Next steps ────────────────────────────────────────────────────
        _SectionLabel(icon: Icons.checklist_rounded, label: 'Next steps'),
        const SizedBox(height: 8),
        ...g.nextSteps.asMap().entries.map((e) => _NumberedStep(
              number: e.key + 1,
              text: e.value,
            )),
        const SizedBox(height: 16),

        // ── Your rights ───────────────────────────────────────────────────
        _SectionLabel(icon: Icons.gavel_rounded, label: 'Your legal rights'),
        const SizedBox(height: 8),
        ...g.yourRights.map((r) => _RightItem(text: r)),
        const SizedBox(height: 16),

        // ── Template letter hint ──────────────────────────────────────────
        if (g.templateLetterHint != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? HuddlColors.darkSurface
                  : _kSendInfoBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: HuddlColors.teal.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.description_outlined,
                    size: 16, color: HuddlColors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    g.templateLetterHint!,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.teal,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Resources ──────────────────────────────────────────────────────
        _SectionLabel(
            icon: Icons.volunteer_activism_outlined,
            label: 'Recommended support'),
        const SizedBox(height: 8),
        ...g.resources.map((r) => _ResourceCard(resource: r)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _NumberedStep extends StatelessWidget {
  final int number;
  final String text;
  const _NumberedStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _kSendAccent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _kSendAccent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: isDark
                    ? HuddlColors.darkTextSecondary
                    : HuddlColors.textDark,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RightItem extends StatelessWidget {
  final String text;
  const _RightItem({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.shield_outlined,
                size: 14, color: _kSendCrimson),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: isDark
                    ? HuddlColors.darkTextSecondary
                    : HuddlColors.textDark,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  final SendResource resource;
  const _ResourceCard({required this.resource});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.inputBorderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                resource.isCharity
                    ? Icons.favorite_outline
                    : Icons.account_balance_outlined,
                size: 14,
                color: resource.isCharity
                    ? _kSendCrimson
                    : HuddlColors.teal,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  resource.name,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? HuddlColors.darkTextPrimary
                        : HuddlColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            resource.description,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: HuddlColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (resource.phone != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone_outlined,
                    size: 12, color: HuddlColors.textHint),
                const SizedBox(width: 4),
                Text(
                  resource.phone!,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.teal,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            resource.url,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: HuddlColors.teal,
              decoration: TextDecoration.underline,
              decorationColor: HuddlColors.teal,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 2 — AI ADVISOR  (EHCP Advisor + Anonymous Q&A toggle)
//
// Agent capabilities:
//   • Multi-turn conversation memory — full history sent on every request
//   • Suggested starter questions — tap to auto-fill and send
//   • Message timestamps — shown below each bubble
//   • Long-press to copy — copies any bubble's text to clipboard
//   • Clear conversation — wipe and start fresh
//   • Stage-aware context — EHCP stage woven into every model turn
// =============================================================================

class _ChatMsg {
  final String text;
  final bool isUser;
  final DateTime sentAt;
  /// True when this message represents an AI call failure (shows error styling).
  final bool isError;
  /// True when the failure is a permanent config issue (API key blocked/missing)
  /// rather than a transient network error. Used to suppress the retry hint.
  final bool isConfigError;

  const _ChatMsg({
    required this.text,
    required this.isUser,
    required this.sentAt,
    this.isError = false,
    this.isConfigError = false,
  });

  /// Convert to the [AnonMessage] format the service expects.
  AnonMessage toServiceMsg() =>
      AnonMessage(text: text, isUser: isUser, createdAt: sentAt);
}

// ── Suggested starter prompts ─────────────────────────────────────────────────

const List<(String, String)> _kEhcpStarters = [
  ('📋', 'What are my rights if the LA refuses to assess?'),
  ('⏱️', 'What are the key statutory deadlines I need to know?'),
  ('📝', 'What should I look for in a draft EHCP?'),
  ('🏫', 'Can I choose my child\'s school in Section I?'),
  ('⚖️', 'How do I appeal to the SEND Tribunal?'),
  ('💬', 'What does the SEND Code of Practice say about provision?'),
];

const List<(String, String)> _kAnonStarters = [
  ('💙', 'I\'m feeling completely overwhelmed. Where do I start?'),
  ('🧩', 'My child was just diagnosed with autism. What now?'),
  ('😔', 'School keeps excluding my child. Is this legal?'),
  ('😤', 'The LA keeps ignoring my requests. What can I do?'),
  ('🌙', 'My child\'s sleep issues are affecting the whole family.'),
  ('🤐', 'I feel embarrassed asking for help. Is that normal?'),
];

// ─────────────────────────────────────────────────────────────────────────────

class _AiAdvisorTab extends StatefulWidget {
  const _AiAdvisorTab();

  @override
  State<_AiAdvisorTab> createState() => _AiAdvisorTabState();
}

class _AiAdvisorTabState extends State<_AiAdvisorTab> {
  // ── Rec 1 / 5: Consent gate ──────────────────────────────────────────────
  bool _consentLoading = true;
  bool _consentGranted = false;

  bool _anonymousMode = false;

  // EHCP Advisor state
  final TextEditingController _ehcpController = TextEditingController();
  final ScrollController _ehcpScrollCtrl = ScrollController();
  final List<_ChatMsg> _ehcpMessages = [];
  bool _ehcpLoading = false;
  EhcpStage? _stage;

  // Anonymous Q&A state
  final TextEditingController _anonController = TextEditingController();
  final ScrollController _anonScrollCtrl = ScrollController();
  final List<_ChatMsg> _anonMessages = [];
  bool _anonLoading = false;

  @override
  void initState() {
    super.initState();
    _loadConsent();
    _loadStage();
  }

  // ── Consent persistence ──────────────────────────────────────────────────

  Future<void> _loadConsent() async {
    final stored = await BrowserStorage.getString(_kAiConsentKey);
    if (mounted) {
      setState(() {
        _consentGranted = stored == _kAiConsentAccepted;
        _consentLoading = false;
      });
    }
  }

  Future<void> _grantConsent() async {
    await BrowserStorage.setString(_kAiConsentKey, _kAiConsentAccepted);
    if (mounted) setState(() => _consentGranted = true);
  }

  Future<void> _loadStage() async {
    final s = await SendNavigatorService().loadStage();
    if (mounted) setState(() => _stage = s);
  }

  @override
  void dispose() {
    _ehcpController.dispose();
    _ehcpScrollCtrl.dispose();
    _anonController.dispose();
    _anonScrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom(ScrollController ctrl) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ctrl.hasClients) {
        ctrl.animateTo(
          ctrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Rec 3: Crisis intercept ───────────────────────────────────────────────
  // Checks the message text against _kCrisisKeywords BEFORE sending to Gemini.
  // If a match is found, shows _CrisisInterceptSheet and does not send.
  // Returns true if a crisis was detected (caller should abort send).
  bool _checkAndHandleCrisis(String text) {
    final lower = text.toLowerCase();
    final isCrisis = _kCrisisKeywords.any((kw) => lower.contains(kw));
    if (isCrisis) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _CrisisInterceptSheet(),
      );
      return true;
    }
    return false;
  }

  // ── Send helpers ─────────────────────────────────────────────────────────

  Future<void> _sendEhcpMessage([String? override]) async {
    final text = (override ?? _ehcpController.text).trim();
    if (text.isEmpty || _ehcpLoading) return;

    // Rec 3: crisis check before touching any state
    if (_checkAndHandleCrisis(text)) return;

    _ehcpController.clear();

    final userMsg = _ChatMsg(text: text, isUser: true, sentAt: DateTime.now());
    setState(() {
      _ehcpMessages.add(userMsg);
      _ehcpLoading = true;
    });
    _scrollToBottom(_ehcpScrollCtrl);

    // Build history for multi-turn (everything except the message we just added)
    final history = _ehcpMessages
        .sublist(0, _ehcpMessages.length - 1)
        .map((m) => m.toServiceMsg())
        .toList();

    String replyText;
    bool isError = false;
    bool isConfigError = false;
    try {
      final reply = await SendNavigatorService().askEhcpAdvisor(
        question: text,
        currentStage: _stage ?? EhcpStage.notStarted,
        borough: SendNavigatorService().userBorough,
        history: history,
      );
      replyText = reply ?? 'I didn\'t receive a response. Please try again.';
    } on SendAiException catch (e) {
      isError = true;
      isConfigError = e.isConfigError;
      replyText = isConfigError
          ? 'The AI service isn\'t configured yet — the Generative Language '
              'API needs to be enabled in Google Cloud Console for this app.'
          : 'I couldn\'t connect right now. Please check your connection and try again.';
    } catch (_) {
      isError = true;
      replyText = 'Something went wrong. Please try again.';
    }

    if (mounted) {
      setState(() {
        _ehcpMessages.add(_ChatMsg(
          text: replyText,
          isUser: false,
          sentAt: DateTime.now(),
          isError: isError,
          isConfigError: isConfigError,
        ));
        _ehcpLoading = false;
      });
      _scrollToBottom(_ehcpScrollCtrl);
    }
  }

  Future<void> _sendAnonMessage([String? override]) async {
    final text = (override ?? _anonController.text).trim();
    if (text.isEmpty || _anonLoading) return;

    // Rec 3: crisis check before touching any state
    if (_checkAndHandleCrisis(text)) return;

    _anonController.clear();

    final userMsg = _ChatMsg(text: text, isUser: true, sentAt: DateTime.now());
    setState(() {
      _anonMessages.add(userMsg);
      _anonLoading = true;
    });
    _scrollToBottom(_anonScrollCtrl);

    final history = _anonMessages
        .sublist(0, _anonMessages.length - 1)
        .map((m) => m.toServiceMsg())
        .toList();

    String replyText;
    bool isError = false;
    bool isConfigError = false;
    try {
      final reply = await SendNavigatorService().askAnonAdvisor(
        text,
        history: history,
      );
      replyText = reply ?? 'I didn\'t receive a response. Please try again.';
    } on SendAiException catch (e) {
      isError = true;
      isConfigError = e.isConfigError;
      replyText = isConfigError
          ? 'The AI service isn\'t configured yet — the Generative Language '
              'API needs to be enabled in Google Cloud Console for this app.'
          : 'I couldn\'t connect right now. Please check your connection and try again.';
    } catch (_) {
      isError = true;
      replyText = 'Something went wrong. Please try again.';
    }

    if (mounted) {
      setState(() {
        _anonMessages.add(_ChatMsg(
          text: replyText,
          isUser: false,
          sentAt: DateTime.now(),
          isError: isError,
          isConfigError: isConfigError,
        ));
        _anonLoading = false;
      });
      _scrollToBottom(_anonScrollCtrl);
    }
  }

  // ── Clear conversation ───────────────────────────────────────────────────

  void _clearChat() {
    final isAnon = _anonymousMode;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear conversation?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          'This will delete all messages in this session.',
          style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('Cancel', style: GoogleFonts.poppins(color: HuddlColors.textHint)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              setState(() {
                if (isAnon) {
                  _anonMessages.clear();
                } else {
                  _ehcpMessages.clear();
                }
              });
            },
            child: Text('Clear',
                style: GoogleFonts.poppins(
                    color: HuddlColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Rec 1: Show loading shimmer while checking stored consent
    if (_consentLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Rec 1: Gate the entire advisor behind explicit consent
    if (!_consentGranted) {
      return _SendAiConsentGate(onConsent: _grantConsent);
    }

    final messages = _anonymousMode ? _anonMessages : _ehcpMessages;
    final isLoading = _anonymousMode ? _anonLoading : _ehcpLoading;
    final accent = _anonymousMode ? _kSendCrimson : _kSendAccent;
    final starters = _anonymousMode ? _kAnonStarters : _kEhcpStarters;

    return Column(
      children: [
        // ── Compact header: mode toggle + stage pill + clear ─────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
          child: Row(
            children: [
              // Segmented mode toggle
              Expanded(
                child: _AdvisorModeToggle(
                  isAnon: _anonymousMode,
                  onChanged: (v) => setState(() => _anonymousMode = v),
                ),
              ),
              // Stage pill — only in EHCP mode, tucked right of toggle
              if (!_anonymousMode && _stage != null) ...[
                const SizedBox(width: 6),
                _StageContextPill(
                  stage: _stage!,
                  onTap: () => DefaultTabController.of(context).animateTo(0),
                ),
              ],
              // Clear button — only when conversation exists
              if (messages.isNotEmpty) ...[
                const SizedBox(width: 2),
                IconButton(
                  onPressed: _clearChat,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  color: HuddlColors.textHint,
                  tooltip: 'Clear conversation',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ],
          ),
        ),

        // ── Chat area ────────────────────────────────────────────────────
        Expanded(
          child: _ChatView(
            messages: messages,
            scrollCtrl: _anonymousMode ? _anonScrollCtrl : _ehcpScrollCtrl,
            isLoading: isLoading,
            accentColor: accent,
            starters: messages.isEmpty ? starters : const [],
            onStarterTap: (q) => _anonymousMode
                ? _sendAnonMessage(q)
                : _sendEhcpMessage(q),
          ),
        ),

        // ── Input bar ─────────────────────────────────────────────────────
        _ChatInputBar(
          controller: _anonymousMode ? _anonController : _ehcpController,
          isLoading: isLoading,
          hint: _anonymousMode
              ? 'Ask anything — not stored by Huddl…'
              : 'Ask about EHCP, rights, schools, appeals…',
          accentColor: accent,
          onSend: () => _anonymousMode ? _sendAnonMessage() : _sendEhcpMessage(),
        ),
      ],
    );
  }
}

// =============================================================================
// REC 1 + 5: AI ADVISOR CONSENT GATE
// Shown the first time a user opens the AI Advisor tab.
// Explains: what the AI is, what it isn't, data processor (Google), DPA,
// and obtains explicit GDPR Article 9(2)(a) consent before any data flows.
// Consent is stored in shared_preferences (_kAiConsentKey) so it is asked
// once only per device/profile.
// =============================================================================

class _SendAiConsentGate extends StatelessWidget {
  final VoidCallback onConsent;
  const _SendAiConsentGate({required this.onConsent});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Icon + title ───────────────────────────────────────────────
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _kSendAccent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.privacy_tip_outlined,
                  color: _kSendAccent, size: 30),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Before you use the AI Advisor',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? HuddlColors.darkTextPrimary
                    : HuddlColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Please read this short notice carefully',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: HuddlColors.textHint),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),

          // ── What it is ────────────────────────────────────────────────
          _ConsentSection(
            icon: Icons.auto_awesome_outlined,
            color: _kSendAccent,
            title: 'What this AI Advisor is',
            body: 'A conversational AI assistant informed by publicly '
                'available UK SEND law and guidance (Children and Families '
                'Act 2014, SEND Code of Practice 2015). It can help you '
                'understand your rights, navigate the EHCP process, and '
                'identify the right support organisations.',
          ),
          const SizedBox(height: 16),

          // ── What it isn't ─────────────────────────────────────────────
          _ConsentSection(
            icon: Icons.gavel_outlined,
            color: _kSendCrimson,
            title: 'What it is NOT',
            body: 'It is not a solicitor, not a therapist, and not a '
                'replacement for professional legal or clinical advice. '
                'It can make mistakes. Always verify important information '
                'with IPSEA (ipsea.org.uk) or Contact (contact.org.uk) '
                'before acting on it.',
          ),
          const SizedBox(height: 16),

          // ── Data & infrastructure ─────────────────────────────────────
          _ConsentSection(
            icon: Icons.cloud_outlined,
            color: HuddlColors.teal,
            title: 'How your messages are processed',
            body: 'Your messages are sent to Google\'s AI infrastructure '
                '(Vertex AI / Gemini API) to generate responses. This means '
                'Google processes your message text as part of this service. '
                'Huddl does not store your AI Advisor conversations in its '
                'own database. Google operates under a Data Processing '
                'Agreement with Huddl and processes data in accordance with '
                'Google Cloud\'s privacy and security terms.',
          ),
          const SizedBox(height: 16),

          // ── Special category data ─────────────────────────────────────
          _ConsentSection(
            icon: Icons.shield_outlined,
            color: HuddlColors.warning,
            title: 'Special category data (GDPR Article 9)',
            body: 'Questions about your child\'s disability, diagnosis, or '
                'health, or about your own emotional wellbeing, constitute '
                '\'special category\' personal data under UK GDPR. By '
                'continuing, you explicitly consent (Article 9(2)(a)) to '
                'this data being processed by Huddl and Google solely to '
                'generate your AI Advisor response. You may withdraw this '
                'consent at any time via Profile → Privacy Settings.',
          ),
          const SizedBox(height: 16),

          // ── Crisis & safeguarding ─────────────────────────────────────
          _ConsentSection(
            icon: Icons.favorite_outline,
            color: _kSendCrimson,
            title: 'If you\'re in crisis',
            body: 'If you or your child are in immediate danger, please '
                'call 999. For emotional support, the Contact helpline is '
                'free: 0808 808 3555. The AI Advisor is not an emergency '
                'service and cannot contact anyone on your behalf.',
          ),
          const SizedBox(height: 28),

          // ── Privacy policy link ───────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/privacy'),
              child: Text(
                'Read Huddl\'s full Privacy Policy →',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: _kSendAccent,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                  decorationColor: _kSendAccent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Consent button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onConsent,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kSendAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'I understand — open the AI Advisor',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'You can withdraw consent at any time in Profile → Privacy Settings.',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: HuddlColors.textHint, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the consent gate — icon, title, body text.
class _ConsentSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _ConsentSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? HuddlColors.darkTextPrimary
                        : HuddlColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: isDark
                        ? HuddlColors.darkTextSecondary
                        : HuddlColors.textSecondary,
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

// =============================================================================
// REC 2: PERSISTENT AI DISCLAIMER STRIP
// Shown above the chat area on every render — not just in the footer.
// One-line, dismissible per session (not persisted — intentionally reappears).
// =============================================================================

class _AiDisclaimerStrip extends StatefulWidget {
  const _AiDisclaimerStrip();

  @override
  State<_AiDisclaimerStrip> createState() => _AiDisclaimerStripState();
}

class _AiDisclaimerStripState extends State<_AiDisclaimerStrip> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: HuddlColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: HuddlColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 13, color: HuddlColors.warning),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'AI — not legal advice. Verify with IPSEA or Contact before acting.',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: HuddlColors.warningDark,
                height: 1.3,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _dismissed = true),
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close_rounded,
                  size: 14, color: HuddlColors.warningDark),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// REC 3: CRISIS INTERCEPT SHEET
// Shown when crisis keywords are detected in the user's message.
// Hard-coded — cannot be bypassed by model behaviour.
// Provides immediate human support contacts before any AI response.
// =============================================================================

class _CrisisInterceptSheet extends StatelessWidget {
  const _CrisisInterceptSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: HuddlColors.inputBorderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _kSendCrimson.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.favorite_outline,
                color: _kSendCrimson, size: 26),
          ),
          const SizedBox(height: 14),

          Text(
            'You\'re not alone',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _kSendCrimson,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'It sounds like things might be very hard right now. '
            'Please reach out to one of these services — '
            'real people are ready to help.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: HuddlColors.textSecondary,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // ── Emergency ──────────────────────────────────────────────────
          _CrisisContactCard(
            icon: Icons.emergency_outlined,
            color: HuddlColors.error,
            label: 'Immediate danger',
            name: 'Emergency services',
            detail: 'Call 999',
          ),
          const SizedBox(height: 10),

          // ── Contact helpline ───────────────────────────────────────────
          _CrisisContactCard(
            icon: Icons.phone_in_talk_outlined,
            color: _kSendAccent,
            label: 'Free SEND family helpline',
            name: 'Contact charity',
            detail: '0808 808 3555',
          ),
          const SizedBox(height: 10),

          // ── Samaritans ─────────────────────────────────────────────────
          _CrisisContactCard(
            icon: Icons.support_agent_outlined,
            color: HuddlColors.teal,
            label: 'Emotional support — 24 / 7',
            name: 'Samaritans',
            detail: '116 123 (free, any time)',
          ),
          const SizedBox(height: 10),

          // ── GP ─────────────────────────────────────────────────────────
          _CrisisContactCard(
            icon: Icons.local_hospital_outlined,
            color: HuddlColors.teal,
            label: 'Non-emergency medical / mental health',
            name: 'Your GP or NHS 111',
            detail: 'Call 111',
          ),
          const SizedBox(height: 24),

          // ── Dismiss ───────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side:
                    BorderSide(color: HuddlColors.inputBorderLight),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Go back',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrisisContactCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String name;
  final String detail;
  const _CrisisContactCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.name,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: HuddlColors.textHint,
                      fontWeight: FontWeight.w500),
                ),
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? HuddlColors.darkTextPrimary
                        : HuddlColors.textPrimary,
                  ),
                ),
                Text(
                  detail,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// END OF SAFETY / COMPLIANCE WIDGETS
// =============================================================================

/// Compact segmented toggle — a single rounded pill containing two options.
/// Matches the style used on other Huddl screens (e.g. Market Buy/Sell tabs).
class _AdvisorModeToggle extends StatelessWidget {
  final bool isAnon;
  final ValueChanged<bool> onChanged;
  const _AdvisorModeToggle({required this.isAnon, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark ? HuddlColors.darkSurface : HuddlColors.gray100;
    final selectedBg = isDark
        ? HuddlColors.darkSurfaceVariant
        : HuddlColors.white;
    final selectedBorder = isDark ? HuddlColors.darkDivider : HuddlColors.divider;

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? HuddlColors.darkDivider : HuddlColors.inputBorderLight,
        ),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: 'EHCP Advisor',
            icon: Icons.school_outlined,
            isActive: !isAnon,
            activeColor: _kSendAccent,
            selectedBg: selectedBg,
            selectedBorder: selectedBorder,
            isDark: isDark,
            onTap: () { HapticFeedback.selectionClick(); onChanged(false); },
          ),
          _SegmentButton(
            label: 'Anonymous Q&A',
            icon: Icons.visibility_off_outlined,
            isActive: isAnon,
            activeColor: _kSendAccent,
            selectedBg: selectedBg,
            selectedBorder: selectedBorder,
            isDark: isDark,
            onTap: () { HapticFeedback.selectionClick(); onChanged(true); },
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final Color selectedBg;
  final Color selectedBorder;
  final bool isDark;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.selectedBg,
    required this.selectedBorder,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isActive ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: isActive
                ? Border.all(color: selectedBorder, width: 0.5)
                : null,
            boxShadow: isActive && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isActive ? activeColor : HuddlColors.textHint,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? activeColor : HuddlColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact inline stage pill — sits in the header row next to the mode toggle.
class _StageContextPill extends StatelessWidget {
  final EhcpStage stage;
  final VoidCallback onTap;
  const _StageContextPill({required this.stage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? HuddlColors.darkSurface
              : _kSendAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _kSendAccent.withValues(alpha: isDark ? 0.4 : 0.25),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_outlined, size: 11, color: _kSendAccent),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(
                stage.displayTitle,
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: _kSendAccent,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.edit_outlined, size: 10, color: _kSendAccent),
          ],
        ),
      ),
    );
  }
}

class _ChatView extends StatelessWidget {
  final List<_ChatMsg> messages;
  final ScrollController scrollCtrl;
  final bool isLoading;
  final Color accentColor;
  /// Suggested starter questions shown as tappable chips when the chat is empty.
  /// Each record is (emoji, questionText). Pass an empty list to suppress chips.
  final List<(String, String)> starters;
  /// Called with the full question text when a starter chip is tapped.
  final void Function(String question) onStarterTap;

  const _ChatView({
    required this.messages,
    required this.scrollCtrl,
    required this.isLoading,
    required this.accentColor,
    this.starters = const [],
    required this.onStarterTap,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && !isLoading) {
      return _EmptyChat(
        accentColor: accentColor,
        starters: starters,
        onStarterTap: onStarterTap,
      );
    }

    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: messages.length + (isLoading ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == messages.length) {
          return _TypingIndicator(color: accentColor);
        }
        final msg = messages[i];
        return _ChatBubble(msg: msg, accentColor: accentColor);
      },
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final Color accentColor;
  final List<(String, String)> starters;
  final void Function(String question) onStarterTap;

  const _EmptyChat({
    required this.accentColor,
    this.starters = const [],
    required this.onStarterTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? HuddlColors.darkSurface : HuddlColors.white;
    final borderColor = isDark ? HuddlColors.darkDivider : HuddlColors.divider;

    if (starters.isEmpty) {
      // Fallback when no starters — simple centred prompt
      return Center(
        child: Text(
          'Type a question below to get started',
          style: GoogleFonts.poppins(
              fontSize: 13, color: HuddlColors.textHint),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'Suggested questions',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: HuddlColors.textHint,
              letterSpacing: 0.2,
            ),
          ),
        ),
        ...starters.map((starter) {
          final (emoji, question) = starter;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onStarterTap(question);
            },
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      question,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: HuddlColors.textDark,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: HuddlColors.textHint),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatMsg msg;
  final Color accentColor;
  const _ChatBubble({required this.msg, required this.accentColor});

  static final _timeFmt = DateFormat('HH:mm');

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: msg.text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied to clipboard',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeLabel = _timeFmt.format(msg.sentAt);

    // ── Error bubble (AI call failed) ──────────────────────────────────────
    if (msg.isError) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.88,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? HuddlColors.error.withValues(alpha: 0.12)
                : HuddlColors.errorLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: HuddlColors.error.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 14, color: HuddlColors.error),
                  const SizedBox(width: 6),
                  Text(
                    msg.isConfigError ? 'AI not available' : 'Connection failed',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                msg.text,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  height: 1.45,
                  color: isDark
                      ? HuddlColors.darkTextSecondary
                      : HuddlColors.textSecondary,
                ),
              ),
              if (!msg.isConfigError) ...[
                const SizedBox(height: 6),
                Text(
                  'Tap the send button to try again.',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: HuddlColors.textHint,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (msg.isConfigError) ...[
                const SizedBox(height: 6),
                Text(
                  'For SEND advice now: IPSEA ipsea.org.uk · 01799 582030',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: HuddlColors.textHint,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Align(
      alignment:
          msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Column(
          crossAxisAlignment: msg.isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // ── Bubble ────────────────────────────────────────────────────
            GestureDetector(
              onLongPress: () {
                HapticFeedback.mediumImpact();
                _copyToClipboard(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: msg.isUser
                      ? accentColor
                      : (isDark
                          ? HuddlColors.darkSurface
                          : HuddlColors.gray100),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: msg.isUser
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                    bottomRight: msg.isUser
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                  ),
                ),
                child: Text(
                  msg.text,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    height: 1.5,
                    color: msg.isUser
                        ? Colors.white
                        : (isDark
                            ? HuddlColors.darkTextPrimary
                            : HuddlColors.textDark),
                  ),
                ),
              ),
            ),
            // ── Timestamp ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 4,
                  left: 4, right: 4),
              child: Text(
                timeLabel,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: HuddlColors.textHint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  final Color color;
  const _TypingIndicator({required this.color});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? HuddlColors.darkSurface : HuddlColors.gray100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [1, 2, 3].map((i) {
              final delay = i * 0.2;
              final v = ((_anim.value - delay).clamp(0.0, 1.0));
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: v),
                  shape: BoxShape.circle,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final String hint;
  final Color accentColor;
  final VoidCallback onSend;

  const _ChatInputBar({
    required this.controller,
    required this.isLoading,
    required this.hint,
    required this.accentColor,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: isDark ? HuddlColors.darkDivider : HuddlColors.divider,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.poppins(fontSize: 14),
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.poppins(
                    fontSize: 13, color: HuddlColors.textHint),
                filled: true,
                fillColor: isDark
                    ? HuddlColors.darkSurfaceVariant
                    : HuddlColors.inputBg,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(
            accentColor: accentColor,
            isLoading: isLoading,
            onTap: onSend,
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final Color accentColor;
  final bool isLoading;
  final VoidCallback onTap;
  const _SendButton(
      {required this.accentColor,
      required this.isLoading,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isLoading
              ? HuddlColors.inputBorderLight
              : accentColor,
          shape: BoxShape.circle,
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send_rounded,
                color: Colors.white, size: 18),
      ),
    );
  }
}

// =============================================================================
// TAB 3 — DEADLINES TRACKER
// =============================================================================

class _DeadlinesTab extends StatefulWidget {
  const _DeadlinesTab();

  @override
  State<_DeadlinesTab> createState() => _DeadlinesTabState();
}

class _DeadlinesTabState extends State<_DeadlinesTab> {
  List<SendDeadline> _deadlines = [];
  bool _loading = true;
  bool _showCompleted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var deadlines = await SendNavigatorService().loadDeadlines();
    // Seed if empty
    if (deadlines.isEmpty) {
      final borough = SendNavigatorService().userBorough;
      final seeded =
          SendNavigatorService().boroughSuggestedDeadlines(borough);
      for (final d in seeded) {
        await SendNavigatorService().addDeadline(d);
      }
      deadlines = await SendNavigatorService().loadDeadlines();
    }
    if (mounted) {
      setState(() {
        _deadlines = List.from(deadlines);
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String id) async {
    await SendNavigatorService().toggleDeadlineComplete(id);
    final updated = await SendNavigatorService().loadDeadlines();
    if (mounted) setState(() => _deadlines = List.from(updated));
  }

  Future<void> _remove(String id) async {
    await SendNavigatorService().removeDeadline(id);
    final updated = await SendNavigatorService().loadDeadlines();
    if (mounted) setState(() => _deadlines = List.from(updated));
  }

  Future<void> _showAddDialog() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime pickedDate = DateTime.now().add(const Duration(days: 30));
    DeadlineCategory pickedCategory = DeadlineCategory.ehcpReview;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          title: Text('Add deadline',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle:
                        GoogleFonts.poppins(fontSize: 13),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle:
                        GoogleFonts.poppins(fontSize: 13),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                // Category dropdown
                DropdownButtonFormField<DeadlineCategory>(
                  initialValue: pickedCategory,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    labelStyle:
                        GoogleFonts.poppins(fontSize: 13),
                    border: const OutlineInputBorder(),
                  ),
                  items: DeadlineCategory.values
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.displayLabel,
                                style:
                                    GoogleFonts.poppins(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => pickedCategory = v);
                    }
                  },
                ),
                const SizedBox(height: 10),
                // Date picker
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined,
                      size: 18),
                  title: Text(
                    _formatDate(pickedDate),
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                  subtitle: Text('Tap to change',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: HuddlColors.textHint)),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx2,
                      initialDate: pickedDate,
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 1825)),
                    );
                    if (d != null) {
                      setDialogState(() => pickedDate = d);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(fontSize: 13)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                final deadline = SendDeadline(
                  id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                  title: titleCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  date: pickedDate,
                  category: pickedCategory,
                );
                await SendNavigatorService().addDeadline(deadline);
                final updated =
                    await SendNavigatorService().loadDeadlines();
                if (mounted) {
                  setState(() => _deadlines = List.from(updated));
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kSendAccent,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: Text('Add',
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final visible = _deadlines
        .where((d) => _showCompleted || !d.isCompleted)
        .toList()
      ..sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        return a.date.compareTo(b.date);
      });

    return Column(
      children: [
        // ── Toolbar ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(
                '${_deadlines.where((d) => !d.isCompleted).length} upcoming',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textSecondary),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    setState(() => _showCompleted = !_showCompleted),
                child: Text(
                  _showCompleted ? 'Hide done' : 'Show done',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: _kSendAccent),
                ),
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add, size: 14),
                label: Text('Add',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kSendAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── List ────────────────────────────────────────────────────────
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 48, color: HuddlColors.textHint),
                      const SizedBox(height: 12),
                      Text(
                        'No upcoming deadlines',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap "Add" to track EHCP reviews,\nschool applications, or appeal windows.',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: HuddlColors.textHint,
                            height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, i) => _DeadlineCard(
                    deadline: visible[i],
                    onToggle: () => _toggle(visible[i].id),
                    onDelete: () => _remove(visible[i].id),
                  ),
                ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _DeadlineCard extends StatelessWidget {
  final SendDeadline deadline;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _DeadlineCard({
    required this.deadline,
    required this.onToggle,
    required this.onDelete,
  });

  static Color _urgencyColor(SendDeadline d) {
    if (d.isCompleted) return HuddlColors.textHint;
    if (d.isOverdue) return HuddlColors.error;
    if (d.isUrgent) return HuddlColors.warning;
    return _kSendAccent;
  }

  static IconData _categoryIcon(DeadlineCategory c) => switch (c) {
        DeadlineCategory.schoolApplication => Icons.school_outlined,
        DeadlineCategory.ehcpReview => Icons.assignment_outlined,
        DeadlineCategory.appealWindow => Icons.gavel_outlined,
        DeadlineCategory.tribunalHearing => Icons.balance_outlined,
        DeadlineCategory.fundingApplication => Icons.account_balance_outlined,
        DeadlineCategory.other => Icons.event_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _urgencyColor(deadline);
    final days = deadline.daysUntil;

    return Dismissible(
      key: Key(deadline.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: HuddlColors.errorLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: HuddlColors.error),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: deadline.isCompleted
              ? (isDark ? HuddlColors.darkSurface : HuddlColors.gray100)
              : (isDark ? HuddlColors.darkSurface : HuddlColors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: deadline.isCompleted
                ? HuddlColors.inputBorderLight
                : color.withValues(alpha: 0.35),
            width: deadline.isCompleted ? 1.0 : 1.5,
          ),
        ),
        child: Row(
          children: [
            // Category icon
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_categoryIcon(deadline.category),
                  size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deadline.title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: deadline.isCompleted
                          ? HuddlColors.textHint
                          : (isDark
                              ? HuddlColors.darkTextPrimary
                              : HuddlColors.textPrimary),
                      decoration: deadline.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    deadline.description,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: HuddlColors.textHint,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Days indicator
                  Text(
                    deadline.isCompleted
                        ? 'Completed'
                        : deadline.isOverdue
                            ? 'Overdue by ${days.abs()} day${days.abs() == 1 ? '' : 's'}'
                            : days == 0
                                ? 'Due today'
                                : 'In $days day${days == 1 ? '' : 's'} — ${_formatDate(deadline.date)}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            // Checkbox
            GestureDetector(
              onTap: onToggle,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: deadline.isCompleted
                      ? HuddlColors.successGreen
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: deadline.isCompleted
                        ? HuddlColors.successGreen
                        : HuddlColors.inputBorderLight,
                    width: 1.5,
                  ),
                ),
                child: deadline.isCompleted
                    ? const Icon(Icons.check,
                        size: 14, color: Colors.white)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]}';

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

// =============================================================================
// TAB 4 — SUPPORT DIRECTORY
// =============================================================================

class _SupportDirectoryTab extends StatefulWidget {
  const _SupportDirectoryTab();

  @override
  State<_SupportDirectoryTab> createState() => _SupportDirectoryTabState();
}

class _SupportDirectoryTabState extends State<_SupportDirectoryTab> {
  SendNeedType _selectedNeed = SendNeedType.general;

  @override
  Widget build(BuildContext context) {
    final resources =
        SendNavigatorService.resourcesForNeed(_selectedNeed);

    return Column(
      children: [
        // ── Need type chips ──────────────────────────────────────────────
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: SendNeedType.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final n = SendNeedType.values[i];
              final isSelected = _selectedNeed == n;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedNeed = n);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _kSendAccent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? _kSendAccent
                          : HuddlColors.inputBorderLight,
                    ),
                  ),
                  child: Text(
                    n.displayLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected
                          ? Colors.white
                          : HuddlColors.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        // ── Resource list ────────────────────────────────────────────────
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            itemCount: resources.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) =>
                _DirectoryCard(resource: resources[i]),
          ),
        ),
      ],
    );
  }
}

class _DirectoryCard extends StatelessWidget {
  final SendResource resource;
  const _DirectoryCard({required this.resource});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuddlColors.inputBorderLight),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: HuddlColors.gray900.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: resource.isCharity
                      ? _kSendCrimson.withValues(alpha: 0.10)
                      : HuddlColors.blueBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  resource.isCharity
                      ? Icons.volunteer_activism_outlined
                      : Icons.account_balance_outlined,
                  size: 18,
                  color: resource.isCharity
                      ? _kSendCrimson
                      : HuddlColors.teal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resource.name,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? HuddlColors.darkTextPrimary
                            : HuddlColors.textPrimary,
                      ),
                    ),
                    Text(
                      resource.isCharity
                          ? 'Charity'
                          : 'Government / Official',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: resource.isCharity
                            ? _kSendCrimson
                            : HuddlColors.teal,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            resource.description,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: HuddlColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (resource.phone != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone_outlined,
                    size: 13, color: HuddlColors.textHint),
                const SizedBox(width: 5),
                Text(
                  resource.phone!,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.teal,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.open_in_new,
                  size: 12, color: HuddlColors.textHint),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  resource.url,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.teal,
                    decoration: TextDecoration.underline,
                    decorationColor: HuddlColors.teal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 15, color: _kSendAccent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? HuddlColors.darkTextPrimary
                  : HuddlColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
