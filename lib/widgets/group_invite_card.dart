import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';
import 'common/huddl_card.dart';
import '../screens/groups/group_details_screen.dart';
import '../constants/app_text_styles.dart';

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

  /// Renders a group image from either a local asset path or a network URL.
  /// Falls back to a generic group icon if the URL is empty or fails.
  Widget _buildGroupImage(String imageUrl, dynamic hc) {
    if (imageUrl.isEmpty) {
      return Container(
        color: hc.surfaceAlt,
        child: Center(
          child: Icon(Icons.group, size: 48, color: hc.textTertiary),
        ),
      );
    }

    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Container(
          color: hc.surfaceAlt,
          child: Center(
            child: Icon(Icons.group, size: 48, color: hc.textTertiary),
          ),
        ),
      );
    }

    if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (_, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: hc.surfaceAlt,
            child: Center(
              child: Icon(Icons.group, size: 48, color: hc.textTertiary),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          color: hc.surfaceAlt,
          child: Center(
            child: Icon(Icons.group, size: 48, color: hc.textTertiary),
          ),
        ),
      );
    }

    // Fallback for any unrecognised URL scheme
    return Container(
      color: hc.surfaceAlt,
      child: Center(
        child: Icon(Icons.group, size: 48, color: hc.textTertiary),
      ),
    );
  }

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
          child: HuddlCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Group image — handles assets/ and http:// paths
                if (imageUrl.isNotEmpty)
                  SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: _buildGroupImage(imageUrl, hc),
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
                        style: HuddlText.body(weight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Description
                      if (description.isNotEmpty)
                        Text(
                          description,
                          style: HuddlText.caption(),
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
                            style: HuddlText.caption(),
                          ),
                          if (creatorName.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.person,
                                size: 14, color: hc.textTertiary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                creatorName,
                                style: HuddlText.caption(),
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
                              style: HuddlText.caption(),
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
                          style: HuddlText.caption(weight: FontWeight.w600),
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
