import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/send_navigator_service.dart';
import '../../theme/huddl_colors.dart';

// =============================================================================
// SEND HUB SCREEN — HUDDL SEND NAVIGATOR
//
// ── EHCP PIPELINE DESIGN COLOURS ─────────────────────────────────────────────
// These two colours are domain-specific data-visualisation tokens for the
// EHCP journey pipeline. They are intentionally NOT HuddlColors brand tokens —
// the SEND navigator is a specialist tool with its own established visual
// language (NHS/DfE-adjacent documentation palette).
//
//   _kSendIndigo   — primary pipeline accent (requesting, progress, info)
//   _kSendCrimson  — escalation/appeal accent (urgency, legal challenge)
//   _kSendInfoBg   — light info card background (template hints, guidance)
//
// Do NOT replace these with brand orange/teal — they carry specific meaning
// in a legal/medical context and must remain visually distinct from brand UI.
// ─────────────────────────────────────────────────────────────────────────────
const Color _kSendIndigo  = Color(0xFF5B5EA6);
const Color _kSendCrimson = Color(0xFF9B2335);
const Color _kSendInfoBg  = Color(0xFFEFF6FF);
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
          ],
        ),
      ),
      // ── Bottom disclaimer ──────────────────────────────────────────────────
      bottomNavigationBar: _Disclaimer(isDark: isDark),
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
                    color: _kSendIndigo,
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
          // Tab bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? HuddlColors.darkSurface : HuddlColors.gray100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: tabController,
                indicator: BoxDecoration(
                  color: _kSendIndigo,
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w600),
                unselectedLabelStyle: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w400),
                labelColor: Colors.white,
                unselectedLabelColor: HuddlColors.textSecondary,
                padding: const EdgeInsets.all(3),
                tabs: const [
                  Tab(text: 'EHCP'),
                  Tab(text: 'AI Advisor'),
                  Tab(text: 'Deadlines'),
                  Tab(text: 'Support'),
                ],
              ),
            ),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(
          'Huddl is not a legal service. For formal SEND legal advice contact '
          'IPSEA (ipsea.org.uk) or SOS!SEN (sossen.org.uk). '
          'In a crisis call Contact: 0808 808 3555.',
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: HuddlColors.textHint,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
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

  static const List<Color> _stageColors = [
    Color(0xFF7B68EE), // not started — medium slate blue
    _kSendIndigo, // requesting — indigo
    Color(0xFF3A7BD5), // awaiting — blue
    Color(0xFF00B4D8), // being assessed — sky
    Color(0xFF06D6A0), // draft received — teal
    Color(0xFF22C55E), // final issued — green
    Color(0xFFF59E0B), // annual review — amber
    _kSendCrimson, // appealing — crimson
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
                color: HuddlColors.blue.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.description_outlined,
                    size: 16, color: HuddlColors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    g.templateLetterHint!,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.blue,
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
              color: _kSendIndigo.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _kSendIndigo,
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
                    : HuddlColors.blue,
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
              color: HuddlColors.blue,
              decoration: TextDecoration.underline,
              decorationColor: HuddlColors.blue,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 2 — AI ADVISOR  (EHCP Advisor + Anonymous Q&A toggle)
// =============================================================================

class _AiAdvisorTab extends StatefulWidget {
  const _AiAdvisorTab();

  @override
  State<_AiAdvisorTab> createState() => _AiAdvisorTabState();
}

class _AiAdvisorTabState extends State<_AiAdvisorTab> {
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
    _loadStage();
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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendEhcpMessage() async {
    final text = _ehcpController.text.trim();
    if (text.isEmpty || _ehcpLoading) return;
    _ehcpController.clear();

    setState(() {
      _ehcpMessages.add(_ChatMsg(text: text, isUser: true));
      _ehcpLoading = true;
    });
    _scrollToBottom(_ehcpScrollCtrl);

    final reply = await SendNavigatorService().askEhcpAdvisor(
      question: text,
      currentStage: _stage ?? EhcpStage.notStarted,
      borough: SendNavigatorService().userBorough,
    );

    if (mounted) {
      setState(() {
        _ehcpMessages.add(_ChatMsg(
          text: reply ??
              'I\'m sorry, I couldn\'t connect right now. Please try again, '
                  'or contact IPSEA directly: ipsea.org.uk | 01799 582030.',
          isUser: false,
        ));
        _ehcpLoading = false;
      });
      _scrollToBottom(_ehcpScrollCtrl);
    }
  }

  Future<void> _sendAnonMessage() async {
    final text = _anonController.text.trim();
    if (text.isEmpty || _anonLoading) return;
    _anonController.clear();

    setState(() {
      _anonMessages.add(_ChatMsg(text: text, isUser: true));
      _anonLoading = true;
    });
    _scrollToBottom(_anonScrollCtrl);

    final reply = await SendNavigatorService().askAnonAdvisor(text);

    if (mounted) {
      setState(() {
        _anonMessages.add(_ChatMsg(
          text: reply ??
              'I\'m sorry, I\'m having trouble connecting right now. '
                  'You can reach the Contact helpline any time: 0808 808 3555.',
          isUser: false,
        ));
        _anonLoading = false;
      });
      _scrollToBottom(_anonScrollCtrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Mode toggle ──────────────────────────────────────────────────
        _AdvisorModeToggle(
          isAnon: _anonymousMode,
          onChanged: (v) => setState(() => _anonymousMode = v),
        ),
        // ── Stage context pill (EHCP mode only) ──────────────────────────
        if (!_anonymousMode && _stage != null)
          _StageContextPill(
            stage: _stage!,
            onTap: () {
              // Navigate to EHCP tab
              final tabController = DefaultTabController.of(context);
              tabController.animateTo(0);
            },
          ),
        // ── Chat area ────────────────────────────────────────────────────
        Expanded(
          child: _anonymousMode
              ? _ChatView(
                  messages: _anonMessages,
                  scrollCtrl: _anonScrollCtrl,
                  isLoading: _anonLoading,
                  emptyTitle: 'Ask anything — completely anonymously',
                  emptySubtitle:
                      'Your question is not stored and carries no identifying information. '
                      'Ask about behaviour, diagnosis, exclusions, coping — anything.',
                  accentColor: _kSendCrimson,
                )
              : _ChatView(
                  messages: _ehcpMessages,
                  scrollCtrl: _ehcpScrollCtrl,
                  isLoading: _ehcpLoading,
                  emptyTitle: 'Ask your EHCP Advisor',
                  emptySubtitle:
                      'Ask about your rights, next steps, timelines, school placements, '
                      'or tribunal appeals. Powered by Huddl\'s SEND AI.',
                  accentColor: _kSendIndigo,
                ),
        ),
        // ── Input bar ─────────────────────────────────────────────────────
        _ChatInputBar(
          controller:
              _anonymousMode ? _anonController : _ehcpController,
          isLoading:
              _anonymousMode ? _anonLoading : _ehcpLoading,
          hint: _anonymousMode
              ? 'Ask anything — your question is anonymous…'
              : 'Ask about EHCP, rights, schools, appeals…',
          accentColor: _anonymousMode
              ? _kSendCrimson
              : _kSendIndigo,
          onSend: _anonymousMode ? _sendAnonMessage : _sendEhcpMessage,
        ),
      ],
    );
  }
}

class _ChatMsg {
  final String text;
  final bool isUser;
  const _ChatMsg({required this.text, required this.isUser});
}

class _AdvisorModeToggle extends StatelessWidget {
  final bool isAnon;
  final ValueChanged<bool> onChanged;
  const _AdvisorModeToggle({required this.isAnon, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: 'EHCP Advisor',
              icon: Icons.school_outlined,
              isActive: !isAnon,
              color: _kSendIndigo,
              onTap: () => onChanged(false),
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ModeButton(
              label: 'Anonymous Q&A',
              icon: Icons.visibility_off_outlined,
              isActive: isAnon,
              color: _kSendCrimson,
              onTap: () => onChanged(true),
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;
  final bool isDark;
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.color,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: isDark ? 0.25 : 0.10)
              : (isDark ? HuddlColors.darkSurface : HuddlColors.gray100),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? color : HuddlColors.inputBorderLight,
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14, color: isActive ? color : HuddlColors.textHint),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? color : HuddlColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageContextPill extends StatelessWidget {
  final EhcpStage stage;
  final VoidCallback onTap;
  const _StageContextPill({required this.stage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _kSendIndigo.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _kSendIndigo.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined,
                  size: 12, color: _kSendIndigo),
              const SizedBox(width: 5),
              Text(
                'Stage: ${stage.displayTitle}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _kSendIndigo,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit_outlined,
                  size: 11, color: _kSendIndigo),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatView extends StatelessWidget {
  final List<_ChatMsg> messages;
  final ScrollController scrollCtrl;
  final bool isLoading;
  final String emptyTitle;
  final String emptySubtitle;
  final Color accentColor;

  const _ChatView({
    required this.messages,
    required this.scrollCtrl,
    required this.isLoading,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && !isLoading) {
      return _EmptyChat(
        title: emptyTitle,
        subtitle: emptySubtitle,
        accentColor: accentColor,
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
  final String title;
  final String subtitle;
  final Color accentColor;
  const _EmptyChat({
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chat_bubble_outline,
                  color: accentColor, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: HuddlColors.textHint,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatMsg msg;
  final Color accentColor;
  const _ChatBubble({required this.msg, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment:
          msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                backgroundColor: _kSendIndigo,
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
                      color: _kSendIndigo),
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
                  backgroundColor: _kSendIndigo,
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
    return _kSendIndigo;
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
                        ? _kSendIndigo
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? _kSendIndigo
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
                      : HuddlColors.blue,
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
                            : HuddlColors.blue,
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
                    color: HuddlColors.blue,
                    decoration: TextDecoration.underline,
                    decorationColor: HuddlColors.blue,
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
        Icon(icon, size: 15, color: _kSendIndigo),
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
