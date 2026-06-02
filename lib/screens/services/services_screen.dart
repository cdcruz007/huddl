import 'dart:async';
import '../../theme/huddl_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../constants/app_text_styles.dart';
// import 'package:flutter/services.dart'; // removed — provided by material.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/local_services_service.dart';
import '../../services/ai_directory_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common/underlined_text_field.dart';
import '../../widgets/common/huddl_button.dart';

import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';
import '../../widgets/animations/huddl_loading_states.dart';
import '../../widgets/huddl_character.dart';

// =============================================================================
// SERVICES SCREEN — HUDDL TRUSTED LOCAL DIRECTORY
//
// Single unified screen (no sub-tabs).
//   • AnimatedCrossFade filter pill ↔ inline search
//   • "Suggested for you" / "Search results" section label
//   • Card: same _GroupMessageRow shell (horizontal tile with rounded avatar)
//   • AI badge  — shown when listingSource is 'places_api' / 'ai_discovered*'
//   • Parent badge — shown when listingSource is 'parent_added'
//   • + FAB (bottom-right) → opens Add / AI bottom sheet
// =============================================================================

// ── Category hero images — stable Unsplash CDN URLs (full-width hero covers) ─
const Map<ServiceCategory, String> _kCategoryImages = {
  ServiceCategory.childcare:
      'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?w=800&h=400&fit=crop',
  ServiceCategory.babysitting:
      'https://images.unsplash.com/photo-1566004100631-35d015d6a491?w=800&h=400&fit=crop',
  ServiceCategory.cleaning:
      'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=800&h=400&fit=crop',
  ServiceCategory.healthWellness:
      'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=800&h=400&fit=crop',
  ServiceCategory.education:
      'https://images.unsplash.com/photo-1503676260728-1c00da094a0b?w=800&h=400&fit=crop',
  ServiceCategory.fitness:
      'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&h=400&fit=crop',
  ServiceCategory.firstAid:
      'https://images.unsplash.com/photo-1516549655169-df83a0774514?w=800&h=400&fit=crop',
  ServiceCategory.doula:
      'https://images.unsplash.com/photo-1555252333-9f8e92e65df9?w=800&h=400&fit=crop',
  ServiceCategory.homeServices:
      'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800&h=400&fit=crop',
  ServiceCategory.photography:
      'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=800&h=400&fit=crop',
  ServiceCategory.food:
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&h=400&fit=crop',
  ServiceCategory.other:
      'https://images.unsplash.com/photo-1497366216548-37526070297c?w=800&h=400&fit=crop',
};

// ── Avatar colour palette for endorser initial circles ─────────────────────────
const List<Color> _kAvatarPalette = [
  HuddlColors.nearBlack,
  HuddlColors.primary,
  HuddlColors.nearBlack,
];

// ─── Shimmer placeholder for image load ──────────────────────────────────────
Widget _buildImageShimmer({required double height, required Color color}) {
  return _ShimmerBox(height: height, color: color);
}

class _ShimmerBox extends StatefulWidget {
  final double height;
  final Color color;
  const _ShimmerBox({required this.height, required this.color});
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
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        height: widget.height,
        width: double.infinity,
        color: widget.color.withValues(alpha: 0.08 + 0.06 * _anim.value),
      ),
    );
  }
}

// ─── Star rating picker (interactive, 1–5 stars) ─────────────────────────────

/// Stateful inline star-picker — used inside endorse dialogs.
/// [onChanged] fires whenever the user taps a star.
class _StarRatingPicker extends StatefulWidget {
  final int? initialRating;
  final ValueChanged<int?> onChanged;
  const _StarRatingPicker({this.initialRating, required this.onChanged});

  @override
  State<_StarRatingPicker> createState() => _StarRatingPickerState();
}

class _StarRatingPickerState extends State<_StarRatingPicker> {
  int? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialRating;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final star = i + 1;
        final filled = _selected != null && star <= _selected!;
        return GestureDetector(
          onTap: () {
            // Tapping the same star again clears the rating
            final next = _selected == star ? null : star;
            setState(() => _selected = next);
            widget.onChanged(next);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              filled ? HuddlIcons.starFill : HuddlIcons.star,
              size: 32,
              color: filled ? HuddlColors.amberWarm : HuddlColors.textTertiary,
            ),
          ),
        );
      }),
    );
  }
}

/// Displays a compact read-only star row (filled + empty stars + decimal label).
Widget _buildStarDisplay(double rating, {int count = 0, double size = 13}) {
  final fullStars = rating.floor();
  final hasHalf   = (rating - fullStars) >= 0.25;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (int i = 0; i < 5; i++)
        Icon(
          i < fullStars
              ? HuddlIcons.starFill
              : (i == fullStars && hasHalf
                  ? HuddlIcons.starHalf
                  : HuddlIcons.star),
          size: size,
          color: i < fullStars || (i == fullStars && hasHalf)
              ? HuddlColors.amberWarm
              : HuddlColors.textTertiary,
        ),
      const SizedBox(width: 4),
      Text(
        count > 0 ? '${rating.toStringAsFixed(1)} ($count)' : rating.toStringAsFixed(1),
        style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.textSecondary),
      ),
    ],
  );
}

// ─── Source badge helpers ─────────────────────────────────────────────────────

bool _isParentSource(String source) => source == 'parent_added';

// Badge colour token — teal, same as 'Free' badge in Events
const Color _kBadgeParent = HuddlColors.nearBlack;

// ─── Cambridge seed listings — shown when Firestore is unavailable ────────────
// Rich, realistic local service data so the tab is never blank.

List<ServiceListing> get _kCambridgeSeedListings {
  final now = DateTime.now();
  return [
  ServiceListing(
    id: 'seed_001',
    name: 'Little Stars Childcare',
    tagline: '12 Arbury Road, Cambridge CB4 2JB',
    description: 'Award-winning OFSTED Outstanding nursery serving Cambridge families since 2008. Flexible sessions, farm-to-fork meals, outdoor learning garden.',
    category: ServiceCategory.childcare,
    borough: 'Cambridge',
    createdByUid: '',
    listingSource: 'ai_discovered',
    phone: '01223 456789',
    website: 'littlestars-cambridge.co.uk',
    endorsementCount: 47,
    viewCount: 312,
    createdAt: now.subtract(const Duration(days: 90)),
    updatedAt: now.subtract(const Duration(days: 5)),
    isVerified: true,
    verificationTier: VerificationTier.verified,
    imageUrl: 'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?w=800&h=400&fit=crop',
    tags: ['OFSTED Outstanding', 'Baby rooms', 'Toddlers', 'Full day'],
  ),
  ServiceListing(
    id: 'seed_002',
    name: 'Cambridge Baby Sitters',
    tagline: 'Reliable evening & weekend childcare across Cambridge',
    description: 'Fully vetted, DBS-checked sitters matched to your family. All our sitters are first-aid trained and experienced with newborns through to age 10.',
    category: ServiceCategory.babysitting,
    borough: 'Cambridge',
    createdByUid: '',
    listingSource: 'ai_discovered',
    phone: '07812 345678',
    website: 'cambridgebabysitters.com',
    endorsementCount: 31,
    viewCount: 204,
    createdAt: now.subtract(const Duration(days: 60)),
    updatedAt: now.subtract(const Duration(days: 3)),
    isVerified: false,
    verificationTier: VerificationTier.community,
    imageUrl: 'https://images.unsplash.com/photo-1566004100631-35d015d6a491?w=800&h=400&fit=crop',
    tags: ['DBS checked', 'First aid', 'Evenings', 'Newborns'],
  ),
  ServiceListing(
    id: 'seed_003',
    name: 'Mama & Me Yoga',
    tagline: 'Cherry Hinton Village Hall, Cambridge CB1 8HH',
    description: 'Postnatal yoga for mums and babies from 6 weeks. Relaxing classes focused on recovery, bonding and meeting other new mums in Cambridge.',
    category: ServiceCategory.fitness,
    borough: 'Cambridge',
    createdByUid: '',
    listingSource: 'ai_discovered',
    phone: '07923 111222',
    endorsementCount: 28,
    viewCount: 180,
    createdAt: now.subtract(const Duration(days: 30)),
    updatedAt: now.subtract(const Duration(days: 2)),
    isVerified: false,
    verificationTier: VerificationTier.none,
    imageUrl: 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&h=400&fit=crop',
    tags: ['Postnatal', 'Mums & babies', 'Recovery', 'Bonding'],
  ),
  ServiceListing(
    id: 'seed_004',
    name: 'Bright Futures Tutoring',
    tagline: '24 Mill Road, Cambridge CB1 2AD',
    description: 'GCSE and primary school tutoring from experienced Cambridge University graduates. Specialising in maths, English and science for ages 5–16.',
    category: ServiceCategory.education,
    borough: 'Cambridge',
    createdByUid: '',
    listingSource: 'parent_added',
    parentName: 'Sophie T.',
    phone: '01223 789012',
    website: 'brightfuturescambridge.co.uk',
    endorsementCount: 22,
    viewCount: 156,
    createdAt: now.subtract(const Duration(days: 45)),
    updatedAt: now.subtract(const Duration(days: 7)),
    isVerified: false,
    verificationTier: VerificationTier.none,
    imageUrl: 'https://images.unsplash.com/photo-1503676260728-1c00da094a0b?w=800&h=400&fit=crop',
    tags: ['GCSE', 'Primary', 'Maths', 'English', 'Science'],
  ),
  ServiceListing(
    id: 'seed_005',
    name: 'The Clean Team Cambridge',
    tagline: 'Professional home cleaning across Cambridge & surrounds',
    description: 'Trusted family home cleaning service. Eco-friendly products, fully insured, background-checked cleaners. One-off deep cleans or regular weekly visits.',
    category: ServiceCategory.cleaning,
    borough: 'Cambridge',
    createdByUid: '',
    listingSource: 'ai_discovered',
    phone: '01223 567890',
    website: 'cleanteamcambridge.co.uk',
    endorsementCount: 19,
    viewCount: 134,
    createdAt: now.subtract(const Duration(days: 20)),
    updatedAt: now.subtract(const Duration(days: 1)),
    isVerified: true,
    verificationTier: VerificationTier.verified,
    imageUrl: 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=800&h=400&fit=crop',
    tags: ['Eco-friendly', 'Insured', 'Weekly', 'Deep clean'],
  ),
  ServiceListing(
    id: 'seed_006',
    name: 'Cambridge Birth Doula',
    tagline: 'Continuous support through your birth journey',
    description: 'Experienced DONA-certified doula offering antenatal, birth and postnatal support. Free consultation. Serving Cambridge, Ely and surrounding villages.',
    category: ServiceCategory.doula,
    borough: 'Cambridge',
    createdByUid: '',
    listingSource: 'parent_added',
    parentName: 'Priya M.',
    phone: '07744 888999',
    endorsementCount: 16,
    viewCount: 98,
    createdAt: now.subtract(const Duration(days: 14)),
    updatedAt: now.subtract(const Duration(days: 1)),
    isVerified: false,
    verificationTier: VerificationTier.community,
    imageUrl: 'https://images.unsplash.com/photo-1555252333-9f8e92e65df9?w=800&h=400&fit=crop',
    tags: ['DONA certified', 'Antenatal', 'Birth', 'Postnatal'],
  ),
  ServiceListing(
    id: 'seed_007',
    name: 'Little Clicks Photography',
    tagline: 'Newborn, baby & family portraits in Cambridge',
    description: 'Specialised newborn and family photographer with a cosy Cambridge studio. Natural, relaxed shoots capturing those first precious moments.',
    category: ServiceCategory.photography,
    borough: 'Cambridge',
    createdByUid: '',
    listingSource: 'ai_discovered',
    phone: '07600 123456',
    website: 'littleclicksphotography.co.uk',
    endorsementCount: 38,
    viewCount: 267,
    createdAt: now.subtract(const Duration(days: 55)),
    updatedAt: now.subtract(const Duration(days: 4)),
    isVerified: true,
    verificationTier: VerificationTier.verified,
    imageUrl: 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=800&h=400&fit=crop',
    tags: ['Newborn', 'Family', 'Studio', 'Natural light'],
  ),
  ServiceListing(
    id: 'seed_008',
    name: 'Cambridge Paediatric First Aid',
    tagline: 'Paediatric first aid courses for parents & childcarers',
    description: 'Ofqual-regulated 6-hour and 12-hour paediatric first aid courses. Weekday and weekend options. Groups of 4+ get a private session discount.',
    category: ServiceCategory.firstAid,
    borough: 'Cambridge',
    createdByUid: '',
    listingSource: 'ai_discovered',
    phone: '01223 334455',
    website: 'cambridgefirstaid.co.uk',
    endorsementCount: 24,
    viewCount: 189,
    createdAt: now.subtract(const Duration(days: 40)),
    updatedAt: now.subtract(const Duration(days: 6)),
    isVerified: true,
    verificationTier: VerificationTier.verified,
    imageUrl: 'https://images.unsplash.com/photo-1516549655169-df83a0774514?w=800&h=400&fit=crop',
    tags: ['Ofqual', 'Parents', 'Childcarers', 'Weekend courses'],
  ),
  ServiceListing(
    id: 'seed_009',
    name: 'Nourish Cambridge',
    tagline: 'Healthy meal prep & delivery for new families',
    description: 'Nutritionist-designed meal boxes delivered to your door in Cambridge. Postnatal recovery menus, toddler-friendly meals and family bundles available.',
    category: ServiceCategory.food,
    borough: 'Cambridge',
    createdByUid: '',
    listingSource: 'ai_discovered',
    phone: '07500 445566',
    website: 'nourishcambridge.co.uk',
    endorsementCount: 12,
    viewCount: 87,
    createdAt: now.subtract(const Duration(days: 10)),
    updatedAt: now,
    isVerified: false,
    verificationTier: VerificationTier.none,
    imageUrl: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&h=400&fit=crop',
    tags: ['Postnatal nutrition', 'Meal delivery', 'Toddler food', 'Family'],
  ),
  ServiceListing(
    id: 'seed_010',
    name: 'Cambridge Bump to Baby Physio',
    tagline: 'Women\'s health physiotherapy, Cambridge city centre',
    description: 'Specialist women\'s health physiotherapy for pregnancy, postnatal recovery and pelvic floor rehabilitation. All appointments with a fully qualified NHS-trained physio.',
    category: ServiceCategory.healthWellness,
    borough: 'Cambridge',
    createdByUid: '',
    listingSource: 'ai_discovered',
    phone: '01223 112233',
    website: 'cambridgebumptobaby.co.uk',
    endorsementCount: 33,
    viewCount: 221,
    createdAt: now.subtract(const Duration(days: 75)),
    updatedAt: now.subtract(const Duration(days: 8)),
    isVerified: true,
    verificationTier: VerificationTier.verified,
    imageUrl: 'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=800&h=400&fit=crop',
    tags: ['Physio', 'Postnatal', 'Pelvic floor', 'NHS trained'],
  ),
];
}

// ─── Main screen ─────────────────────────────────────────────────────────────

class ServicesScreen extends StatefulWidget {
  final ValueNotifier<bool> searchTrigger;
  /// Set to `true` to exit search mode (e.g. when the user navigates away).
  final ValueNotifier<bool>? resetTrigger;
  const ServicesScreen({
    super.key,
    required this.searchTrigger,
    this.resetTrigger,
  });

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _service = LocalServicesService();

  ServiceCategory? _selectedCategory;
  String _searchQuery = '';
  bool _isSearchActive = false;
  bool _streamTimedOut = false;      // true once the 2-second timeout fires
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.searchTrigger.addListener(_onSearchTrigger);
    widget.resetTrigger?.addListener(_onResetTrigger);
    _triggerAiRefreshIfDue();
    // If Firestore stream hasn't emitted data within 2 seconds, fall back to
    // seed listings immediately rather than showing an infinite spinner.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_streamTimedOut) {
        setState(() => _streamTimedOut = true);
      }
    });
  }

  void _onResetTrigger() {
    if (widget.resetTrigger?.value == true) {
      widget.resetTrigger?.value = false;
      _deactivateSearch();
    }
  }

  // AppBar magnifier tap activates search mode (inline bar + compact rows)
  void _onSearchTrigger() {
    if (widget.searchTrigger.value) {
      widget.searchTrigger.value = false;
      setState(() => _isSearchActive = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  /// Exits search mode and resets query — called by Cancel tap or back gesture.
  void _deactivateSearch() {
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() {
      _isSearchActive = false;
      _searchQuery = '';
    });
  }

  Future<void> _triggerAiRefreshIfDue() async {
    try {
      await AiDirectoryService().runIfDue();
    } catch (_) {
      // Silent
    }
  }

  @override
  void dispose() {
    widget.searchTrigger.removeListener(_onSearchTrigger);
    widget.resetTrigger?.removeListener(_onResetTrigger);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // Keywords that signal an entry is an event/activity, not a service provider.
  static const _kEventKeywords = [
    'parkrun', 'park run', 'fun run', 'race', '5k', '10k', 'marathon',
    'community event', 'open day', 'open house', 'festival', 'fair',
    'boot camp event', 'boot camp run',
  ];

  bool _isEventLike(ServiceListing l) {
    final haystack =
        '${l.name} ${l.tagline} ${l.description} ${l.tags.join(' ')}'
            .toLowerCase();
    return _kEventKeywords.any((kw) => haystack.contains(kw));
  }

  List<ServiceListing> _filter(List<ServiceListing> all) {
    var result = all.where((l) => !_isEventLike(l)).toList();
    if (_selectedCategory != null) {
      result = result.where((l) => l.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((l) {
        return l.name.toLowerCase().contains(q) ||
            l.tagline.toLowerCase().contains(q) ||
            l.description.toLowerCase().contains(q) ||
            l.tags.any((t) => t.toLowerCase().contains(q));
      }).toList();
    }
    // Partner listings sorted first, then by endorsementCount
    result.sort((a, b) {
      if (a.isPartnerListing != b.isPartnerListing) {
        return a.isPartnerListing ? -1 : 1;
      }
      return b.endorsementCount.compareTo(a.endorsementCount);
    });
    return result;
  }

  void _openAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddServiceSheet(service: _service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    const Color filterText = HuddlColors.textDark;
    final bool hasActiveFilter = _selectedCategory != null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
        Column(
        children: [
          // ══ TOP HEADER ═══════════════════════════════════════════════════════
          // Default  : filter pill + "Suggested for you" label
          // Search   : inline search bar pill only (matches Groups/Meetups exactly)
          if (!_isSearchActive)
            // ── Default header: filter pill + section label ────────────────
            Container(
              color: hc.surface,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filter pill row
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showCategorySheet(context),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: hasActiveFilter
                                ? HuddlColors.primary.withValues(alpha: 0.08)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: hasActiveFilter
                                  ? HuddlColors.primary.withValues(alpha: 0.3)
                                  : hc.divider,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                HuddlIcons.filter,
                                size: 16,
                                color: hasActiveFilter
                                    ? HuddlColors.primary
                                    : filterText,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                hasActiveFilter
                                    ? _selectedCategory!.displayName
                                    : 'Filter by category',
                                style: HuddlText.body(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (hasActiveFilter) ...[
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            HuddlAnimations.lightTap();
                            setState(() => _selectedCategory = null);
                          },
                          child: Text(
                            'Clear',
                            style: HuddlText.body(weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Section label
                  Text(
                    'Suggested for you',
                    style: HuddlText.display(),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),

          if (_isSearchActive)
            // ── Search header: inline pill + Cancel (Groups/Meetups pattern) ─
            Container(
              color: hc.surface,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: hc.inputBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 12, right: 6),
                            child: Icon(HuddlIcons.search, size: 18,
                                color: HuddlColors.textDark),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              textAlignVertical: TextAlignVertical.center,
                              onChanged: (v) =>
                                  setState(() => _searchQuery = v.trim()),
                              style: HuddlText.body(color: filterText),
                              decoration: InputDecoration(
                                hintText: 'Search services…',
                                hintStyle: HuddlText.body(),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.only(bottom: 2),
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                HuddlAnimations.lightTap();
                                setState(() => _searchQuery = '');
                                _searchCtrl.clear();
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Icon(HuddlIcons.close,
                                    size: 16,
                                    color: HuddlColors.textTertiary),
                              ),
                            )
                          else
                            const SizedBox(width: 10),
                        ],
                      ),
                    ),
                  ),
                  // Cancel — exits search mode entirely (back to big cards)
                  GestureDetector(
                    onTap: () {
                      HuddlAnimations.lightTap();
                      _deactivateSearch();
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        'Cancel',
                        style: HuddlText.body(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Listing stream ────────────────────────────────────────────────

          // Verification nudge banner — unverified Plus/Partner users only.
          // Hidden once verified or for free (Welcome) users.
          if (SubscriptionService().isPlusOrAbove &&
              !SubscriptionService().isBusinessVerified)
            GestureDetector(
              onTap: () =>
                  Navigator.pushNamed(context, '/business_verification'),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: HuddlColors.infoBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: HuddlColors.infoBlue.withValues(alpha: 0.20),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(HuddlIcons.verified,
                        size: 18, color: HuddlColors.infoBlue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Verify your business to list your services here',
                        style: HuddlText.body(
                          weight: FontWeight.w500,
                          color: HuddlColors.infoBlue,
                        ),
                      ),
                    ),
                    Text(
                      'Get verified →',
                      style: HuddlText.caption(
                        weight: FontWeight.w600,
                        color: HuddlColors.infoBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Expanded(
            child: ColoredBox(
              color: _isSearchActive ? hc.surface : HuddlColors.neutral50,
              child: StreamBuilder<List<ServiceListing>>(
                stream: _service.listingsStream(category: _selectedCategory)
                    .handleError((_) => <ServiceListing>[]),
                builder: (context, snap) {
                  // Show spinner only for the first 2 seconds; after timeout
                  // (or on error/null) we fall through to seed listings.
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData &&
                      !_streamTimedOut) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      child: HuddlSkeletonFeed(cardCount: 2),
                    );
                  }
                  // On timeout, error, or empty Firestore result → seed data
                  final all = (snap.hasError ||
                              snap.data == null ||
                              snap.data!.isEmpty)
                      ? _kCambridgeSeedListings
                      : snap.data!;
                  final filtered = _filter(all);

                  if (filtered.isEmpty) {
                    return _EmptyDirectory(
                      hasFilter: _selectedCategory != null ||
                          _searchQuery.isNotEmpty,
                      onClear: () {
                        setState(() {
                          _selectedCategory = null;
                          _searchCtrl.clear();
                          _searchQuery = '';
                        });
                      },
                    );
                  }

                  if (_isSearchActive) {
                    // ── Compact search result rows (Groups/Meetups pattern) ──
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 4, bottom: 120),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => _ServiceSearchRow(
                        listing: filtered[i],
                        service: _service,
                      ),
                    );
                  }

                  // ── Default: full hero-image cards ──────────────────────
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _ListingCard(
                      listing: filtered[i],
                      service: _service,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
          // ── + FAB — positioned above floating pill nav ────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 64 + 12 + 16,
            right: 20,
            child: Material(
              elevation: 6,
              shadowColor: HuddlColors.primary.withValues(alpha: 0.40),
              shape: const CircleBorder(),
              color: HuddlColors.primary,
              child: InkWell(
                onTap: () {
                  HuddlAnimations.mediumTap();
                  final ss = SubscriptionService();
                  if (!ss.isPlusOrAbove) {
                    // Free users: route to upgrade gate
                    Navigator.pushNamed(context, '/subscription_gate',
                        arguments: {
                          'featureTitle': 'Service Listings',
                          'featureDescription':
                              'List your business in the Cambridge services '
                              'directory. Requires Huddl Plus with business '
                              'verification.',
                          'requiredPlan': 'Huddl Plus',
                          'featureIcon': HuddlIcons.storefront.codePoint,
                        });
                    return;
                  }
                  if (!ss.isBusinessVerified) {
                    // Plus/Partner unverified: verification SnackBar + action
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                        'Verify your business first to create a service listing.',
                        style: HuddlText.body(color: Colors.white),
                      ),
                      backgroundColor: HuddlColors.nearBlack,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      action: SnackBarAction(
                        label: 'Verify',
                        textColor: HuddlColors.primary,
                        onPressed: () => Navigator.pushNamed(
                            context, '/business_verification'),
                      ),
                    ));
                    return;
                  }
                  // Verified Plus/Partner — open the add sheet
                  _openAddSheet(context);
                },
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(HuddlIcons.add, color: Colors.white, size: 26),
                ),
              ),
            ),
          ),
      ], // Stack children
      ),
    );
  }

  // Category filter bottom sheet
  void _showCategorySheet(BuildContext context) {
    HuddlAnimations.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Filter by category',
              style: HuddlText.body(weight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _CategorySheetTile(
              label: 'All categories',
              emoji: '🏠',
              selected: _selectedCategory == null,
              onTap: () {
                setState(() => _selectedCategory = null);
                Navigator.pop(ctx);
              },
            ),
            ...ServiceCategory.values.map((cat) => _CategorySheetTile(
                  label: cat.displayName,
                  emoji: cat.emoji,
                  selected: _selectedCategory == cat,
                  onTap: () {
                    setState(() => _selectedCategory =
                        _selectedCategory == cat ? null : cat);
                    Navigator.pop(ctx);
                  },
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Category sheet tile ──────────────────────────────────────────────────────

class _CategorySheetTile extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _CategorySheetTile({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: () {
        HuddlAnimations.selectionClick();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? HuddlColors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? HuddlColors.primary : hc.divider,
          ),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: HuddlText.body(),
              ),
            ),
            if (selected)
              const Icon(HuddlIcons.check,
                  size: 18, color: HuddlColors.primary),
          ],
        ),
      ),
    );
  }
}

// ─── Service category initial avatar (replaces emoji in compact list thumbnail) ─
// Shows the first 1-2 letters of the listing name on a soft-coloured background,
// matching the existing initials-avatar pattern used across the Huddl app.

class _ServiceCategoryInitial extends StatelessWidget {
  final String name;
  final Color color;

  const _ServiceCategoryInitial({required this.name, required this.color});

  String get _initial {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _initial,
      style: HuddlText.heading(),
    );
  }
}

// ─── Overlaid badge pill (Events-style: solid colour, white text) ────────────

class _BadgePill extends StatelessWidget {
  final String label;
  final Color color;

  const _BadgePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: HuddlText.caption(weight: FontWeight.w700),
      ),
    );
  }
}

// ─── Relative-time helper ────────────────────────────────────────────────────
String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60)  return 'Just now';
  if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
  if (diff.inHours < 24)    return '${diff.inHours}h ago';
  if (diff.inDays < 7)      return '${diff.inDays}d ago';
  if (diff.inDays < 30)     return '${(diff.inDays / 7).floor()}w ago';
  if (diff.inDays < 365)    return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

// ─── Search result row — compact Meetups-style (shown when _isSearchActive) ──────────────
// Thumbnail 56×56 left | CATEGORY / Name / Location · Count | Endorse pill right

class _ServiceSearchRow extends StatefulWidget {
  final ServiceListing listing;
  final LocalServicesService service;
  const _ServiceSearchRow({required this.listing, required this.service});
  @override
  State<_ServiceSearchRow> createState() => _ServiceSearchRowState();
}

class _ServiceSearchRowState extends State<_ServiceSearchRow> {
  bool _hasEndorsed = false;
  bool _endorsing   = false;
  late int _count;

  @override
  void initState() {
    super.initState();
    _hasEndorsed = widget.listing.hasEndorsed;
    _count       = widget.listing.endorsementCount;
    _checkEndorsed();
  }

  Future<void> _checkEndorsed() async {
    final result = await widget.service.hasEndorsed(widget.listing.id);
    if (mounted) setState(() => _hasEndorsed = result);
  }

  Future<void> _toggleEndorse() async {
    if (_endorsing) return;
    setState(() => _endorsing = true);
    HuddlAnimations.mediumTap();
    try {
      if (_hasEndorsed) {
        await widget.service.removeEndorsement(widget.listing.id);
        if (mounted) setState(() { _hasEndorsed = false; _count = (_count - 1).clamp(0, 9999); });
      } else {
        final result = await _showEndorseDialog();
        if (result == null) { if (mounted) setState(() => _endorsing = false); return; }
        final quote  = result['quote']  as String?;
        final rating = result['rating'] as int?;
        await widget.service.endorseListing(widget.listing.id,
            quote: (quote?.isEmpty == true) ? null : quote,
            rating: rating);
        if (mounted) {
          setState(() { _hasEndorsed = true; _count = _count + 1; });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("You've endorsed ${widget.listing.name}!"),
              backgroundColor: HuddlColors.success,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
          // 🎉 First endorsement celebration overlay
          try {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null) {
              final doc = await FirebaseFirestore.instance.doc('users/$uid').get();
              final achievements = (doc.data()?['achievements'] as Map?) ?? {};
              if (achievements['firstEndorsement'] != true) {
                await FirebaseFirestore.instance.doc('users/$uid')
                    .set({'achievements': {'firstEndorsement': true}}, SetOptions(merge: true));
                if (mounted) {
                  await HuddlCelebrationOverlay.show(context,
                      message: "First endorsement given! You're helping the community ⭐");
                }
              }
            }
          } catch (_) { /* non-critical */ }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Endorse] _toggleEndorse error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kDebugMode
                  ? 'Endorse failed: $e'
                  : 'Something went wrong. Please try again.',
            ),
            backgroundColor: HuddlColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _endorsing = false);
  }

  /// Returns {'quote': String, 'rating': int?} or null if cancelled.
  Future<Map<String, dynamic>?> _showEndorseDialog() {
    int? pickedRating;
    final ctrl = TextEditingController();
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: context.hc.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Endorse ${widget.listing.name}',
                style: HuddlText.body(weight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your rating (optional)',
                    style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                const SizedBox(height: 6),
                Center(
                  child: _StarRatingPicker(
                    initialRating: pickedRating,
                    onChanged: (r) => setDialogState(() => pickedRating = r),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Add a personal note (optional)',
                    style: HuddlText.body(color: context.hc.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  maxLength: 120,
                  style: HuddlText.body(),
                  decoration: InputDecoration(
                    hintText: '"Reliable, insured, brilliant with our kids"',
                    hintStyle: HuddlText.caption(color: context.hc.textTertiary),
                    filled: true,
                    fillColor: context.hc.inputBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('Cancel',
                      style: HuddlText.body(color: context.hc.textSecondary))),
              HuddlButton(
                label: 'Endorse',
                onPressed: () => Navigator.pop(ctx, {'quote': ctrl.text.trim(), 'rating': pickedRating}),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final catColor = _categoryColor(listing.category);
    final imageUrl = (listing.imageUrl?.isNotEmpty == true)
        ? listing.imageUrl!
        : (_kCategoryImages[listing.category] ?? _kCategoryImages[ServiceCategory.other]!);
    final locationText = _isParentSource(listing.listingSource)
        ? listing.borough
        : (listing.tagline.isNotEmpty ? listing.tagline : listing.borough);
    final countText = _count > 0 ? '$_count endorsements' : '0 endorsements';

    return GestureDetector(
      onTap: () {
        HuddlAnimations.lightTap();
        widget.service.recordView(listing.id);
        _showListingDetail(context, listing, widget.service);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: context.hc.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // ── Square thumbnail 56×56 ────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) return child;
                  return _buildImageShimmer(height: 56, color: catColor);
                },
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      listing.name.isNotEmpty ? listing.name[0].toUpperCase() : 'S',
                      style: HuddlText.display(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // ── 3-line text block ─────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.category.displayName.toUpperCase(),
                    style: HuddlText.label(color: context.hc.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    listing.name,
                    style: HuddlText.body(weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$locationText  ·  $countText',
                    style: HuddlText.caption(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Community rating — shown when at least 1 rating exists
                  if (listing.communityRating != null) ...[
                    const SizedBox(height: 2),
                    _buildStarDisplay(listing.communityRating!, count: listing.ratingCount, size: 12),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ── Book Now pill — only on Partner listings with a booking URL ─
            if (listing.externalBookingUrl != null && listing.externalBookingUrl!.isNotEmpty) ...[  
              GestureDetector(
                onTap: () async {
                  HuddlAnimations.selectionClick();
                  final raw = listing.externalBookingUrl!;
                  final hasScheme = raw.startsWith('http://') || raw.startsWith('https://');
                  final uri = Uri.parse(hasScheme ? raw : 'https://$raw');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: HuddlColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Book Now',
                    style: HuddlText.body(weight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // ── Endorse / Endorsed pill — hidden for own listing ─────────
            if (FirebaseAuth.instance.currentUser?.uid != widget.listing.ownerUid)
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    opacity: _endorsing ? 0.4 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: JoinButton(
                      isJoined: _hasEndorsed,
                      onTap: _endorsing ? () {} : _toggleEndorse,
                      label: 'Endorse',
                      joinedLabel: 'Endorsed',
                      joinedColor: HuddlColors.teal,
                      unJoinedColor: HuddlColors.primary.withValues(alpha: 0.10),
                      unJoinedTextColor: HuddlColors.primary,
                    ),
                  ),
                  if (_endorsing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(HuddlColors.primary),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Listing card — Events-style (full-width hero + overlaid badges + body + avatar row) ─

class _ListingCard extends StatefulWidget {
  final ServiceListing listing;
  final LocalServicesService service;

  const _ListingCard({required this.listing, required this.service});

  @override
  State<_ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends State<_ListingCard> {
  bool _hasEndorsed = false;
  bool _endorsing   = false;
  late int _count;

  @override
  void initState() {
    super.initState();
    _hasEndorsed = widget.listing.hasEndorsed;
    _count       = widget.listing.endorsementCount;
    _checkEndorsed();
  }

  Future<void> _checkEndorsed() async {
    final result = await widget.service.hasEndorsed(widget.listing.id);
    if (mounted) setState(() => _hasEndorsed = result);
  }

  Future<void> _toggleEndorse() async {
    if (_endorsing) return;
    setState(() => _endorsing = true);
    HuddlAnimations.mediumTap();
    try {
      if (_hasEndorsed) {
        await widget.service.removeEndorsement(widget.listing.id);
        if (mounted) setState(() { _hasEndorsed = false; _count = (_count - 1).clamp(0, 9999); });
      } else {
        final result = await _showEndorseDialog();
        if (result == null) { if (mounted) setState(() => _endorsing = false); return; }
        final quote  = result['quote']  as String?;
        final rating = result['rating'] as int?;
        await widget.service.endorseListing(widget.listing.id,
            quote: (quote?.isEmpty == true) ? null : quote,
            rating: rating);
        if (mounted) {
          setState(() { _hasEndorsed = true; _count = _count + 1; });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("You've endorsed ${widget.listing.name}!"),
              backgroundColor: HuddlColors.success,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Endorse] _toggleEndorse error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kDebugMode
                  ? 'Endorse failed: $e'
                  : 'Something went wrong. Please try again.',
            ),
            backgroundColor: HuddlColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _endorsing = false);
  }

  /// Returns {'quote': String, 'rating': int?} or null if cancelled.
  Future<Map<String, dynamic>?> _showEndorseDialog() {
    int? pickedRating;
    final ctrl = TextEditingController();
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: context.hc.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Endorse ${widget.listing.name}',
                style: HuddlText.body(weight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your rating (optional)',
                    style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                const SizedBox(height: 6),
                Center(
                  child: _StarRatingPicker(
                    initialRating: pickedRating,
                    onChanged: (r) => setDialogState(() => pickedRating = r),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Add a personal note (optional)',
                    style: HuddlText.body(color: context.hc.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  maxLength: 120,
                  style: HuddlText.body(),
                  decoration: InputDecoration(
                    hintText: '"Reliable, insured, brilliant with our kids"',
                    hintStyle: HuddlText.caption(color: context.hc.textTertiary),
                    filled: true,
                    fillColor: context.hc.inputBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('Cancel',
                      style: HuddlText.body(color: context.hc.textSecondary))),
              HuddlButton(
                label: 'Endorse',
                onPressed: () => Navigator.pop(ctx, {'quote': ctrl.text.trim(), 'rating': pickedRating}),
              ),
            ],
          ),
        );
      },
    );
  }

  // Builds 1-3 overlapping coloured initial circles from real endorser data.
  // Falls back to category-coloured circles if recentEndorsements is sparse.
  List<Widget> _buildAvatarStack(ServiceListing listing, Color catColor) {
    final endorsers = listing.recentEndorsements;
    const int max = 3;
    final int shown = endorsers.length.clamp(0, max);
    final palette = _kAvatarPalette;
    return [
      SizedBox(
        width: 6.0 + (shown > 0 ? shown * 18.0 : 18.0),
        height: 24,
        child: Stack(
          children: [
            for (int i = 0; i < (shown > 0 ? shown : 1); i++)
              Positioned(
                left: i * 18.0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette[i % palette.length].withValues(alpha: 0.18),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      shown > 0
                          ? (endorsers[i].firstName.isNotEmpty
                              ? endorsers[i].firstName[0].toUpperCase()
                              : '?')
                          : '?',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: palette[i % palette.length],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 6),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final catColor = _categoryColor(listing.category);

    // Hero image: Google Places photo first, then Unsplash category fallback
    final imageUrl = (listing.imageUrl?.isNotEmpty == true)
        ? listing.imageUrl!
        : (_kCategoryImages[listing.category] ?? _kCategoryImages[ServiceCategory.other]!);

    final isParent = _isParentSource(listing.listingSource);
    final isVerified = listing.isVerified ||
        listing.verificationTier == VerificationTier.verified;
    final isCommunityPick = listing.verificationTier == VerificationTier.community ||
        listing.endorsementCount >= 3;

    // ── Events-style card shell ───────────────────────────────────────────
    return GestureDetector(
      onTap: () {
        HuddlAnimations.lightTap();
        widget.service.recordView(listing.id);
        _showListingDetail(context, listing, widget.service);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.hc.divider, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero image with overlaid badge pills ────────────────────
            Stack(
              children: [
                SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 190,
                    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                      if (wasSynchronouslyLoaded || frame != null) return child;
                      return _buildImageShimmer(height: 190, color: catColor);
                    },
                    errorBuilder: (_, __, ___) => Container(
                      height: 190,
                      color: catColor.withValues(alpha: 0.14),
                      child: Center(
                        child: Icon(HuddlIcons.storefront,
                            size: 48, color: catColor.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ),
                // Subtle bottom gradient (mirrors Events card)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.22),
                        ],
                      ),
                    ),
                  ),
                ),
                // Top-left: Partner badge — highest priority, else Parent Added
                if (listing.isPartnerListing)
                  Positioned(
                    top: 12, left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: HuddlColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(HuddlIcons.verifiedFill, size: 13, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Partner',
                            style: HuddlText.caption(weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (isParent)
                  Positioned(
                    top: 12, left: 12,
                    child: _BadgePill(label: 'Parent Added', color: _kBadgeParent),
                  )
                else
                  Positioned(
                    top: 12, left: 12,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(HuddlIcons.ai, size: 12, color: Colors.white),
                    ),
                  ),
                // Top-right: Verified / Community Pick
                if (isVerified || isCommunityPick)
                  Positioned(
                    top: 12, right: 12,
                    child: _BadgePill(
                      label: isVerified ? 'Verified' : 'Community Pick',
                      color: HuddlColors.nearBlack,
                    ),
                  ),
              ],
            ),

            // ── Card body (category meta + bold name + tagline/address) ───────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category row — small uppercase label (no emoji — Huddl design standard)
                  Text(
                    listing.category.displayName.toUpperCase(),
                    style: HuddlText.caption(),
                  ),
                  const SizedBox(height: 6),
                  // Bold listing name — 2-line max (mirrors Event title style)
                  Text(
                    listing.name,
                    style: HuddlText.body(weight: FontWeight.w700, color: context.hc.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Tagline / borough (mirrors Event location row)
                  Row(
                    children: [
                      Icon(HuddlIcons.locationPin,
                          size: 14, color: context.hc.textTertiary),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _isParentSource(listing.listingSource)
                              ? listing.borough
                              : (listing.tagline.isNotEmpty
                                  ? listing.tagline
                                  : listing.borough),
                          style: HuddlText.caption(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Bottom row: avatar stack + endorsement count + Enquire pill ──
            // Mirrors exactly the Events card bottom row (avatars + count + Join pill)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  // Overlapping avatar circles — real endorser initials or placeholder
                  if (_count > 0) ...
                    _buildAvatarStack(listing, catColor)
                  else
                    const SizedBox(width: 8),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _count > 0 ? '$_count endorsed' : '0 endorsements',
                          style: HuddlText.caption(),
                        ),
                        if (listing.communityRating != null) ...[
                          const SizedBox(height: 2),
                          _buildStarDisplay(listing.communityRating!, count: listing.ratingCount, size: 12),
                        ],
                      ],
                    ),
                  ),
                  // Endorse pill — hidden for own listing
                  if (FirebaseAuth.instance.currentUser?.uid != widget.listing.ownerUid)
                    JoinButton(
                      isJoined: _hasEndorsed,
                      onTap: _endorsing ? () {} : _toggleEndorse,
                      label: 'Endorse',
                      joinedLabel: 'Endorsed',
                      joinedColor: HuddlColors.neutral900,
                      unJoinedColor: HuddlColors.primary.withValues(alpha: 0.10),
                      unJoinedTextColor: HuddlColors.primary,
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
// ─── Inline tag chip ─────────────────────────────────────────────────────────

class _InlineTagChip extends StatelessWidget {
  final String tag;
  const _InlineTagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: hc.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.divider),
      ),
      child: Text(
        tag,
        style: HuddlText.label(color: hc.textSecondary),
      ),
    );
  }
}

// ─── Verified badge (used in detail sheet) ────────────────────────────────────

class _VerifiedBadge extends StatelessWidget {
  final VerificationTier tier;
  const _VerifiedBadge({required this.tier});

  @override
  Widget build(BuildContext context) {
    final isVerified = tier == VerificationTier.verified;
    const color = HuddlColors.nearBlack;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVerified ? HuddlIcons.verifiedFill : HuddlIcons.usersThree,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            tier.badgeLabel,
            style: HuddlText.label(),
          ),
        ],
      ),
    );
  }
}

// ─── Listing detail bottom sheet ─────────────────────────────────────────────

void _showListingDetail(BuildContext context, ServiceListing listing,
    LocalServicesService service) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) =>
        _ListingDetailSheet(listing: listing, service: service),
  );
}

class _ListingDetailSheet extends StatefulWidget {
  final ServiceListing listing;
  final LocalServicesService service;
  const _ListingDetailSheet(
      {required this.listing, required this.service});

  @override
  State<_ListingDetailSheet> createState() => _ListingDetailSheetState();
}

class _ListingDetailSheetState extends State<_ListingDetailSheet> {
  List<ServiceEndorsement> _endorsements = [];
  bool _loadingEndorsements = true;
  // Endorse state mirrored locally so the detail sheet updates without reload
  late bool _hasEndorsed;
  late int _endorseCount;
  bool _endorsing = false;

  @override
  void initState() {
    super.initState();
    _hasEndorsed = widget.listing.hasEndorsed;
    _endorseCount = widget.listing.endorsementCount;
    _load();
    _checkEndorsed();
  }

  Future<void> _checkEndorsed() async {
    final result = await widget.service.hasEndorsed(widget.listing.id);
    if (mounted) setState(() => _hasEndorsed = result);
  }

  Future<void> _load() async {
    final endorsements =
        await widget.service.getEndorsements(widget.listing.id);
    if (mounted) {
      setState(() {
        _endorsements = endorsements;
        _loadingEndorsements = false;
      });
    }
  }

  Future<void> _toggleEndorse() async {
    if (_endorsing) return;
    setState(() => _endorsing = true);
    HuddlAnimations.mediumTap();
    try {
    if (_hasEndorsed) {
      await widget.service.removeEndorsement(widget.listing.id);
      if (mounted) {
        setState(() {
          _hasEndorsed = false;
          _endorseCount = (_endorseCount - 1).clamp(0, 9999);
        });
      }
    } else {
      // Show rating + note dialog before endorsing
      int? pickedRating;
      final ctrl = TextEditingController();
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: context.hc.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Endorse ${widget.listing.name}',
                style: HuddlText.body(weight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your rating (optional)',
                    style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                const SizedBox(height: 6),
                Center(
                  child: _StarRatingPicker(
                    initialRating: pickedRating,
                    onChanged: (r) => setDialogState(() => pickedRating = r),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Add a personal note (optional)',
                    style: HuddlText.body(color: context.hc.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  maxLength: 120,
                  style: HuddlText.body(),
                  decoration: InputDecoration(
                    hintText: '"Reliable, insured, brilliant with our kids"',
                    hintStyle: HuddlText.caption(color: context.hc.textTertiary),
                    filled: true,
                    fillColor: context.hc.inputBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('Cancel', style: HuddlText.body(color: context.hc.textSecondary))),
              HuddlButton(
                label: 'Endorse',
                onPressed: () => Navigator.pop(ctx, {'quote': ctrl.text.trim(), 'rating': pickedRating}),
              ),
            ],
          ),
        ),
      );
      if (result == null) { if (mounted) setState(() => _endorsing = false); return; }
      final quote  = result['quote']  as String?;
      final rating = result['rating'] as int?;
      await widget.service.endorseListing(widget.listing.id,
          quote: (quote?.isEmpty == true) ? null : quote,
          rating: rating);
      if (mounted) {
        setState(() {
          _hasEndorsed = true;
          _endorseCount = _endorseCount + 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("You've endorsed ${widget.listing.name}!"),
            backgroundColor: HuddlColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        // Reload endorsements list to show new entry
        _load();
      }
    }
    } catch (e) {
      if (kDebugMode) debugPrint('[Endorse] _toggleEndorse error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kDebugMode
                  ? 'Endorse failed: $e'
                  : 'Something went wrong. Please try again.',
            ),
            backgroundColor: HuddlColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _endorsing = false);
  }

  /// Opens reply bottom sheet for listing owners (Partner feature) — v4 spec
  void _showReplyBottomSheet(String listingId, String endorsementUid) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: context.hc.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: HuddlColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Respond to endorsement',
                  style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
              const SizedBox(height: 12),
              UnderlinedTextField(
                controller: controller,
                hintText: 'Write a public response...',
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              HuddlButton(
                label: 'Post response',
                onPressed: () async {
                  if (controller.text.trim().isEmpty) return;
                  await widget.service.replyToEndorsement(
                    listingId: listingId,
                    endorsementUid: endorsementUid,
                    replyText: controller.text.trim(),
                  );
                  if (mounted) {
                    Navigator.pop(ctx);
                    _load(); // refresh endorsements
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Reply posted!'),
                        backgroundColor: HuddlColors.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final listing = widget.listing;
    final catColor = _categoryColor(listing.category);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── Hero + name ──────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: _ServiceCategoryInitial(
                        name: listing.name,
                        color: catColor,
                      ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.name,
                        style: HuddlText.heading(),
                      ),
                      Row(
                        children: [
                          Text(
                            listing.category.displayName,
                            style: HuddlText.body(color: hc.textSecondary),
                          ),
                          const SizedBox(width: 6),
                          if (_isParentSource(listing.listingSource))
                            _BadgePill(label: 'Parent Added', color: _kBadgeParent),
                        ],
                      ),
                      // 6c — View business profile link
                      if (listing.isPartnerListing && listing.ownerUid != null)
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/partner_profile',
                            arguments: {'partnerUid': listing.ownerUid},
                          ),
                          child: Text(
                            'View business profile →',
                            style: HuddlText.caption(color: HuddlColors.primary),
                          ),
                        ),
                    ],
                  ),
                ),
                if (listing.isVerified ||
                    listing.verificationTier == VerificationTier.community)
                  _VerifiedBadge(tier: listing.verificationTier),
              ],
            ),
            const SizedBox(height: 14),
            // ── "Added by parent" row — only on parent_added listings ────
            if (_isParentSource(listing.listingSource) &&
                listing.parentName != null &&
                listing.parentName!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: HuddlColors.nearBlack.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: HuddlColors.nearBlack.withValues(alpha: 0.22)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: HuddlColors.nearBlack.withValues(alpha: 0.15),
                      child: Text(
                        listing.parentName![0].toUpperCase(),
                        style: HuddlText.body(weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recommended by',
                            style: HuddlText.caption(color: HuddlColors.nearBlack.withValues(alpha: 0.8))),
                          Text(
                            listing.parentName!,
                            style: HuddlText.body(weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    // Message this parent if they are a Huddl member
                    if (listing.createdByUid.isNotEmpty &&
                        listing.createdByUid !=
                            FirebaseAuth.instance.currentUser?.uid)
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).pushNamed(
                            '/dm_chat',
                            arguments: {
                              'recipientId':   listing.createdByUid,
                              'recipientName': listing.parentName,
                              'recipientAvatarColor': '#3580F0',
                              'conversationId': '',
                            },
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: HuddlColors.nearBlack,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(HuddlIcons.chat,
                                  size: 13, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(
                                'Message',
                                style: HuddlText.caption(weight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            // ── Tagline / Address — source-aware ─────────────────────────
            if (_isParentSource(listing.listingSource)) ...[
              // parent-added: tagline holds the endorser's description → "About"
              if (listing.tagline.isNotEmpty) ...[
                Text(
                  'About',
                  style: HuddlText.caption(weight: FontWeight.w600, color: hc.textTertiary),
                ),
                const SizedBox(height: 4),
                Text(
                  listing.tagline,
                  style: HuddlText.body(color: hc.textSecondary),
                ),
                const SizedBox(height: 10),
              ],
            ] else ...[
              // AI-discovered: tagline holds the formatted Places API address → pin icon
              if (listing.tagline.isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(HuddlIcons.locationPin,
                        size: 15, color: hc.textTertiary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        listing.tagline,
                        style: HuddlText.body(color: hc.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ],
            // ── Description ──────────────────────────────────────────────
            if (listing.description.isNotEmpty) ...[
              Text(
                listing.description,
                style: HuddlText.body(color: hc.textSecondary).copyWith(height: 1.5),
              ),
              const SizedBox(height: 12),
            ],
            // ── Tags ────────────────────────────────────────────────────
            if (listing.tags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    listing.tags.map((t) => _InlineTagChip(tag: t)).toList(),
              ),
              const SizedBox(height: 16),
            ],
            // ── Stats row ────────────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _StatPill(
                  icon: HuddlIcons.thumbUpFill,
                  label: '$_endorseCount ${_endorseCount == 1 ? "endorsement" : "endorsements"}',
                  color: HuddlColors.nearBlack,
                ),
                _StatPill(
                  icon: HuddlIcons.visibility,
                  label: '${listing.viewCount} ${listing.viewCount == 1 ? "view" : "views"}',
                  color: HuddlColors.nearBlack,
                ),
                if (listing.communityRating != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: HuddlColors.yellowBackground,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(HuddlIcons.starFill, size: 14, color: HuddlColors.amberWarm),
                        const SizedBox(width: 4),
                        Text(
                          '${listing.communityRating!.toStringAsFixed(1)} community rating'
                          '${listing.ratingCount > 0 ? " (${listing.ratingCount})" : ""}',
                          style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.orangeDeep)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Endorse CTA \u2014 hidden for own listing ─────────────────────
            if (FirebaseAuth.instance.currentUser?.uid != listing.ownerUid)
              HuddlButton(
                label: _hasEndorsed ? 'Endorsed' : 'Endorse this service',
                leadingIcon: _hasEndorsed
                    ? HuddlIcons.thumbUpFill
                    : HuddlIcons.thumbUp,
                isLoading: _endorsing,
                variant: _hasEndorsed
                    ? HuddlButtonVariant.secondary
                    : HuddlButtonVariant.primary,
                onPressed: _endorsing ? null : _toggleEndorse,
              ),
            const SizedBox(height: 12),
            // ── Contact CTAs ─────────────────────────────────────────────
            if (listing.phone != null) ...[
              _ContactRow(
                icon: HuddlIcons.phone,
                label: listing.phone!,
                color: HuddlColors.nearBlack,
                onTap: () async {
                  // Gate: service contact requires Plus
                  final ss = SubscriptionService();
                  if (!ss.isPlusOrAbove) {
                    Navigator.pushNamed(context, '/subscription_gate',
                        arguments: {
                          'featureTitle': 'Contact this service',
                          'featureDescription': ss.limitReachedMessage('service_contact'),
                          'requiredPlan': 'Huddl Plus',
                          'featureIcon': HuddlIcons.phone.codePoint,
                        });
                    return;
                  }
                  HuddlAnimations.selectionClick();
                  final uri = Uri(scheme: 'tel', path: listing.phone);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Cannot call ${listing.phone}'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 4),
              // "Huddl Plus to contact" label for free users
              if (!SubscriptionService().isPlusOrAbove)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(HuddlIcons.lock, size: 13,
                          color: HuddlColors.textTertiary),
                      const SizedBox(width: 4),
                      Text('Huddl Plus to contact',
                          style: HuddlText.caption(
                              color: HuddlColors.textTertiary)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
            // ── Book Now — Partner listing booking URL ─────────────────
            if (listing.externalBookingUrl != null && listing.externalBookingUrl!.isNotEmpty) ...[  
              const SizedBox(height: 4),
              HuddlButton(
                label: 'Book Now',
                leadingIcon: HuddlIcons.calendar,
                onPressed: () async {
                  // Gate: service contact requires Plus
                  final ss = SubscriptionService();
                  if (!ss.isPlusOrAbove) {
                    Navigator.pushNamed(context, '/subscription_gate',
                        arguments: {
                          'featureTitle': 'Contact this service',
                          'featureDescription': ss.limitReachedMessage('service_contact'),
                          'requiredPlan': 'Huddl Plus',
                          'featureIcon': HuddlIcons.calendar.codePoint,
                        });
                    return;
                  }
                  HuddlAnimations.selectionClick();
                  final raw = listing.externalBookingUrl!;
                  final hasScheme = raw.startsWith('http://') ||
                      raw.startsWith('https://');
                  final uri = Uri.parse(hasScheme ? raw : 'https://$raw');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
            if (listing.website != null) ...[
              _ContactRow(
                icon: HuddlIcons.language,
                label: listing.website!,
                color: HuddlColors.nearBlack,
                onTap: () async {
                  HuddlAnimations.selectionClick();
                  final raw = listing.website!;
                  final hasScheme = raw.startsWith('http://') ||
                      raw.startsWith('https://');
                  final uri = Uri.parse(hasScheme ? raw : 'https://$raw');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Cannot open ${listing.website}'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
            // ── Enquire via Huddl DM ────────────────────────────────────
            if (listing.ownerUid != null &&
                listing.ownerUid !=
                    FirebaseAuth.instance.currentUser?.uid) ...[
              const SizedBox(height: 4),
              HuddlButton(
                label: 'Enquire via Huddl',
                leadingIcon: HuddlIcons.chat,
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(
                    '/dm_chat',
                    arguments: {
                      'recipientId': listing.ownerUid,
                      'recipientName': listing.name,
                      'recipientAvatarColor': '#3580F0',
                      'conversationId': '',
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            // ── Endorsements section ─────────────────────────────────────
            Row(
              children: [
                Text(
                  'Parent Endorsements',
                  style: HuddlText.body(weight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: HuddlColors.nearBlack.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_endorseCount',
                    style: HuddlText.caption(weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loadingEndorsements)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: HuddlSkeletonFeed(cardCount: 2),
              )
            else if (_endorsements.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    const WarmCircleIllustration(
                      assetPath: 'assets/illustrations/waving_thumbs.webp',
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No endorsements yet — be the first local parent to vouch!',
                        style: HuddlText.body(color: hc.textSecondary),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...(_endorsements.map((e) => _EndorsementTile(
                endorsement: e,
                listing: widget.listing,
                onReplyTap: () => _showReplyBottomSheet(widget.listing.id, e.uid),
              ))),
          ],
        ),
      ),
    );
  }
}

// ─── Endorsement tile ────────────────────────────────────────────────────────

class _EndorsementTile extends StatelessWidget {
  final ServiceEndorsement endorsement;
  final ServiceListing listing;
  final VoidCallback onReplyTap;
  const _EndorsementTile({
    required this.endorsement,
    required this.listing,
    required this.onReplyTap,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? HuddlColors.darkSurfaceVariant
            : HuddlColors.peachSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: HuddlColors.nearBlack.withValues(alpha: 0.15),
                child: Text(
                  endorsement.firstName.isNotEmpty
                      ? endorsement.firstName[0].toUpperCase()
                      : '?',
                  style: HuddlText.caption(weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  endorsement.credit,
                  style: HuddlText.caption(weight: FontWeight.w600),
                ),
              ),
              // Per-endorsement star rating pill
              if (endorsement.rating != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: HuddlColors.yellowBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(HuddlIcons.starFill, size: 12, color: HuddlColors.amberWarm),
                      const SizedBox(width: 2),
                      Text(
                        '${endorsement.rating}',
                        style: HuddlText.caption(weight: FontWeight.w700, color: HuddlColors.orangeDeep)),
                    ],
                  ),
                ),
            ],
          ),
          if (endorsement.quote != null && endorsement.quote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"${endorsement.quote}"',
              style: HuddlText.body(color: hc.textSecondary).copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _relativeTime(endorsement.createdAt),
            style: HuddlText.caption(),
          ),
          // 6d — Owner reply — v4 spec: surfaceAlt + subdirectory icon + italic
          if (endorsement.ownerReply != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.hc.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: HuddlColors.primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(HuddlIcons.subArrowRight,
                      size: 14, color: HuddlColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      endorsement.ownerReply!,
                      style: HuddlText.caption(color: context.hc.textSecondary).copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 6e — "Respond" TextButton for Partner owners (no reply yet)
          if (currentUid != null &&
              currentUid == listing.ownerUid &&
              SubscriptionService().canRespondToEndorsements &&
              endorsement.ownerReply == null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onReplyTap,
                child: Text(
                  'Respond',
                  style: HuddlText.caption(color: HuddlColors.primary),
                ),
              ),
            ),

          // Locked reply hint for Plus owners — upgrade to Partner to reply
          if (currentUid != null &&
              currentUid == listing.ownerUid &&
              !SubscriptionService().canRespondToEndorsements &&
              endorsement.ownerReply == null)
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/subscription_gate',
                    arguments: {
                      'featureTitle': 'Endorsement Replies',
                      'featureDescription':
                          'Reply publicly to parent endorsements on your listings. '
                          'Exclusive to Huddl Partner.',
                      'requiredPlan': 'Huddl Partner',
                      'featureIcon': HuddlIcons.reply.codePoint,
                    }),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(HuddlIcons.lock,
                        size: 11, color: HuddlColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      'Reply (Partner)',
                      style: HuddlText.caption(
                          color: HuddlColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Stat pill ───────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatPill(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: HuddlText.caption(weight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Contact row ─────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hc.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hc.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style:
                    HuddlText.body(color: hc.textPrimary),
              ),
            ),
            Icon(HuddlIcons.openInNew, size: 14, color: hc.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyDirectory extends StatelessWidget {
  final bool hasFilter;
  final VoidCallback onClear;
  const _EmptyDirectory({required this.hasFilter, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return HuddlEmptyState(
      mood: hasFilter ? HuddlMood.curious : HuddlMood.supportive,
      illustrationAsset: hasFilter
          ? 'assets/illustrations/search_found.webp'
          : 'assets/illustrations/handshake.webp',
      title: hasFilter
          ? 'No listings match your filter'
          : 'No listings in your area yet',
      subtitle: hasFilter
          ? 'Try a different category or search term'
          : 'Be the first to add a trusted local pro.\nPaste a WhatsApp recommendation or add manually.',
      ctaLabel: hasFilter ? 'Clear filters' : null,
      onCtaTap: hasFilter ? onClear : null,
    );
  }
}

// ─── Add / AI bottom sheet (triggered by FAB) ────────────────────────────────

class _AddServiceSheet extends StatefulWidget {
  final LocalServicesService service;
  const _AddServiceSheet({required this.service});

  @override
  State<_AddServiceSheet> createState() => _AddServiceSheetState();
}

class _AddServiceSheetState extends State<_AddServiceSheet> {
  final TextEditingController _chatPasteCtrl = TextEditingController();
  final TextEditingController _parentNameCtrl = TextEditingController();
  bool _extracting = false;
  List<ExtractedServiceRecommendation> _extracted = [];
  String? _extractError;
  bool _showManual = false;

  // ── Rate-limit constants ──────────────────────────────────────────────────
  static const String _kRateLimitKey = 'ai_extract_rate_limit_v1';
  static const int _kDailyLimit = 10;

  /// Returns null if the call is allowed, or a human-readable reason string
  /// if the daily limit has been reached.
  Future<String?> _checkRateLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10); // "YYYY-MM-DD"
    final stored = prefs.getString(_kRateLimitKey); // "YYYY-MM-DD:N"
    int usedToday = 0;
    if (stored != null) {
      final parts = stored.split(':');
      if (parts.length == 2 && parts[0] == today) {
        usedToday = int.tryParse(parts[1]) ?? 0;
      }
    }
    if (usedToday >= _kDailyLimit) {
      return 'You\'ve reached the daily limit of $_kDailyLimit AI extractions. '
          'Limit resets at midnight.';
    }
    // Increment and persist
    await prefs.setString(_kRateLimitKey, '$today:${usedToday + 1}');
    return null; // allowed
  }

  @override
  void dispose() {
    _chatPasteCtrl.dispose();
    _parentNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _runExtraction() async {
    final text = _chatPasteCtrl.text.trim();
    if (text.isEmpty) return;

    // Check rate limit before showing spinner
    final rateLimitMsg = await _checkRateLimit();
    if (rateLimitMsg != null) {
      if (mounted) setState(() => _extractError = rateLimitMsg);
      return;
    }

    setState(() {
      _extracting = true;
      _extracted = [];
      _extractError = null;
    });
    try {
      final results = await widget.service.extractFromChatText(text);
      if (mounted) {
        setState(() {
          _extracted = results;
          _extracting = false;
          _extractError = results.isEmpty
              ? 'No service recommendations found in that text. Try pasting a message like "Has anyone tried Sandra at Clean2Perfection?"'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractError = 'AI extraction failed. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return DraggableScrollableSheet(
      initialChildSize: 0.70,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          children: [
            // Handle + title
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: HuddlColors.aiGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(HuddlIcons.addBusiness,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add a Service',
                          style: HuddlText.body(weight: FontWeight.w700),
                        ),
                        Text(
                          'Paste a WhatsApp message or add manually',
                          style: HuddlText.caption(color: hc.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── AI extraction card ────────────────────────────────────────
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          gradient: HuddlColors.aiGradient,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(HuddlIcons.ai,
                            color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'AI Extraction',
                          style: HuddlText.body(weight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _chatPasteCtrl,
                    maxLines: 4,
                    style: HuddlText.body(color: hc.textPrimary),
                    decoration: InputDecoration(
                      hintText:
                          '"Has anyone used Sandra at Clean2Perfection? She\'s insured, reliable — 07700 900123"',
                      hintStyle: HuddlText.caption(color: hc.textTertiary).copyWith(fontStyle: FontStyle.italic),
                      filled: true,
                      fillColor: hc.inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ─ Parent name for attribution ────────────────────────
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: HuddlColors.nearBlack.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color: HuddlColors.nearBlack.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(HuddlIcons.user,
                                size: 14, color: HuddlColors.nearBlack),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Your name in the borough (optional)',
                                style: HuddlText.caption(weight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'So other parents can message you about this recommendation.',
                          style: HuddlText.caption(color: HuddlColors.nearBlack.withValues(alpha: 0.85)).copyWith(height: 1.4),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _parentNameCtrl,
                          style: HuddlText.body(color: hc.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'e.g. Sarah from Chesterton',
                            hintStyle: HuddlText.caption(color: hc.textTertiary),
                            filled: true,
                            fillColor: hc.inputBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  HuddlButton(
                    label: _extracting ? 'Analysing\u2026' : 'Extract recommendations',
                    variant: HuddlButtonVariant.primary,
                    leadingIcon: HuddlIcons.search,
                    isLoading: _extracting,
                    fullWidth: true,
                    onPressed: _extracting ? null : _runExtraction,
                  ),
                  if (_extractError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: HuddlColors.warningBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _extractError!,
                        style: HuddlText.body(color: HuddlColors.warningDark),
                      ),
                    ),
                  ],
                  if (_extracted.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${_extracted.length} recommendation${_extracted.length > 1 ? 's' : ''} found',
                      style: HuddlText.body(weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ..._extracted.map((r) => _ExtractedRecommendationCard(
                          rec: r,
                          service: widget.service,
                          parentName: _parentNameCtrl.text.trim().isEmpty
                              ? null
                              : _parentNameCtrl.text.trim(),
                          onSubmit: (listingId) {
                            if (listingId != null) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${r.name} added to the directory!'),
                                  backgroundColor: HuddlColors.success,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        )),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Manual add toggle ─────────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _showManual = !_showManual),
              child: Row(
                children: [
                  Icon(
                    _showManual
                        ? HuddlIcons.caretUp
                        : HuddlIcons.caretDown,
                    color: hc.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showManual ? 'Hide manual form' : 'Or add manually',
                    style: HuddlText.body(weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (_showManual) ...[
              const SizedBox(height: 12),
              _ManualAddForm(
                service: widget.service,
                onSubmit: (listingId) {
                  if (listingId != null) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Listing added to the directory!'),
                        backgroundColor: HuddlColors.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Extracted recommendation card ───────────────────────────────────────────

class _ExtractedRecommendationCard extends StatefulWidget {
  final ExtractedServiceRecommendation rec;
  final LocalServicesService service;
  final void Function(String? listingId) onSubmit;
  final String? parentName;

  const _ExtractedRecommendationCard({
    required this.rec,
    required this.service,
    required this.onSubmit,
    this.parentName,
  });

  @override
  State<_ExtractedRecommendationCard> createState() =>
      _ExtractedRecommendationCardState();
}

class _ExtractedRecommendationCardState
    extends State<_ExtractedRecommendationCard> {
  bool _submitting = false;
  bool _submitted = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final id = await widget.service.createListing(
      name: widget.rec.name,
      tagline: widget.rec.quote ?? widget.rec.category.displayName,
      description: widget.rec.quote ?? '',
      category: widget.rec.category,
      tags: widget.rec.tags,
      phone: widget.rec.phone,
      website: widget.rec.website,
      parentName: widget.parentName,
    );
    if (mounted) {
      setState(() {
        _submitting = false;
        _submitted = id != null;
      });
      widget.onSubmit(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final rec = widget.rec;

    if (_submitted) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HuddlColors.successBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(HuddlIcons.checkCircleFill,
                color: HuddlColors.success, size: 20),
            const SizedBox(width: 8),
            Text('${rec.name} added!',
                style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.success)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hc.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hc.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rec.name,
                  style: HuddlText.body(weight: FontWeight.w700),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      _confidenceColor(rec.confidence).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  rec.confidence,
                  style: HuddlText.label(color: _confidenceColor(rec.confidence))),
              ),
            ],
          ),
          if (rec.quote != null && rec.quote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"${rec.quote}"',
              style: HuddlText.caption().copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          if (rec.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: rec.tags.map((t) => _InlineTagChip(tag: t)).toList(),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: HuddlButton(
              label: 'Add to directory',
              isLoading: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }
}

Color _confidenceColor(String confidence) => switch (confidence) {
      'high' => HuddlColors.success,
      'medium' => HuddlColors.warning,
      _ => HuddlColors.textTertiary,
    };

// ─── Manual add form ──────────────────────────────────────────────────────────

class _ManualAddForm extends StatefulWidget {
  final LocalServicesService service;
  final void Function(String? listingId) onSubmit;
  const _ManualAddForm({required this.service, required this.onSubmit});

  @override
  State<_ManualAddForm> createState() => _ManualAddFormState();
}

class _ManualAddFormState extends State<_ManualAddForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _parentNameCtrl = TextEditingController();
  ServiceCategory _category = ServiceCategory.other;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _taglineCtrl.dispose();
    _descriptionCtrl.dispose();
    _phoneCtrl.dispose();
    _websiteCtrl.dispose();
    _tagsCtrl.dispose();
    _parentNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final tags = _tagsCtrl.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final id = await widget.service.createListing(
      name: _nameCtrl.text.trim(),
      tagline: _taglineCtrl.text.trim(),
      description: _descriptionCtrl.text.trim(),
      category: _category,
      tags: tags,
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      website: _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
      parentName: _parentNameCtrl.text.trim().isEmpty ? null : _parentNameCtrl.text.trim(),
    );
    if (mounted) {
      setState(() => _submitting = false);
      widget.onSubmit(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return _SectionCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add manually',
              style: HuddlText.body(weight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            _FormField(
              controller: _nameCtrl,
              label: 'Name *',
              hint: 'e.g. Sandra at Clean2Perfection',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<ServiceCategory>(
              initialValue: _category,
              items: ServiceCategory.values
                  .map((cat) => DropdownMenuItem(
                        value: cat,
                        child: Row(
                          children: [
                            Text(cat.emoji,
                                style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(cat.displayName,
                                style: HuddlText.body()),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (cat) =>
                  setState(() => _category = cat ?? ServiceCategory.other),
              decoration: InputDecoration(
                labelText: 'Category',
                labelStyle: HuddlText.body(color: hc.textSecondary),
                filled: true,
                fillColor: hc.inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: _taglineCtrl,
              label: 'Tagline',
              hint: 'e.g. Insured, reliable, DBS checked',
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: _descriptionCtrl,
              label: 'Endorsement / description',
              hint: 'What would you tell a friend about them?',
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: _tagsCtrl,
              label: 'Tags (comma-separated)',
              hint: 'insured, DBS checked, flexible hours',
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: _phoneCtrl,
              label: 'Phone (optional)',
              hint: '07700 900123',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: _websiteCtrl,
              label: 'Website / Instagram (optional)',
              hint: 'instagram.com/sandracleans',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            // ── Who's recommending this? ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HuddlColors.nearBlack.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: HuddlColors.nearBlack.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(HuddlIcons.user,
                          size: 15, color: HuddlColors.nearBlack),
                      const SizedBox(width: 6),
                      Text(
                        'Your recommendation (optional)',
                        style: HuddlText.caption(weight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add your name so other parents can message you about your experience with this provider.',
                    style: HuddlText.caption(color: HuddlColors.nearBlack.withValues(alpha: 0.85)).copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  _FormField(
                    controller: _parentNameCtrl,
                    label: 'Your name in the borough',
                    hint: 'e.g. Sarah from Chesterton',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: HuddlButton(
                label: 'Add to directory',
                isLoading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.validator,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: HuddlText.body(color: hc.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: HuddlText.body(color: hc.textSecondary),
        hintStyle: HuddlText.caption(color: hc.textTertiary),
        filled: true,
        fillColor: hc.inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        errorStyle:
            HuddlText.caption(color: HuddlColors.error),
      ),
    );
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(16),
        border: hc.cardBorder,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: child,
    );
  }
}

// ─── Category colour helper ───────────────────────────────────────────────────

Color _categoryColor(ServiceCategory cat) => switch (cat) {
      ServiceCategory.childcare => HuddlColors.categoryBaby,
      ServiceCategory.babysitting => HuddlColors.accentCoral,
      ServiceCategory.cleaning => HuddlColors.nearBlack,
      ServiceCategory.healthWellness => HuddlColors.success,
      ServiceCategory.education => HuddlColors.nearBlack,
      ServiceCategory.fitness => HuddlColors.categorySport,
      ServiceCategory.firstAid => HuddlColors.error,
      ServiceCategory.doula => HuddlColors.primaryLight,
      ServiceCategory.homeServices => HuddlColors.primary,
      ServiceCategory.photography => HuddlColors.brandTeal,
      ServiceCategory.food => HuddlColors.primary,
      ServiceCategory.other => HuddlColors.gray400,
    };
