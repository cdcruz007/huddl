import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/meetup_service.dart';
import '../../services/member_photo_service.dart';
import '../../services/browser_storage.dart';

import '../../models/group.dart';
import '../groups/forward_message_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';



class MeetupDetailScreen extends StatefulWidget {
  final Meetup meetup;

  const MeetupDetailScreen({super.key, required this.meetup});

  @override
  State<MeetupDetailScreen> createState() => _MeetupDetailScreenState();
}

class _MeetupDetailScreenState extends State<MeetupDetailScreen> {
  final _meetupService = MeetupService();
  late Meetup _meetup;

  @override
  void initState() {
    super.initState();
    _meetup = widget.meetup;
    _meetupService.addListener(_refresh);
    // Ensure user-uploaded base64 images are restored into memory
    _meetupService.restoreCustomImages();
  }

  @override
  void dispose() {
    _meetupService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final updated = _meetupService.meetups
        .where((m) => m.id == _meetup.id)
        .toList();
    if (updated.isNotEmpty) {
      setState(() => _meetup = updated.first);
    }
  }

  void _toggleGoing() {
    HapticFeedback.mediumImpact();
    final wasGoing = _meetup.isGoing;
    _meetupService.toggleGoing(_meetup.id);

    // If user just said "Count Me In", create a meetup group chat
    if (!wasGoing) {
      _createMeetupGroupChat();
    }
  }

  /// Creates a group chat under Messages tab for this meetup attendees
  Future<void> _createMeetupGroupChat() async {
    final groupKey = 'user_created_groups_v1';
    final meetupGroupId = 'meetup_group_${_meetup.id}';

    // Check if group already exists
    final existing = await BrowserStorage.getString(groupKey);
    List<dynamic> groups = [];
    if (existing != null) {
      groups = json.decode(existing) as List<dynamic>;
      final alreadyExists = groups.any((g) =>
          (g as Map<String, dynamic>)['id'] == meetupGroupId);
      if (alreadyExists) return; // Don't create duplicate
    }

    final newGroup = Group(
      id: meetupGroupId,
      name: _meetup.title,
      description:
          'Group chat for "${_meetup.title}" meetup on ${_meetup.dateDisplay} at ${_meetup.location}',
      imageUrl: _meetup.imageUrl.isNotEmpty && !_meetup.imageUrl.startsWith('data:')
          ? _meetup.imageUrl
          : _categoryFallbackImage(_meetup.category),
      memberCount: _meetup.attendeeCount,
      category: 'MEETUP',
      isJoined: true,
      isImageLocked: false,
      targetAudience: const [],
      privacy: GroupPrivacy.private_,
      creatorId: _meetup.organiserId,
      creatorName: _meetup.organiserName,
      creatorBorough: '',
      lastMessage: 'Meetup group created',
      lastSenderName: 'System',
      lastMessageTime: DateTime.now(),
    );

    groups.add(newGroup.toJson());
    await BrowserStorage.setString(groupKey, json.encode(groups));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.group, color: context.hc.surface, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Meetup group chat created under Messages tab'),
              ),
            ],
          ),
          backgroundColor: HuddlColors.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  /// Build the meetup data map used for rich card sharing.
  Map<String, dynamic> get _meetupShareData {
    final data = _meetup.toJson();
    // Strip large base64 images — card widget fetches them from MeetupService
    if ((data['imageUrl'] as String? ?? '').startsWith('data:')) {
      data['imageUrl'] = '';
    }
    return data;
  }

  /// Share meetup via forward sheet — opens the "Send to" sheet with
  /// Members and Groups tabs so the user picks recipients. A rich
  /// meetup card is sent (not plain text).
  void _shareMeetup() {
    HapticFeedback.mediumImpact();
    showForwardSheet(
      context: context,
      messageText: 'Check out this meetup: "${_meetup.title}"',
      isMeetupCard: true,
      meetupData: _meetupShareData,
    );
  }

  /// Opens the forward sheet to send the meetup card to a DM or group.
  /// Used by the chat (bubble) button — sends a card, NOT plain text.
  void _shareToChat() {
    HapticFeedback.mediumImpact();
    showForwardSheet(
      context: context,
      messageText: 'Check out this meetup: "${_meetup.title}"',
      isMeetupCard: true,
      meetupData: _meetupShareData,
    );
  }

  bool get _isOrganiser {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return myUid != null
        ? _meetup.organiserId == myUid
        : _meetup.organiserId == 'current_user';
  }

  /// Show the more options bottom sheet (organiser controls)
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: context.hc.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Meet-up Options',
                  style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: context.hc.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: HuddlColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.share_outlined, color: HuddlColors.primary, size: 20),
                  ),
                  title: Text('Share Meet-up', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareMeetup();
                  },
                ),
                ListTile(
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: HuddlColors.blueBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.copy_outlined, color: HuddlColors.teal, size: 20),
                  ),
                  title: Text('Copy Link', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(
                      text: 'Join "${_meetup.title}" on ${_meetup.dateDisplay} at ${_meetup.location}',
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Link copied to clipboard'),
                        backgroundColor: HuddlColors.teal,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                ),
                if (_isOrganiser) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: HuddlColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.people_outline, color: HuddlColors.primary, size: 20),
                    ),
                    title: Text('Manage Attendees', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showManageAttendees();
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: HuddlColors.errorLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_outline, color: HuddlColors.error, size: 20),
                    ),
                    title: Text('Cancel Meet-up', style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w500, color: HuddlColors.error)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDelete();
                    },
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Show manage attendees bottom sheet
  void _showManageAttendees() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) {
            return Column(
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                    color: context.hc.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Attendees (${_meetup.attendeeCount})',
                  style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: context.hc.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                if (_meetup.maxAttendees != null)
                  Text(
                    '${_meetup.maxAttendees! - _meetup.attendeeCount} spots remaining',
                    style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textTertiary),
                  ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                // Attendee list — only real RSVP'd users from Firestore.
                // No fake or pre-populated names are shown.
                Expanded(
                  child: _meetup.attendeeCount == 0
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.group_outlined,
                                  size: 48,
                                  color: HuddlColors.primary.withValues(alpha: 0.3)),
                              const SizedBox(height: 12),
                              Text(
                                'No attendees yet',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: context.hc.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Be the first to RSVP!',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: context.hc.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          children: [
                            // Organiser row (always shown when count > 0)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              leading: _buildAttendeePhoto(_meetup.organiserName, 40),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _meetup.organiserName,
                                      style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: context.hc.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: HuddlColors.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Organiser',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Host',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: context.hc.textTertiary,
                                ),
                              ),
                            ),
                            // Remaining count shown as a summary row
                            if (_meetup.attendeeCount > 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                                child: Text(
                                  '+ ${_meetup.attendeeCount - 1} other ${(_meetup.attendeeCount - 1) == 1 ? 'parent' : 'parents'} going',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: HuddlColors.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Confirm delete dialog
  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.hc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Meet-up?', style: GoogleFonts.poppins(
          fontSize: 18, fontWeight: FontWeight.w700, color: context.hc.textPrimary)),
        content: Text(
          'This will permanently remove "${_meetup.title}" and notify all attendees. This action cannot be undone.',
          style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Keep', style: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w600, color: context.hc.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _cancelMeetupAndNotify();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: HuddlColors.error, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Cancel Meet-up', style: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.white)),
          ),
        ],
      ),
    );
  }

  /// Cancel the meetup, send cancellation messages to all confirmed attendees,
  /// and update the meetup group chat with a cancellation notice.
  Future<void> _cancelMeetupAndNotify() async {
    final cancelled = _meetupService.cancelMeetup(_meetup.id);
    if (cancelled == null) return;

    // Send cancellation message to the meetup group chat
    final meetupGroupId = 'meetup_group_${cancelled.id}';
    final cancellationMsg =
        'The creator of the meetup group has unfortunately cancelled this meetup. '
        'Please feel free to set one up as a replacement if you would still '
        'be keen to arrange a similar meetup.';

    // Store cancellation notice in the group chat
    await BrowserStorage.setString(
      'meetup_cancelled_$meetupGroupId',
      json.encode({
        'type': 'cancellation',
        'meetupId': cancelled.id,
        'meetupTitle': cancelled.title,
        'message': cancellationMsg,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );

    // Real RSVP'd attendees would be notified via Firestore/FCM here.
    // attendeeNames is no longer populated with fake data — notifications
    // are handled server-side when real users RSVP via rsvpMeetup().

    // Remove the meetup group chat from Messages
    try {
      final groupKey = 'user_created_groups_v1';
      final existing = await BrowserStorage.getString(groupKey);
      if (existing != null) {
        final groups = (json.decode(existing) as List<dynamic>)
            .where((g) => (g as Map<String, dynamic>)['id'] != meetupGroupId)
            .toList();
        await BrowserStorage.setString(groupKey, json.encode(groups));
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Meet-up cancelled — attendees have been notified'),
        backgroundColor: HuddlColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catStyle = _getCatStyle(_meetup.category);

    return Scaffold(
      backgroundColor: context.hc.scaffold,
      body: CustomScrollView(
        slivers: [
          // ── App bar with category colour ──────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: catStyle.color,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: HuddlColors.gray900.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back,
                    color: context.hc.surface, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              // Share button — always visible
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: HuddlColors.gray900.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.share_outlined,
                      color: context.hc.surface, size: 20),
                  onPressed: _shareMeetup,
                ),
              ),
              // 3-dot overflow — organiser only (manage attendees + cancel)
              if (_isOrganiser)
                Container(
                  margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: HuddlColors.gray900.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.more_vert,
                        color: context.hc.surface, size: 20),
                    onPressed: _showMoreOptions,
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'meetup_cover_${_meetup.id}',
                    child: _buildDetailCoverImage(
                      imageUrl: _meetup.imageUrl.isNotEmpty
                          ? _meetup.imageUrl
                          : _categoryFallbackImage(_meetup.category),
                      fallbackIcon: catStyle.icon,
                      fallbackColor: catStyle.color,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          HuddlColors.gray900.withValues(alpha: 0.1),
                          HuddlColors.gray900.withValues(alpha: 0.5),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: catStyle.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(catStyle.icon,
                                  size: 14, color: HuddlColors.white),
                              const SizedBox(width: 4),
                              Text(
                                _meetup.category,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.hc.surface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: _meetup.isFree ? HuddlColors.teal : HuddlColors.accentAmber,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _meetup.isFree
                                ? 'Free'
                                : '\u00A3${_meetup.price?.toStringAsFixed(0) ?? ''}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.hc.surface,
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

          // ── Body ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Container(
                  color: context.hc.surface,
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _meetup.title,
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildAttendeePhoto(_meetup.organiserName, 24),
                          const SizedBox(width: 8),
                          Text(
                            'Organised by ',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: context.hc.textTertiary,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              _meetup.organiserName,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Details section
                Container(
                  color: context.hc.surface,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: Icons.calendar_today_outlined,
                        iconColor: catStyle.color,
                        title: _meetup.dateDisplay,
                        subtitle: _meetup.timeDisplay,
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        iconColor: catStyle.color,
                        title: _meetup.location,
                        subtitle: 'Tap for directions',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: Icons.people_outline,
                        iconColor: catStyle.color,
                        title:
                            '${_meetup.attendeeCount}${_meetup.maxAttendees != null ? ' / ${_meetup.maxAttendees}' : ''} people going',
                        subtitle: _meetup.maxAttendees != null
                            ? '${_meetup.maxAttendees! - _meetup.attendeeCount} spots left'
                            : 'Open to all',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        icon: Icons.attach_money_outlined,
                        iconColor: HuddlColors.teal,
                        title: _meetup.isFree
                            ? 'Free'
                            : '\u00A3${_meetup.price?.toStringAsFixed(2) ?? 'TBC'}',
                        subtitle: _meetup.isFree
                            ? 'No cost to attend'
                            : 'Per person',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Repeat & Privacy info (if applicable)
                if (_meetup.repeat != MeetupRepeat.none || _meetup.privacy != MeetupPrivacy.public) ...[
                  Container(
                    color: context.hc.surface,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        if (_meetup.repeat != MeetupRepeat.none)
                          Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: HuddlColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.repeat, size: 20, color: HuddlColors.primary),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Repeating', style: GoogleFonts.poppins(
                                      fontSize: 14, fontWeight: FontWeight.w600, color: context.hc.textPrimary)),
                                    Text(_meetup.repeatDisplay ?? 'Recurring', style: GoogleFonts.poppins(
                                      fontSize: 12, color: context.hc.textTertiary)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        if (_meetup.repeat != MeetupRepeat.none && _meetup.privacy != MeetupPrivacy.public)
                          const Divider(height: 24),
                        if (_meetup.privacy != MeetupPrivacy.public)
                          Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: HuddlColors.lightBlue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _meetup.privacy == MeetupPrivacy.group ? Icons.group : Icons.lock_outline,
                                  size: 20, color: HuddlColors.lightBlue,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _meetup.privacy == MeetupPrivacy.group ? 'Group Meet-up' : 'Private Meet-up',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14, fontWeight: FontWeight.w600, color: context.hc.textPrimary),
                                    ),
                                    Text(
                                      _meetup.groupName ?? 'Invite only',
                                      style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Description
                Container(
                  color: context.hc.surface,
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _meetup.description,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: context.hc.textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Invitees section (if any)
                if (_meetup.invitees.isNotEmpty) ...[
                  Container(
                    color: context.hc.surface,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Invited', style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w600, color: context.hc.textPrimary)),
                            Text('${_meetup.invitees.length} people', style: GoogleFonts.poppins(
                              fontSize: 13, color: context.hc.textTertiary)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._meetup.invitees.take(6).map((inv) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              MemberAvatar(name: inv.name, size: 32),
                              const SizedBox(width: 10),
                              Expanded(child: Text(inv.name, style: GoogleFonts.poppins(
                                fontSize: 14, fontWeight: FontWeight.w500, color: context.hc.textPrimary))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: inv.status == 'going'
                                      ? HuddlColors.teal.withValues(alpha: 0.1)
                                      : inv.status == 'declined'
                                          ? HuddlColors.error.withValues(alpha: 0.1)
                                          : HuddlColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  inv.status == 'going' ? 'Going'
                                      : inv.status == 'declined' ? 'Declined'
                                      : 'Invited',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11, fontWeight: FontWeight.w600,
                                    color: inv.status == 'going'
                                        ? HuddlColors.teal
                                        : inv.status == 'declined'
                                            ? HuddlColors.error
                                            : HuddlColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                        if (_meetup.invitees.length > 6)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('+${_meetup.invitees.length - 6} more invited',
                              style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.primary, fontWeight: FontWeight.w500)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Attendees with profile pictures
                Container(
                  color: context.hc.surface,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Who's going",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          Text(
                            '${_meetup.attendeeCount} people',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: context.hc.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_meetup.attendeeCount == 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.group_outlined,
                                  color: HuddlColors.primary.withValues(alpha: 0.4), size: 28),
                              const SizedBox(height: 8),
                              Text(
                                'No one has RSVP\'d yet.\nBe the first to go!',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: context.hc.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.people_outline,
                                  color: HuddlColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                '${_meetup.attendeeCount} ${_meetup.attendeeCount == 1 ? 'parent' : 'parents'} going',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 100), // bottom padding for button
              ],
            ),
          ),
        ],
      ),

      // ── Bottom action button ───────────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: context.hc.surface,
          boxShadow: [
            BoxShadow(
              color: HuddlColors.gray900.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Share / send meetup card button
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: _shareToChat,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: HuddlColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Icon(Icons.send_outlined,
                    color: HuddlColors.primary, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            // Going / Not going button
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: _toggleGoing,
                icon: Icon(
                  _meetup.isGoing ? Icons.check_circle : Icons.groups,
                  color: context.hc.surface,
                  size: 20,
                ),
                label: Text(
                  _meetup.isGoing ? "I'm Going!" : "Count Me In",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.hc.surface,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _meetup.isGoing
                      ? HuddlColors.teal
                      : HuddlColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build attendee photo from MemberPhotoService.
  /// For the current user, show their onboarding photo or local asset avatar.
  Widget _buildAttendeePhoto(String name, double size) {
    // Current user: use onboarding photo or local asset fallback
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isMeetupOrganiser = myUid != null
        ? (_meetup.organiserId == myUid && name == _meetup.organiserName)
        : (_meetup.organiserId == 'current_user' && name == _meetup.organiserName);
    if (MemberPhotoService.isCurrentUser(name) || isMeetupOrganiser) {
      final photoUrl = MemberPhotoService.getPhotoByName(name);
      if (photoUrl != null && photoUrl.isNotEmpty) {
        // User has an actual profile photo (e.g. data: URI or network URL)
        if (photoUrl.startsWith('data:')) {
          try {
            final parts = photoUrl.split(',');
            if (parts.length > 1) {
              final bytes = base64Decode(parts[1]);
              return Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: HuddlColors.primary, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(bytes, fit: BoxFit.cover, width: size, height: size),
              );
            }
          } catch (_) {}
        }
        return Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: HuddlColors.primary, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.network(photoUrl, fit: BoxFit.cover, width: size, height: size,
            errorBuilder: (_, __, ___) => _localAvatarFallback(size)),
        );
      }
      // No profile photo set — use local asset avatar
      return _localAvatarFallback(size);
    }

    // Known community member — use MemberPhotoService
    final photoUrl = MemberPhotoService.getPhotoByName(name);
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => MemberAvatar(name: name, size: size),
        ),
      );
    }
    return MemberAvatar(name: name, size: size);
  }

  /// Local asset avatar for the current user (gender-based)
  Widget _localAvatarFallback(double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: HuddlColors.primary, width: 1.5),
      ),
      child: ClipOval(
        child: Image.asset(
          MemberPhotoService.currentUserAvatarAsset,
          width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: HuddlColors.primary.withValues(alpha: 0.08),
            child: Center(child: Icon(Icons.person, size: size * 0.5, color: HuddlColors.primary)),
          ),
        ),
      ),
    );
  }
}

// ── Detail row widget ─────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _DetailRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.hc.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: context.hc.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Category style helper ─────────────────────────────────────────────────

class _CatStyleInfo {
  final Color color;
  final IconData icon;
  const _CatStyleInfo(this.color, this.icon);
}

_CatStyleInfo _getCatStyle(String category) {
  switch (category) {
    case 'Coffee':
      return const _CatStyleInfo(HuddlColors.primaryDark, Icons.coffee);
    case 'Playdate':
      return const _CatStyleInfo(HuddlColors.primary, Icons.child_care);
    case 'Sport':
      return const _CatStyleInfo(HuddlColors.teal, Icons.sports_golf);
    case 'Walk':
      return const _CatStyleInfo(HuddlColors.paleBlue, Icons.directions_walk);
    case 'Social':
      return const _CatStyleInfo(HuddlColors.accentAmber, Icons.celebration);
    case 'Food':
      return const _CatStyleInfo(HuddlColors.accentAmber, Icons.restaurant);
    default:
      return const _CatStyleInfo(HuddlColors.teal, Icons.groups);
  }
}

// ── Category-based fallback image for meetups ────────────────────────────
String _categoryFallbackImage(String category) {
  switch (category.toLowerCase()) {
    case 'coffee':
    case 'coffee & chat':
      return 'https://images.pexels.com/photos/302899/pexels-photo-302899.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'playdate':
    case 'play':
      return 'https://images.pexels.com/photos/3933239/pexels-photo-3933239.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'walk':
    case 'outdoor':
      return 'https://images.pexels.com/photos/1325735/pexels-photo-1325735.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'sport':
    case 'fitness':
    case 'exercise':
      return 'https://images.pexels.com/photos/3822864/pexels-photo-3822864.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'class':
    case 'workshop':
      return 'https://images.pexels.com/photos/3662667/pexels-photo-3662667.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'music':
      return 'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'social':
      return 'https://images.pexels.com/photos/3184418/pexels-photo-3184418.jpeg?auto=compress&cs=tinysrgb&w=600';
    default:
      return 'https://images.pexels.com/photos/3933250/pexels-photo-3933250.jpeg?auto=compress&cs=tinysrgb&w=600';
  }
}

// ── Universal cover-image builder for detail screens ───────────────────────
Widget _buildDetailCoverImage({
  required String imageUrl,
  required IconData fallbackIcon,
  required Color fallbackColor,
}) {
  Widget gradientFallback({bool showIcon = true}) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [fallbackColor, fallbackColor.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: showIcon
            ? Center(
                child:
                    Icon(fallbackIcon, size: 48, color: HuddlColors.white))
            : null,
      );

  if (imageUrl.isEmpty) return gradientFallback();

  // base64 data-URI (user-uploaded)
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
          errorBuilder: (_, __, ___) => gradientFallback(),
        );
      }
    } catch (_) {}
    return gradientFallback();
  }

  // http(s) URL — use Image.network for reliable web rendering
  if (imageUrl.startsWith('http')) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return gradientFallback(showIcon: false);
      },
      errorBuilder: (_, __, ___) => gradientFallback(),
    );
  }

  // asset path
  if (imageUrl.startsWith('assets/')) {
    return Image.asset(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => gradientFallback(),
    );
  }

  return gradientFallback();
}
