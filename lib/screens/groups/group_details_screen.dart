import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/group.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/invitation_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/saved_message_service.dart';
import '../../services/dm_service.dart';

// ── Design tokens — use HuddlColors as single source of truth ────────

class GroupDetailsScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String groupImageUrl;
  final String? groupDescription;
  final int? memberCount;
  final bool isPrivate;
  final String? creatorId;
  final bool isJoined;

  const GroupDetailsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupImageUrl,
    this.groupDescription,
    this.memberCount,
    this.isPrivate = false,
    this.creatorId,
    this.isJoined = true,
  });

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  bool _aboutExpanded = false;
  bool _isJoined = true;
  bool _isJoining = false;
  final InvitationService _invitationService = InvitationService();
  final SavedMessageService _savedMessageService = SavedMessageService();
  bool _isCreator = false;

  /// Public groups are immutable -- details cannot be changed by anyone.
  bool get _isPublicGroup => !widget.isPrivate;

  /// Editing is only allowed for private group creator or admins.
  bool get _isAdmin => _isCreator; // In a real app, check admin list from backend
  bool get _canEdit => _isAdmin && !_isPublicGroup;

  // Editable fields for creators
  late String _editableName;
  late String _editableDescription;
  bool _isEditing = false;
  final TextEditingController _nameEditController = TextEditingController();
  final TextEditingController _descEditController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isJoined = widget.isJoined;
    _isCreator = widget.creatorId == 'current_user';
    _editableName = widget.groupName;
    _editableDescription = widget.groupDescription ??
        'Connect with parents in your community. Share experiences, advice, and build lasting friendships with people who understand your journey.';
    _nameEditController.text = _editableName;
    _descEditController.text = _editableDescription;
    _checkJoinStatus();
  }

  @override
  void dispose() {
    _nameEditController.dispose();
    _descEditController.dispose();
    super.dispose();
  }

  Future<void> _checkJoinStatus() async {
    await _invitationService.initialize();
    await _savedMessageService.initialize();
    if (mounted) {
      setState(() {
        _isJoined = widget.isJoined || _invitationService.isGroupJoined(widget.groupId);
      });
    }
  }

  Future<void> _joinGroup() async {
    setState(() => _isJoining = true);

    final onboarding = OnboardingDataService();
    await onboarding.initialize();
    final userName = onboarding.name ?? 'You';

    final group = Group(
      id: widget.groupId,
      name: widget.groupName,
      description: widget.groupDescription ?? '',
      imageUrl: widget.groupImageUrl,
      memberCount: (widget.memberCount ?? 42) + 1,
      category: '',
      isJoined: true,
      privacy: widget.isPrivate ? GroupPrivacy.private_ : GroupPrivacy.public,
    );
    await _invitationService.joinPublicGroup(group, userName);

    if (mounted) {
      setState(() {
        _isJoined = true;
        _isJoining = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined ${widget.groupName}! Check your Messages tab.'),
          backgroundColor: HuddlColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _shareGroup() {
    final shareText =
        '$_editableName\n👥 ${widget.memberCount ?? 0} members'
        '${widget.isPrivate ? ' · Private group' : ''}'
        '\n\nJoin us on Huddl Connect!';
    Clipboard.setData(ClipboardData(text: shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Group link copied to clipboard'),
          ],
        ),
        backgroundColor: HuddlColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showInviteMembersSheet() {
    final dmService = DMService();
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
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return FutureBuilder(
              future: dmService.initialize().then((_) => dmService.conversations),
              builder: (context, snapshot) {
                final conversations = snapshot.data ?? [];
                // Build a list of potential members from DM contacts
                final contacts = conversations
                    .map((c) => {'id': c.recipientId, 'name': c.recipientName, 'color': c.recipientAvatarColor})
                    .toList();
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 36, height: 4,
                        decoration: BoxDecoration(
                          color: context.hc.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Text(
                            'Invite Members',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _shareGroup();
                            },
                            icon: const Icon(Icons.link, size: 18, color: HuddlColors.primary),
                            label: Text(
                              'Share link',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (contacts.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline,
                                  size: 48,
                                  color: context.hc.textTertiary.withValues(alpha: 0.5)),
                              const SizedBox(height: 12),
                              Text(
                                'No contacts yet',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: context.hc.textTertiary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Share the group link to invite members',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: context.hc.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: contacts.length,
                          itemBuilder: (_, i) {
                            final contact = contacts[i];
                            return ListTile(
                              leading: MemberAvatar(
                                  name: contact['name'] as String, size: 40),
                              title: Text(
                                contact['name'] as String,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              trailing: OutlinedButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Invitation sent to ${contact['name']}'),
                                      backgroundColor: HuddlColors.teal,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10)),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: HuddlColors.primary),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 4),
                                ),
                                child: Text(
                                  'Invite',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: HuddlColors.primary,
                                  ),
                                ),
                              ),
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
      },
    );
  }

  void _toggleEditing() {
    // Public groups cannot be edited
    if (_isPublicGroup) return;

    if (_isEditing) {
      // Save changes
      setState(() {
        _editableName = _nameEditController.text.trim().isNotEmpty
            ? _nameEditController.text.trim()
            : _editableName;
        _editableDescription = _descEditController.text.trim().isNotEmpty
            ? _descEditController.text.trim()
            : _editableDescription;
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Group details updated'),
          backgroundColor: HuddlColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      // Enter edit mode
      setState(() {
        _nameEditController.text = _editableName;
        _descEditController.text = _editableDescription;
        _isEditing = true;
        _aboutExpanded = true;
      });
    }
  }

  void _showLeaveGroupDialog() {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HuddlColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sentiment_dissatisfied_outlined,
                    size: 32, color: HuddlColors.error),
              ),
              const SizedBox(height: 18),
              Text(
                'Leave this group?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'We are sad to see you go, but you can always come back or find another group that interests you in the Discover tab.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        final onboarding = OnboardingDataService();
                        await onboarding.initialize();
                        final userName = onboarding.name ?? 'You';
                        await _invitationService.leaveGroup(widget.groupId, userName);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Left ${widget.groupName}')),
                          );
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Leave',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.error,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final description = _editableDescription;
    final memberCount = widget.memberCount ?? 42;
    final savedCount = _savedMessageService.getSavedForGroup(widget.groupId).length;

    return Scaffold(
      backgroundColor: context.hc.scaffold,
      body: CustomScrollView(
        slivers: [
          // ── Hero image area ─────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: context.hc.surface,
            leading: _CircleButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.pop(context),
            ),
            actions: [
              // Edit button for private-group creators only
              if (_canEdit && _isJoined)
                _CircleButton(
                  icon: _isEditing ? Icons.check : Icons.edit,
                  onTap: _toggleEditing,
                ),
              _CircleButton(
                icon: Icons.more_vert,
                onTap: () => _showMoreActions(context),
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeroImage(),
            ),
          ),

          // ── Group info ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: context.hc.surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Creator badge
                  if (_isCreator)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: HuddlColors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 14, color: HuddlColors.blue),
                          const SizedBox(width: 4),
                          Text(
                            'You created this group',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Category chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: HuddlColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _extractCategory(_editableName),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Name (editable for creator)
                  _isEditing
                      ? TextField(
                          controller: _nameEditController,
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: context.hc.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Group name',
                            hintStyle: GoogleFonts.poppins(
                                fontSize: 22, color: context.hc.textTertiary),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: HuddlColors.primary.withValues(alpha: 0.3)),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: HuddlColors.primary),
                            ),
                          ),
                        )
                      : Text(
                          _editableName,
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: context.hc.textPrimary,
                          ),
                        ),
                  const SizedBox(height: 8),

                  // Public/Private badge + member count
                  Row(
                    children: [
                      Icon(
                        widget.isPrivate ? Icons.lock_outline : Icons.public,
                        size: 16,
                        color: context.hc.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.isPrivate ? 'Private group' : 'Public group',
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: context.hc.textSecondary),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.people_outline,
                          size: 16, color: context.hc.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        '$memberCount member${memberCount != 1 ? 's' : ''}',
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: context.hc.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── About section ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: context.hc.surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'About',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _aboutExpanded = !_aboutExpanded),
                        child: Icon(
                          _aboutExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: context.hc.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _isEditing
                      ? TextField(
                          controller: _descEditController,
                          maxLines: null,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: context.hc.textSecondary,
                            height: 1.5,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Group description',
                            hintStyle: GoogleFonts.poppins(
                                fontSize: 14, color: context.hc.textTertiary),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: HuddlColors.primary.withValues(alpha: 0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: HuddlColors.primary),
                            ),
                          ),
                        )
                      : Text(
                          description,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: context.hc.textSecondary,
                            height: 1.5,
                          ),
                          maxLines: _aboutExpanded ? null : 3,
                          overflow:
                              _aboutExpanded ? null : TextOverflow.ellipsis,
                        ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Members section ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: context.hc.surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Members ($memberCount)',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/group_members',
                              arguments: {
                                'groupName': widget.groupName,
                                'memberCount': memberCount,
                              });
                        },
                        child: Text(
                          'See all',
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: HuddlColors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 8,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final names = [
                          'Emma', 'Sophie', 'Kate', 'Lucy',
                          'James', 'Anna', 'Mia', 'You'
                        ];
                        final colors = [
                          HuddlColors.primary,
                          HuddlColors.blue,
                          HuddlColors.accentAmber,
                          HuddlColors.paleBlue,
                          HuddlColors.lightBlue,
                          HuddlColors.accentCoral,
                          HuddlColors.primaryDark,
                          HuddlColors.blue,
                        ];
                        return Column(
                          children: [
                            MemberAvatar(
                              name: names[index],
                              size: 48,
                              accentColor: colors[index],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              names[index],
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: context.hc.textSecondary),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Saved messages section ─────────────────────────────────
          if (_isJoined && savedCount > 0)
            SliverToBoxAdapter(
              child: Container(
                color: context.hc.surface,
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: HuddlColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bookmark_outline,
                        color: HuddlColors.primary, size: 22),
                  ),
                  title: Text(
                    'Saved Messages',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w500, color: context.hc.textPrimary),
                  ),
                  subtitle: Text(
                    '$savedCount saved message${savedCount != 1 ? 's' : ''}',
                    style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
                  ),
                  trailing: Icon(Icons.chevron_right, color: context.hc.textTertiary),
                  onTap: () {
                    Navigator.pushNamed(context, '/saved_messages_for_group', arguments: {
                      'groupId': widget.groupId,
                      'groupName': _editableName,
                    });
                  },
                ),
              ),
            ),

          if (_isJoined && savedCount > 0)
            const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Polls section ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: context.hc.surface,
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.poll_outlined,
                      color: HuddlColors.primary, size: 22),
                ),
                title: Text(
                  'Polls',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w500, color: context.hc.textPrimary),
                ),
                subtitle: Text(
                  '2 active polls',
                  style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
                ),
                trailing: Icon(Icons.chevron_right, color: context.hc.textTertiary),
                onTap: () {
                  // Navigate to group chat which contains the polls
                  Navigator.pushNamed(context, '/group_chat', arguments: {
                    'groupId': widget.groupId,
                    'groupName': _editableName,
                    'groupImageUrl': widget.groupImageUrl,
                    'isPrivate': widget.isPrivate,
                    'creatorId': widget.creatorId,
                  });
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Action buttons ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: context.hc.surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (_isJoined) ...[
                    // Open chat (already joined)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/group_chat', arguments: {
                            'groupId': widget.groupId,
                            'groupName': _editableName,
                            'groupImageUrl': widget.groupImageUrl,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          elevation: 0,
                        ),
                        child: Text(
                          'Open Chat',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.hc.surface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Invite members (only for private group admins/creator)
                    if (widget.isPrivate && _isAdmin)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _showInviteMembersSheet,
                          icon: const Icon(Icons.person_add_outlined,
                              color: HuddlColors.primary),
                          label: Text(
                            'Invite Members',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: HuddlColors.primary),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                      ),
                  ] else ...[
                    // Join button (not yet joined)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isJoining ? null : _joinGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          elevation: 0,
                        ),
                        child: _isJoining
                            ? const SizedBox(
                                width: 24, height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: HuddlColors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.group_add, color: HuddlColors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Join Group',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: context.hc.surface,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Join to start chatting with this group',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: context.hc.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildHeroImage() {
    if (widget.groupImageUrl.startsWith('assets/')) {
      return Image.asset(
        widget.groupImageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _heroFallback(),
      );
    } else if (widget.groupImageUrl.startsWith('http')) {
      return Image.network(
        widget.groupImageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _heroFallback(),
      );
    } else if (widget.groupImageUrl.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(widget.groupImageUrl);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => _heroFallback(),
          );
        }
      } catch (_) {
        // fall through
      }
    }
    return _heroFallback();
  }

  Widget _heroFallback() {
    return Container(
      color: HuddlColors.peachLight,
      child: CustomPaint(
        painter: _TwoPeoplePainter(),
        child: const SizedBox.expand(),
      ),
    );
  }

  String _extractCategory(String groupName) {
    final n = groupName.toLowerCase();
    if (n.contains('expecting')) return 'Expecting Parents';
    if (n.contains('aspiring')) return 'Aspiring Parents';
    if (n.contains('parents')) return 'Parents';
    return 'Community';
  }

  void _showMoreActions(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: context.hc.divider, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            // Info notice for public groups or non-admin private group members
            if (_isPublicGroup)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: context.hc.textTertiary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: context.hc.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This is a public group. Group details cannot be changed by any member.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: context.hc.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_isPublicGroup && !_isAdmin)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: context.hc.textTertiary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: context.hc.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Only the group creator or admins can edit group details.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: context.hc.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Edit option -- private-group admin/creator only
            if (_canEdit && _isJoined)
              ListTile(
                leading: Icon(Icons.edit_outlined, color: context.hc.textPrimary),
                title: Text('Edit group details',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(c);
                  _toggleEditing();
                },
              ),
            ListTile(
              leading:
                  Icon(Icons.notifications_outlined, color: context.hc.textPrimary),
              title: Text('Mute notifications',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(c);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Notifications muted')),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.bookmark_outline, color: context.hc.textPrimary),
              title: Text('Saved messages',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(c);
                // Navigate to saved tab
              },
            ),
            ListTile(
              leading: Icon(Icons.share_outlined, color: context.hc.textPrimary),
              title: Text('Share group',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(c);
                _shareGroup();
              },
            ),
            if (_isJoined)
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: HuddlColors.error),
                title: Text('Leave group',
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.error)),
                onTap: () {
                  Navigator.pop(c);
                  _showLeaveGroupDialog();
                },
              ),
            // Delete group — only for private group admins/creator
            if (widget.isPrivate && _isAdmin)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: HuddlColors.error),
                title: Text('Delete group',
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.error)),
                onTap: () {
                  Navigator.pop(c);
                  _confirmDeleteGroup(ctx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteGroup(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HuddlColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline, size: 32, color: HuddlColors.error),
              ),
              const SizedBox(height: 18),
              Text(
                'Delete this group?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'This will permanently delete the group and all messages. All members will be removed. This action cannot be undone.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text('Cancel',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(c);
                        // Pop back to messages list
                        Navigator.pop(ctx);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('${widget.groupName} has been deleted'),
                              backgroundColor: HuddlColors.primary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }
                      },
                      child: Text('Delete',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Circle button for app bar ──────────────────────────────────────────────
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: context.hc.surface, size: 20),
        ),
      ),
    );
  }
}

// ── Custom painter for fallback hero illustration ──────────────────────────
class _TwoPeoplePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintPrimary = Paint()..color = HuddlColors.primary;
    final paintSecondary = Paint()..color = HuddlColors.primaryLight;

    canvas.drawCircle(
        Offset(size.width * 0.35, size.height * 0.45), 30, paintPrimary);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * 0.35, size.height * 0.7),
          width: 45,
          height: 40,
        ),
        const Radius.circular(12),
      ),
      paintPrimary,
    );

    canvas.drawCircle(
        Offset(size.width * 0.65, size.height * 0.45), 30, paintSecondary);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * 0.65, size.height * 0.7),
          width: 45,
          height: 40,
        ),
        const Radius.circular(12),
      ),
      paintSecondary,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
