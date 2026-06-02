import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../constants/app_text_styles.dart';
import '../../models/group.dart';
import '../../services/default_group_service.dart';
import '../../services/event_service.dart';
import '../../services/local_services_service.dart';
import '../../services/meetup_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/rehome_service.dart';
import '../../services/huddl_user_service.dart';
import '../../services/postcode_service.dart';
import '../../theme/huddl_animations.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/animations/huddl_spring_animations.dart';
import '../../widgets/huddl_character.dart';
import '../events/event_detail_screen.dart';
import '../events/meetup_detail_screen.dart';
import '../groups/group_chat_screen.dart';
import '../marketplace/item_detail_screen.dart';

// =============================================================================
// UNIFIED SEARCH SCREEN
//
// Searches across: Groups · Meetups · Events · Services · Market
// simultaneously. Results appear as a single scrollable list grouped by type.
//
// Triggered by:
//   • Search icon tap in home_screen.dart logo row
//   • Search icon long-press in Discover header (events_screen.dart)
//   • Search icon long-press in Connect header (groups_screen.dart)
//   • Search icon long-press in Market header (marketplace_screen.dart)
//
// Design pattern: Airbnb-style full-screen modal over the current screen,
// prominent input at top, category quick-picks beneath, live results below.
// =============================================================================

class UnifiedSearchScreen extends StatefulWidget {
  const UnifiedSearchScreen({
    super.key,
    this.initialQuery = '',
  });

  final String initialQuery;

  @override
  State<UnifiedSearchScreen> createState() => _UnifiedSearchScreenState();
}

class _UnifiedSearchScreenState extends State<UnifiedSearchScreen>
    with SingleTickerProviderStateMixin {

  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  String _query = '';
  bool _hasSearched = false;

  // ── Services ─────────────────────────────────────────────────────────────
  final _groupService   = DefaultGroupService();
  final _meetupService  = MeetupService();
  final _eventService   = EventService();
  final _serviceDir     = LocalServicesService();
  final _rehomeService  = RehomeService();
  final _onboarding     = OnboardingDataService();

  // ── Cached services listings (stream-backed) ──────────────────────────────
  List<ServiceListing> _cachedServiceListings = [];
  StreamSubscription<List<ServiceListing>>? _serviceStreamSub;

  // ── Result buckets ────────────────────────────────────────────────────────
  List<Group>          _groupResults   = [];
  List<Meetup>         _meetupResults  = [];
  List<Event>          _eventResults   = [];
  List<ServiceListing> _serviceResults = [];
  List<RehomeItem>     _marketResults  = [];
  List<HuddlUser>      _memberResults  = [];

  // ── Debounce timer for member search ──────────────────────────────
  Timer? _debounceTimer;

  // ── Quick-pick categories ─────────────────────────────────────────────────
  static const _quickPicks = [
    _QuickPick(emoji: '😴', label: 'Sleep advice',  query: 'sleep'),
    _QuickPick(emoji: '🍼', label: 'Feeding',        query: 'feeding breastfeeding'),
    _QuickPick(emoji: '🛺', label: 'Buggy walks',   query: 'buggy walk'),
    _QuickPick(emoji: '🧒', label: 'Childcare',      query: 'childcare nursery'),
    _QuickPick(emoji: '☕', label: 'Coffee chats',  query: 'coffee chat'),
    _QuickPick(emoji: '🛒', label: 'Free items',    query: 'free'),
    _QuickPick(emoji: '🎉', label: 'Playgroups',    query: 'playgroup toddler'),
    _QuickPick(emoji: '👨', label: 'Dads',           query: 'dads fathers'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl  = TextEditingController(text: widget.initialQuery);
    _focus = FocusNode();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // Subscribe to services stream so we have a cached list for sync search.
    _serviceStreamSub = _serviceDir.listingsStream().listen((listings) {
      if (mounted) {
        setState(() => _cachedServiceListings = listings);
        // Re-run search with updated service data if a query is active.
        if (_hasSearched && _query.isNotEmpty) _runSearch(_query);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeCtrl.forward();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _focus.requestFocus();
      });
    });

    if (widget.initialQuery.isNotEmpty) {
      _query = widget.initialQuery;
      _runSearch(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _serviceStreamSub?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Search logic ──────────────────────────────────────────────────────────

  void _runSearch(String q) {
    if (q.trim().isEmpty) {
      setState(() {
        _groupResults   = [];
        _meetupResults  = [];
        _eventResults   = [];
        _serviceResults = [];
        _marketResults  = [];
        _memberResults  = [];
        _hasSearched    = false;
      });
      return;
    }

    final query = q.trim().toLowerCase();

    setState(() {
      _hasSearched = true;

      // Groups — name + description (non-nullable) + aiTagline
      _groupResults = _groupService.getAllDefaultGroups().where((g) =>
        g.name.toLowerCase().contains(query) ||
        g.description.toLowerCase().contains(query) ||
        (g.aiTagline?.toLowerCase().contains(query) ?? false)
      ).take(4).toList();

      // Meetups — title + location + category + description (all non-nullable)
      _meetupResults = _meetupService.meetups.where((m) =>
        m.title.toLowerCase().contains(query) ||
        m.location.toLowerCase().contains(query) ||
        m.category.toLowerCase().contains(query) ||
        m.description.toLowerCase().contains(query)
      ).take(4).toList();

      // Events — title + location + description (non-nullable)
      _eventResults = _eventService.events.where((e) =>
        e.title.toLowerCase().contains(query) ||
        e.location.toLowerCase().contains(query) ||
        e.description.toLowerCase().contains(query)
      ).take(4).toList();

      // Services — name + description + tags + category.displayName
      _serviceResults = _cachedServiceListings.where((s) =>
        s.name.toLowerCase().contains(query) ||
        s.description.toLowerCase().contains(query) ||
        s.tags.any((t) => t.toLowerCase().contains(query)) ||
        s.category.displayName.toLowerCase().contains(query)
      ).take(4).toList();

      // Market — title + description + category.label
      _marketResults = _rehomeService.allItems.where((i) =>
        i.title.toLowerCase().contains(query) ||
        i.description.toLowerCase().contains(query) ||
        i.category.label.toLowerCase().contains(query)
      ).take(4).toList();
    });

    // Member search is async — debounced 400ms to avoid Firestore spam
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _runMemberSearch(query);
    });
  }

  Future<void> _runMemberSearch(String query) async {
    if (query.isEmpty || !mounted) return;
    final postcode = _onboarding.postcode ?? '';
    final borough = PostcodeService().getBoroughFromPostcode(postcode) ?? '';
    if (borough.isEmpty) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      final members = await HuddlUserService().getBoroughMembers(borough);
      if (!mounted) return;
      setState(() {
        _memberResults = members
            .where((m) =>
                m.uid != myUid &&
                (m.name.toLowerCase().contains(query) ||
                    m.firstName.toLowerCase().contains(query)))
            .take(5)
            .toList();
      });
    } catch (_) {
      // Network unavailable — member section simply stays empty
    }
  }

  int get _totalResults =>
    _groupResults.length + _meetupResults.length +
    _eventResults.length + _serviceResults.length +
    _marketResults.length + _memberResults.length;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: context.hc.surface,
        body: SafeArea(
          child: Column(
            children: [
              // ── Search bar ─────────────────────────────────────────────
              _buildSearchBar(),
              // ── Results / quick-picks ──────────────────────────────────
              Expanded(
                child: _hasSearched
                    ? _buildResults()
                    : _buildQuickPicks(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Hero(
      tag: 'huddl_search_pill',
      child: Material(
        color: context.hc.surface,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          decoration: BoxDecoration(
            color: context.hc.surface,
            border: Border(
              bottom: BorderSide(
                color: context.hc.divider,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // Back button
              GestureDetector(
                onTap: () {
                  HuddlAnimations.lightTap();
                  Navigator.pop(context);
                },
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 20,
                  color: HuddlColors.nearBlack,
                ),
              ),
              const SizedBox(width: 12),
              // Input field — full width, auto-focus
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: HuddlColors.receivedBubbleLight,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    onChanged: (v) {
                      setState(() => _query = v);
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(const Duration(milliseconds: 350), () {
                        if (mounted) _runSearch(v);
                      });
                    },
                    onSubmitted: _runSearch,
                    textInputAction: TextInputAction.search,
                    style: HuddlText.body(color: context.hc.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search groups, meetups, services…',
                      hintStyle: HuddlText.body(color: HuddlColors.textTertiary),
                      border: InputBorder.none,
                      prefixIcon: const Icon(
                        Icons.search,
                        color: HuddlColors.textTertiary,
                        size: 20,
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _ctrl.clear();
                                setState(() {
                                  _query = '';
                                  _hasSearched = false;
                                });
                              },
                              child: const Icon(
                                Icons.cancel,
                                color: HuddlColors.textTertiary,
                                size: 18,
                              ),
                            )
                          : null,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Quick picks — shown before any search ─────────────────────────────────
  Widget _buildQuickPicks() {
    final borough = _onboarding.borough ?? 'Cambridge';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What are you looking for?', style: HuddlText.heading()),
          const SizedBox(height: 4),
          Text('Search everything in $borough', style: HuddlText.body()),
          const SizedBox(height: 20),
          // Grid of quick-pick chips
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _quickPicks.map((qp) {
              return _QuickPickChip(
                quickPick: qp,
                onTap: () {
                  _ctrl.text = qp.query;
                  setState(() => _query = qp.query);
                  _runSearch(qp.query);
                  HuddlAnimations.lightTap();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          Text('Popular in $borough', style: HuddlText.heading()),
          const SizedBox(height: 12),
          ...[
            ('Sleep training groups',   Icons.people_outline,            HuddlColors.primary),
            ('Sunday morning walks',    Icons.location_on_outlined,      HuddlColors.infoBlue),
            ('Nearly new baby gear',    Icons.storefront_outlined,       HuddlColors.yellow),
            ('Paediatric physio',       Icons.health_and_safety_outlined, HuddlColors.primary),
          ].map((item) => _PopularRow(
            label: item.$1,
            icon: item.$2,
            iconColor: item.$3,
            onTap: () {
              _ctrl.text = item.$1;
              setState(() => _query = item.$1);
              _runSearch(item.$1);
            },
          )),
        ],
      ),
    );
  }

  // ── Results ───────────────────────────────────────────────────────────────
  Widget _buildResults() {
    if (_totalResults == 0) {
      return HuddlEmptyState(
        mood: HuddlMood.curious,
        illustrationAsset: 'assets/illustrations/search_found.webp',
        title: 'No results for "$_query"',
        subtitle:
            'Try different keywords — or browse Discover for local groups and meetups.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
      children: [
        // Results summary
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            '$_totalResults result${_totalResults == 1 ? '' : 's'} for "$_query"',
            style: HuddlText.caption(color: HuddlColors.textTertiary),
          ),
        ),

        // ── Groups ────────────────────────────────────────────────────
        if (_groupResults.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.people_outline,
            label: 'Groups',
            color: HuddlColors.primary,
            count: _groupResults.length,
            onSeeAll: () => Navigator.pop(context),
          ),
          ..._groupResults.asMap().entries.map((e) =>
            HuddlSpringMount(
              delay: Duration(milliseconds: e.key * 40),
              child: _GroupResultRow(
                group: e.value,
                query: _query,
                onTap: () => Navigator.of(context).push(HuddlSpringPageRoute(
                  page: GroupChatScreen(
                    groupId: e.value.id,
                    groupName: e.value.name,
                    groupImageUrl: e.value.imageUrl,
                  ),
                )),
              ),
            ),
          ),
        ],

        // ── Meetups ───────────────────────────────────────────────────
        if (_meetupResults.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.location_on_outlined,
            label: 'Meetups',
            color: HuddlColors.infoBlue,
            count: _meetupResults.length,
            onSeeAll: () => Navigator.pop(context),
          ),
          ..._meetupResults.asMap().entries.map((e) =>
            HuddlSpringMount(
              delay: Duration(milliseconds: e.key * 40),
              child: _MeetupResultRow(
                meetup: e.value,
                query: _query,
                onTap: () => Navigator.of(context).push(HuddlSpringPageRoute(
                  page: MeetupDetailScreen(meetup: e.value),
                )),
              ),
            ),
          ),
        ],

        // ── Events ────────────────────────────────────────────────────
        if (_eventResults.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.calendar_today_outlined,
            label: 'Events',
            color: HuddlColors.infoBlue,
            count: _eventResults.length,
            onSeeAll: () => Navigator.pop(context),
          ),
          ..._eventResults.asMap().entries.map((e) =>
            HuddlSpringMount(
              delay: Duration(milliseconds: e.key * 40),
              child: _EventResultRow(
                event: e.value,
                query: _query,
                onTap: () => Navigator.of(context).push(HuddlSpringPageRoute(
                  page: EventDetailScreen(event: e.value.toMap()),
                )),
              ),
            ),
          ),
        ],

        // ── Services ──────────────────────────────────────────────────
        if (_serviceResults.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.storefront_outlined,
            label: 'Services',
            color: HuddlColors.teal,
            count: _serviceResults.length,
            onSeeAll: () => Navigator.pop(context),
          ),
          ..._serviceResults.asMap().entries.map((e) =>
            HuddlSpringMount(
              delay: Duration(milliseconds: e.key * 40),
              child: _ServiceResultRow(
                listing: e.value,
                query: _query,
              ),
            ),
          ),
        ],

        // ── Market ────────────────────────────────────────────────────
        if (_marketResults.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.sell_outlined,
            label: 'Market',
            color: HuddlColors.yellow,
            count: _marketResults.length,
            onSeeAll: () => Navigator.pop(context),
          ),
          ..._marketResults.asMap().entries.map((e) =>
            HuddlSpringMount(
              delay: Duration(milliseconds: e.key * 40),
              child: _MarketResultRow(
                item: e.value,
                query: _query,
                onTap: () => Navigator.of(context).push(HuddlSpringPageRoute(
                  page: ItemDetailScreen(item: e.value),
                )),
              ),
            ),
          ),
        ],

        // ── Members ───────────────────────────────────────────────────
        if (_memberResults.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.person_outline,
            label: 'Members',
            color: HuddlColors.teal,
            count: _memberResults.length,
            onSeeAll: () => Navigator.pop(context),
          ),
          ..._memberResults.asMap().entries.map((e) {
            final member = e.value;
            final displayName = member.name.isNotEmpty
                ? member.name
                : member.firstName;
            final initial = displayName.isNotEmpty
                ? displayName[0].toUpperCase()
                : '?';
            return HuddlSpringMount(
              delay: Duration(milliseconds: e.key * 40),
              child: InkWell(
                onTap: () {
                  HuddlAnimations.lightTap();
                  Navigator.pushNamed(context, '/dm_chat', arguments: {
                    'recipientId': member.uid,
                    'recipientName': displayName,
                    'recipientAvatarColor': member.avatarColor,
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      // Avatar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: member.photoUrl.isNotEmpty
                              ? Image.network(
                                  member.photoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _MemberAvatar(
                                          initial: initial,
                                          color: member.avatarColor),
                                )
                              : _MemberAvatar(
                                  initial: initial,
                                  color: member.avatarColor),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Name + parent type
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _HighlightedText(
                              text: displayName,
                              query: _query,
                              style: HuddlText.body(
                                color: HuddlColors.nearBlack,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              member.parentType == 'mum' ? 'Mum' : 'Dad',
                              style: HuddlText.caption(),
                            ),
                          ],
                        ),
                      ),
                      // DM icon
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: HuddlColors.tealIconBg,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.send_outlined,
                          size: 15,
                          color: HuddlColors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ── Member avatar fallback ────────────────────────────────────────────────────
class _MemberAvatar extends StatelessWidget {
  final String initial;
  final String color;
  const _MemberAvatar({required this.initial, required this.color});

  @override
  Widget build(BuildContext context) {
    Color bg;
    try {
      bg = Color(int.parse('FF${color.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      bg = HuddlColors.primaryPale;
    }
    return Container(
      color: bg,
      child: Center(
        child: Text(
          initial,
          style: HuddlText.body(
            color: HuddlColors.nearBlack,
            weight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SUPPORTING WIDGETS
// =============================================================================

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData  icon;
  final String   label;
  final Color    color;
  final int      count;
  final VoidCallback? onSeeAll;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
    required this.count,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Text(label, style: HuddlText.heading()),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: HuddlColors.infoBluePale,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: HuddlText.caption(
                color: HuddlColors.infoBlue,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all',
                style: HuddlText.caption(
                  color: HuddlColors.primary,
                  weight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Generic result row base ───────────────────────────────────────────────────
class _ResultRow extends StatelessWidget {
  final Widget    leading;
  final String   title;
  final String   subtitle;
  final String?  tag;
  final Color?   tagColor;
  final String   query;
  final VoidCallback? onTap;

  const _ResultRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.tag,
    this.tagColor,
    required this.query,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HuddlAnimations.lightTap();
        onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightedText(
                    text: title,
                    query: query,
                    style: HuddlText.body(
                      color: HuddlColors.nearBlack,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: HuddlText.caption(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (tag != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (tagColor ?? HuddlColors.primary).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tag!,
                  style: HuddlText.label(color: tagColor ?? HuddlColors.primary),
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: HuddlColors.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Highlighted text — bolds query matches in HuddlColors.primary ─────────────
class _HighlightedText extends StatelessWidget {
  final String    text;
  final String    query;
  final TextStyle style;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: style);
    final lower = text.toLowerCase();
    final q     = query.toLowerCase();
    final spans = <TextSpan>[];
    int start   = 0;
    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: style.copyWith(
          fontWeight: FontWeight.w700,
          color: HuddlColors.primary,
        ),
      ));
      start = idx + query.length;
    }
    return RichText(
      text: TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ── Concrete row types ────────────────────────────────────────────────────────

class _GroupResultRow extends StatelessWidget {
  final Group          group;
  final String         query;
  final VoidCallback   onTap;

  const _GroupResultRow({
    required this.group,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => _ResultRow(
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 44,
        height: 44,
        child: group.imageUrl.isNotEmpty
            ? Image.network(
                group.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    ),
    title:    group.name,
    subtitle: '${group.memberCount} members · ${group.creatorBorough ?? 'Cambridge'}',
    tag:      'GROUP',
    tagColor: HuddlColors.primary,
    query:    query,
    onTap:    onTap,
  );

  Widget _fallback() => Container(
    color: HuddlColors.primaryPale,
    child: const Icon(Icons.people, color: HuddlColors.primary, size: 22),
  );
}

class _MeetupResultRow extends StatelessWidget {
  final Meetup         meetup;
  final String         query;
  final VoidCallback   onTap;

  const _MeetupResultRow({
    required this.meetup,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => _ResultRow(
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: HuddlColors.infoBluePale,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.location_on_outlined,
        color: HuddlColors.infoBlue,
        size: 22,
      ),
    ),
    title:    meetup.title,
    subtitle: '${meetup.dateDisplay} · ${meetup.location}',
    tag:      'MEETUP',
    tagColor: HuddlColors.infoBlue,
    query:    query,
    onTap:    onTap,
  );
}

class _EventResultRow extends StatelessWidget {
  final Event          event;
  final String         query;
  final VoidCallback   onTap;

  const _EventResultRow({
    required this.event,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => _ResultRow(
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: HuddlColors.infoBluePale,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.calendar_today_outlined,
        color: HuddlColors.infoBlue,
        size: 22,
      ),
    ),
    title:    event.title,
    subtitle: event.location,
    tag:      'EVENT',
    tagColor: HuddlColors.infoBlue,
    query:    query,
    onTap:    onTap,
  );
}

class _ServiceResultRow extends StatelessWidget {
  final ServiceListing listing;
  final String         query;

  const _ServiceResultRow({required this.listing, required this.query});

  @override
  Widget build(BuildContext context) => _ResultRow(
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: HuddlColors.tealIconBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          listing.name.isNotEmpty ? listing.name[0].toUpperCase() : 'S',
          style: HuddlText.heading(color: HuddlColors.teal),
        ),
      ),
    ),
    title:    listing.name,
    subtitle: listing.category.displayName,
    tag:      'SERVICE',
    tagColor: HuddlColors.teal,
    query:    query,
  );
}

class _MarketResultRow extends StatelessWidget {
  final RehomeItem     item;
  final String         query;
  final VoidCallback   onTap;

  const _MarketResultRow({
    required this.item,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => _ResultRow(
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 44,
        height: 44,
        child: item.imageUrls.isNotEmpty
            ? Image.network(
                item.imageUrls.first,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    ),
    title:    item.title,
    subtitle: item.isFree
        ? 'Free · ${item.borough ?? 'Cambridge'}'
        : '£${item.price.toStringAsFixed(0)} · ${item.borough ?? 'Cambridge'}',
    tag:      item.isFree ? 'FREE' : 'MARKET',
    tagColor: item.isFree ? HuddlColors.yellowDark : HuddlColors.nearBlack,
    query:    query,
    onTap:    onTap,
  );

  Widget _fallback() => Container(
    color: HuddlColors.yellowBackground,
    child: const Icon(Icons.sell_outlined, color: HuddlColors.yellow, size: 22),
  );
}

// ── Quick pick data class ─────────────────────────────────────────────────────
class _QuickPick {
  final String emoji;
  final String label;
  final String query;
  const _QuickPick({
    required this.emoji,
    required this.label,
    required this.query,
  });
}

class _QuickPickChip extends StatelessWidget {
  final _QuickPick   quickPick;
  final VoidCallback onTap;

  const _QuickPickChip({required this.quickPick, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ScaleOnPress(
      scale: 0.95,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.hc.surfaceAlt,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.hc.divider, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(quickPick.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              quickPick.label,
              style: HuddlText.body(
                color: context.hc.textPrimary,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularRow extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final Color        iconColor;
  final VoidCallback onTap;

  const _PopularRow({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HuddlAnimations.lightTap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: HuddlText.body(color: context.hc.textPrimary),
              ),
            ),
            Icon(
              Icons.north_west,
              size: 14,
              color: context.hc.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
