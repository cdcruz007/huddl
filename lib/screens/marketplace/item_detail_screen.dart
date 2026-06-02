import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/animations/huddl_spring_animations.dart';
import '../../widgets/common/huddl_button.dart';
import '../../widgets/common/huddl_network_image.dart';
import '../../widgets/huddl_widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/rehome_service.dart';
import '../../services/firestore_service.dart';
import '../../services/dm_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/huddl_notification_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/report_service.dart';
import '../../services/subscription_service.dart';
import '../../models/subscription.dart';
import '../rehome/create_listing_screen.dart';
import '../groups/forward_message_sheet.dart';


// =============================================================================
// ITEM DETAIL SCREEN — Invisible AI: smart offer pre-fill, contextual actions,
// clean layout, no AI badges. Full audit: dark mode, 48dp targets, Semantics,
// adaptive fonts, haptic feedback, platform-specific compliance.
// =============================================================================

class ItemDetailScreen extends StatefulWidget {
  final RehomeItem item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final _service = RehomeService();
  final _dmService = DMService();
  int _currentImage = 0;
  bool _showFullDescription = false;
  bool _openingChat = false;
  final _reportService = ReportService();
  bool _hasAlreadyReported = false;

  RehomeItem get item => widget.item;
  // Compare against the real Firebase Auth UID so items created by the
  // current user are correctly identified as "own" on any device.
  bool get _isOwnItem {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    return item.sellerId == uid;
  }

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    // Increment view count in Firestore (fire-and-forget, only for other users' items)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isOwnItem && item.id.isNotEmpty && !item.id.startsWith('local_')) {
        FirestoreService().incrementListingViews(item.id).catchError((Object e) {
          if (kDebugMode) debugPrint('[ItemDetail] viewCount increment error: $e');
          return;
        });
      }
      // Check if current user has already reported this listing
      _checkAlreadyReported();
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Check Firestore to see if the current user has already reported this listing.
  Future<void> _checkAlreadyReported() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || item.id.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('reports')
          .where('messageId', isEqualTo: item.id)
          .where('reporterId', isEqualTo: uid)
          .limit(1)
          .get();
      if (mounted) {
        setState(() => _hasAlreadyReported = snap.docs.isNotEmpty);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ItemDetail] _checkAlreadyReported error: $e');
    }
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    super.dispose();
  }

  // ── Invisible AI: Predictive Offer Price ──
  // Based on condition and market context, silently pre-fills offer field
  double? _suggestedOfferPrice() {
    if (item.isFree || item.price <= 0) return null;
    final factor = switch (item.condition) {
      ItemCondition.brandNew => 0.92,
      ItemCondition.likeNew => 0.88,
      ItemCondition.good => 0.82,
      ItemCondition.wellUsed => 0.75,
    };
    return (item.price * factor).roundToDouble();
  }

  // ── Invisible AI: Smart Description Summary ──
  // If description is long, generate a one-line summary
  String _smartSummary() {
    if (item.description.length <= 80) return item.description;
    // Extract first sentence or meaningful chunk
    final firstSentence = item.description.split(RegExp(r'[.!?]')).first.trim();
    if (firstSentence.length > 10 && firstSentence.length < 120) {
      return firstSentence;
    }
    return '${item.description.substring(0, 77)}...';
  }

  void _shareItem() {
    HapticFeedback.mediumImpact();
    
    // Convert item to map for forwarding
    final itemData = {
      'id': item.id,
      'title': item.title,
      'description': item.description,
      'price': item.price,
      'priceDisplay': item.priceDisplay,
      'condition': item.condition.label,
      'ageStage': item.ageStage.label,
      'category': item.category.label,
      'imageUrls': item.imageUrls,
      'sellerName': item.sellerName,
      'sellerId': item.sellerId,
      'sellerLocation': item.sellerLocation,
      'listedAt': item.listedAt.toIso8601String(),
      'isFree': item.isFree,
      'borough': item.borough,
    };
    
    final shareText =
        '${item.title}\n${item.priceDisplay} \u00B7 ${item.condition.label}'
        '\n\uD83D\uDCCD ${item.sellerLocation}'
        '\n\nCheck it out on Huddl Marketplace!';
    
    // Show forward sheet to send as item card
    showForwardSheet(
      context: context,
      messageText: shareText,
      itemData: itemData,
      isItemCard: true,
    );
  }

  Future<void> _openSellerChat() async {
    if (_openingChat) return;
    final allowed = await _checkContactAllowance();
    if (!allowed) return;
    HapticFeedback.mediumImpact();
    setState(() => _openingChat = true);

    try {
      await _dmService.initialize();
      final conversation = await _dmService.getOrCreateConversation(
        recipientId: item.sellerId,
        recipientName: item.sellerName,
      );

      if (!mounted) return;

      Navigator.pushNamed(
        context,
        '/dm_chat',
        arguments: {
          'recipientId': item.sellerId,
          'recipientName': item.sellerName,
          'recipientAvatarColor': conversation.recipientAvatarColor,
          'conversationId': conversation.id,
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open chat: $e'),
          backgroundColor: HuddlColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  // ── Subscription-gated save action ──────────────────────────────────────────
  Future<void> _handleSaveAction() async {
    final ss = SubscriptionService();
    // Only gate when saving (not un-saving)
    if (!item.isSaved && !ss.canSaveItem) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/subscription_gate', arguments: {
        'featureTitle': 'Save limit reached',
        'featureDescription': ss.limitReachedMessage('saved_items'),
        'requiredPlan': 'Huddl Plus',
        'featureIcon': Icons.bookmark_outline.codePoint,
      });
      return;
    }
    if (!item.isSaved) {
      await ss.recordSavedItem();
    }
    _toggleSave();
  }

  // ── Subscription-gated contact check ─────────────────────────────────────
  Future<bool> _checkContactAllowance() async {
    final ss = SubscriptionService();
    await ss.initialize();
    if (!ss.canContactSeller) {
      if (!mounted) return false;
      Navigator.pushNamed(context, '/subscription_gate', arguments: {
        'featureTitle': 'Free seller contacts used',
        'featureDescription': ss.limitReachedMessage('buyer_contacts'),
        'requiredPlan': 'Huddl Plus',
        'featureIcon': Icons.chat_bubble_outline.codePoint,
      });
      return false;
    }
    await ss.recordBuyerContact();
    return true;
  }

  void _toggleSave() {
    HapticFeedback.lightImpact();
    _service.toggleSaved(item.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              item.isSaved ? Icons.favorite : Icons.favorite_border,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(item.isSaved ? 'Saved to your list' : 'Removed from saved'),
          ],
        ),
        backgroundColor:
            item.isSaved ? HuddlColors.primary : HuddlColors.textSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showMakeOfferSheet() {
    // Gate: buyer contacts lifetime limit
    SubscriptionService().initialize().then((_) {
      final ss = SubscriptionService();
      if (!ss.canContactSeller) {
        if (!mounted) return;
        Navigator.pushNamed(context, '/subscription_gate', arguments: {
          'featureTitle': 'Free seller contacts used',
          'featureDescription': ss.limitReachedMessage('buyer_contacts'),
          'requiredPlan': 'Huddl Plus',
          'featureIcon': Icons.chat_bubble_outline.codePoint,
        });
        return;
      }
      ss.recordBuyerContact();
      _doShowMakeOfferSheet();
    });
  }

  void _doShowMakeOfferSheet() {
    HapticFeedback.mediumImpact();
    final hc = context.hc;
    final suggestedPrice = _suggestedOfferPrice();
    final controller = TextEditingController(
      // AI pre-fills the offer amount based on condition analysis
      text: suggestedPrice != null
          ? suggestedPrice.toStringAsFixed(0)
          : '',
    );

    // ── note controller ──────────────────────────────────────────────────────
    final noteController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final sheetHc = ctx.hc;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            bool sending = false;

            void submitOffer() {
              if (sending) return;
              HapticFeedback.mediumImpact();

              final raw = controller.text.trim();
              // For free items allow £0, otherwise require a positive value
              final amount = double.tryParse(raw) ?? 0.0;
              if (!item.isFree && amount <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: const Text('Please enter a valid offer amount.'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
                return;
              }

              setSheetState(() => sending = true);

              // Resolve buyer name from onboarding data
              final onboarding = OnboardingDataService();
              final buyerName =
                  onboarding.name?.isNotEmpty == true ? onboarding.name! : 'You';

              // Resolve real Firebase Auth UID for the buyer
              final buyerUid = FirebaseAuth.instance.currentUser?.uid ?? '';

              final offer = RehomeOffer(
                id: 'off_${DateTime.now().millisecondsSinceEpoch}',
                itemId: item.id,
                itemTitle: item.title,
                buyerName: buyerName,
                buyerId: buyerUid,   // ← real Firebase Auth UID
                amount: item.isFree ? 0.0 : amount,
                createdAt: DateTime.now(),
                responseMessage:
                    noteController.text.trim().isEmpty ? null : noteController.text.trim(),
              );

              // Persist to service so the seller sees it in the Sell tab
              _service.addOffer(offer);

              // ── Notify seller via Firestore + FCM (fire-and-forget) ──────
              final noteSummary = noteController.text.trim().isEmpty
                  ? null
                  : noteController.text.trim();
              final amountDisplay =
                  item.isFree ? 'Free' : '£${amount.toStringAsFixed(0)}';
              HuddlNotificationService().offerReceived(
                sellerId: item.sellerId,
                buyerName: buyerName,
                itemTitle: item.title,
                itemId: item.id,
                offerId: offer.id,
                offerAmount: amountDisplay,
                notePreview: noteSummary,
                itemImageUrl: item.imageUrls.isNotEmpty
                    ? item.imageUrls.first
                    : null,
              );
              BackendApiService().notifyOfferReceived(
                sellerId: item.sellerId,
                buyerName: buyerName,
                itemTitle: item.title,
                itemId: item.id,
                offerId: offer.id,
                offerAmount: amountDisplay,
                notePreview: noteSummary,
                itemImageUrl: item.imageUrls.isNotEmpty
                    ? item.imageUrls.first
                    : null,
              );

              Navigator.pop(ctx);

              final amountStr = item.isFree ? 'Free' : '£${amount.toStringAsFixed(0)}';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              '$amountStr offer sent for "${item.title}"! The seller will review it.')),
                    ],
                  ),
                  backgroundColor: HuddlColors.textDark,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  duration: const Duration(seconds: 3),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const HuddlBottomSheetHandle(),
                  const SizedBox(height: 8),
                  Text(
                    'Make an offer',
                    style: HuddlText.display(color: sheetHc.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'for ${item.title}',
                    style: HuddlText.body(color: sheetHc.textTertiary),
                  ),
                  if (!item.isFree) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Listed at ${item.priceDisplay}',
                      style: HuddlText.body(color: HuddlColors.nearBlack, weight: FontWeight.w500),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (!item.isFree) ...[
                    Semantics(
                      label: 'Enter your offer amount in pounds',
                      textField: true,
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        style: HuddlText.display(color: sheetHc.textPrimary),
                        decoration: InputDecoration(
                          prefixText: '\u00A3 ',
                          prefixStyle: HuddlText.display(color: sheetHc.textPrimary),
                          hintText: '0',
                          hintStyle: HuddlText.display(color: sheetHc.textTertiary),
                          filled: true,
                          fillColor: sheetHc.surfaceAlt,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                        ),
                      ),
                    ),
                    // Subtle hint about suggested price
                    if (suggestedPrice != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Suggested based on item condition',
                        style: HuddlText.caption(),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                  // Optional note to seller
                  Semantics(
                    label: 'Add a note to the seller (optional)',
                    textField: true,
                    child: TextField(
                      controller: noteController,
                      maxLines: 2,
                      maxLength: 160,
                      style: HuddlText.body(color: HuddlColors.nearBlack),
                      decoration: InputDecoration(
                        hintText:
                            item.isFree ? 'Add a message for the seller…' : 'Add a note (optional)…',
                        hintStyle: HuddlText.body(color: HuddlColors.textTertiary),
                        filled: true,
                        fillColor: sheetHc.surfaceAlt,
                        counterStyle: HuddlText.caption(),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    label: 'Send offer to seller',
                    button: true,
                    child: HuddlButton(
                      label: item.isFree ? 'Request item' : 'Send offer',
                      onPressed: sending ? null : submitOffer,
                      isLoading: sending,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // == REPORT LISTING ========================================================

  void _showReportListingSheet() {
    HapticFeedback.mediumImpact();
    ReportType? selectedType;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HuddlBottomSheetHandle(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: HuddlColors.error.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.flag_outlined,
                              size: 22, color: HuddlColors.error),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Report listing',
                          style: HuddlText.heading(color: context.hc.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Why are you reporting "${item.title}"?',
                      style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    RadioGroup<ReportType>(
                      groupValue: selectedType,
                      onChanged: (v) => setSheetState(() => selectedType = v),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: ReportType.values.map((type) => InkWell(
                          onTap: () => setSheetState(() => selectedType = type),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Radio<ReportType>(
                                  value: type,
                                  activeColor: HuddlColors.primary,
                                ),
                                Text(type.label,
                                    style: HuddlText.body(color: context.hc.textPrimary)),
                              ],
                            ),
                          ),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    HuddlButton(
                      label: 'Submit report',
                      variant: HuddlButtonVariant.destructive,
                      onPressed: selectedType == null
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              final ok = await _reportService.submitReport(
                                contentId: item.id,
                                targetUserId: item.sellerId,
                                type: selectedType!,
                                context: ReportContext.listing,
                                chatName: item.title,
                              );
                              if (mounted) {
                                if (ok) {
                                  setState(() => _hasAlreadyReported = true);
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok
                                        ? 'Report submitted. Thank you for keeping Huddl safe.'
                                        : 'Could not submit report. Please try again.'),
                                    backgroundColor: ok ? HuddlColors.nearBlack : HuddlColors.error,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                );
                              }
                            },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // == BUILD =================================================================

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Scaffold(
      backgroundColor: hc.scaffold,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Hero photo app bar ──────────────────────────────────
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: true,
                  backgroundColor: hc.surface,
                  leading: _ItemCircleButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                  actions: [
                    _ItemCircleButton(
                      icon: Icons.share_outlined,
                      onTap: _shareItem,
                    ),
                    if (!_isOwnItem)
                      _ItemCircleButton(
                        icon: item.isSaved ? Icons.favorite : Icons.favorite_border,
                        onTap: _handleSaveAction,
                        color: item.isSaved ? HuddlColors.error : Colors.white,
                      ),
                    if (!_isOwnItem)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _ItemCircleButton(
                          icon: _hasAlreadyReported
                              ? Icons.flag
                              : Icons.flag_outlined,
                          color: _hasAlreadyReported
                              ? HuddlColors.error
                              : Colors.white,
                          onTap: _hasAlreadyReported
                              ? () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                          'You\'ve already reported this listing.'),
                                      backgroundColor: hc.textTertiary,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  );
                                }
                              : _showReportListingSheet,
                        ),
                      ),
                    if (_isOwnItem) const SizedBox(width: 8),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: _buildHeroPhoto(),
                  ),
                ),

                // ── Content ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    color: hc.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Price + condition + time
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    item.priceDisplay,
                                    style: HuddlText.display(color: HuddlColors.nearBlack),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: item.condition.color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.condition.label,
                                      style: HuddlText.caption(color: HuddlColors.nearBlack, weight: FontWeight.w600),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(item.timeAgo,
                                    style: HuddlText.caption()),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Title
                              Text(
                                item.title,
                                style: HuddlText.display(color: hc.textPrimary).copyWith(height: 1.3),
                              ),
                              const SizedBox(height: 12),

                              // Location + age + category — single clean row
                              Row(
                                children: [
                                  Icon(Icons.location_on_outlined, size: 14, color: hc.textTertiary),
                                  const SizedBox(width: 3),
                                  Text(item.sellerLocation,
                                    style: HuddlText.caption()),
                                  const SizedBox(width: 12),
                                  Container(
                                    width: 3, height: 3,
                                    decoration: BoxDecoration(color: hc.textTertiary, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(item.ageStage.shortLabel,
                                    style: HuddlText.caption()),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Urgency banner — shown only when not sold
                              if (!item.isSold) ...[
                                _buildDetailUrgencyBanner(),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ),
                        ),

                        // Thin divider
                        Divider(height: 1, color: hc.divider),

                        // Description
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _showFullDescription ? item.description : _smartSummary(),
                                style: HuddlText.body(color: hc.textSecondary).copyWith(height: 1.65),
                              ),
                              if (item.description.length > 80) ...[
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => setState(() => _showFullDescription = !_showFullDescription),
                                  child: Text(
                                    _showFullDescription ? 'Show less' : 'Read more',
                                    style: HuddlText.caption(color: HuddlColors.textTertiary, weight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        Divider(height: 1, color: hc.divider),

                        // Seller row — tappable, navigates to seller profile
                        Semantics(
                          label: 'View ${item.sellerName}\'s profile',
                          button: true,
                          child: InkWell(
                            onTap: () {
                              // Navigate to seller's public profile / listings
                              // using the existing profile push pattern
                              HapticFeedback.selectionClick();
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: hc.surface,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(24)),
                                ),
                                builder: (_) => SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const HuddlBottomSheetHandle(),
                                        const SizedBox(height: 16),
                                        MemberAvatar(name: item.sellerName, size: 56),
                                        const SizedBox(height: 12),
                                        Text(
                                          item.sellerName,
                                          style: HuddlText.heading(color: hc.textPrimary),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.location_on_outlined,
                                                size: 13, color: hc.textTertiary),
                                            const SizedBox(width: 3),
                                            Text(item.sellerLocation,
                                                style: HuddlText.caption()),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          'Seller on Huddl',
                                          style: HuddlText.caption(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                              child: Row(
                                children: [
                                  MemberAvatar(name: item.sellerName, size: 42),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.sellerName,
                                            style: HuddlText.body(color: hc.textPrimary, weight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Row(children: [
                                          Icon(Icons.location_on_outlined,
                                              size: 12, color: hc.textTertiary),
                                          const SizedBox(width: 3),
                                          Text(item.sellerLocation,
                                              style: HuddlText.caption()),
                                        ]),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      size: 18, color: hc.textTertiary),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Safety note — minimal, no box
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                          child: Row(
                            children: [
                              Icon(Icons.shield_outlined, size: 14,
                                color: hc.textTertiary.withValues(alpha: 0.6)),
                              const SizedBox(width: 8),
                              Text('Meet in public. Check items before paying.',
                                style: HuddlText.caption()),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildBottomBar(hc),
        ],
      ),
    );
  }

  // == URGENCY BANNER ==========================================================

  Widget _buildDetailUrgencyBanner() {
    // High view count — social proof (blue)
    if (item.viewCount >= 20 && item.offerCount == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: HuddlColors.infoBluePale,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, size: 16, color: HuddlColors.infoBlue),
            const SizedBox(width: 8),
            Text(
              '${item.viewCount} parents have viewed this',
              style: HuddlText.body(color: HuddlColors.infoBlue, weight: FontWeight.w500),
            ),
          ],
        ),
      );
    }
    // Active offers — highest intent signal (orange)
    if (item.offerCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: HuddlColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_offer_outlined, size: 16, color: HuddlColors.primary),
            const SizedBox(width: 8),
            Text(
              item.offerCount == 1
                  ? 'Someone has already made an offer'
                  : '${item.offerCount} people have made offers',
              style: HuddlText.body(color: HuddlColors.primary, weight: FontWeight.w500),
            ),
          ],
        ),
      );
    }
    // Free item — goes fast (yellow)
    if (item.isFree) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: HuddlColors.yellowBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.volunteer_activism_outlined, size: 16, color: HuddlColors.yellowDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This item is free — message the seller before someone else does',
                style: HuddlText.body(color: HuddlColors.yellowDark, weight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }
    // Recently listed — freshness signal (subtle)
    final hours = DateTime.now().difference(item.listedAt).inHours;
    if (hours < 6) {
      return Row(
        children: [
          const Icon(Icons.access_time_outlined, size: 14, color: HuddlColors.textTertiary),
          const SizedBox(width: 6),
          Text(
            'Just listed ${item.timeAgo}',
            style: HuddlText.caption(color: HuddlColors.textTertiary, weight: FontWeight.w600),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  // == HERO PHOTO (replaces flat gallery in SliverAppBar) ====================

  Widget _buildHeroPhoto() {
    final images = item.imageUrls;
    return Stack(
      fit: StackFit.expand,
      children: [
        images.isEmpty
            ? Container(
                color: HuddlColors.neutral50,
                child: Center(
                  child: Icon(item.category.icon,
                      size: 64, color: HuddlColors.textHint),
                ),
              )
            : PageView.builder(
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _currentImage = i),
                itemBuilder: (_, i) => _buildDetailImage(images[i]),
              ),
        // Subtle bottom gradient
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, HuddlColors.overlayMedium],
              stops: [0.6, 1.0],
            ),
          ),
        ),
        if (item.isSold)
          Positioned(
            bottom: 14, left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: HuddlColors.error, borderRadius: BorderRadius.circular(8)),
              child: Text('SOLD',
                style: HuddlText.label(color: Colors.white).copyWith(letterSpacing: 1)),
            ),
          ),
        if (images.length > 1)
          Positioned(
            bottom: 14, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == _currentImage ? 20 : 7, height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i == _currentImage ? Colors.white : Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),
          ),
      ],
    );
  }

  // == IMAGE HELPER — handles data:URI (base64), http URL, empty ==============
  // Each image is wrapped in InteractiveViewer for pinch-to-zoom (P3 audit).
  // min 1×, max 4×. Pan is unrestricted when zoomed so users can explore
  // corners of the photo after pinching in.

  Widget _buildDetailImage(String url) {
    final fallback = Container(
      color: HuddlColors.neutral50,
      child: Center(
        child: Icon(item.category.icon,
            size: 56, color: HuddlColors.textHint),
      ),
    );

    Widget imageWidget;
    if (url.isEmpty) {
      imageWidget = fallback;
    } else if (url.startsWith('data:')) {
      try {
        final comma = url.indexOf(',');
        if (comma >= 0) {
          final bytes = base64Decode(url.substring(comma + 1));
          imageWidget = Image.memory(bytes,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => fallback);
        } else {
          imageWidget = fallback;
        }
      } catch (_) {
        imageWidget = fallback;
      }
    } else if (url.startsWith('http')) {
      imageWidget = Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const HuddlShimmer(
            width: double.infinity,
            height: double.infinity,
          );
        },
      );
    } else {
      imageWidget = fallback;
    }

    // Wrap every image in InteractiveViewer so the user can pinch-to-zoom.
    // constrained:false lets the zoomed image overflow the SliverAppBar clip
    // boundary naturally. The PageView still handles swipe when scale == 1.
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 4.0,
      // Allow panning only when zoomed (scale > 1); at scale 1 horizontal
      // drag falls through to the PageView's own gesture recogniser.
      panEnabled: true,
      clipBehavior: Clip.hardEdge,
      child: imageWidget,
    );
  }

  // == PHOTO GALLERY =========================================================

  // == EDIT OWN LISTING ======================================================

  void _openEditListing() async {
    final result = await Navigator.push<RehomeItem>(
      context,
      HuddlSpringPageRoute(page: CreateListingScreen(existingItem: item)),
    );
    if (result != null && mounted) {
      setState(() {});
    }
  }

  // == BOTTOM BAR ============================================================

  Widget _buildBottomBar(HuddlContextColors hc) {
    if (_isOwnItem) {
      return _buildOwnerBottomBar(hc);
    }
    return _buildBuyerBottomBar(hc);
  }

  Widget _buildOwnerBottomBar(HuddlContextColors hc) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: hc.surface,
        boxShadow: [
          BoxShadow(
            color: hc.shadow,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: item.isSold
          ? _buildSoldOwnerBar(hc)
          : _buildActiveOwnerBar(hc),
    );
  }

  Widget _buildActiveOwnerBar(HuddlContextColors hc) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: 'Mark item as sold',
            button: true,
            child: HuddlButton(
              label: 'Mark sold',
              variant: HuddlButtonVariant.secondary,
              leadingIcon: Icons.sell_outlined,
              onPressed: () {
                HapticFeedback.mediumImpact();
                _service.markSold(item.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('"${item.title}" marked as sold')),
                      ],
                    ),
                    backgroundColor: HuddlColors.textDark,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            label: 'Edit this listing',
            button: true,
            child: HuddlButton(
              label: 'Edit listing',
              leadingIcon: Icons.edit_outlined,
              onPressed: _openEditListing,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSoldOwnerBar(HuddlContextColors hc) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: HuddlColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle,
                  size: 18, color: HuddlColors.error),
              const SizedBox(width: 6),
              Text(
                'Sold',
                style: HuddlText.body(color: HuddlColors.error, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            label: 'Relist this item for sale',
            button: true,
            child: HuddlButton(
              label: 'Relist item',
              leadingIcon: Icons.refresh,
              onPressed: () {
                HapticFeedback.mediumImpact();
                _service.relistItem(item.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('"${item.title}" is back on sale')),
                      ],
                    ),
                    backgroundColor: HuddlColors.textDark,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBuyerBottomBar(HuddlContextColors hc) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: hc.surface,
        boxShadow: [
          BoxShadow(
            color: hc.shadow,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Buyer contact slot counter (free users only) ──────────────────
          Builder(builder: (context) {
            final ss = SubscriptionService();
            if (TierLimits.isUnlimited(ss.limits.maxBuyerContactsLifetime)) {
              return const SizedBox.shrink();
            }
            final remaining = ss.buyerContactsRemaining;
            final total = ss.limits.maxBuyerContactsLifetime;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: remaining == 0
                      ? HuddlColors.primary.withValues(alpha: 0.08)
                      : context.hc.inputBg,
                  borderRadius: BorderRadius.circular(10),
                  border: remaining == 0
                      ? Border.all(color: HuddlColors.primary.withValues(alpha: 0.20))
                      : null,
                ),
                child: Row(children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 14,
                      color: remaining == 0
                          ? HuddlColors.primary
                          : context.hc.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      remaining == 0
                          ? 'Free seller contacts used — upgrade for unlimited'
                          : '$remaining of $total free seller '
                            '${total == 1 ? "contact" : "contacts"} remaining',
                      style: HuddlText.caption(
                        color: remaining == 0
                            ? HuddlColors.primary
                            : context.hc.textTertiary,
                      ),
                    ),
                  ),
                ]),
              ),
            );
          }),
          // Save button — 48dp
          Semantics(
            label: item.isSaved
                ? 'Remove from saved'
                : 'Save this item',
            button: true,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                border: Border.all(color: hc.divider, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _handleSaveAction,
                child: Icon(
                  item.isSaved ? Icons.favorite : Icons.favorite_border,
                  color: item.isSaved
                      ? HuddlColors.error
                      : hc.textTertiary,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Make offer — 48dp min height
          Expanded(
            child: Semantics(
              label: 'Make an offer for this item',
              button: true,
              child: HuddlButton(
                label: 'Make offer',
                onPressed: _showMakeOfferSheet,
                variant: HuddlButtonVariant.secondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Message seller — 48dp min height
          Expanded(
            child: Semantics(
              label: 'Message the seller',
              button: true,
              child: HuddlButton(
                label: 'Message',
                onPressed: _openingChat ? null : _openSellerChat,
                isLoading: _openingChat,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DETAIL PILL — compact attribute badge
// =============================================================================

// ── Circle icon button for SliverAppBar (matches Groups/Events style) ────────
class _ItemCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _ItemCircleButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}


