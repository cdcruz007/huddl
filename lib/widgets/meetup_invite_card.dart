import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/huddl_colors.dart';
import '../services/meetup_service.dart';
import '../screens/events/meetup_detail_screen.dart';

/// A clickable meetup card that appears in DM and group chats
/// instead of a text notification message. Tapping it navigates
/// to the MeetupDetailScreen.
class MeetupInviteCard extends StatelessWidget {
  final Map<String, dynamic> meetupData;
  final bool isMe;

  const MeetupInviteCard({
    super.key,
    required this.meetupData,
    this.isMe = true,
  });

  @override
  Widget build(BuildContext context) {
    final title = meetupData['title'] as String? ?? 'Meetup';
    final dateDisplay = meetupData['dateDisplay'] as String? ?? '';
    final timeDisplay = meetupData['timeDisplay'] as String? ?? '';
    final location = meetupData['location'] as String? ?? '';
    final organiser = meetupData['organiserName'] as String? ?? '';
    final imageUrl = meetupData['imageUrl'] as String? ?? '';
    final category = meetupData['category'] as String? ?? 'Other';
    final isFree = meetupData['isFree'] as bool? ?? true;
    final price = meetupData['price'];

    final catStyle = _getCatStyle(category);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 48 : 40,
          right: isMe ? 0 : 48,
        ),
        constraints: const BoxConstraints(maxWidth: 300),
        child: GestureDetector(
          onTap: () => _navigateToMeetupDetail(context),
          child: Container(
            decoration: BoxDecoration(
              color: HuddlColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: catStyle.color.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cover image / category gradient ──
                SizedBox(
                  height: 100,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildCoverImage(imageUrl, catStyle),
                      // Gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.45),
                            ],
                          ),
                        ),
                      ),
                      // Category + price badges
                      Positioned(
                        bottom: 8,
                        left: 10,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: catStyle.color,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(catStyle.icon,
                                      size: 11, color: HuddlColors.white),
                                  const SizedBox(width: 3),
                                  Text(
                                    category,
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: HuddlColors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isFree
                                    ? HuddlColors.blue
                                    : HuddlColors.accentAmber,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isFree
                                    ? 'Free'
                                    : '\u00A3${price is num ? price.toStringAsFixed(0) : ''}',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Card content ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.textDark,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Date / time row
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 12, color: catStyle.color),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '$dateDisplay  $timeDisplay',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: HuddlColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Location row
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 12, color: catStyle.color),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              location,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: HuddlColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Organiser row
                      Row(
                        children: [
                          Icon(Icons.person_outline,
                              size: 12, color: catStyle.color),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Organised by $organiser',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: HuddlColors.textHint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // "View meetup" button
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: catStyle.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.open_in_new,
                                size: 14, color: catStyle.color),
                            const SizedBox(width: 6),
                            Text(
                              'View meetup details',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: catStyle.color,
                              ),
                            ),
                          ],
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

  Widget _buildCoverImage(String imageUrl, _CatStyle catStyle) {
    Widget fallback() => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [catStyle.color, catStyle.color.withValues(alpha: 0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Icon(catStyle.icon, size: 32, color: HuddlColors.white),
          ),
        );

    if (imageUrl.isEmpty) return fallback();

    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback(),
        errorWidget: (_, __, ___) => fallback(),
      );
    }

    return fallback();
  }

  void _navigateToMeetupDetail(BuildContext context) {
    // Reconstruct the Meetup object from the data
    try {
      final meetup = Meetup.fromJson(meetupData);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetupDetailScreen(meetup: meetup),
        ),
      );
    } catch (_) {
      // If reconstruction fails, try finding it in MeetupService
      final meetupId = meetupData['id'] as String?;
      if (meetupId != null) {
        final service = MeetupService();
        final found = service.meetups.where((m) => m.id == meetupId).toList();
        if (found.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MeetupDetailScreen(meetup: found.first),
            ),
          );
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to load meetup details'),
          backgroundColor: HuddlColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}

// ── Category style helper (mirrors meetup_detail_screen.dart) ──
class _CatStyle {
  final Color color;
  final IconData icon;
  const _CatStyle(this.color, this.icon);
}

_CatStyle _getCatStyle(String category) {
  switch (category) {
    case 'Coffee':
      return const _CatStyle(HuddlColors.primaryDark, Icons.coffee);
    case 'Playdate':
      return const _CatStyle(HuddlColors.primary, Icons.child_care);
    case 'Sport':
      return const _CatStyle(HuddlColors.blue, Icons.sports_golf);
    case 'Walk':
      return const _CatStyle(HuddlColors.paleBlue, Icons.directions_walk);
    case 'Social':
      return const _CatStyle(HuddlColors.accentAmber, Icons.celebration);
    case 'Food':
      return const _CatStyle(HuddlColors.accentAmber, Icons.restaurant);
    default:
      return const _CatStyle(HuddlColors.blue, Icons.groups);
  }
}
