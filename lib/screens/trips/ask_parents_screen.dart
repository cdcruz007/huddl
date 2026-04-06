import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_community_service.dart';

/// Ask Parents — clean Q&A with subtle conversational urgency cues.
/// Audit-hardened: WCAG 2.2, 48 dp touch targets, Semantics,
/// micro-interactions, Material ripples, haptic feedback.
class AskParentsScreen extends StatefulWidget {
  const AskParentsScreen({super.key});

  @override
  State<AskParentsScreen> createState() => _AskParentsScreenState();
}

class _AskParentsScreenState extends State<AskParentsScreen>
    with SingleTickerProviderStateMixin {
  final TravelCommunityService _svc = TravelCommunityService();
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _filter = 'All';
  bool _loading = true;

  final _filters = ['All', 'Accommodation', 'Transport', 'Gear', 'Health', 'Food', 'Activities'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    await _svc.initialize();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  QuestionCategory? get _cat {
    switch (_filter) {
      case 'Accommodation': return QuestionCategory.accommodation;
      case 'Transport': return QuestionCategory.transport;
      case 'Gear': return QuestionCategory.gear;
      case 'Health': return QuestionCategory.health;
      case 'Food': return QuestionCategory.food;
      case 'Activities': return QuestionCategory.activities;
      default: return null;
    }
  }

  List<TravelQuestion> get _filtered => _svc.filterQuestions(category: _cat, searchQuery: _query.isNotEmpty ? _query : null);

  Color _hex(String h) => Color(int.parse(h.replaceFirst('#', '0xFF')));

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
          : SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  _buildTabs(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _list(_filtered),
                        _list(List<TravelQuestion>.from(_filtered)..sort((a, b) => b.totalUpvotes.compareTo(a.totalUpvotes))),
                        _unanswered(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _postSheet(context),
              backgroundColor: HuddlColors.primary,
              icon: const Icon(Icons.edit, color: HuddlColors.white, size: 20),
              label: Text('Ask Parents', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.white)),
            ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final total = _svc.questions.length;
    final unanswered = _svc.questions.where((q) => q.answers.where((a) => !a.isAiGenerated).isEmpty).length;

    return Container(
      color: HuddlColors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Go back',
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 20, color: HuddlColors.textDark),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ask Parents', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
                  Text('$total questions · $unanswered waiting for answers', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Search
          Container(
            decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search questions, destinations...',
                hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
                prefixIcon: const Icon(Icons.search, color: HuddlColors.textHint, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(onTap: () { _searchCtrl.clear(); setState(() => _query = ''); }, child: const Icon(Icons.close, color: HuddlColors.textHint, size: 18))
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Filter chips
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              itemBuilder: (_, i) {
                final sel = _filter == _filters[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    button: true,
                    label: 'Filter by ${_filters[i]}',
                    selected: sel,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _filter = _filters[i]);
                        },
                        borderRadius: BorderRadius.circular(17),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? HuddlColors.primary : HuddlColors.white,
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(color: sel ? HuddlColors.primary : HuddlColors.divider),
                          ),
                          child: Text(_filters[i], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: sel ? HuddlColors.white : HuddlColors.textSecondary)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── Tabs ─────────────────────────────────────────────────────────────────
  Widget _buildTabs() {
    final count = _svc.questions.where((q) => q.answers.where((a) => !a.isAiGenerated).isEmpty).length;
    return Container(
      color: HuddlColors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: HuddlColors.primary,
        unselectedLabelColor: HuddlColors.textHint,
        labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
        indicatorColor: HuddlColors.primary,
        indicatorWeight: 3,
        tabs: [
          const Tab(text: 'Recent'),
          const Tab(text: 'Popular'),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Need Help'),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(8)),
                child: Text('$count', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: HuddlColors.white)),
              ),
            ],
          ])),
        ],
      ),
    );
  }

  // ── Lists ────────────────────────────────────────────────────────────────
  Widget _unanswered() {
    final qs = _filtered.where((q) => q.answers.where((a) => !a.isAiGenerated).isEmpty).toList();
    if (qs.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle_outline, size: 48, color: HuddlColors.teal.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text('All caught up!', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
        Text('Every question has been answered', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
      ]));
    }
    return _list(qs);
  }

  Widget _list(List<TravelQuestion> qs) {
    if (qs.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.forum_outlined, size: 48, color: HuddlColors.textHint.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Text('No questions yet', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
        Text('Be the first to ask!', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: qs.length,
      itemBuilder: (_, i) => _card(qs[i]),
    );
  }

  // ── Question card ───────────────────────────────────────────────────────
  Widget _card(TravelQuestion q) {
    final c = _hex(q.authorAvatarColor);
    final parentReplies = q.answers.where((a) => !a.isAiGenerated).length;
    final isOpen = parentReplies == 0;
    final last = q.answers.where((a) => !a.isAiGenerated).isNotEmpty ? q.answers.where((a) => !a.isAiGenerated).last : null;

    return Semantics(
      button: true,
      label: '${q.authorName} asks: ${q.question}. ${isOpen ? "Needs help." : "$parentReplies replies."}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _detail(q),
          borderRadius: BorderRadius.circular(14),
          child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          border: isOpen ? Border.all(color: HuddlColors.primary.withValues(alpha: 0.2)) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Author
          Row(children: [
            CircleAvatar(radius: 16, backgroundColor: c.withValues(alpha: 0.15),
              child: Text(q.authorName[0], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: c))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.authorName, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              Text(_ago(q.createdAt), style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
            ])),
            if (isOpen)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(10)),
                child: Text('Help', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.white)),
              )
            else if (q.isSolved)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle, size: 12, color: HuddlColors.teal),
                  const SizedBox(width: 3),
                  Text('Solved', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.teal)),
                ]),
              ),
          ]),
          const SizedBox(height: 10),
          Text(q.question, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.textDark, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          // Tags
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (q.destination != null) _chip(q.destination!, HuddlColors.blue),
            if (q.childAge != null) _chip(q.childAge!, HuddlColors.teal),
            _chip(q.category.label, HuddlColors.primary),
          ]),
          // Last answer preview
          if (last != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 12, backgroundColor: _hex(last.authorAvatarColor).withValues(alpha: 0.15),
                  child: Text(last.authorName[0], style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: _hex(last.authorAvatarColor)))),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(last.authorName, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                    if (last.hasBeenThereBadge) ...[const SizedBox(width: 4), const Icon(Icons.verified, size: 12, color: HuddlColors.teal)],
                  ]),
                  Text(last.content, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                ])),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          // Stats
          Row(children: [
            const Icon(Icons.chat_bubble_outline, size: 14, color: HuddlColors.textHint),
            const SizedBox(width: 4),
            Text('$parentReplies ${parentReplies == 1 ? "reply" : "replies"}', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
            const SizedBox(width: 12),
            const Icon(Icons.thumb_up_outlined, size: 14, color: HuddlColors.textHint),
            const SizedBox(width: 4),
            Text('${q.totalUpvotes}', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
            const SizedBox(width: 12),
            const Icon(Icons.visibility_outlined, size: 14, color: HuddlColors.textHint),
            const SizedBox(width: 4),
            Text('${q.views}', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
            const Spacer(),
            if (q.hasAiSynthesis)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_awesome, size: 11, color: HuddlColors.aiBlue),
                  const SizedBox(width: 3),
                  Text('AI Summary', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: HuddlColors.aiBlue)),
                ]),
              ),
          ]),
        ]),
      ),
    ),
    ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
    );
  }

  // ── Detail ──────────────────────────────────────────────────────────────
  void _detail(TravelQuestion q) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _DetailScreen(question: q, svc: _svc),
    )).then((_) => setState(() {}));
  }

  // ── Post sheet ──────────────────────────────────────────────────────────
  void _postSheet(BuildContext ctx) {
    final qCtrl = TextEditingController();
    final dCtrl = TextEditingController();
    final aCtrl = TextEditingController();

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: HuddlColors.gray300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Ask the Community', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
            Text('Parents who\'ve been there will answer from experience', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
            const SizedBox(height: 20),
            Text('Your question', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(14)),
              child: TextField(
                controller: qCtrl, maxLines: 4, style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. "Going to Tenerife with a 10-month-old — best area to stay?"',
                  hintStyle: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textHint),
                  border: InputBorder.none, contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _field('Destination', 'e.g. Tenerife', dCtrl, Icons.place)),
              const SizedBox(width: 12),
              Expanded(child: _field('Child age', 'e.g. 10 months', aCtrl, Icons.child_care)),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: HuddlColors.blueBackground, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.auto_awesome, size: 18, color: HuddlColors.blue),
                const SizedBox(width: 10),
                Expanded(child: Text('AI will provide an instant starter answer while parents respond.', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.blue, height: 1.4))),
              ]),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (qCtrl.text.trim().isEmpty) return;
                  Navigator.pop(sheetCtx);
                  final newQ = await _svc.postQuestion(
                    question: qCtrl.text.trim(),
                    destination: dCtrl.text.trim().isNotEmpty ? dCtrl.text.trim() : null,
                    childAge: aCtrl.text.trim().isNotEmpty ? aCtrl.text.trim() : null,
                  );
                  if (mounted) { setState(() {}); _detail(newQ); }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.primary, foregroundColor: HuddlColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
                ),
                child: Text('Post Question', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _field(String label, String hint, TextEditingController ctrl, IconData icon) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.textDark)),
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(12)),
        child: TextField(
          controller: ctrl, style: GoogleFonts.poppins(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint, hintStyle: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint),
            prefixIcon: Icon(icon, size: 18, color: HuddlColors.textHint),
            border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    ]);
  }
}

// =============================================================================
// QUESTION DETAIL SCREEN
// =============================================================================
class _DetailScreen extends StatefulWidget {
  final TravelQuestion question;
  final TravelCommunityService svc;
  const _DetailScreen({required this.question, required this.svc});

  @override
  State<_DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<_DetailScreen> {
  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Color _hex(String h) => Color(int.parse(h.replaceFirst('#', '0xFF')));

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final ac = _hex(q.authorAvatarColor);
    final replies = q.answers.where((a) => !a.isAiGenerated).length;

    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Question', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          Text('$replies ${replies == 1 ? "parent replied" : "parents replied"}', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
        ]),
        actions: [
          IconButton(
            icon: Icon(q.isBookmarked ? Icons.bookmark : Icons.bookmark_outline, size: 22, color: q.isBookmarked ? HuddlColors.primary : HuddlColors.textHint),
            onPressed: () { widget.svc.toggleBookmark(q.id); setState(() {}); },
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Question card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 18, backgroundColor: ac.withValues(alpha: 0.15),
                      child: Text(q.authorName[0], style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: ac))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(q.authorName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                      Text(_ago(q.createdAt), style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
                    ])),
                  ]),
                  const SizedBox(height: 14),
                  Text(q.question, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark, height: 1.4)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (q.destination != null) _tag(q.destination!, HuddlColors.blue),
                    if (q.childAge != null) _tag(q.childAge!, HuddlColors.teal),
                    _tag(q.category.label, HuddlColors.primary),
                  ]),
                ]),
              ),
              // AI synthesis
              if (q.hasAiSynthesis) ...[
                const SizedBox(height: 12),
                _aiSynthesis(q.aiSynthesis!),
              ],
              // Answers
              const SizedBox(height: 16),
              Text('${q.answers.length} ${q.answers.length == 1 ? "Response" : "Responses"}', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const SizedBox(height: 10),
              ...q.answers.map((a) => _answerCard(a)),
              // CTA for unanswered
              if (q.answers.where((a) => !a.isAiGenerated).isEmpty)
                Container(
                  padding: const EdgeInsets.all(20), margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: HuddlColors.peachLight, borderRadius: BorderRadius.circular(14)),
                  child: Column(children: [
                    Text('Be the first parent to help!', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                    const SizedBox(height: 4),
                    Text('Share your experience below to help ${q.authorName}.', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
                  ]),
                ),
              const SizedBox(height: 80),
            ]),
          ),
        ),
        _input(),
      ]),
    );
  }

  Widget _aiSynthesis(AiSynthesis s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.blueBackground, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HuddlColors.aiBlue.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(gradient: HuddlColors.aiGradient, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI Summary', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            Text('Based on ${s.parentResponseCount} parent responses', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.aiBlue)),
          ])),
        ]),
        const SizedBox(height: 12),
        Text(s.summary, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textDark, height: 1.5)),
        if (s.recommendations.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...s.recommendations.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle, size: 14, color: HuddlColors.teal),
              const SizedBox(width: 6),
              Expanded(child: Text(r, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textDark, height: 1.3))),
            ]),
          )),
        ],
        if (s.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...s.warnings.map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber, size: 14, color: HuddlColors.warning),
              const SizedBox(width: 6),
              Expanded(child: Text(w, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textDark, height: 1.3))),
            ]),
          )),
        ],
      ]),
    );
  }

  Widget _answerCard(TravelAnswer a) {
    final c = _hex(a.authorAvatarColor);
    final ai = a.isAiGenerated;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ai ? const Color(0xFFF8FBFF) : HuddlColors.white,
        borderRadius: BorderRadius.circular(14),
        border: ai ? Border.all(color: HuddlColors.aiBlue.withValues(alpha: 0.12)) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 16,
            backgroundColor: ai ? HuddlColors.aiBlue.withValues(alpha: 0.15) : c.withValues(alpha: 0.15),
            child: ai ? const Icon(Icons.auto_awesome, size: 16, color: HuddlColors.aiBlue)
                : Text(a.authorName[0], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: c))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(a.authorName, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: ai ? HuddlColors.aiBlue : HuddlColors.textDark)),
              const SizedBox(width: 6),
              if (a.hasBeenThereBadge && !ai)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified, size: 10, color: HuddlColors.teal),
                    const SizedBox(width: 2),
                    Text('Been There', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: HuddlColors.teal)),
                  ]),
                ),
              if (ai)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text('AI', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: HuddlColors.aiBlue)),
                ),
            ]),
            Row(children: [
              Text(_ago(a.createdAt), style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
              if (a.childAgesAtVisit != null) ...[
                Text(' · ', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
                Text('Visited with ${a.childAgesAtVisit}', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.teal)),
              ],
            ]),
          ])),
        ]),
        const SizedBox(height: 10),
        Text(a.content, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textDark, height: 1.5)),
        const SizedBox(height: 10),
        Row(children: [
          Semantics(
            button: true,
            label: 'Upvote, ${a.upvotes} upvotes',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.svc.upvoteAnswer(widget.question.id, a.id);
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: a.upvotedBy.contains('current_user') ? HuddlColors.primary.withValues(alpha: 0.1) : HuddlColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(a.upvotedBy.contains('current_user') ? Icons.thumb_up : Icons.thumb_up_outlined, size: 14,
                    color: a.upvotedBy.contains('current_user') ? HuddlColors.primary : HuddlColors.textHint),
                  const SizedBox(width: 4),
                  Text('${a.upvotes}', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500,
                    color: a.upvotedBy.contains('current_user') ? HuddlColors.primary : HuddlColors.textSecondary)),
                ]),
              ),
            ),
          ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Save answer to trip research',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.svc.saveAnswer(a, widget.question);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Saved to your trip research', style: GoogleFonts.poppins(fontSize: 13)),
                    backgroundColor: HuddlColors.teal, behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ));
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.bookmark_outline, size: 14, color: HuddlColors.textHint),
                    const SizedBox(width: 4),
                    Text('Save', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _input() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: Row(children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(20)),
              child: TextField(
                controller: _ctrl, style: GoogleFonts.poppins(fontSize: 14),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Share your experience...', hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
                  border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Send reply',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _send,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 48, height: 48,
              decoration: const BoxDecoration(gradient: HuddlColors.primaryGradient, shape: BoxShape.circle),
                child: _sending
                    ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: HuddlColors.white, strokeWidth: 2))
                    : const Icon(Icons.send, color: HuddlColors.white, size: 18),
              ),
            ),
          ),
          ),
        ]),
      ),
    );
  }

  Future<void> _send() async {
    if (_ctrl.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    await widget.svc.postAnswer(questionId: widget.question.id, content: _ctrl.text.trim());
    _ctrl.clear();
    setState(() => _sending = false);
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
    );
  }
}
