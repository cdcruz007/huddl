import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/huddl_colors.dart';
import '../screens/groups/group_details_screen.dart';

/// A clickable group card that appears in chats
/// Tapping it navigates to the GroupDetailsScreen
class GroupInviteCard extends StatelessWidget {
  final Map<String, dynamic> groupData;
  final bool isMe;

  const GroupInviteCard({
    super.key,
    required this.groupData,
    this.isMe = true,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final name = groupData['name'] as String? ?? 'Group';
    final description = groupData['description'] as String? ?? '';
    final imageUrl = groupData['imageUrl'] as String? ?? '';
    final memberCount = (groupData['memberCount'] as num?)?.toInt() ?? 0;
    final creatorName = groupData['creatorName'] as String? ?? '';
    final borough = groupData['creatorBorough'] as String? ?? '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 24 : 40,
          right: isMe ? 0 : 24,
        ),
        constraints: const BoxConstraints(maxWidth: 320),
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupDetailsScreen(
                  groupId: groupData['id'] as String? ?? '',
                  groupName: name,
                  groupImageUrl: imageUrl,
                  groupDescription: description,
                  memberCount: memberCount,
                  isPrivate: false,
                  isJoined: false,
                ),
              ),
            );
          },
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
                // Group image
                if (imageUrl.isNotEmpty)
                  SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: hc.surfaceAlt,
                        child: Center(
                          child: Icon(Icons.group,
                              size: 48, color: hc.textTertiary),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: hc.surfaceAlt,
                        child: Center(
                          child: Icon(Icons.group,
                              size: 48, color: hc.textTertiary),
                        ),
                      ),
                    ),
                  ),
                // Group info
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group name
                      Text(
                        name,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: hc.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Description
                      if (description.isNotEmpty)
                        Text(
                          description,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: hc.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 8),
                      // Member count and creator
                      Row(
                        children: [
                          Icon(Icons.people,
                              size: 14, color: hc.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            '$memberCount members',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: hc.textTertiary,
                            ),
                          ),
                          if (creatorName.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.person,
                                size: 14, color: hc.textTertiary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                creatorName,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: hc.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (borough.isNotEmpty &&
                          borough != 'Unknown Borough') ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on,
                                size: 14, color: hc.textTertiary),
                            const SizedBox(width: 4),
                            Text(
                              borough,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: hc.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Join button
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: HuddlColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Tap to view group',
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
}


