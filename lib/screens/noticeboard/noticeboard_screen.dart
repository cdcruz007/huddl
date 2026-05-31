import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';
import '../../services/announcement_service.dart';
import '../../services/browser_storage.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';
import '../../services/invitation_service.dart';
import '../../services/subscription_service.dart';
import '../../services/local_services_service.dart';
import '../../widgets/huddl_widgets.dart';
import '../../widgets/huddl_character.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/common/huddl_button.dart';

class NoticeboardScreen extends StatefulWidget {
  const NoticeboardScreen({super.key});
  @override
  State<NoticeboardScreen> createState() => _NoticeboardScreenState();
}

class _NoticeboardScreenState extends State<NoticeboardScreen> {
  final AnnouncementService _announcementService = AnnouncementService();
  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcodeService = PostcodeService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  List<ServiceListing> _partnerListings = [];
  ServiceListing? _selectedListing;
  bool _partnerListingsLoaded = false;
  String _borough = '';
  int _memberCount = 0;

  @override
  void initState() {
    super.initState();
    _loadContext();
    if (_subscriptionService.isPartner) {
      _loadPartnerListings();
    }
  }

  Future<void> _loadContext() async {
    await _onboarding.initialize();
    await _announcementService.initialize();
    final pc = _onboarding.postcode;
    final borough = pc != null ? (_postcodeService.getBoroughFromPostcode(pc) ?? '') : '';
    final members = pc != null ? InvitationService.getBoroughMembers(pc) : [];
    if (mounted) setState(() { _borough = borough; _memberCount = members.length; });
  }

  Future<void> _loadPartnerListings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('local_services')
          .where('ownerUid', isEqualTo: uid)
          .where('isPartnerListing', isEqualTo: true)
          .get();
      if (!mounted) return;
      setState(() {
        _partnerListings = snap.docs
            .map((d) => ServiceListing.fromFirestore(d))
            .toList();
        _partnerListingsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _partnerListingsLoaded = true);
    }
  }

  Future<void> _postToBoroughNoticeboard(String content) async {
    if (content.trim().isEmpty) return;
    try {
      await _announcementService.post(content.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Posted to ${_borough.isNotEmpty ? _borough : 'community'} community',
              style: HuddlText.body()),
          backgroundColor: HuddlColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        try {
          final raw = await BrowserStorage.getString('huddl_interaction_count');
          final count = (int.tryParse(raw ?? '') ?? 0) + 1;
          await BrowserStorage.setString('huddl_interaction_count', count.toString());
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to post. Please try again.', style: HuddlText.body()),
          backgroundColor: HuddlColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _openComposerSheet() {
    if (_subscriptionService.isPartner) {
      _openPartnerComposerSheet();
    } else {
      _openStandardComposerSheet();
    }
  }

  void _openStandardComposerSheet() {
    final hc = context.hc;
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const HuddlBottomSheetHandle(),
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Post to ${_borough.isNotEmpty ? _borough : 'community'}',
                  style: HuddlText.body(weight: FontWeight.w700, color: hc.textPrimary))),
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: controller, autofocus: true, maxLength: 280, maxLines: 5, minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Share something with your neighbours...',
                  hintStyle: HuddlText.body(color: hc.textTertiary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hc.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hc.divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: HuddlColors.primary)),
                  filled: true, fillColor: hc.scaffold, contentPadding: const EdgeInsets.all(12),
                ),
                style: HuddlText.body(color: hc.textPrimary),
                onChanged: (_) => setSheet(() {}),
              )),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: HuddlButton(
                label: 'Post to ${_borough.isNotEmpty ? _borough : 'community'}',
                variant: HuddlButtonVariant.primary,
                fullWidth: true,
                onPressed: controller.text.trim().isEmpty ? null : () {
                  final content = controller.text.trim();
                  Navigator.pop(ctx);
                  _postToBoroughNoticeboard(content);
                },
              )),
          ])),
        ),
      )),
    );
  }

  void _openPartnerComposerSheet() {
    final hc = context.hc;
    final controller = TextEditingController();
    ServiceListing? selectedListing = _selectedListing;
    final businessName = _onboarding.name ?? 'My Business';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  const HuddlBottomSheetHandle(),

                  // ── Partner header ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.verified_rounded,
                              size: 16, color: HuddlColors.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Post as $businessName',
                                style: HuddlText.body(
                                  weight: FontWeight.w700,
                                  color: hc.textPrimary,
                                ),
                              ),
                              Text(
                                'Huddl Partner · ${_borough.isNotEmpty ? _borough : 'Community'}',
                                style: HuddlText.caption(
                                  color: HuddlColors.primary,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Text composer ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      maxLength: 280,
                      maxLines: 5,
                      minLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Share a promotion, update, or tip '
                            'with ${_borough.isNotEmpty ? _borough : 'your community'}...',
                        hintStyle: HuddlText.body(color: hc.textTertiary),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: hc.divider)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: hc.divider)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: HuddlColors.primary)),
                        filled: true,
                        fillColor: hc.scaffold,
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      style: HuddlText.body(color: hc.textPrimary),
                      onChanged: (_) => setSheet(() {}),
                    ),
                  ),

                  // ── Listing attachment (optional) ──────────────────────
                  if (_partnerListings.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Attach a listing (optional)',
                            style: HuddlText.caption(
                              weight: FontWeight.w600,
                              color: hc.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _partnerListings.length + 1,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                // First chip = "None"
                                if (i == 0) {
                                  final isNone = selectedListing == null;
                                  return GestureDetector(
                                    onTap: () =>
                                        setSheet(() => selectedListing = null),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: isNone
                                            ? HuddlColors.nearBlack
                                            : hc.inputBg,
                                        borderRadius:
                                            BorderRadius.circular(18),
                                      ),
                                      child: Text(
                                        'None',
                                        style: HuddlText.caption(
                                          weight: FontWeight.w600,
                                          color: isNone
                                              ? Colors.white
                                              : hc.textSecondary,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final listing = _partnerListings[i - 1];
                                final isSelected =
                                    selectedListing?.id == listing.id;
                                return GestureDetector(
                                  onTap: () => setSheet(
                                      () => selectedListing = listing),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? HuddlColors.primary
                                          : hc.inputBg,
                                      borderRadius:
                                          BorderRadius.circular(18),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.store_outlined,
                                            size: 12,
                                            color: isSelected
                                                ? Colors.white
                                                : hc.textSecondary),
                                        const SizedBox(width: 5),
                                        Text(
                                          listing.name,
                                          style: HuddlText.caption(
                                            weight: FontWeight.w600,
                                            color: isSelected
                                                ? Colors.white
                                                : hc.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Post CTA ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: controller.text.trim().isEmpty
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _announcementService.postAsPartner(
                                  content: controller.text.trim(),
                                  businessName: businessName,
                                  linkedListingId: selectedListing?.id,
                                  linkedListingName: selectedListing?.name,
                                );
                                if (mounted) setState(() {});
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              HuddlColors.primary.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 13),
                          elevation: 0,
                        ),
                        child: Text(
                          'Post to ${_borough.isNotEmpty ? _borough : 'community'} as $businessName',
                          style: HuddlText.body(weight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _dismissAnnouncement(Announcement ann) {
    _announcementService.delete(ann.id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Post removed', style: HuddlText.body()),
      backgroundColor: HuddlColors.textDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: hc.scaffold,
      appBar: AppBar(
        backgroundColor: hc.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_borough.isNotEmpty ? _borough : 'Borough'} Noticeboard',
              style: HuddlText.body(weight: FontWeight.w700, color: hc.textPrimary)),
          if (_memberCount > 0)
            Text('$_memberCount+ parents', style: HuddlText.caption(color: hc.textTertiary)),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: hc.divider),
        ),
      ),
      body: Column(children: [
        // Sticky composer bar
        GestureDetector(
          onTap: _openComposerSheet,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: hc.surface, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hc.divider),
              boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Icon(Icons.campaign_outlined, size: 20, color: hc.textTertiary),
              const SizedBox(width: 10),
              Expanded(child: Text('Post something to ${_borough.isNotEmpty ? _borough : 'your community'}...',
                  style: HuddlText.body(color: hc.textTertiary).copyWith(fontStyle: FontStyle.italic))),
              Container(padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.send_rounded, size: 14, color: Colors.white)),
            ]),
          ),
        ),
        // Stream feed
        Expanded(child: StreamBuilder<List<Announcement>>(
          stream: _announcementService.boroughStream,
          initialData: _announcementService.boroughAnnouncements,
          builder: (context, snapshot) {
            final posts = snapshot.data ?? [];
            if (posts.isEmpty) return _buildEmptyState(hc);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              itemCount: posts.length,
              itemBuilder: (_, i) => Dismissible(
                key: ValueKey(posts[i].id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: HuddlColors.error,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) => _dismissAnnouncement(posts[i]),
                child: _buildPostCard(posts[i], hc, isDark),
              ),
            );
          },
        )),
      ]),
    );
  }

  Widget _buildPostCard(Announcement ann, dynamic hc, bool isDark) {
    final timeAgo = _timeAgo(ann.createdAt);
    final isPartner = ann.isPartnerPost;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          // Partner posts get a subtle orange border to stand out
          color: isPartner
              ? HuddlColors.primary.withValues(alpha: 0.25)
              : hc.divider,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Author row ──────────────────────────────────────────────
          Row(
            children: [
              // Avatar or Partner badge
              if (isPartner)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    size: 20,
                    color: HuddlColors.primary,
                  ),
                )
              else
                CircleAvatar(
                  backgroundColor: HuddlColors.orangeIconBg,
                  radius: 18,
                  child: Text(
                    ann.authorName.isNotEmpty
                        ? ann.authorName[0].toUpperCase()
                        : '?',
                    style: HuddlText.body(
                      weight: FontWeight.w700,
                      color: HuddlColors.primary,
                    ),
                  ),
                ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            ann.authorName,
                            style: HuddlText.body(
                              weight: FontWeight.w600,
                              color: hc.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Partner badge pill
                        if (isPartner) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: HuddlColors.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 10,
                                  color: HuddlColors.primary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Partner',
                                  style: HuddlText.caption(
                                    color: HuddlColors.primary,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      timeAgo,
                      style: HuddlText.caption(color: hc.textTertiary),
                    ),
                  ],
                ),
              ),

              if (ann.isPinned)
                Icon(Icons.push_pin, size: 14, color: HuddlColors.textTertiary),
            ],
          ),

          const SizedBox(height: 10),

          // ── Post content ────────────────────────────────────────────
          Text(
            ann.content,
            style: HuddlText.body(color: hc.textPrimary).copyWith(height: 1.45),
          ),

          // ── Linked listing card — Partner only ──────────────────────
          if (isPartner && ann.linkedListingName != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                if (ann.linkedListingId != null) {
                  Navigator.pushNamed(
                    context,
                    '/services',
                    arguments: {'highlightListingId': ann.linkedListingId},
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: HuddlColors.primary.withValues(alpha: 0.18),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.store_outlined,
                      size: 16,
                      color: HuddlColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ann.linkedListingName!,
                        style: HuddlText.body(
                          color: HuddlColors.primary,
                          weight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'See listing \u2192',
                      style: HuddlText.caption(color: HuddlColors.primary),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Action row ──────────────────────────────────────────────
          Row(
            children: [
              _actionBtn(
                icon: ann.isLiked ? Icons.favorite : Icons.favorite_border,
                color: ann.isLiked ? HuddlColors.error : hc.textTertiary,
                label: ann.likes > 0 ? ann.likes.toString() : 'Like',
                onTap: () async {
                  await _announcementService.toggleLike(ann.id);
                  setState(() {});
                },
              ),
              const SizedBox(width: 16),
              _actionBtn(
                icon: Icons.chat_bubble_outline,
                color: hc.textTertiary,
                label: ann.comments > 0 ? ann.comments.toString() : 'Comment',
                onTap: () {},
              ),
              const SizedBox(width: 16),
              _actionBtn(
                icon: Icons.share_outlined,
                color: hc.textTertiary,
                label: 'Share',
                onTap: () {
                  _announcementService.share(ann.id);
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () { HuddlAnimations.lightTap(); onTap(); },
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: HuddlText.caption(color: color)),
      ]),
    );
  }

  Widget _buildEmptyState(dynamic hc) {
    return HuddlEmptyState(
      mood: HuddlMood.noticeboard,
      title: 'No posts yet',
      subtitle: 'Be the first to post something to ${_borough.isNotEmpty ? _borough : 'your community'}.',
      ctaLabel: 'Post to community',
      onCtaTap: _openComposerSheet,
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
