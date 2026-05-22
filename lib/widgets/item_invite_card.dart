import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/huddl_colors.dart';
import '../services/rehome_service.dart';
import '../screens/marketplace/item_detail_screen.dart';

/// A clickable item for sale card that appears in chats
/// Tapping it navigates to the ItemDetailScreen
class ItemInviteCard extends StatelessWidget {
  final Map<String, dynamic> itemData;
  final bool isMe;

  const ItemInviteCard({
    super.key,
    required this.itemData,
    this.isMe = true,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final title = itemData['title'] as String? ?? 'Item';
    final priceDisplay = itemData['priceDisplay'] as String? ?? 'Free';
    final condition = itemData['condition'] as String? ?? 'Good';
    final ageStage = itemData['ageStage'] as String? ?? '';
    final sellerName = itemData['sellerName'] as String? ?? '';
    final sellerLocation = itemData['sellerLocation'] as String? ?? '';
    final imageUrls = (itemData['imageUrls'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final imageUrl = imageUrls.isNotEmpty ? imageUrls.first : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 24 : 40,
          right: isMe ? 0 : 24,
        ),
        constraints: const BoxConstraints(maxWidth: 280),
        child: GestureDetector(
          onTap: () => _navigateToItemDetail(context),
          child: Container(
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hc.divider, width: 1),
              boxShadow: [
                BoxShadow(
                  color: HuddlColors.gray900.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item image
                SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: hc.surfaceAlt,
                            child: Center(
                              child: Icon(Icons.shopping_bag,
                                  size: 48, color: hc.textTertiary),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: hc.surfaceAlt,
                            child: Center(
                              child: Icon(Icons.shopping_bag,
                                  size: 48, color: hc.textTertiary),
                            ),
                          ),
                        )
                      : Container(
                          color: hc.surfaceAlt,
                          child: Center(
                            child: Icon(Icons.shopping_bag,
                                size: 48, color: hc.textTertiary),
                          ),
                        ),
                ),
                // Item info
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: hc.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Price and condition
                      Row(
                        children: [
                          Text(
                            priceDisplay,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.textDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: HuddlColors.teal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              condition,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.teal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (ageStage.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: hc.surfaceAlt,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ageStage,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: hc.textSecondary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Seller info
                      if (sellerName.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.person,
                                size: 14, color: hc.textTertiary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                sellerName,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: hc.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      if (sellerLocation.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on,
                                size: 14, color: hc.textTertiary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                sellerLocation,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: hc.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      // View button
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: HuddlColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Tap to view item',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToItemDetail(BuildContext context) {
    // Convert itemData to RehomeItem
    final item = RehomeItem(
      id: itemData['id'] as String? ?? '',
      title: itemData['title'] as String? ?? '',
      description: itemData['description'] as String? ?? '',
      ageStage: _parseAgeStage(itemData['ageStage'] as String? ?? ''),
      category: _parseCategory(itemData['category'] as String? ?? ''),
      condition: _parseCondition(itemData['condition'] as String? ?? ''),
      price: (itemData['price'] as num?)?.toDouble() ?? 0.0,
      imageUrls: (itemData['imageUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      sellerName: itemData['sellerName'] as String? ?? '',
      sellerId: itemData['sellerId'] as String? ?? '',
      sellerLocation: itemData['sellerLocation'] as String? ?? '',
      listedAt: DateTime.tryParse(itemData['listedAt'] as String? ?? '') ??
          DateTime.now(),
      borough: itemData['borough'] as String?,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(item: item),
      ),
    );
  }

  AgeStage _parseAgeStage(String label) {
    return AgeStage.values.firstWhere(
      (e) => e.label == label,
      orElse: () => AgeStage.allAges,
    );
  }

  ItemCategory _parseCategory(String label) {
    return ItemCategory.values.firstWhere(
      (e) => e.label == label,
      orElse: () => ItemCategory.other,
    );
  }

  ItemCondition _parseCondition(String label) {
    return ItemCondition.values.firstWhere(
      (e) => e.label == label,
      orElse: () => ItemCondition.good,
    );
  }
}


