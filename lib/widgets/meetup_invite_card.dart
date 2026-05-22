import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import '../services/meetup_service.dart';
import '../screens/events/meetup_detail_screen.dart';

/// A clickable meetup card that appears in DM and group chats
/// instead of a text notification message. Tapping it navigates
/// to the MeetupDetailScreen.
///
/// The layout now matches the Nearby tab's _MeetupCard so the user
/// sees the same image, details and visual hierarchy everywhere.
class MeetupInviteCard extends StatelessWidget {
  final Map<String, dynamic> meetupData;
  final bool isMe;

  const MeetupInviteCard({
    super.key,
    required this.meetupData,
    this.isMe = true,
  });

  /// Try to resolve the best available image URL for this meetup.
  /// The notification storage intentionally strips data: URIs (too large),
  /// so we look up the live Meetup object from MeetupService first.
  String _resolveImageUrl() {
    final storedUrl = meetupData['imageUrl'] as String? ?? '';
    if (storedUrl.isNotEmpty) return storedUrl;

    // Fall back to MeetupService's in-memory copy which keeps data: URIs
    final meetupId = meetupData['id'] as String?;
    if (meetupId != null) {
      final service = MeetupService();
      final found = service.meetups.where((m) => m.id == meetupId).toList();
      if (found.isNotEmpty && found.first.imageUrl.isNotEmpty) {
        return found.first.imageUrl;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final title = meetupData['title'] as String? ?? 'Meetup';
    final dateDisplay = meetupData['dateDisplay'] as String? ?? '';
    final timeDisplay = meetupData['timeDisplay'] as String? ?? '';
    final location = meetupData['location'] as String? ?? '';
    final organiser = meetupData['organiserName'] as String? ?? '';
    final category = meetupData['category'] as String? ?? 'Other';
    // Safe num→bool/int casts: JSON decode on the web can return num/double
    // for fields that were stored as Dart int, causing 'as int?' to throw.
    final isFree = (meetupData['isFree'] as bool?) ?? true;
    final price = meetupData['price'];
    final attendeeCount = (meetupData['attendeeCount'] as num?)?.toInt() ?? 1;
    final maxAttendees = (meetupData['maxAttendees'] as num?)?.toInt();
    // privacy can be stored as int (index) OR as String (e.g. 'MeetupPrivacy.public')
    final privacyRaw = meetupData['privacy'];
    final privacyIdx = (privacyRaw is num)
        ? privacyRaw.toInt()
        : (privacyRaw is String && privacyRaw.contains('group'))
            ? 1
            : (privacyRaw is String && privacyRaw.contains('private'))
                ? 2
                : 0;
    final privacy = MeetupPrivacy.values[privacyIdx.clamp(0, MeetupPrivacy.values.length - 1)];

    final imageUrl = _resolveImageUrl();
    final catStyle = _getCatStyle(category);

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
          onTap: () => _navigateToMeetupDetail(context),
          child: Container(
            decoration: BoxDecoration(
              color: context.hc.surface,
              borderRadius: BorderRadius.circular(16),
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
                // ── Cover image (matches Nearby tab: 150 px) ─────────
                Stack(
                  children: [
                    SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: _buildCoverImage(imageUrl, catStyle),
                    ),
                    // Gradient overlay at bottom for readability
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              HuddlColors.white.withValues(alpha: 0.0),
                              HuddlColors.gray900.withValues(alpha: 0.4),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Category badge (top-left)
                    Positioned(
                      top: 10, left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: catStyle.color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(catStyle.icon, size: 13, color: HuddlColors.white),
                            const SizedBox(width: 4),
                            Text(
                              category,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: context.hc.surface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Price + privacy badges (top-right)
                    Positioned(
                      top: 10, right: 10,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (privacy != MeetupPrivacy.public)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: HuddlColors.gray900.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      privacy == MeetupPrivacy.group
                                          ? Icons.group
                                          : Icons.lock,
                                      size: 12,
                                      color: context.hc.surface,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      privacy == MeetupPrivacy.group
                                          ? 'Group'
                                          : 'Private',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: context.hc.surface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isFree ? HuddlColors.nearBlack : HuddlColors.accentAmber,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isFree
                                  ? 'Free'
                                  : '\u00A3${price is num ? price.toStringAsFixed(0) : ''}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: context.hc.surface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Attendee count overlay (bottom-right)
                    Positioned(
                      bottom: 8, right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: HuddlColors.gray900.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people, size: 13, color: HuddlColors.white),
                            const SizedBox(width: 4),
                            Text(
                              '$attendeeCount${maxAttendees != null ? '/$maxAttendees' : ''} going',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: context.hc.surface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Card body (matches Nearby tab layout) ────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Date + time
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 13, color: catStyle.color),
                          const SizedBox(width: 5),
                          Text(
                            dateDisplay,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: context.hc.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.access_time,
                              size: 13, color: catStyle.color),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              timeDisplay,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: context.hc.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Location
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 13, color: catStyle.color),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              location,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: context.hc.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Organiser row with avatar
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 11,
                            backgroundColor: catStyle.color.withValues(alpha: 0.15),
                            child: Text(
                              organiser.isNotEmpty
                                  ? organiser[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: catStyle.color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Organised by $organiser',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: context.hc.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // View button
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: catStyle.color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_new, size: 12, color: catStyle.color),
                                const SizedBox(width: 4),
                                Text(
                                  'View',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: catStyle.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

  /// Build cover image — supports data: URIs, http URLs, and gradient fallback.
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
            child: Icon(catStyle.icon, size: 40, color: HuddlColors.white),
          ),
        );

    Widget placeholder() => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                catStyle.color.withValues(alpha: 0.12),
                catStyle.color.withValues(alpha: 0.06),
              ],
            ),
          ),
          child: Center(
            child: Icon(catStyle.icon, size: 40,
                color: catStyle.color.withValues(alpha: 0.4)),
          ),
        );

    if (imageUrl.isEmpty) return fallback();

    // ── base64 data-URI (user-uploaded photos) ────────────────────────
    if (imageUrl.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(imageUrl);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => fallback(),
          );
        }
      } catch (_) {}
      return fallback();
    }

    // ── http(s) URL (Pexels images etc.) ──────────────────────────────
    // Use Image.network for reliable web rendering
    if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder();
        },
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    // ── Local asset path ──────────────────────────────────────────────
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => fallback(),
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

// ── Category style helper (mirrors events_screen.dart _meetupCategoryStyle) ──
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
      return const _CatStyle(HuddlColors.nearBlack, Icons.sports_golf);
    case 'Walk':
      return const _CatStyle(HuddlColors.accentAmber, Icons.directions_walk);
    case 'Social':
      return const _CatStyle(HuddlColors.accentAmber, Icons.celebration);
    case 'Food':
      return const _CatStyle(HuddlColors.accentAmber, Icons.restaurant);
    case 'Other':
      return const _CatStyle(HuddlColors.nearBlack, Icons.more_horiz);
    default:
      return const _CatStyle(HuddlColors.nearBlack, Icons.groups);
  }
}
