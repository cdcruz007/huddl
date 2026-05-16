import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ai_knowledge_base_service.dart';
import '../../services/ai_knowledge_flywheel_service.dart';
import '../../theme/huddl_colors.dart';
import 'send_hub_screen.dart';

// =============================================================================
// INSIGHTS SCREEN
//
// The Insights feed: a unified, searchable knowledge base combining:
//   1. Curated expert articles (from AiKnowledgeBaseService — NHS, NCT, etc.)
//   2. Community insights articles (from AiKnowledgeFlywheelService — Firestore)
//   3. SEND Navigator — full SendHubScreen embedded as tab 3
//
// Navigation:
//   Top tabs: "Community" | "Expert Guides" | "SEND"
//   Category chip row (scrollable — hidden on SEND tab)
//   Search bar (hidden on SEND tab)
//   Article cards with contributor credit
//
// Moderator view (debug builds or isAdmin):
//   Floating "Review Queue" badge showing pending article count
//   Tapping opens the inline pending-review panel
// =============================================================================

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  KnowledgeCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final isSendTab = _tabController.index == 2;
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(tabController: _tabController),
                if (!isSendTab) _SearchBar(controller: _searchController),
                if (!isSendTab)
                  _CategoryChips(
                    selected: _selectedCategory,
                    onSelected: (cat) =>
                        setState(() => _selectedCategory = cat),
                  ),
                if (!isSendTab) const SizedBox(height: 4),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _CommunityTab(
                        searchQuery: _searchQuery,
                        selectedCategory: _selectedCategory,
                      ),
                      _ExpertTab(
                        searchQuery: _searchQuery,
                        selectedCategory: _selectedCategory,
                      ),
                      const _SendTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final TabController tabController;
  const _Header({required this.tabController});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row ──────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Insights',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? HuddlColors.darkTextPrimary
                      : HuddlColors.textPrimary,
                ),
              ),
              // Pending review badge — debug only
              if (kDebugMode) _PendingReviewBadge(),
            ],
          ),
          const SizedBox(height: 8),
          // ── Tab bar — same style as Discover (underline) ───────
          TabBar(
            controller: tabController,
            tabs: const [
              Tab(text: 'Community'),
              Tab(text: 'Expert Guides'),
              Tab(text: 'SEND'),
            ],
            labelColor: HuddlColors.primary,
            unselectedLabelColor: HuddlColors.textTertiary,
            labelStyle: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            indicatorColor: HuddlColors.primary,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: isDark ? HuddlColors.darkDivider : HuddlColors.divider,
          ),
        ],
      ),
    );
  }
}

// ─── Search bar ───────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: controller,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search Insights…',
          hintStyle: GoogleFonts.poppins(
            fontSize: 14,
            color: HuddlColors.textHint,
          ),
          prefixIcon: const Icon(Icons.search, color: HuddlColors.textHint, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, v, __) => v.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: controller.clear,
                    color: HuddlColors.textHint,
                  )
                : const SizedBox.shrink(),
          ),
          filled: true,
          fillColor: isDark ? HuddlColors.darkSurfaceVariant : HuddlColors.inputBg,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? HuddlColors.darkDivider : HuddlColors.inputBorderLight,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: HuddlColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ─── Category chips ───────────────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final KnowledgeCategory? selected;
  final ValueChanged<KnowledgeCategory?> onSelected;

  const _CategoryChips({required this.selected, required this.onSelected});

  static const List<(KnowledgeCategory, String, IconData)> _cats = [
    (KnowledgeCategory.sleep,           'Sleep',         Icons.bedtime_outlined),
    (KnowledgeCategory.feeding,         'Feeding',       Icons.restaurant_outlined),
    (KnowledgeCategory.health,          'Health',        Icons.favorite_outline),
    (KnowledgeCategory.mentalHealth,    'Wellbeing',     Icons.self_improvement_outlined),
    (KnowledgeCategory.education,       'Education',     Icons.school_outlined),
    (KnowledgeCategory.activities,      'Activities',    Icons.directions_run_outlined),
    (KnowledgeCategory.baby,            'Baby',          Icons.child_care_outlined),
    (KnowledgeCategory.toddler,         'Toddler',       Icons.emoji_people_outlined),
    (KnowledgeCategory.pregnancy,       'Pregnancy',     Icons.pregnant_woman_outlined),
    (KnowledgeCategory.finance,         'Finance',       Icons.account_balance_outlined),
    (KnowledgeCategory.safety,          'Safety',        Icons.shield_outlined),
    (KnowledgeCategory.senDisability,   'SEN',           Icons.accessibility_outlined),
    (KnowledgeCategory.singleParent,    'Single Parent', Icons.person_outlined),
    (KnowledgeCategory.dadSpecific,     'Dads',          Icons.face_outlined),
    (KnowledgeCategory.parentalWellbeing,'Self-Care',    Icons.spa_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _cats.length + 1, // +1 for "All" chip
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            final isAll = selected == null;
            return _Chip(
              label: 'All',
              icon: Icons.auto_awesome_outlined,
              isSelected: isAll,
              onTap: () => onSelected(null),
            );
          }
          final (cat, label, icon) = _cats[i - 1];
          return _Chip(
            label: label,
            icon: icon,
            isSelected: selected == cat,
            onTap: () => onSelected(selected == cat ? null : cat),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? HuddlColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? HuddlColors.primary
                : HuddlColors.inputBorderLight,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : HuddlColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? Colors.white : HuddlColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SEND tab ─────────────────────────────────────────────────────────────────
// Shows the SEND Navigator hero card at the top, then embeds SendHubScreen
// below it.  Wrapped in a local Navigator so internal push routes stay scoped.

class _SendTab extends StatefulWidget {
  const _SendTab();

  @override
  State<_SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<_SendTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // preserve chat state across tab switches

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // ── Embedded SendHubScreen only — no hero card banner above it.
    // The user is already on the SEND tab, so a redundant title tile adds
    // no value.  SendHubScreen itself carries the SEND Navigator header.
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => const _EmbeddedSendHubScreen(),
      ),
    );
  }
}

/// SendHubScreen with the header back-button hidden — it is embedded in a tab
/// so the user switches tabs rather than pressing back.
class _EmbeddedSendHubScreen extends StatelessWidget {
  const _EmbeddedSendHubScreen();

  @override
  Widget build(BuildContext context) {
    return const SendHubScreen(embedded: true);
  }
}

// ─── Community tab ────────────────────────────────────────────────────────────

class _CommunityTab extends StatelessWidget {
  final String searchQuery;
  final KnowledgeCategory? selectedCategory;

  const _CommunityTab({
    required this.searchQuery,
    required this.selectedCategory,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommunityWisdomArticle>>(
      stream: AiKnowledgeFlywheelService().publishedArticlesStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorState(
            message: 'Could not load community wisdom.\n${snap.error}',
          );
        }

        var articles = snap.data ?? [];

        // Apply category filter
        if (selectedCategory != null) {
          articles = articles
              .where((a) => a.category == selectedCategory)
              .toList();
        }

        // Apply search filter
        if (searchQuery.isNotEmpty) {
          articles = articles.where((a) {
            return a.title.toLowerCase().contains(searchQuery) ||
                a.summary.toLowerCase().contains(searchQuery) ||
                a.tags.any((t) => t.toLowerCase().contains(searchQuery));
          }).toList();
        }

        if (articles.isEmpty) {
          return _EmptyState(
            icon: Icons.auto_awesome_outlined,
            title: searchQuery.isNotEmpty
                ? 'No results for "$searchQuery"'
                : 'No community wisdom yet',
            subtitle: searchQuery.isNotEmpty
                ? 'Try a different search term or category.'
                : 'When parents share helpful insights in group chats, '
                    'they\'ll appear here as Insights articles.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: articles.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _WisdomCard(article: articles[i]),
        );
      },
    );
  }
}

// ─── Expert Guides tab ────────────────────────────────────────────────────────

class _ExpertTab extends StatelessWidget {
  final String searchQuery;
  final KnowledgeCategory? selectedCategory;

  const _ExpertTab({
    required this.searchQuery,
    required this.selectedCategory,
  });

  @override
  Widget build(BuildContext context) {
    final svc = AiKnowledgeBaseService();

    List<KnowledgeArticle> articles;
    if (selectedCategory != null) {
      articles = svc.getArticlesByCategory(selectedCategory!);
    } else if (searchQuery.isNotEmpty) {
      articles = svc.searchArticles(searchQuery);
    } else {
      articles = svc.allArticles;
    }

    // Secondary search filter when category is selected
    if (selectedCategory != null && searchQuery.isNotEmpty) {
      articles = articles.where((a) {
        return a.title.toLowerCase().contains(searchQuery) ||
            a.summary.toLowerCase().contains(searchQuery) ||
            a.tags.any((t) => t.toLowerCase().contains(searchQuery));
      }).toList();
    }

    if (articles.isEmpty) {
      return _EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No expert guides found',
        subtitle: 'Try clearing the search or selecting a different category.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: articles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _ExpertCard(article: articles[i]),
    );
  }
}

// _SendHeroCard removed — redundant when user is already on the SEND tab.

// ─── Community wisdom card ────────────────────────────────────────────────────

class _WisdomCard extends StatelessWidget {
  final CommunityWisdomArticle article;
  const _WisdomCard({required this.article});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _openArticle(context),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? HuddlColors.darkDivider
                : HuddlColors.inputBorderLight,
          ),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: HuddlColors.gray900.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top bar — category + flywheel badge
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: HuddlColors.primary.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 13,
                    color: HuddlColors.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Insights',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.primary,
                    ),
                  ),
                  const Spacer(),
                  _CategoryBadge(category: article.category),
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? HuddlColors.darkTextPrimary
                          : HuddlColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    article.summary,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: HuddlColors.textSecondary,
                      height: 1.45,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  // Tags
                  if (article.tags.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: article.tags
                          .take(3)
                          .map((t) => _Tag(label: t))
                          .toList(),
                    ),
                  const SizedBox(height: 12),
                  // Footer — contributor + engagement
                  Row(
                    children: [
                      // Contributor avatar
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: HuddlColors.primary.withValues(alpha: 0.15),
                        child: Text(
                          article.contributorFirstName.isNotEmpty
                              ? article.contributorFirstName[0].toUpperCase()
                              : 'P',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          article.contributorCredit,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: HuddlColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Upvotes
                      Row(
                        children: [
                          Icon(
                            Icons.favorite_outline,
                            size: 14,
                            color: HuddlColors.textHint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${article.upvotes}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: HuddlColors.textHint,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      // Read indicator
                      Row(
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 14,
                            color: HuddlColors.textHint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${article.viewCount}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: HuddlColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openArticle(BuildContext context) {
    AiKnowledgeFlywheelService().recordView(article.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WisdomArticleScreen(article: article),
      ),
    );
  }
}

// ─── Expert article card ──────────────────────────────────────────────────────

class _ExpertCard extends StatelessWidget {
  final KnowledgeArticle article;
  const _ExpertCard({required this.article});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ExpertArticleScreen(article: article),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? HuddlColors.darkDivider
                : HuddlColors.inputBorderLight,
          ),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: HuddlColors.gray900.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Source banner
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: BoxDecoration(
                color: HuddlColors.teal.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined,
                      size: 13, color: HuddlColors.teal),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      article.source,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.teal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _CategoryBadge(category: article.category, teal: true),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? HuddlColors.darkTextPrimary
                          : HuddlColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    article.summary,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: HuddlColors.textSecondary,
                      height: 1.45,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: article.tags
                          .take(3)
                          .map((t) => _Tag(label: t, teal: true))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.menu_book_outlined,
                          size: 14, color: HuddlColors.textHint),
                      const SizedBox(width: 5),
                      Text(
                        'Expert guide',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.textHint,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Read more →',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.teal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Wisdom article full-screen reader ───────────────────────────────────────

class _WisdomArticleScreen extends StatefulWidget {
  final CommunityWisdomArticle article;
  const _WisdomArticleScreen({required this.article});

  @override
  State<_WisdomArticleScreen> createState() => _WisdomArticleScreenState();
}

class _WisdomArticleScreenState extends State<_WisdomArticleScreen> {
  bool _upvoted = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final article = widget.article;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Upvote button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _upvoted ? null : _upvote,
              icon: Icon(
                _upvoted ? Icons.favorite : Icons.favorite_outline,
                size: 18,
                color: _upvoted ? HuddlColors.error : HuddlColors.textSecondary,
              ),
              label: Text(
                _upvoted ? 'Helpful!' : 'Helpful',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _upvoted ? HuddlColors.error : HuddlColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Huddl Wisdom badge
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lightbulb,
                          size: 12, color: HuddlColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Insights',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _CategoryBadge(category: article.category),
              ],
            ),
            const SizedBox(height: 14),
            // Title
            Text(
              article.title,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? HuddlColors.darkTextPrimary
                    : HuddlColors.textPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
            // Contributor credit
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? HuddlColors.darkSurface
                    : HuddlColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: HuddlColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: HuddlColors.primary.withValues(alpha: 0.15),
                    child: Text(
                      article.contributorFirstName.isNotEmpty
                          ? article.contributorFirstName[0].toUpperCase()
                          : 'P',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.contributorCredit,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? HuddlColors.darkTextPrimary
                                : HuddlColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Shared in ${article.groupName}',
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
            const SizedBox(height: 20),
            // Body
            Text(
              article.body,
              style: GoogleFonts.poppins(
                fontSize: 15,
                height: 1.65,
                color: isDark
                    ? HuddlColors.darkTextSecondary
                    : HuddlColors.textDark,
              ),
            ),
            const SizedBox(height: 20),
            // Tags
            if (article.tags.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children:
                    article.tags.map((t) => _Tag(label: t)).toList(),
              ),
              const SizedBox(height: 20),
            ],
            // Engagement stats
            Row(
              children: [
                Icon(Icons.favorite,
                    size: 16,
                    color: _upvoted ? HuddlColors.error : HuddlColors.textHint),
                const SizedBox(width: 4),
                Text(
                  '${article.upvotes + (_upvoted ? 1 : 0)} parents found this helpful',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.textHint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _upvote() async {
    setState(() => _upvoted = true);
    await AiKnowledgeFlywheelService().upvoteArticle(widget.article.id);
  }
}

// ─── Expert article full-screen reader ───────────────────────────────────────

class _ExpertArticleScreen extends StatelessWidget {
  final KnowledgeArticle article;
  const _ExpertArticleScreen({required this.article});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Source badge
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: HuddlColors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_outlined,
                          size: 12, color: HuddlColors.teal),
                      const SizedBox(width: 4),
                      Text(
                        article.source,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _CategoryBadge(category: article.category, teal: true),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              article.title,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? HuddlColors.darkTextPrimary
                    : HuddlColors.textPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              article.summary,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: HuddlColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              article.body,
              style: GoogleFonts.poppins(
                fontSize: 15,
                height: 1.65,
                color: isDark
                    ? HuddlColors.darkTextSecondary
                    : HuddlColors.textDark,
              ),
            ),
            if (article.tags.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: article.tags
                    .map((t) => _Tag(label: t, teal: true))
                    .toList(),
              ),
            ],
            if (article.sourceUrl != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? HuddlColors.darkSurface
                      : HuddlColors.successBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: HuddlColors.teal.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.open_in_new,
                        size: 16, color: HuddlColors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Read the full guide at ${article.source}',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: HuddlColors.teal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Pending review badge (moderator / debug) ─────────────────────────────────

class _PendingReviewBadge extends StatelessWidget {
  const _PendingReviewBadge();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommunityWisdomArticle>>(
      stream: AiKnowledgeFlywheelService().pendingReviewStream(),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _showReviewSheet(context, snap.data ?? []),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: HuddlColors.warningBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: HuddlColors.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pending_actions,
                    size: 14, color: HuddlColors.warning),
                const SizedBox(width: 4),
                Text(
                  '$count to review',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.warningDark,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReviewSheet(
      BuildContext context, List<CommunityWisdomArticle> articles) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewQueueSheet(articles: articles),
    );
  }
}

// ─── Moderator review queue bottom sheet ─────────────────────────────────────

class _ReviewQueueSheet extends StatelessWidget {
  final List<CommunityWisdomArticle> articles;
  const _ReviewQueueSheet({required this.articles});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: HuddlColors.inputBorderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.pending_actions,
                      color: HuddlColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Pending Review (${articles.length})',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                itemCount: articles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) =>
                    _ReviewCard(article: articles[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final CommunityWisdomArticle article;
  const _ReviewCard({required this.article});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? HuddlColors.darkSurfaceVariant : HuddlColors.gray100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuddlColors.inputBorderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            article.title,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            article.summary,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: HuddlColors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            'From: ${article.groupName} · ${article.contributorCredit}',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: HuddlColors.textHint,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _reject(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: HuddlColors.error,
                    side: const BorderSide(color: HuddlColors.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text('Reject',
                      style: GoogleFonts.poppins(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _approve(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text('Publish',
                      style: GoogleFonts.poppins(fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approve(BuildContext context) async {
    final ok = await AiKnowledgeFlywheelService().approveArticle(article.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Article published!' : 'Failed to publish'),
        backgroundColor: ok ? HuddlColors.success : HuddlColors.error,
      ));
    }
  }

  Future<void> _reject(BuildContext context) async {
    final ok = await AiKnowledgeFlywheelService().rejectArticle(article.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Article rejected' : 'Failed to reject'),
        backgroundColor: ok ? HuddlColors.textSecondary : HuddlColors.error,
      ));
    }
  }
}

// ─── Shared helper widgets ────────────────────────────────────────────────────

class _CategoryBadge extends StatelessWidget {
  final KnowledgeCategory category;
  final bool teal;
  const _CategoryBadge({required this.category, this.teal = false});

  String get _label => category.name
      .replaceAllMapped(
        RegExp(r'(?<=[a-z])[A-Z]'),
        (m) => ' ${m.group(0)}',
      )
      .replaceFirst(
        category.name[0],
        category.name[0].toUpperCase(),
      );

  @override
  Widget build(BuildContext context) {
    final color = teal ? HuddlColors.teal : HuddlColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool teal;
  const _Tag({required this.label, this.teal = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: teal
            ? HuddlColors.teal.withValues(alpha: 0.08)
            : HuddlColors.gray100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: teal
              ? HuddlColors.teal.withValues(alpha: 0.2)
              : HuddlColors.inputBorderLight,
        ),
      ),
      child: Text(
        '#$label',
        style: GoogleFonts.poppins(
          fontSize: 11,
          color: teal ? HuddlColors.teal : HuddlColors.textSecondary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: HuddlColors.textHint),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 16,
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

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: HuddlColors.textHint),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: HuddlColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
