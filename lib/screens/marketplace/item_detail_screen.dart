import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/rehome_service.dart';
import '../../services/dm_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ITEM DETAIL SCREEN — consistent with Create Meetup / Create Group design
// ═══════════════════════════════════════════════════════════════════════════════

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

  RehomeItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    super.dispose();
  }

  void _shareItem() {
    final shareText =
        '${item.title}\n${item.priceDisplay} \u00B7 ${item.condition.label}'
        '\n\uD83D\uDCCD ${item.sellerLocation}'
        '\nSold by ${item.sellerName}'
        '\n\nCheck it out on Huddl Connect Preloved!';
    Clipboard.setData(ClipboardData(text: shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Listing link copied to clipboard'),
          ],
        ),
        backgroundColor: HuddlColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Open (or create) a DM conversation with the item seller and navigate.
  Future<void> _openSellerChat() async {
    if (_openingChat) return;
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  void _toggleSave() {
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
        backgroundColor: item.isSaved ? HuddlColors.primary : HuddlColors.textSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showMakeOfferSheet() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
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
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'for ${item.title}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: HuddlColors.textHint,
                ),
              ),
              if (!item.isFree) ...[
                const SizedBox(height: 4),
                Text(
                  'Listed at ${item.priceDisplay}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.primary,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: GoogleFonts.poppins(
                    fontSize: 24, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  prefixText: '\u00A3 ',
                  prefixStyle: GoogleFonts.poppins(
                      fontSize: 24, fontWeight: FontWeight.w600),
                  hintText: '0',
                  hintStyle: GoogleFonts.poppins(
                      fontSize: 24, color: HuddlColors.textHint),
                  filled: true,
                  fillColor: HuddlColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Offer sent! The seller will be notified.'),
                          ],
                        ),
                        backgroundColor: HuddlColors.teal,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: Text(
                    'Send offer',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD — consistent layout: AppBar > Photo > scrollable form-like body
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('Back',
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark)),
            ),
          ),
        ),
        leadingWidth: 80,
        centerTitle: true,
        title: Text(
          'Item details',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: _shareItem,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Icon(Icons.share_outlined,
                    size: 22, color: HuddlColors.textDark),
              ),
            ),
          ),
          GestureDetector(
            onTap: _toggleSave,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Icon(
                  item.isSaved ? Icons.favorite : Icons.favorite_border,
                  size: 22,
                  color: item.isSaved ? HuddlColors.error : HuddlColors.textDark,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─────────── PHOTO GALLERY (full-width banner) ───────────
                  _buildPhotoGallery(),
                  const SizedBox(height: 20),

                  // ─────────── PRICE & CONDITION ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _sectionLabel('Price'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: HuddlColors.gray300),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            item.priceDisplay,
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: item.isFree
                                  ? HuddlColors.teal
                                  : HuddlColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: item.condition.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              item.condition.label,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: item.condition.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─────────── ITEM NAME ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _sectionLabel('Item name'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: HuddlColors.gray300),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: HuddlColors.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Listed ${item.timeAgo}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─────────── DETAILS (age, category, location) ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _sectionLabel('Details'),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _detailRow(
                      icon: Icons.child_care,
                      label: 'Age',
                      value: item.ageStage.shortLabel,
                      color: HuddlColors.primary,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _detailRow(
                      icon: item.category.icon,
                      label: 'Category',
                      value: item.category.label,
                      color: item.category.color,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _detailRow(
                      icon: Icons.location_on_outlined,
                      label: 'Location',
                      value: item.sellerLocation,
                      color: HuddlColors.blue,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ─────────── DESCRIPTION ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _sectionLabel('Description'),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: HuddlColors.gray300),
                      ),
                      child: Text(
                        _showFullDescription
                            ? item.description
                            : (item.description.length > 160
                                ? '${item.description.substring(0, 160)}...'
                                : item.description),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: HuddlColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                  if (item.description.length > 160)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 6),
                      child: GestureDetector(
                        onTap: () => setState(
                            () => _showFullDescription = !_showFullDescription),
                        child: Text(
                          _showFullDescription ? 'Show less' : 'Read more',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // ─────────── SELLER ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _sectionLabel('Seller'),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSellerCard(),
                  ),

                  const SizedBox(height: 24),

                  // ─────────── SAFETY TIPS ───────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSafetyTips(),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Bottom action bar ──
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMPONENT WIDGETS (matching Create Meetup / Create Group design language)
  // ══════════════════════════════════════════════════════════════════════════

  // ── PHOTO GALLERY (full-width banner, matching Create Meetup photo area) ──

  Widget _buildPhotoGallery() {
    final images = item.imageUrls;
    return SizedBox(
      width: double.infinity,
      height: 200,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _currentImage = i),
            itemBuilder: (_, i) => Image.network(
              images[i],
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                color: HuddlColors.peachLight,
                child: Center(
                  child: Icon(item.category.icon,
                      size: 56,
                      color: HuddlColors.primary.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ),
          // Page indicator dots
          if (images.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (i) {
                  return Container(
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
          // Image counter badge
          if (images.length > 1)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentImage + 1}/${images.length}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── SECTION LABEL — bold dark text matching Create Meetup / Create Group ──

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: HuddlColors.textDark,
        ),
      ),
    );
  }

  // ── DETAIL ROW (underline style matching Create Meetup fields) ──

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: HuddlColors.gray300),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: HuddlColors.textHint,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: HuddlColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  // ── SELLER CARD ───────────────────────────────────────────────────────────

  Widget _buildSellerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.gray300),
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
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: HuddlColors.textHint),
                    const SizedBox(width: 3),
                    Text(
                      item.sellerLocation,
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
          GestureDetector(
            onTap: _openSellerChat,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: HuddlColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chat_bubble_outline,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Chat',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── SAFETY TIPS ───────────────────────────────────────────────────────────

  Widget _buildSafetyTips() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.peachLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: HuddlColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shield_outlined,
                size: 18, color: HuddlColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stay safe',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Meet in a public place. Check items before paying. Never share bank details in chat.',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── BOTTOM BAR ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Save button
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: HuddlColors.gray300, width: 1.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _toggleSave,
              child: Icon(
                item.isSaved ? Icons.favorite : Icons.favorite_border,
                color: item.isSaved ? HuddlColors.error : HuddlColors.textHint,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Make offer button
          Expanded(
            child: OutlinedButton(
              onPressed: _showMakeOfferSheet,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: HuddlColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'Make offer',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Message seller button
          Expanded(
            child: ElevatedButton(
              onPressed: _openingChat ? null : _openSellerChat,
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
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
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
