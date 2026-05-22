import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import '../screens/events/event_detail_screen.dart';

/// A clickable event card that appears in DM and group chats when an event
/// is shared. Tapping it navigates to the EventDetailScreen.
class EventInviteCard extends StatelessWidget {
  final Map<String, dynamic> eventData;
  final bool isMe;

  const EventInviteCard({
    super.key,
    required this.eventData,
    this.isMe = true,
  });

  @override
  Widget build(BuildContext context) {
    final title = eventData['title'] as String? ?? 'Event';
    final date = eventData['date'] as String? ?? '';
    final time = eventData['time'] as String? ?? '';
    final location = eventData['location'] as String? ?? '';
    final organiser = eventData['organiser'] as String? ?? '';
    final category = eventData['category'] as String? ?? 'community';
    final isFree = eventData['isFree'] as bool? ?? true;
    final price = eventData['price'];
    final attendees = (eventData['attendees'] as num?)?.toInt() ?? 0;
    final imageUrl = eventData['imageUrl'] as String? ?? '';
    final isOnline = eventData['isOnline'] as bool? ?? false;

    final catStyle = _getEventCatStyle(category);

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
          onTap: () => _navigateToEventDetail(context),
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
                // ── Cover image ─────────────────────────────────────────
                Stack(
                  children: [
                    SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: _buildCoverImage(imageUrl, catStyle),
                    ),
                    // Gradient overlay
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
                              _formatCategory(category),
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Price badge (top-right)
                    Positioned(
                      top: 10, right: 10,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isOnline)
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
                                    Icon(Icons.videocam, size: 12, color: HuddlColors.white),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Online',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.white,
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
                                  : (price is String && price.isNotEmpty
                                      ? price
                                      : (price is num ? '\u00A3${price.toStringAsFixed(0)}' : 'Paid')),
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Attendee count (bottom-right)
                    if (attendees > 0)
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
                                '$attendees going',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: HuddlColors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                // ── Card body ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // "Shared an event" label
                      Row(
                        children: [
                          Icon(Icons.event_outlined, size: 12, color: catStyle.color),
                          const SizedBox(width: 4),
                          Text(
                            'Shared an event',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: catStyle.color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
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
                            date,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: context.hc.textSecondary,
                            ),
                          ),
                          if (time.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.access_time,
                                size: 13, color: catStyle.color),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                time,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: context.hc.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
                              isOnline ? 'Online event' : location,
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
                      // Organiser row with view button
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 11,
                            backgroundColor: catStyle.color.withValues(alpha: 0.15),
                            child: Text(
                              organiser.isNotEmpty ? organiser[0].toUpperCase() : 'E',
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
                              organiser.isNotEmpty ? 'By $organiser' : 'Event',
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

  Widget _buildCoverImage(String imageUrl, _EventCatStyle catStyle) {
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

  void _navigateToEventDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(event: eventData),
      ),
    );
  }

  String _formatCategory(String cat) {
    if (cat.isEmpty) return 'Event';
    return cat[0].toUpperCase() + cat.substring(1);
  }
}

// ── Category style helper for events ──────────────────────────────────────
class _EventCatStyle {
  final Color color;
  final IconData icon;
  const _EventCatStyle(this.color, this.icon);
}

_EventCatStyle _getEventCatStyle(String category) {
  switch (category.toLowerCase()) {
    case 'class':
      return const _EventCatStyle(HuddlColors.primary, Icons.school_outlined);
    case 'workshop':
      return const _EventCatStyle(HuddlColors.primaryDark, Icons.handyman_outlined);
    case 'community':
      return const _EventCatStyle(HuddlColors.nearBlack, Icons.people_outlined);
    case 'health':
      return const _EventCatStyle(HuddlColors.nearBlack, Icons.health_and_safety_outlined);
    case 'play':
      return const _EventCatStyle(HuddlColors.accentAmber, Icons.child_care_outlined);
    case 'sport':
      return const _EventCatStyle(HuddlColors.nearBlack, Icons.sports_outlined);
    case 'music':
      return const _EventCatStyle(HuddlColors.primaryDark, Icons.music_note_outlined);
    case 'food':
      return const _EventCatStyle(HuddlColors.accentAmber, Icons.restaurant_outlined);
    case 'arts':
    case 'art':
      return const _EventCatStyle(HuddlColors.accentCoral, Icons.palette_outlined);
    default:
      return const _EventCatStyle(HuddlColors.nearBlack, Icons.event_outlined);
  }
}
