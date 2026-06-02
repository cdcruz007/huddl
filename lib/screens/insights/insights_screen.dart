import 'package:flutter/foundation.dart';
import '../../theme/huddl_icons.dart';
import 'package:flutter/material.dart';
import '../../widgets/animations/huddl_spring_animations.dart';
import '../../widgets/huddl_character.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/ai_knowledge_base_service.dart';
import '../../services/ai_knowledge_flywheel_service.dart';
import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';
import '../../widgets/common/huddl_button.dart';
import '../../widgets/common/huddl_network_image.dart';
import '../../constants/app_text_styles.dart';
import '../main_shell.dart';

// ── UHD hero images per article ID (sourced from Pexels / Unsplash) ─────────
const Map<String, String> _kArticleHeroImages = {
  'preg_001': 'https://images.pexels.com/photos/3662667/pexels-photo-3662667.jpeg?auto=compress&cs=tinysrgb&w=800',
  'preg_002': 'https://images.pexels.com/photos/8942991/pexels-photo-8942991.jpeg?auto=compress&cs=tinysrgb&w=800',
  'preg_003': 'https://images.pexels.com/photos/35537/child-children-girl-happy.jpg?auto=compress&cs=tinysrgb&w=800',
  'preg_004': 'https://images.pexels.com/photos/1648377/pexels-photo-1648377.jpeg?auto=compress&cs=tinysrgb&w=800',
  'nb_001':   'https://images.pexels.com/photos/35537/child-children-girl-happy.jpg?auto=compress&cs=tinysrgb&w=800',
  'nb_002':   'https://images.pexels.com/photos/3662667/pexels-photo-3662667.jpeg?auto=compress&cs=tinysrgb&w=800',
  'feed_001': 'https://images.pexels.com/photos/6815664/pexels-photo-6815664.jpeg?auto=compress&cs=tinysrgb&w=800',
  'feed_002': 'https://images.pexels.com/photos/6624329/pexels-photo-6624329.jpeg?auto=compress&cs=tinysrgb&w=800',
  'health_001': 'https://images.pexels.com/photos/4386466/pexels-photo-4386466.jpeg?auto=compress&cs=tinysrgb&w=800',
  'health_002': 'https://images.pexels.com/photos/4386467/pexels-photo-4386467.jpeg?auto=compress&cs=tinysrgb&w=800',
  'mh_001':   'https://images.pexels.com/photos/3807571/pexels-photo-3807571.jpeg?auto=compress&cs=tinysrgb&w=800',
  'mh_002':   'https://images.pexels.com/photos/6964122/pexels-photo-6964122.jpeg?auto=compress&cs=tinysrgb&w=800',
  'dev_001':  'https://images.pexels.com/photos/3662674/pexels-photo-3662674.jpeg?auto=compress&cs=tinysrgb&w=800',
  'tod_001':  'https://images.pexels.com/photos/1648386/pexels-photo-1648386.jpeg?auto=compress&cs=tinysrgb&w=800',
  'tod_002':  'https://images.pexels.com/photos/6624361/pexels-photo-6624361.jpeg?auto=compress&cs=tinysrgb&w=800',
  'sch_001':  'https://images.pexels.com/photos/5905857/pexels-photo-5905857.jpeg?auto=compress&cs=tinysrgb&w=800',
  'dad_001':  'https://images.pexels.com/photos/1648377/pexels-photo-1648377.jpeg?auto=compress&cs=tinysrgb&w=800',
  'dad_002':  'https://images.pexels.com/photos/3807571/pexels-photo-3807571.jpeg?auto=compress&cs=tinysrgb&w=800',
  'fin_001':  'https://images.pexels.com/photos/4386373/pexels-photo-4386373.jpeg?auto=compress&cs=tinysrgb&w=800',
};

// ── Tag-filter notification — bubbles a tag string up to InsightsScreen ───────
class _TagFilterNotification extends Notification {
  final String tag;
  const _TagFilterNotification(this.tag);
}

// ── Source brand colours ─────────────────────────────────────────────────────
Color _sourceColor(String source) {
  final s = source.toLowerCase();
  if (s.contains('nhs'))      return HuddlColors.partnerNhs;
  if (s.contains('nct'))      return HuddlColors.partnerNct;
  if (s.contains('bounty'))   return HuddlColors.partnerBounty;
  if (s.contains('netmums'))  return HuddlColors.brandTeal;
  if (s.contains('dadsnet'))  return HuddlColors.infoBlue;
  if (s.contains('gov'))      return HuddlColors.neutral900;
  return HuddlColors.nearBlack;
}

// =============================================================================
// INSIGHTS SCREEN
//
// The Insights feed: a unified, searchable knowledge base combining:
//   1. Curated expert articles (from AiKnowledgeBaseService — NHS, NCT, etc.)
//   2. Community insights articles (from AiKnowledgeFlywheelService — Firestore)
//
// Navigation:
//   Single unified feed (Expert Guides + Community Wisdom interleaved)
//   Category chip row (scrollable)
//   Search bar
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

class _InsightsScreenState extends State<InsightsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  KnowledgeCategory? _selectedCategory;
  bool _searchOpen = false;
  // Sort options: 'newest' | 'a-z' | 'relevance'
  String _sortBy = 'relevance';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    HapticFeedback.selectionClick();
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _showSortSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SortSheet(
        current: _sortBy,
        onSelected: (v) => setState(() => _sortBy = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<_TagFilterNotification>(
      onNotification: (n) {
        // When a hashtag pill is tapped, open search and pre-fill with the tag
        setState(() {
          _searchOpen = true;
          _searchController.text = n.tag;
          _searchQuery = n.tag.toLowerCase();
        });
        return true;
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: title + search icon ───────────────────────────
            _Header(
              searchOpen: _searchOpen,
              onSearchToggle: _toggleSearch,
              searchController: _searchController,
            ),
            // ── Filter/sort row ────────────────────────────────────────
            _FilterSortRow(
              selectedCategory: _selectedCategory,
              sortBy: _sortBy,
              onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
              onSortTap: _showSortSheet,
            ),
            const SizedBox(height: 2),
            // ── SEND Navigator banner (school-age children only) ───────
            _SendNavigatorBanner(),
            // ── Unified feed ───────────────────────────────────────────
            Expanded(
              child: _UnifiedInsightsFeed(
                searchQuery: _searchQuery,
                selectedCategory: _selectedCategory,
                sortBy: _sortBy,
              ),
            ),
          ],
        ),
      ),
    ), // Scaffold
    ); // NotificationListener
  }
}

// ─── SEND Navigator banner (school-age children only) ────────────────────────

class _SendNavigatorBanner extends StatelessWidget {
  const _SendNavigatorBanner();

  /// Always show — SEND support is relevant to all families.
  bool _isEligible() => true;

  @override
  Widget build(BuildContext context) {
    if (!_isEligible()) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            // SEND is Discover sub-tab 4 — switch shell to Discover then open SEND
            MainShell.shellKey.currentState?.switchDiscoverTab(4);
          },
          child: Ink(
            decoration: BoxDecoration(
              color: isDark
                  ? HuddlColors.primary.withValues(alpha: 0.12)
                  : HuddlColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: HuddlColors.primary.withValues(alpha: isDark ? 0.35 : 0.22),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    HuddlIcons.school,
                    size: 18,
                    color: HuddlColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SEND Navigator',
                        style: HuddlText.body(
                          weight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                      Text(
                        'EHCP support, deadlines & AI advisor',
                        style: HuddlText.caption(color: isDark
                            ? HuddlColors.primary.withValues(alpha: 0.75)
                            : HuddlColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(
                  HuddlIcons.arrowForward,
                  size: 14,
                  color: HuddlColors.primary.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Header (title + search icon) ────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool searchOpen;
  final VoidCallback onSearchToggle;
  final TextEditingController searchController;

  const _Header({
    required this.searchOpen,
    required this.onSearchToggle,
    required this.searchController,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row + search icon ────────────────────────────
          Row(
            children: [
              Text(
                'Insights',
                style: HuddlText.display(),
              ),
              const Spacer(),
              if (kDebugMode) _PendingReviewBadge(),
              // Search toggle icon
              IconButton(
                onPressed: onSearchToggle,
                icon: Icon(
                  searchOpen ? HuddlIcons.searchOff : HuddlIcons.search,
                  size: 22,
                  color: searchOpen ? HuddlColors.primary : HuddlColors.textSecondary,
                ),
                tooltip: searchOpen ? 'Close search' : 'Search',
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
            ],
          ),
          // ── Inline search field (animated) ─────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: searchOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 4),
            secondChild: Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8, top: 2),
              child: TextField(
                controller: searchController,
                autofocus: true,
                style: HuddlText.body(),
                decoration: InputDecoration(
                  hintText: 'Search insights…',
                  hintStyle: HuddlText.body(color: HuddlColors.textHint),
                  prefixIcon: const Icon(HuddlIcons.search, color: HuddlColors.textTertiary, size: 20),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: searchController,
                    builder: (_, v, __) => v.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(HuddlIcons.close, size: 16),
                            onPressed: searchController.clear,
                            color: HuddlColors.textHint,
                          )
                        : const SizedBox.shrink(),
                  ),
                  filled: true,
                  fillColor: isDark ? HuddlColors.darkSurfaceVariant : HuddlColors.inputBg,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: isDark ? HuddlColors.darkDivider : HuddlColors.inputBorderLight,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: HuddlColors.primary, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Filter + Sort row (Discover-style) ─────────────────────────────────────

class _FilterSortRow extends StatelessWidget {
  final KnowledgeCategory? selectedCategory;
  final String sortBy;
  final ValueChanged<KnowledgeCategory?> onCategorySelected;
  final VoidCallback onSortTap;

  const _FilterSortRow({
    required this.selectedCategory,
    required this.sortBy,
    required this.onCategorySelected,
    required this.onSortTap,
  });

  String get _sortLabel {
    switch (sortBy) {
      case 'newest': return 'Newest';
      case 'a-z':    return 'A–Z';
      default:       return 'Relevance';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFilter = selectedCategory != null;
    final sortActive = sortBy != 'relevance';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: GestureDetector(
        onTap: onSortTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: (sortActive || hasFilter)
                ? HuddlColors.primary
                : (isDark ? HuddlColors.darkSurface : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (sortActive || hasFilter)
                  ? HuddlColors.primary
                  : HuddlColors.inputBorderLight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                HuddlIcons.filter,
                size: 15,
                color: (sortActive || hasFilter)
                    ? Colors.white
                    : HuddlColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                (sortActive || hasFilter) ? _sortLabel : 'Filter & Sort',
                style: HuddlText.body(color: (sortActive || hasFilter) ? Colors.white : HuddlColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sort bottom sheet ────────────────────────────────────────────────────────

class _SortSheet extends StatelessWidget {
  final String current;
  final ValueChanged<String> onSelected;

  const _SortSheet({required this.current, required this.onSelected});

  static const _options = [
    ('relevance', 'Relevance', HuddlIcons.ai),
    ('newest',    'Newest first', HuddlIcons.clock),
    ('a-z',       'A – Z', HuddlIcons.sortAscending),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? HuddlColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: HuddlColors.inputBorderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(HuddlIcons.filter, size: 18, color: HuddlColors.textTertiary),
              const SizedBox(width: 8),
              Text('Sort by',
                style: HuddlText.body(weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          ..._options.map((opt) {
            final (value, label, icon) = opt;
            final selected = current == value;
            return GestureDetector(
              onTap: () {
                onSelected(value);
                Navigator.pop(context);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? HuddlColors.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? HuddlColors.primary : HuddlColors.inputBorderLight,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18,
                        color: selected ? HuddlColors.primary : HuddlColors.textSecondary),
                    const SizedBox(width: 12),
                    Text(label,
                      style: HuddlText.body(),
                    ),
                    if (selected) ...[
                      const Spacer(),
                      const Icon(HuddlIcons.check, size: 18, color: HuddlColors.primary),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Community tab ────────────────────────────────────────────────────────────

class _CommunityTab extends StatefulWidget {
  final String searchQuery;
  final KnowledgeCategory? selectedCategory;
  final String sortBy;

  const _CommunityTab({
    required this.searchQuery,
    required this.selectedCategory,
    required this.sortBy,
  });

  @override
  State<_CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<_CommunityTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required for keepAlive
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

        if (widget.selectedCategory != null) {
          articles = articles.where((a) => a.category == widget.selectedCategory).toList();
        }
        if (widget.searchQuery.isNotEmpty) {
          articles = articles.where((a) {
            return a.title.toLowerCase().contains(widget.searchQuery) ||
                a.summary.toLowerCase().contains(widget.searchQuery) ||
                a.tags.any((t) => t.toLowerCase().contains(widget.searchQuery));
          }).toList();
        }
        // Apply sort
        if (widget.sortBy == 'a-z') {
          articles.sort((a, b) => a.title.compareTo(b.title));
        }
        // 'newest' and 'relevance' use default stream ordering (newest first)

        if (articles.isEmpty) {
          return _EmptyState(
            icon: HuddlIcons.ai,
            illustrationAsset: widget.searchQuery.isEmpty
                ? 'assets/illustrations/growth_yellow.webp'
                : 'assets/illustrations/search_found.webp',
            title: widget.searchQuery.isNotEmpty
                ? 'No results for "${widget.searchQuery}"'
                : 'No community wisdom yet',
            subtitle: widget.searchQuery.isNotEmpty
                ? 'Try a different search term or category.'
                : 'When parents share helpful insights in group chats, '
                    'they\'ll appear here as Insights articles.',
          );
        }

        return ListView.separated(
          controller: _scrollCtrl,
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

class _ExpertTab extends StatefulWidget {
  final String searchQuery;
  final KnowledgeCategory? selectedCategory;
  final String sortBy;

  const _ExpertTab({
    required this.searchQuery,
    required this.selectedCategory,
    required this.sortBy,
  });

  @override
  State<_ExpertTab> createState() => _ExpertTabState();
}

class _ExpertTabState extends State<_ExpertTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required for keepAlive
    final svc = AiKnowledgeBaseService();

    List<KnowledgeArticle> articles;
    if (widget.selectedCategory != null) {
      articles = svc.getArticlesByCategory(widget.selectedCategory!);
    } else if (widget.searchQuery.isNotEmpty) {
      articles = svc.searchArticles(widget.searchQuery);
    } else {
      articles = svc.allArticles;
    }

    if (widget.selectedCategory != null && widget.searchQuery.isNotEmpty) {
      articles = articles.where((a) {
        return a.title.toLowerCase().contains(widget.searchQuery) ||
            a.summary.toLowerCase().contains(widget.searchQuery) ||
            a.tags.any((t) => t.toLowerCase().contains(widget.searchQuery));
      }).toList();
    }

    // Apply sort
    final sorted = List<KnowledgeArticle>.from(articles);
    if (widget.sortBy == 'a-z') {
      sorted.sort((a, b) => a.title.compareTo(b.title));
    } else if (widget.sortBy == 'newest') {
      sorted.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    } else {
      // relevance — sort by relevanceWeight descending
      sorted.sort((a, b) => b.relevanceWeight.compareTo(a.relevanceWeight));
    }

    if (sorted.isEmpty) {
      return _EmptyState(
        icon: HuddlIcons.menuBook,
        illustrationAsset: 'assets/illustrations/ui_design.webp',
        title: 'No expert guides found',
        subtitle: 'Try clearing the search or selecting a different category.',
      );
    }

    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, i) => _ExpertCard(
            article: sorted[i],
            onTagTap: (tag) => _TagFilterNotification(tag).dispatch(context),
          ),
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
            // Top bar — "Parent shared" badge or "AI curated" label + category
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: article.isParentShared
                    ? HuddlColors.accentAmber.withValues(alpha: 0.10)
                    : HuddlColors.primary.withValues(alpha: 0.07),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    article.isParentShared
                        ? HuddlIcons.user
                        : HuddlIcons.ai,
                    size: 13,
                    color: article.isParentShared
                        ? HuddlColors.accentAmber
                        : HuddlColors.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    article.isParentShared ? 'Parent shared' : 'AI curated',
                    style: HuddlText.caption(
                      weight: FontWeight.w600,
                      color: article.isParentShared
                          ? HuddlColors.accentAmber
                          : HuddlColors.primary,
                    ),
                  ),
                  const Spacer(),
                  _CategoryBadge(category: article.category),
                ],
              ),
            ),
            // Hero image — shown when heroImageUrl is present
            if (article.heroImageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(0),
                  topRight: Radius.circular(0),
                ),
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: Image.network(
                    article.heroImageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return _ShimmerBox(
                        width: double.infinity,
                        height: 120,
                        borderRadius: 0,
                      );
                    },
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      color: HuddlColors.primary.withValues(alpha: 0.06),
                      child: Center(
                        child: Icon(
                          HuddlIcons.imageNotSupported,
                          size: 32,
                          color: HuddlColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
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
                    style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    article.summary,
                    style: HuddlText.body(color: HuddlColors.textSecondary),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  // Tags — tappable, dispatch _TagFilterNotification
                  if (article.tags.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: article.tags
                          .take(3)
                          .map((t) => _Tag(
                                label: t,
                                onTap: () =>
                                    _TagFilterNotification(t).dispatch(context),
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 12),
                  // Footer — contributor + engagement + Read →
                  Row(
                    children: [
                      // Contributor avatar
                      // Contributor avatar fallback — infoBluePale bg (trust/verified).
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: HuddlColors.infoBluePale,
                        child: Text(
                          article.contributorFirstName.isNotEmpty
                              ? article.contributorFirstName[0].toUpperCase()
                              : 'P',
                          style: HuddlText.caption(
                              weight: FontWeight.w600,
                              color: HuddlColors.infoBlue),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          article.contributorCredit,
                          style: HuddlText.caption(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Upvotes
                      Row(
                        children: [
                          Icon(
                            HuddlIcons.heart,
                            size: 14,
                            color: HuddlColors.textHint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${article.upvotes}',
                            style: HuddlText.caption(),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      // Read → CTA (spec §2)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: HuddlColors.nearBlack.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Read →',
                          style: HuddlText.caption(weight: FontWeight.w600),
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

  void _openArticle(BuildContext context) {
    AiKnowledgeFlywheelService().recordView(article.id);
    if (article.isParentShared && article.externalUrl != null) {
      final raw = article.externalUrl!;
      final uri = Uri.parse(
          raw.startsWith('http') ? raw : 'https://$raw');
      launchUrl(uri, mode: LaunchMode.externalApplication)
          .catchError((_) => false);
      return;
    }
    Navigator.of(context).push(
      HuddlSpringPageRoute(page: _WisdomArticleScreen(article: article)),
    );
  }
}

// ─── Expert article card (Groups/Meetup style with UHD hero photo) ───────────

class _ExpertCard extends StatelessWidget {
  final KnowledgeArticle article;
  final ValueChanged<String>? onTagTap;
  const _ExpertCard({required this.article, this.onTagTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heroUrl = _kArticleHeroImages[article.id];
    final srcColor = _sourceColor(article.source);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          HuddlSpringPageRoute(page: _ExpertArticleScreen(article: article)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark
              ? []
              : [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                )],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── UHD hero photo (160px) ─────────────────────────────
            SizedBox(
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo — with shimmer placeholder while loading
                  heroUrl != null
                      ? Image.network(
                          heroUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return _ShimmerBox(
                              width: double.infinity,
                              height: 160,
                              borderRadius: 0,
                            );
                          },
                          errorBuilder: (_, __, ___) => _PhotoFallback(color: srcColor),
                        )
                      : _PhotoFallback(color: srcColor),
                  // Gradient overlay for readability
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        stops: const [0.4, 1.0],
                      ),
                    ),
                  ),
                  // Source badge — bottom-left (spec §3)
                  Positioned(
                    bottom: 10,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: srcColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(HuddlIcons.verifiedFill,
                              size: 11, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            article.source,
                            style: HuddlText.caption(weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Category badge — top-right
                  Positioned(
                    top: 10,
                    right: 12,
                    child: _CategoryBadge(category: article.category, teal: false, light: true),
                  ),
                  // Title overlay — sits above source badge (badge is at bottom:10)
                  Positioned(
                    bottom: 42,
                    left: 12,
                    right: 12,
                    child: Text(
                      article.title,
                      style: HuddlText.body(weight: FontWeight.w700, color: Colors.white).copyWith(height: 1.25),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // ── Card body ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.summary,
                    style: HuddlText.body(color: HuddlColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: article.tags
                          .take(3)
                          .map((t) => _Tag(
                                label: t,
                                teal: true,
                                onTap: onTagTap != null ? () => onTagTap!(t) : null,
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(HuddlIcons.menuBook, size: 13, color: HuddlColors.textHint),
                      const SizedBox(width: 5),
                      Text(
                        'Expert guide',
                        style: HuddlText.caption(color: HuddlColors.textHint),
                      ),
                      const Spacer(),
                      // Read chip — infoBluePale bg / infoBlue text.
                      // Informational: shows article is readable, not a primary CTA.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: HuddlColors.infoBluePale,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Read →',
                          style: HuddlText.caption(
                              weight: FontWeight.w600,
                              color: HuddlColors.infoBlue),
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

// Photo fallback when network image fails
class _PhotoFallback extends StatelessWidget {
  final Color color;
  const _PhotoFallback({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.15),
      child: Center(
        child: Icon(HuddlIcons.menuBook, size: 48, color: color.withValues(alpha: 0.4)),
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
          icon: const Icon(HuddlIcons.arrowBack, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Upvote button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _upvoted ? null : _upvote,
              icon: Icon(
                _upvoted ? HuddlIcons.heartFill : HuddlIcons.heart,
                size: 18,
                color: _upvoted ? HuddlColors.error : HuddlColors.textSecondary,
              ),
              label: Text(
                _upvoted ? 'Helpful!' : 'Helpful',
                style: HuddlText.body(),
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
                    color: HuddlColors.neutral50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(HuddlIcons.lightbulb,
                          size: 12, color: HuddlColors.textDark),
                      const SizedBox(width: 4),
                      Text(
                        'Insights',
                        style: HuddlText.caption(weight: FontWeight.w600),
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
              style: HuddlText.display(color: HuddlColors.textPrimary),
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
                  color: HuddlColors.divider,
                ),
              ),
              child: Row(
                children: [
                  // Contributor avatar — infoBluePale bg (trust signal).
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: HuddlColors.infoBluePale,
                    child: Text(
                      article.contributorFirstName.isNotEmpty
                          ? article.contributorFirstName[0].toUpperCase()
                          : 'P',
                      style: HuddlText.body(
                          weight: FontWeight.w600,
                          color: HuddlColors.infoBlue),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.contributorCredit,
                          style: HuddlText.body(weight: FontWeight.w600),
                        ),
                        Text(
                          'Shared in ${article.groupName}',
                          style: HuddlText.caption(),
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
              style: HuddlText.body().copyWith(height: 1.65),
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
                Icon(HuddlIcons.heartFill,
                    size: 16,
                    color: _upvoted ? HuddlColors.error : HuddlColors.textHint),
                const SizedBox(width: 4),
                Text(
                  '${article.upvotes + (_upvoted ? 1 : 0)} parents found this helpful',
                  style: HuddlText.caption(),
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

  Future<void> _openSourceUrl(BuildContext context) async {
    final url = article.sourceUrl;
    if (url == null || url.isEmpty) return;
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open: $url')),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heroUrl = _kArticleHeroImages[article.id];
    final srcColor = _sourceColor(article.source);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // ── Hero photo app bar ───────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: srcColor,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(HuddlIcons.arrowBack,
                    size: 18, color: HuddlColors.textPrimary),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  heroUrl != null
                      ? HuddlNetworkImage(
                          url: heroUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fallbackWidget: Container(color: srcColor),
                        )
                      : Container(color: srcColor),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        stops: const [0.4, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Article body ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source + category badges
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: srcColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(HuddlIcons.verifiedFill, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(article.source,
                              style: HuddlText.caption(weight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CategoryBadge(category: article.category, teal: true),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Title
                  Text(
                    article.title,
                    style: HuddlText.display(color: isDark ? HuddlColors.darkTextPrimary : HuddlColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  // Summary
                  Text(
                    article.summary,
                    style: HuddlText.body(color: HuddlColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  // Body
                  Text(
                    article.body,
                    style: HuddlText.body().copyWith(height: 1.65),
                  ),
                  // Tags
                  if (article.tags.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8, runSpacing: 6,
                      children: article.tags.map((t) => _Tag(label: t, teal: true)).toList(),
                    ),
                  ],
                  // "Read the full guide" — TAPPABLE
                  if (article.sourceUrl != null && article.sourceUrl!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => _openSourceUrl(context),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? HuddlColors.darkSurface : HuddlColors.successBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: HuddlColors.nearBlack.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: HuddlColors.nearBlack.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(HuddlIcons.openInNew, size: 16, color: HuddlColors.nearBlack),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Read the full guide',
                                    style: HuddlText.body(weight: FontWeight.w600),
                                  ),
                                  Text(
                                    'at ${article.source}',
                                    style: HuddlText.caption(),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(HuddlIcons.caretRight, size: 20, color: HuddlColors.nearBlack),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
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
                const Icon(HuddlIcons.clockCountdown,
                    size: 14, color: HuddlColors.warning),
                const SizedBox(width: 4),
                Text(
                  '$count to review',
                  style: HuddlText.caption(weight: FontWeight.w600),
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
                  const Icon(HuddlIcons.clockCountdown,
                      color: HuddlColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Pending Review (${articles.length})',
                    style: HuddlText.body(),
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
            style: HuddlText.body(),
          ),
          const SizedBox(height: 4),
          Text(
            article.summary,
            style: HuddlText.caption(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            'From: ${article.groupName} · ${article.contributorCredit}',
            style: HuddlText.caption(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: HuddlButton(
                  label: 'Reject',
                  onPressed: () => _reject(context),
                  variant: HuddlButtonVariant.destructive,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HuddlButton(
                  label: 'Publish',
                  onPressed: () => _approve(context),
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
  final bool light; // white text on semi-transparent bg (for photo overlays)
  const _CategoryBadge({required this.category, this.teal = false, this.light = false});

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
    // teal=true (category badge on body): nearBlack bg for contrast.
    // teal=false (category badge on photo overlay / card body): infoBlue accent.
    final color = teal ? HuddlColors.nearBlack : HuddlColors.infoBlue;
    if (light) {
      // White text on semi-transparent dark bg — for use on photo overlays
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _label,
          style: HuddlText.label(color: Colors.white),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label,
        style: HuddlText.label(),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool teal;
  final VoidCallback? onTap;
  const _Tag({required this.label, this.teal = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: teal
            ? HuddlColors.nearBlack.withValues(alpha: 0.08)
            : (Theme.of(context).brightness == Brightness.dark
                ? HuddlColors.darkSurfaceVariant
                : HuddlColors.gray100),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: teal
              ? HuddlColors.nearBlack.withValues(alpha: 0.2)
              : HuddlColors.inputBorderLight,
        ),
      ),
      child: Text(
        '#$label',
        style: HuddlText.caption(),
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: chip,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? illustrationAsset;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.illustrationAsset,
  });

  @override
  Widget build(BuildContext context) {
    return HuddlEmptyState(
      mood: HuddlMood.neutral,
      illustrationAsset: illustrationAsset,
      title: title,
      subtitle: subtitle,
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
            const Icon(HuddlIcons.cloudOff,
                size: 48, color: HuddlColors.textHint),
            const SizedBox(height: 12),
            Text(
              message,
              style: HuddlText.body(color: HuddlColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// SHIMMER LOADING BOX — pure-Dart animated placeholder, no extra packages
// Usage:
//   _ShimmerBox(width: double.infinity, height: 160, borderRadius: 0)
//   _ShimmerBox(width: 64, height: 64, borderRadius: 10)
// =============================================================================
class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.borderRadius = 0,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base =
        isDark ? HuddlColors.darkInputBg : HuddlColors.neutral100;
    final highlight =
        isDark ? HuddlColors.darkSurfaceVariant : HuddlColors.neutral50;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value + 1, 0),
            colors: [base, highlight, base],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// UNIFIED INSIGHTS FEED — merges Expert Guides + Community Wisdom into one feed.
// Sorted by: relevance (default) | newest | a-z
// Filtered by: searchQuery + selectedCategory
// Renders expert articles with _ExpertCard and community articles with _WisdomCard.
// =============================================================================

class _UnifiedInsightsFeed extends StatefulWidget {
  final String searchQuery;
  final KnowledgeCategory? selectedCategory;
  final String sortBy;

  const _UnifiedInsightsFeed({
    required this.searchQuery,
    required this.selectedCategory,
    required this.sortBy,
  });

  @override
  State<_UnifiedInsightsFeed> createState() => _UnifiedInsightsFeedState();
}

class _UnifiedInsightsFeedState extends State<_UnifiedInsightsFeed>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Build the expert articles half of the feed.
  List<_InsightFeedItem> _expertItems() {
    final svc = AiKnowledgeBaseService();
    List<KnowledgeArticle> articles;

    if (widget.selectedCategory != null) {
      articles = svc.getArticlesByCategory(widget.selectedCategory!);
    } else if (widget.searchQuery.isNotEmpty) {
      articles = svc.searchArticles(widget.searchQuery);
    } else {
      articles = svc.allArticles;
    }

    // secondary text filter when both category and query are active
    if (widget.selectedCategory != null && widget.searchQuery.isNotEmpty) {
      final q = widget.searchQuery;
      articles = articles.where((a) {
        return a.title.toLowerCase().contains(q) ||
            a.summary.toLowerCase().contains(q) ||
            a.tags.any((t) => t.toLowerCase().contains(q));
      }).toList();
    }

    return articles.map((a) => _InsightFeedItem.expert(a)).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final expertItems = _expertItems();
    final flywheelSvc = AiKnowledgeFlywheelService();

    return StreamBuilder<List<CommunityWisdomArticle>>(
      stream: flywheelSvc.publishedArticlesStream(),
      builder: (context, snap) {
        // Build community items from snapshot
        List<_InsightFeedItem> communityItems = [];
        if (snap.hasData) {
          var articles = snap.data!;
          if (widget.selectedCategory != null) {
            articles = articles
                .where((a) => a.category == widget.selectedCategory)
                .toList();
          }
          if (widget.searchQuery.isNotEmpty) {
            final q = widget.searchQuery;
            articles = articles.where((a) {
              return a.title.toLowerCase().contains(q) ||
                  a.summary.toLowerCase().contains(q) ||
                  a.tags.any((t) => t.toLowerCase().contains(q));
            }).toList();
          }
          communityItems = articles.map((a) => _InsightFeedItem.community(a)).toList();
        }

        // Merge
        final allItems = [...expertItems, ...communityItems];

        // Sort
        if (widget.sortBy == 'a-z') {
          allItems.sort((a, b) => a.title.compareTo(b.title));
        } else if (widget.sortBy == 'newest') {
          allItems.sort((a, b) => b.sortDate.compareTo(a.sortDate));
        } else {
          // relevance — expert articles by relevanceWeight, community by upvotes
          allItems.sort((a, b) => b.sortWeight.compareTo(a.sortWeight));
        }

        if (snap.connectionState == ConnectionState.waiting && allItems.isEmpty) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        if (snap.hasError && communityItems.isEmpty && expertItems.isEmpty) {
          return _ErrorState(
            message: 'Could not load insights.\n${snap.error}',
          );
        }

        if (allItems.isEmpty) {
          return _EmptyState(
            icon: HuddlIcons.ai,
            illustrationAsset: 'assets/illustrations/growth_yellow.webp',
            title: widget.searchQuery.isNotEmpty
                ? 'No results for "${widget.searchQuery}"'
                : 'No insights yet',
            subtitle: widget.searchQuery.isNotEmpty
                ? 'Try a different search term or category.'
                : 'Expert guides and community wisdom will appear here.',
          );
        }

        return ListView.separated(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: allItems.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final item = allItems[i];
            if (item.isExpert) {
              return _ExpertCard(
                article: item.expertArticle!,
                onTagTap: (tag) => _TagFilterNotification(tag).dispatch(context),
              );
            } else {
              return _WisdomCard(article: item.communityArticle!);
            }
          },
        );
      },
    );
  }
}

// ── Data container for unified insight feed ───────────────────────────────────
class _InsightFeedItem {
  final KnowledgeArticle? expertArticle;
  final CommunityWisdomArticle? communityArticle;

  _InsightFeedItem.expert(this.expertArticle) : communityArticle = null;
  _InsightFeedItem.community(this.communityArticle) : expertArticle = null;

  bool get isExpert => expertArticle != null;

  String get title =>
      isExpert ? expertArticle!.title : communityArticle!.title;

  /// Used for 'newest' sort — expert uses lastUpdated, community uses extractedAt.
  DateTime get sortDate => isExpert
      ? expertArticle!.lastUpdated
      : communityArticle!.extractedAt;

  /// Used for 'relevance' sort — higher is more relevant.
  double get sortWeight => isExpert
      ? expertArticle!.relevanceWeight.toDouble()
      : communityArticle!.upvotes.toDouble();
}

// =============================================================================
// PARENT SHARE COMPOSE SHEET
//
// Shown when any logged-in parent taps the + FAB on the Insights screen.
// Collects: URL, title, short description, category.
// Submits directly to `community_wisdom` as published (parent-sourced, no AI).
// =============================================================================

class ParentShareComposeSheet extends StatefulWidget {
  const ParentShareComposeSheet({super.key});

  @override
  State<ParentShareComposeSheet> createState() =>
      _ParentShareComposeSheetState();
}

class _ParentShareComposeSheetState extends State<ParentShareComposeSheet> {
  final _urlCtrl   = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  KnowledgeCategory _category = KnowledgeCategory.parentalWellbeing;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _urlCtrl.text.trim().isNotEmpty &&
      _titleCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    HuddlAnimations.mediumTap();
    setState(() { _submitting = true; _error = null; });

    final user = FirebaseAuth.instance.currentUser;
    final firstName = (user?.displayName ?? 'Parent').split(' ').first;

    final id = await AiKnowledgeFlywheelService().submitParentSharedLink(
      title:                _titleCtrl.text.trim(),
      summary:              _descCtrl.text.trim().isNotEmpty
                              ? _descCtrl.text.trim()
                              : _titleCtrl.text.trim(),
      externalUrl:          _urlCtrl.text.trim(),
      category:             _category,
      contributorFirstName: firstName,
      contributorBorough:   'Cambridge',
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (id != null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(HuddlIcons.checkCircle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('Thanks! Your insight is now live.')),
          ]),
          backgroundColor: HuddlColors.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      setState(() => _error = 'Something went wrong. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: HuddlColors.inputBorderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                const WarmCircleIllustration(
                  assetPath: 'assets/illustrations/growth_yellow.webp',
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share an insight',
                          style: HuddlText.display()),
                      Text(
                        'Recommend a helpful article for other parents',
                        style: HuddlText.caption(
                            color: HuddlColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // URL field
            _ComposeField(
              controller: _urlCtrl,
              label: 'Link (URL)',
              hint: 'https://nhs.uk/...',
              icon: HuddlIcons.link,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Title field
            _ComposeField(
              controller: _titleCtrl,
              label: 'Title',
              hint: 'e.g. "10 things I wish I\'d known about sleep regressions"',
              icon: HuddlIcons.title,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Description field (optional)
            _ComposeField(
              controller: _descCtrl,
              label: 'Why it helped (optional)',
              hint: 'A short note on why you\'re recommending this…',
              icon: HuddlIcons.shortText,
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            // Category picker
            _CategoryPicker(
              selected: _category,
              onChanged: (cat) => setState(() => _category = cat),
            ),
            const SizedBox(height: 6),

            // Error message
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: HuddlText.caption(color: HuddlColors.error)),
            ],
            const SizedBox(height: 20),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: HuddlButton(
                label: _submitting ? 'Sharing…' : 'Share with parents',
                onPressed: (_isValid && !_submitting) ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Compact labelled text field for compose sheet ─────────────────────────────
class _ComposeField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _ComposeField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: HuddlText.caption(
                weight: FontWeight.w600,
                color: HuddlColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: HuddlText.body(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: HuddlText.body(color: HuddlColors.textTertiary),
            prefixIcon: Icon(icon, size: 18, color: HuddlColors.textTertiary),
            filled: true,
            fillColor: HuddlColors.peachWarm,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: HuddlColors.primary.withValues(alpha: 0.50),
                  width: 1.5),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 12 : 0,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Category chip row picker ──────────────────────────────────────────────────
class _CategoryPicker extends StatelessWidget {
  final KnowledgeCategory selected;
  final ValueChanged<KnowledgeCategory> onChanged;

  const _CategoryPicker({
    required this.selected,
    required this.onChanged,
  });

  // Surface the most common categories for quick selection
  static const _featured = [
    (KnowledgeCategory.parentalWellbeing, 'Wellbeing'),
    (KnowledgeCategory.health,            'Health'),
    (KnowledgeCategory.sleep,             'Sleep'),
    (KnowledgeCategory.feeding,           'Feeding'),
    (KnowledgeCategory.development,       'Development'),
    (KnowledgeCategory.education,         'Education'),
    (KnowledgeCategory.mentalHealth,      'Mental health'),
    (KnowledgeCategory.finance,           'Finance'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category',
            style: HuddlText.caption(
                weight: FontWeight.w600,
                color: HuddlColors.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _featured.map((entry) {
            final (cat, label) = entry;
            final isSel = selected == cat;
            return GestureDetector(
              onTap: () {
                HuddlAnimations.lightTap();
                onChanged(cat);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSel
                      ? HuddlColors.primary
                      : HuddlColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: HuddlText.caption(
                    weight: FontWeight.w600,
                    color: isSel ? Colors.white : HuddlColors.primary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
