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
import '../groups/dm_chat_screen.dart';


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
      imageUrl: _meetup.imageUrl,
      memberCount: _meetup.attendeeCount + 1,
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
              const Icon(Icons.group, color: HuddlColors.white, size: 18),
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

  /// Open a DM with the organiser
  void _chatWithOrganiser() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DMChatScreen(
          recipientId: _meetup.organiserId,
          recipientName: _meetup.organiserName,
          recipientAvatarColor: '#FF975C',
        ),
      ),
    );
  }

  /// Share meetup via forward sheet
  void _shareMeetup() {
    showForwardSheet(
      context: context,
      messageText:
          'Check out this meetup: "${_meetup.title}" on ${_meetup.dateDisplay} ${_meetup.timeDisplay} at ${_meetup.location}',
    );
  }

  bool get _isOrganiser => _meetup.organiserId == 'current_user';

  /// Show the more options bottom sheet (organiser controls)
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: HuddlColors.white,
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
                    color: HuddlColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Meet-up Options',
                  style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: HuddlColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: HuddlColors.peachLight,
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
                    child: const Icon(Icons.copy_outlined, color: HuddlColors.blue, size: 20),
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
                        color: HuddlColors.peachLight,
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
      backgroundColor: HuddlColors.white,
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
                    color: HuddlColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Attendees (${_meetup.attendeeCount})',
                  style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: HuddlColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                if (_meetup.maxAttendees != null)
                  Text(
                    '${_meetup.maxAttendees! - _meetup.attendeeCount} spots remaining',
                    style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textTertiary),
                  ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _meetup.attendeeNames.length,
                    itemBuilder: (_, i) {
                      final name = _meetup.attendeeNames[i];
                      final isOrganiser = i == 0;
                      final photoUrl = MemberPhotoService.getPhotoByName(name);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        leading: photoUrl != null
                            ? Container(
                                width: 40, height: 40,
                                decoration: const BoxDecoration(shape: BoxShape.circle),
                                clipBehavior: Clip.antiAlias,
                                child: Image.network(photoUrl, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => MemberAvatar(name: name, size: 40)),
                              )
                            : MemberAvatar(name: name, size: 40),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(name, style: GoogleFonts.poppins(
                                fontSize: 15, fontWeight: FontWeight.w500,
                                color: HuddlColors.textDark)),
                            ),
                            if (isOrganiser) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: HuddlColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('Organiser', style: GoogleFonts.poppins(
                                  fontSize: 10, fontWeight: FontWeight.w600,
                                  color: HuddlColors.primary)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          isOrganiser ? 'Host' : 'Going',
                          style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textTertiary),
                        ),
                        trailing: !isOrganiser
                            ? IconButton(
                                icon: const Icon(Icons.chat_bubble_outline, size: 20, color: HuddlColors.primary),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => DMChatScreen(
                                      recipientId: 'mem_${name.toLowerCase().replaceAll(' ', '_')}',
                                      recipientName: name,
                                      recipientAvatarColor: '#FF975C',
                                    ),
                                  ));
                                },
                              )
                            : null,
                      );
                    },
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
        backgroundColor: HuddlColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Meet-up?', style: GoogleFonts.poppins(
          fontSize: 18, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
        content: Text(
          'This will permanently remove "${_meetup.title}" and notify all attendees. This action cannot be undone.',
          style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Keep', style: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textHint)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _meetupService.deleteMeetup(_meetup.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Meet-up cancelled'),
                  backgroundColor: HuddlColors.error,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
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
                icon: const Icon(Icons.arrow_back,
                    color: HuddlColors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: HuddlColors.gray900.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.share_outlined,
                      color: HuddlColors.white, size: 20),
                  onPressed: _shareMeetup,
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                decoration: BoxDecoration(
                  color: HuddlColors.gray900.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.more_vert,
                      color: HuddlColors.white, size: 20),
                  onPressed: _showMoreOptions,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _buildDetailCoverImage(
                    imageUrl: _meetup.imageUrl,
                    fallbackIcon: catStyle.icon,
                    fallbackColor: catStyle.color,
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
                                  color: HuddlColors.white,
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
                            color: _meetup.isFree ? HuddlColors.blue : HuddlColors.accentAmber,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _meetup.isFree
                                ? 'Free'
                                : '\u00A3${_meetup.price?.toStringAsFixed(0) ?? ''}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
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
                          color: HuddlColors.textDark,
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
                              color: HuddlColors.textTertiary,
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
                        iconColor: HuddlColors.blue,
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
                                      fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                                    Text(_meetup.repeatDisplay ?? 'Recurring', style: GoogleFonts.poppins(
                                      fontSize: 12, color: HuddlColors.textTertiary)),
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
                                        fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark),
                                    ),
                                    Text(
                                      _meetup.groupName ?? 'Invite only',
                                      style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textTertiary),
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
                          color: HuddlColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _meetup.description,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: HuddlColors.textSecondary,
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
                              fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                            Text('${_meetup.invitees.length} people', style: GoogleFonts.poppins(
                              fontSize: 13, color: HuddlColors.textTertiary)),
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
                                fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.textDark))),
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
                              color: HuddlColors.textDark,
                            ),
                          ),
                          Text(
                            '${_meetup.attendeeCount} people',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: HuddlColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _meetup.attendeeNames
                            .take(8)
                            .map((name) =>
                                _AttendeeChipWithPhoto(name: name))
                            .toList(),
                      ),
                      if (_meetup.attendeeCount > 8)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '+${_meetup.attendeeCount - 8} more',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: HuddlColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
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
            // Message organiser button — opens DM
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: _chatWithOrganiser,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: HuddlColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Icon(Icons.chat_bubble_outline,
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
                  color: HuddlColors.white,
                  size: 20,
                ),
                label: Text(
                  _meetup.isGoing ? "I'm Going!" : "Count Me In",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.white,
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

  /// Build attendee photo from MemberPhotoService
  Widget _buildAttendeePhoto(String name, double size) {
    final photoUrl = MemberPhotoService.getPhotoByName(name);
    if (photoUrl != null) {
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
                  color: HuddlColors.textDark,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: HuddlColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Attendee chip with profile photo ──────────────────────────────────────

class _AttendeeChipWithPhoto extends StatelessWidget {
  final String name;

  const _AttendeeChipWithPhoto({required this.name});

  @override
  Widget build(BuildContext context) {
    final photoUrl = MemberPhotoService.getPhotoByName(name);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: HuddlColors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (photoUrl != null)
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                photoUrl,
                fit: BoxFit.cover,
                width: 24,
                height: 24,
                errorBuilder: (_, __, ___) =>
                    MemberAvatar(name: name, size: 24),
              ),
            )
          else
            MemberAvatar(name: name, size: 24),
          const SizedBox(width: 6),
          Text(
            name,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: HuddlColors.textDark,
            ),
          ),
        ],
      ),
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
      return const _CatStyleInfo(HuddlColors.blue, Icons.sports_golf);
    case 'Walk':
      return const _CatStyleInfo(HuddlColors.paleBlue, Icons.directions_walk);
    case 'Social':
      return const _CatStyleInfo(HuddlColors.accentAmber, Icons.celebration);
    case 'Food':
      return const _CatStyleInfo(HuddlColors.accentAmber, Icons.restaurant);
    default:
      return const _CatStyleInfo(HuddlColors.blue, Icons.groups);
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
