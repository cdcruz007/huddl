import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_community_service.dart';

// =============================================================================
// ASK PARENTS — Chat-style Community Q&A (NOT a forum!)
// Feels like a WhatsApp group where parents jump in to help immediately.
// Every question gets urgency, typing indicators, and "be the first to help" CTAs.
// =============================================================================

class AskParentsScreen extends StatefulWidget {
  const AskParentsScreen({super.key});

  @override
  State<AskParentsScreen> createState() => _AskParentsScreenState();
}

class _AskParentsScreenState extends State<AskParentsScreen>
    with TickerProviderStateMixin {
  final TravelCommunityService _communityService = TravelCommunityService();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';
  bool _isLoading = true;

  // Live presence simulation
  Timer? _presenceTimer;
  int _onlineCount = 0;
  String _typingName = '';
  bool _showTyping = false;

  final List<String> _filters = [
    'All', 'Accommodation', 'Transport', 'Gear', 'Health', 'Food', 'Activities'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    await _communityService.initialize();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _onlineCount = 12 + DateTime.now().second % 6;
      });
      _startPresence();
    }
  }

  void _startPresence() {
    final names = ['Sarah M.', 'Priya K.', 'Meg C.', 'Tom', 'Rachel W.', 'James'];
    _presenceTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (!mounted) return;
      setState(() {
        _typingName = names[timer.tick % names.length];
        _showTyping = timer.tick % 3 != 0;
      });
    });
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  QuestionCategory? get _selectedCategory {
    switch (_selectedFilter) {
      case 'Accommodation': return QuestionCategory.accommodation;
      case 'Transport': return QuestionCategory.transport;
      case 'Gear': return QuestionCategory.gear;
      case 'Health': return QuestionCategory.health;
      case 'Food': return QuestionCategory.food;
      case 'Activities': return QuestionCategory.activities;
      default: return null;
    }
  }

  List<TravelQuestion> get _filteredQuestions {
    return _communityService.filterQuestions(
      category: _selectedCategory,
      searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
          : Column(
              children: [
                _buildHeader(),
                _buildTabs(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRecentTab(),
                      _buildHotTab(),
                      _buildUnansweredTab(),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPostQuestionSheet(context),
        backgroundColor: HuddlColors.primary,
        icon: const Icon(Icons.edit, color: HuddlColors.white, size: 20),
        label: Text('Ask Parents', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.white)),
      ),
    );
  }

  // ── Header with live presence ───────────────────────────────────────────
  Widget _buildHeader() {
    final unansweredCount = _communityService.questions.where((q) => q.answers.where((a) => !a.isAiGenerated).isEmpty).length;

    return Container(
      color: HuddlColors.white,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios, size: 20, color: HuddlColors.textDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ask Parents', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
                    Row(
                      children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: HuddlColors.successGreen, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text('$_onlineCount parents online', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.successGreen, fontWeight: FontWeight.w500)),
                        if (_showTyping) ...[
                          Text(' · ', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
                          Text('$_typingName typing...', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint, fontStyle: FontStyle.italic)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Unanswered badge
              if (unansweredCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.front_hand, size: 12, color: HuddlColors.white),
                    const SizedBox(width: 4),
                    Text('$unansweredCount need help', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.white)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Search bar
          Container(
            decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(14)),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search questions, destinations...',
                hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
                prefixIcon: const Icon(Icons.search, color: HuddlColors.textHint, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                        child: const Icon(Icons.close, color: HuddlColors.textHint, size: 18),
                      )
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
              itemBuilder: (ctx, i) {
                final isSelected = _selectedFilter == _filters[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFilter = _filters[i]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? HuddlColors.primary : HuddlColors.white,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: isSelected ? HuddlColors.primary : HuddlColors.divider),
                      ),
                      child: Text(
                        _filters[i],
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: isSelected ? HuddlColors.white : HuddlColors.textSecondary),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Tabs ───────────────────────────────────────────────────────────────
  Widget _buildTabs() {
    final unansweredCount = _communityService.questions.where((q) => q.answers.where((a) => !a.isAiGenerated).isEmpty).length;

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
            if (unansweredCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(8)),
                child: Text('$unansweredCount', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: HuddlColors.white)),
              ),
            ],
          ])),
        ],
      ),
    );
  }

  // ── Tab content ────────────────────────────────────────────────────────
  Widget _buildRecentTab() => _buildQuestionList(_filteredQuestions);

  Widget _buildHotTab() {
    final questions = List<TravelQuestion>.from(_filteredQuestions)..sort((a, b) => b.totalUpvotes.compareTo(a.totalUpvotes));
    return _buildQuestionList(questions);
  }

  Widget _buildUnansweredTab() {
    final questions = _filteredQuestions.where((q) => q.answers.where((a) => !a.isAiGenerated).isEmpty).toList();
    if (questions.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_outline, size: 56, color: HuddlColors.successGreen.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('All caught up!', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const SizedBox(height: 4),
          Text('Every question has been answered by the community', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
        ]),
      );
    }
    return _buildQuestionList(questions);
  }

  Widget _buildQuestionList(List<TravelQuestion> questions) {
    if (questions.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.forum_outlined, size: 56, color: HuddlColors.textHint.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('No questions yet', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const SizedBox(height: 4),
          Text('Be the first to ask the community!', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: questions.length,
      itemBuilder: (ctx, i) => _buildQuestionCard(questions[i]),
    );
  }

  // ── Question Card — Chat-thread style ──────────────────────────────────
  Widget _buildQuestionCard(TravelQuestion question) {
    final color = Color(int.parse(question.authorAvatarColor.replaceFirst('#', '0xFF')));
    final parentAnswerCount = question.answers.where((a) => !a.isAiGenerated).length;
    final isUnanswered = parentAnswerCount == 0;
    final lastAnswer = question.answers.where((a) => !a.isAiGenerated).isNotEmpty
        ? question.answers.where((a) => !a.isAiGenerated).last
        : null;

    return GestureDetector(
      onTap: () => _openQuestionDetail(question),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isUnanswered ? HuddlColors.primary.withValues(alpha: 0.3) : question.isSolved ? HuddlColors.successGreen.withValues(alpha: 0.3) : HuddlColors.divider),
          boxShadow: [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row with urgency
            Row(
              children: [
                CircleAvatar(
                  radius: 16, backgroundColor: color.withValues(alpha: 0.15),
                  child: Text(question.authorName[0], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(question.authorName, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                    Text(_timeAgo(question.createdAt), style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
                  ]),
                ),
                if (isUnanswered)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.reply, size: 12, color: HuddlColors.white),
                      const SizedBox(width: 3),
                      Text('Help', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.white)),
                    ]),
                  )
                else if (question.isSolved)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: HuddlColors.successGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle, size: 12, color: HuddlColors.successGreen),
                      const SizedBox(width: 3),
                      Text('Solved', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.successGreen)),
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Question text
            Text(question.question, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.textDark, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            // Tags
            Wrap(
              spacing: 6, runSpacing: 4,
              children: [
                if (question.destination != null) _buildTag(question.destination!, HuddlColors.blue),
                if (question.childAge != null) _buildTag(question.childAge!, HuddlColors.teal),
                _buildTag(question.category.label, HuddlColors.primary),
              ],
            ),

            // Latest reply preview — chat-like
            if (lastAnswer != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: HuddlColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Color(int.parse(lastAnswer.authorAvatarColor.replaceFirst('#', '0xFF'))).withValues(alpha: 0.15),
                      child: Text(lastAnswer.authorName[0], style: GoogleFonts.poppins(fontSize: 8, fontWeight: FontWeight.w600, color: Color(int.parse(lastAnswer.authorAvatarColor.replaceFirst('#', '0xFF'))))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(lastAnswer.authorName, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                            if (lastAnswer.hasBeenThereBadge) ...[
                              const SizedBox(width: 3),
                              const Icon(Icons.verified, size: 10, color: HuddlColors.teal),
                            ],
                          ]),
                          Text(lastAnswer.content, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            // Stats row with engagement CTA
            Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 14, color: HuddlColors.textHint),
                const SizedBox(width: 4),
                Text('$parentAnswerCount ${parentAnswerCount == 1 ? "reply" : "replies"}', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
                const SizedBox(width: 12),
                Icon(Icons.thumb_up_outlined, size: 14, color: HuddlColors.textHint),
                const SizedBox(width: 4),
                Text('${question.totalUpvotes}', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
                const Spacer(),
                if (question.hasAiSynthesis)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.auto_awesome, size: 11, color: HuddlColors.aiBlue),
                      const SizedBox(width: 3),
                      Text('AI Summary', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: HuddlColors.aiBlue)),
                    ]),
                  ),
                if (!question.hasAiSynthesis && isUnanswered)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(10)),
                    child: Text('Be first to help', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.white)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
    );
  }

  // ── Question Detail ────────────────────────────────────────────────────
  void _openQuestionDetail(TravelQuestion question) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _QuestionDetailScreen(question: question, communityService: _communityService)));
  }

  // ── Post Question Sheet ────────────────────────────────────────────────
  void _showPostQuestionSheet(BuildContext context) {
    final questionController = TextEditingController();
    final destinationController = TextEditingController();
    final childAgeController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: HuddlColors.gray300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Ask the Community', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
              Row(
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: HuddlColors.successGreen, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('$_onlineCount parents ready to help right now', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.successGreen, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 20),
              Text('Your question', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(14)),
                child: TextField(
                  controller: questionController,
                  maxLines: 4,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. "Going to Tenerife with a 10-month-old — best area to stay?"',
                    hintStyle: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textHint),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildSmallInput('Destination (optional)', 'e.g. Tenerife', destinationController, Icons.place)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildSmallInput('Child age (optional)', 'e.g. 10 months', childAgeController, Icons.child_care)),
                ],
              ),
              const SizedBox(height: 12),
              // Urgency box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: HuddlColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Text('🙋', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Parents typically respond within minutes. AI will provide an instant starter answer while we notify parents who can help!', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.primary, height: 1.4))),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (questionController.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    final newQ = await _communityService.postQuestion(
                      question: questionController.text.trim(),
                      destination: destinationController.text.trim().isNotEmpty ? destinationController.text.trim() : null,
                      childAge: childAgeController.text.trim().isNotEmpty ? childAgeController.text.trim() : null,
                    );
                    if (mounted) {
                      setState(() {});
                      _openQuestionDetail(newQ);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    foregroundColor: HuddlColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: Text('Post Question', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallInput(String label, String hint, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.textDark)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: controller,
            style: GoogleFonts.poppins(fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint),
              prefixIcon: Icon(icon, size: 18, color: HuddlColors.textHint),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// =============================================================================
// QUESTION DETAIL SCREEN — Chat-thread style with live feel
// =============================================================================

class _QuestionDetailScreen extends StatefulWidget {
  final TravelQuestion question;
  final TravelCommunityService communityService;

  const _QuestionDetailScreen({required this.question, required this.communityService});

  @override
  State<_QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends State<_QuestionDetailScreen> with TickerProviderStateMixin {
  final TextEditingController _answerController = TextEditingController();
  bool _isSubmitting = false;
  Timer? _typingTimer;
  bool _showOtherTyping = false;
  String _otherTypingName = '';

  @override
  void initState() {
    super.initState();
    // Simulate someone else typing after a short delay
    final names = ['Sarah M.', 'Tom', 'Priya K.'];
    _typingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) return;
      setState(() {
        _showOtherTyping = timer.tick % 3 != 0;
        _otherTypingName = names[timer.tick % names.length];
      });
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final authorColor = Color(int.parse(q.authorAvatarColor.replaceFirst('#', '0xFF')));

    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Conversation', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            Row(children: [
              Container(width: 5, height: 5, decoration: const BoxDecoration(color: HuddlColors.successGreen, shape: BoxShape.circle)),
              const SizedBox(width: 3),
              Text('${q.answers.where((a) => !a.isAiGenerated).length} parents replied', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.successGreen)),
            ]),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(q.isBookmarked ? Icons.bookmark : Icons.bookmark_outline, size: 22, color: q.isBookmarked ? HuddlColors.primary : HuddlColors.textHint),
            onPressed: () {
              widget.communityService.toggleBookmark(q.id);
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          CircleAvatar(radius: 18, backgroundColor: authorColor.withValues(alpha: 0.15),
                            child: Text(q.authorName[0], style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: authorColor))),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(q.authorName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                            Text(_timeAgo(q.createdAt), style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
                          ])),
                        ]),
                        const SizedBox(height: 14),
                        Text(q.question, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark, height: 1.4)),
                        const SizedBox(height: 12),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          if (q.destination != null) _buildTag(q.destination!, HuddlColors.blue),
                          if (q.childAge != null) _buildTag(q.childAge!, HuddlColors.teal),
                          _buildTag(q.category.label, HuddlColors.primary),
                        ]),
                      ],
                    ),
                  ),

                  // AI Synthesis card (if available)
                  if (q.hasAiSynthesis) ...[
                    const SizedBox(height: 12),
                    _buildAiSynthesisCard(q.aiSynthesis!),
                  ],

                  // Answers section
                  const SizedBox(height: 16),
                  Row(children: [
                    Text('${q.answers.length} ${q.answers.length == 1 ? "Response" : "Responses"}', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                    const Spacer(),
                    if (q.answers.where((a) => !a.isAiGenerated).length >= 2)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text('${q.answers.where((a) => !a.isAiGenerated).length} parents responded', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: HuddlColors.teal)),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  ...q.answers.map((a) => _buildAnswerCard(a)),

                  // Typing indicator
                  if (_showOtherTyping)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        CircleAvatar(radius: 14, backgroundColor: HuddlColors.blue.withValues(alpha: 0.15),
                          child: Text(_otherTypingName[0], style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.blue))),
                        const SizedBox(width: 8),
                        Text('$_otherTypingName is typing an answer', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint, fontStyle: FontStyle.italic)),
                        const SizedBox(width: 4),
                        _AnimatedDots(),
                      ]),
                    ),

                  // CTA for unanswered
                  if (q.answers.where((a) => !a.isAiGenerated).isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFFF3ED), Color(0xFFFFE8D6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(children: [
                        const Text('🙋', style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 8),
                        Text('Be the first parent to help!', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                        const SizedBox(height: 4),
                        Text('${q.authorName} is waiting for a real parent\'s answer. Share your experience below.', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
                      ]),
                    ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          _buildAnswerInput(),
        ],
      ),
    );
  }

  Widget _buildAiSynthesisCard(AiSynthesis synthesis) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFEDF4FF), Color(0xFFF5F9FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HuddlColors.aiBlue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(gradient: HuddlColors.aiGradient, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 14),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI Summary', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              Text('Based on ${synthesis.parentResponseCount} parent responses', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.aiBlue)),
            ])),
          ]),
          const SizedBox(height: 12),
          Text(synthesis.summary, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textDark, height: 1.5)),
          if (synthesis.recommendations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Recommendations', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.teal)),
            const SizedBox(height: 4),
            ...synthesis.recommendations.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle, size: 14, color: HuddlColors.teal),
                const SizedBox(width: 6),
                Expanded(child: Text(r, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textDark, height: 1.3))),
              ]),
            )),
          ],
          if (synthesis.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Watch out for', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.error)),
            const SizedBox(height: 4),
            ...synthesis.warnings.map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber, size: 14, color: HuddlColors.warning),
                const SizedBox(width: 6),
                Expanded(child: Text(w, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textDark, height: 1.3))),
              ]),
            )),
          ],
          if (synthesis.mentionedPlaces.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: synthesis.mentionedPlaces.map((p) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: HuddlColors.aiBlue.withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.place, size: 12, color: HuddlColors.aiBlue),
                const SizedBox(width: 3),
                Text(p, style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.aiBlue, fontWeight: FontWeight.w500)),
              ]),
            )).toList()),
          ],
        ],
      ),
    );
  }

  Widget _buildAnswerCard(TravelAnswer answer) {
    final color = Color(int.parse(answer.authorAvatarColor.replaceFirst('#', '0xFF')));
    final isAi = answer.isAiGenerated;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAi ? const Color(0xFFF8FBFF) : HuddlColors.white,
        borderRadius: BorderRadius.circular(14),
        border: isAi ? Border.all(color: HuddlColors.aiBlue.withValues(alpha: 0.15)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: isAi ? HuddlColors.aiBlue.withValues(alpha: 0.15) : color.withValues(alpha: 0.15),
              child: isAi
                  ? Icon(Icons.auto_awesome, size: 16, color: HuddlColors.aiBlue)
                  : Text(answer.authorName[0], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(answer.authorName, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: isAi ? HuddlColors.aiBlue : HuddlColors.textDark)),
                const SizedBox(width: 6),
                if (answer.hasBeenThereBadge && !isAi)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.verified, size: 10, color: HuddlColors.teal),
                      const SizedBox(width: 2),
                      Text('Been There', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: HuddlColors.teal)),
                    ]),
                  ),
                if (isAi)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text('AI', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: HuddlColors.aiBlue)),
                  ),
              ]),
              Row(children: [
                Text(_timeAgo(answer.createdAt), style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
                if (answer.childAgesAtVisit != null) ...[
                  Text(' · ', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
                  Text('Visited with ${answer.childAgesAtVisit}', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.teal)),
                ],
              ]),
            ])),
          ]),
          const SizedBox(height: 10),
          Text(answer.content, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textDark, height: 1.5)),
          const SizedBox(height: 10),
          Row(children: [
            GestureDetector(
              onTap: () {
                widget.communityService.upvoteAnswer(widget.question.id, answer.id);
                setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: answer.upvotedBy.contains('current_user') ? HuddlColors.primary.withValues(alpha: 0.1) : HuddlColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(answer.upvotedBy.contains('current_user') ? Icons.thumb_up : Icons.thumb_up_outlined, size: 14,
                      color: answer.upvotedBy.contains('current_user') ? HuddlColors.primary : HuddlColors.textHint),
                  const SizedBox(width: 4),
                  Text('${answer.upvotes}', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500,
                      color: answer.upvotedBy.contains('current_user') ? HuddlColors.primary : HuddlColors.textSecondary)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                widget.communityService.saveAnswer(answer, widget.question);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Answer saved to your trip research!', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.white)),
                  backgroundColor: HuddlColors.teal,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ));
              },
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
          ]),
        ],
      ),
    );
  }

  Widget _buildAnswerInput() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          boxShadow: [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showOtherTyping)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Text('$_otherTypingName is typing...', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint, fontStyle: FontStyle.italic)),
                ]),
              ),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(20)),
                    child: TextField(
                      controller: _answerController,
                      style: GoogleFonts.poppins(fontSize: 14),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitAnswer(),
                      decoration: InputDecoration(
                        hintText: 'Share your experience...',
                        hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _submitAnswer,
                  child: Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(gradient: HuddlColors.primaryGradient, shape: BoxShape.circle),
                    child: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: HuddlColors.white, strokeWidth: 2))
                        : const Icon(Icons.send, color: HuddlColors.white, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitAnswer() async {
    if (_answerController.text.trim().isEmpty || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    await widget.communityService.postAnswer(
      questionId: widget.question.id,
      content: _answerController.text.trim(),
    );

    _answerController.clear();
    setState(() => _isSubmitting = false);
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// ── Animated typing dots ──────────────────────────────────────────────────
class _AnimatedDots extends StatefulWidget {
  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 500)));
    _animations = _controllers.map((c) => Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => AnimatedBuilder(
        animation: _animations[i],
        builder: (_, __) => Container(
          width: 4, height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: HuddlColors.textHint.withValues(alpha: 0.3 + _animations[i].value * 0.7),
            shape: BoxShape.circle,
          ),
        ),
      )),
    );
  }
}
