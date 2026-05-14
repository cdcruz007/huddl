import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/rehome_service.dart';
import '../../services/firestore_service.dart';
import '../../services/dm_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/huddl_notification_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/report_service.dart';
import '../rehome/create_listing_screen.dart';
import '../groups/forward_message_sheet.dart';

// =============================================================================
// PLATFORM-ADAPTIVE TEXT HELPER  (SF Pro on iOS/macOS, Poppins elsewhere)
// =============================================================================
TextStyle _adaptiveText({
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w400,
  Color? color,
  double? height,
  FontStyle? fontStyle,
  double? letterSpacing,
  TextDecoration? decoration,
  Color? decorationColor,
}) {
  final bool isApple =
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);
  if (isApple) {
    return TextStyle(
      fontFamily: '.SF Pro Text',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      decoration: decoration,
      decorationColor: decorationColor,
    );
  }
  return GoogleFonts.poppins(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    fontStyle: fontStyle,
    letterSpacing: letterSpacing,
    decoration: decoration,
    decorationColor: decorationColor,
  );
}

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
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  backgroundColor: HuddlColors.teal,
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
                    style: _adaptiveText(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: sheetHc.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'for ${item.title}',
                    style: _adaptiveText(
                      fontSize: 14,
                      color: sheetHc.textTertiary,
                    ),
                  ),
                  if (!item.isFree) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Listed at ${item.priceDisplay}',
                      style: _adaptiveText(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.primary,
                      ),
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
                        style: _adaptiveText(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: sheetHc.textPrimary),
                        decoration: InputDecoration(
                          prefixText: '\u00A3 ',
                          prefixStyle: _adaptiveText(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: sheetHc.textPrimary),
                          hintText: '0',
                          hintStyle: _adaptiveText(
                              fontSize: 24, color: sheetHc.textTertiary),
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
                        style: _adaptiveText(
                          fontSize: 11,
                          color: sheetHc.textTertiary,
                        ),
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
                      style: _adaptiveText(
                          fontSize: 14, color: sheetHc.textPrimary),
                      decoration: InputDecoration(
                        hintText:
                            item.isFree ? 'Add a message for the seller…' : 'Add a note (optional)…',
                        hintStyle: _adaptiveText(
                            fontSize: 14, color: sheetHc.textTertiary),
                        filled: true,
                        fillColor: sheetHc.surfaceAlt,
                        counterStyle: _adaptiveText(
                            fontSize: 11, color: sheetHc.textTertiary),
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
                  SizedBox(
                    width: double.infinity,
                    child: Semantics(
                      label: 'Send offer to seller',
                      button: true,
                      child: ElevatedButton(
                        onPressed: sending ? null : submitOffer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.primary,
                          disabledBackgroundColor:
                              HuddlColors.primary.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          minimumSize: const Size(0, 48),
                        ),
                        child: sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                item.isFree ? 'Request item' : 'Send offer',
                                style: _adaptiveText(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                          style: _adaptiveText(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: context.hc.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Why are you reporting "${item.title}"?',
                      style: _adaptiveText(
                        fontSize: 13,
                        color: context.hc.textSecondary,
                        height: 1.4,
                      ),
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
                                    style: _adaptiveText(
                                        fontSize: 14,
                                        color: context.hc.textPrimary)),
                              ],
                            ),
                          ),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedType == null
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                final ok =
                                    await _reportService.submitReport(
                                  contentId: item.id,
                                  targetUserId: item.sellerId,
                                  type: selectedType!,
                                  context: ReportContext.listing,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'Report submitted. Thank you.'
                                          : 'Could not submit report. Please try again.'),
                                      backgroundColor: ok
                                          ? HuddlColors.teal
                                          : HuddlColors.error,
                                      behavior:
                                          SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.error,
                          disabledBackgroundColor:
                              HuddlColors.error.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          minimumSize: const Size(0, 48),
                        ),
                        child: Text(
                          'Submit report',
                          style: _adaptiveText(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
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
      backgroundColor: hc.surface,
      appBar: AppBar(
        backgroundColor: hc.surface,
        elevation: 0,
        surfaceTintColor: hc.surface,
        automaticallyImplyLeading: false,
        leading: Semantics(
          label: 'Go back',
          button: true,
          child: InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(24),
            child: Center(
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Icon(Icons.arrow_back_ios_new,
                      size: 18, color: hc.textPrimary),
                ),
              ),
            ),
          ),
        ),
        leadingWidth: 56,
        centerTitle: true,
        title: Semantics(
          header: true,
          child: Text(
            'Details',
            style: _adaptiveText(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: hc.textPrimary,
            ),
          ),
        ),
        actions: [
          Semantics(
            label: 'Share this item',
            button: true,
            child: InkWell(
              onTap: _shareItem,
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.share_outlined,
                    size: 22, color: hc.textPrimary),
              ),
            ),
          ),
          if (!_isOwnItem)
            Semantics(
              label: item.isSaved
                  ? 'Remove from saved items'
                  : 'Save this item',
              button: true,
              child: InkWell(
                onTap: _toggleSave,
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    item.isSaved ? Icons.favorite : Icons.favorite_border,
                    size: 22,
                    color: item.isSaved
                        ? HuddlColors.error
                        : hc.textPrimary,
                  ),
                ),
              ),
            ),
          if (!_isOwnItem)
            Semantics(
              label: 'Report this listing',
              button: true,
              child: InkWell(
                onTap: _showReportListingSheet,
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.flag_outlined,
                      size: 22, color: hc.textTertiary),
                ),
              ),
            ),
          if (_isOwnItem) const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPhotoGallery(hc),
                  const SizedBox(height: 16),

                  // Price & Condition — streamlined, no section labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Semantics(
                          label: 'Price: ${item.priceDisplay}',
                          child: Text(
                            item.priceDisplay,
                            style: _adaptiveText(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: item.isFree
                                  ? HuddlColors.teal
                                  : HuddlColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Semantics(
                          label: 'Condition: ${item.condition.label}',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: item.condition.color
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              item.condition.label,
                              style: _adaptiveText(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: item.condition.color,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          item.timeAgo,
                          style: _adaptiveText(
                            fontSize: 12,
                            color: hc.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      item.title,
                      style: _adaptiveText(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: hc.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Details — compact pills row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _DetailPill(
                          icon: Icons.child_care,
                          label: item.ageStage.shortLabel,
                          color: HuddlColors.primary,
                        ),
                        _DetailPill(
                          icon: item.category.icon,
                          label: item.category.label,
                          color: item.category.color,
                        ),
                        _DetailPill(
                          icon: Icons.location_on_outlined,
                          label: item.sellerLocation,
                          color: HuddlColors.blue,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Description — smart summary for long text
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: hc.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _showFullDescription
                                ? item.description
                                : _smartSummary(),
                            style: _adaptiveText(
                              fontSize: 14,
                              color: hc.textSecondary,
                              height: 1.6,
                            ),
                          ),
                          if (item.description.length > 80) ...[
                            const SizedBox(height: 6),
                            Semantics(
                              label: _showFullDescription
                                  ? 'Show less'
                                  : 'Read more',
                              button: true,
                              child: InkWell(
                                onTap: () => setState(() =>
                                    _showFullDescription =
                                        !_showFullDescription),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  child: Text(
                                    _showFullDescription
                                        ? 'Show less'
                                        : 'Read more',
                                    style: _adaptiveText(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: HuddlColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Seller card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSellerCard(hc),
                  ),

                  const SizedBox(height: 20),

                  // Safety Tips — collapsed by default (progressive disclosure)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSafetyTips(hc),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          _buildBottomBar(hc),
        ],
      ),
    );
  }

  // == IMAGE HELPER — handles data:URI (base64), http URL, empty ==============

  Widget _buildDetailImage(String url) {
    final fallback = Container(
      color: HuddlColors.peachLight,
      child: Center(
        child: Icon(item.category.icon,
            size: 56, color: HuddlColors.primary.withValues(alpha: 0.6)),
      ),
    );
    if (url.isEmpty) return fallback;
    if (url.startsWith('data:')) {
      try {
        final comma = url.indexOf(',');
        if (comma >= 0) {
          final bytes = base64Decode(url.substring(comma + 1));
          return Image.memory(bytes,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => fallback);
        }
      } catch (_) {}
      return fallback;
    }
    if (url.startsWith('http')) {
      return Image.network(url,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, __, ___) => fallback);
    }
    return fallback;
  }

  // == PHOTO GALLERY =========================================================

  Widget _buildPhotoGallery(HuddlContextColors hc) {
    final images = item.imageUrls;
    return Semantics(
      label: 'Item photos, ${images.length} image${images.length > 1 ? "s" : ""}',
      child: SizedBox(
        width: double.infinity,
        height: 260,
        child: Stack(
          children: [
            PageView.builder(
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _currentImage = i),
              itemBuilder: (_, i) => Semantics(
                label: '${item.title} photo ${i + 1} of ${images.length}',
                image: true,
                child: _buildDetailImage(images[i]),
              ),
            ),
            if (images.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _currentImage ? 20 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i == _currentImage
                            ? HuddlColors.primary
                            : Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
            if (images.length > 1)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentImage + 1}/${images.length}',
                    style: _adaptiveText(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (item.isSold)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: HuddlColors.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'SOLD',
                    style: _adaptiveText(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // == SELLER CARD ===========================================================

  Widget _buildSellerCard(HuddlContextColors hc) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hc.divider),
      ),
      child: Row(
        children: [
          MemberAvatar(name: item.sellerName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.sellerName,
                  style: _adaptiveText(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: hc.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 14, color: hc.textTertiary),
                    const SizedBox(width: 3),
                    Text(
                      item.sellerLocation,
                      style: _adaptiveText(
                        fontSize: 12,
                        color: hc.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!_isOwnItem)
            Semantics(
              label: 'Chat with ${item.sellerName}',
              button: true,
              child: InkWell(
                onTap: _openSellerChat,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: const BoxConstraints(minHeight: 48),
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          color: HuddlColors.primary, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Chat',
                        style: _adaptiveText(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // == SAFETY TIPS (collapsed by default) ====================================

  Widget _buildSafetyTips(HuddlContextColors hc) {
    return Semantics(
      label: 'Safety tips for buying items',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: HuddlColors.peachLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.shield_outlined,
                size: 18, color: HuddlColors.primary.withValues(alpha: 0.7)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Meet in public. Check items before paying.',
                style: _adaptiveText(
                  fontSize: 12,
                  color: hc.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // == EDIT OWN LISTING ======================================================

  void _openEditListing() async {
    final result = await Navigator.push<RehomeItem>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateListingScreen(existingItem: item),
      ),
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
            child: OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                _service.markSold(item.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('"${item.title}" marked as sold')),
                      ],
                    ),
                    backgroundColor: HuddlColors.teal,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: Text(
                'Mark sold',
                style: _adaptiveText(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.blue,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: HuddlColors.blue,
                side: const BorderSide(color: HuddlColors.blue, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            label: 'Edit this listing',
            button: true,
            child: ElevatedButton.icon(
              onPressed: _openEditListing,
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: Colors.white),
              label: Text(
                'Edit listing',
                style: _adaptiveText(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                minimumSize: const Size(0, 48),
              ),
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
                style: _adaptiveText(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.error,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            label: 'Relist this item for sale',
            button: true,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                _service.relistItem(item.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child:
                                Text('"${item.title}" is back on sale')),
                      ],
                    ),
                    backgroundColor: HuddlColors.teal,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
              icon:
                  const Icon(Icons.refresh, size: 18, color: Colors.white),
              label: Text(
                'Relist item',
                style: _adaptiveText(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.teal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                minimumSize: const Size(0, 48),
              ),
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
                onTap: _toggleSave,
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
              child: OutlinedButton(
                onPressed: _showMakeOfferSheet,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                      color: HuddlColors.primary, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(0, 48),
                ),
                child: Text(
                  'Make offer',
                  style: _adaptiveText(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Message seller — 48dp min height
          Expanded(
            child: Semantics(
              label: 'Message the seller',
              button: true,
              child: ElevatedButton(
                onPressed: _openingChat ? null : _openSellerChat,
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  minimumSize: const Size(0, 48),
                ),
                child: _openingChat
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Message',
                        style: _adaptiveText(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
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

class _DetailPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DetailPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: _adaptiveText(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: hc.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
