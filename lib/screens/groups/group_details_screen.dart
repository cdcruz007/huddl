import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/group.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/invitation_service.dart';
import '../../services/default_group_service.dart';
import '../../services/browser_storage.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/saved_message_service.dart';
import '../../services/dm_service.dart';
import '../../services/firestore_service.dart';
import 'group_polls_screen.dart';
import 'edit_group_screen.dart';
import 'manage_admins_screen.dart';

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
  // Borough of the group creator — required so the borough guard in
  // joinPublicGroup() doesn't silently block the join when creatorBorough is null.
  final String? creatorBorough;

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
    this.creatorBorough,
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
  // ── Section 6A: true admin detection from Firestore admins[] array ──────
  bool _isAdminFromFirestore = false;
  int? _firestoreMemberCount; // live count from Firestore
  int? _firestoreMembersListCount; // count from members[] array

  /// Public groups are immutable -- details cannot be changed by anyone.
  bool get _isPublicGroup => !widget.isPrivate;

  /// Section 6A: Admin = present in admins[] array OR is creator (backward compat)
  bool get _isAdmin => _isAdminFromFirestore || _isCreator;
  bool get _canEdit => _isAdmin;

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
    _isCreator = widget.creatorId != null &&
        widget.creatorId == FirebaseAuth.instance.currentUser?.uid;
    _editableName = widget.groupName;
    _editableDescription = widget.groupDescription ??
        'Connect with parents in your community. Share experiences, advice, and build lasting friendships with people who understand your journey.';
    _nameEditController.text = _editableName;
    _descEditController.text = _editableDescription;
    _checkJoinStatus();
    _loadMemberCount();
    _loadAdminStatus(); // Section 6A: load admin status from Firestore
  }

  Future<void> _loadMemberCount() async {
    try {
      final group = await FirestoreService().getGroup(widget.groupId);
      if (group != null && mounted) {
        setState(() => _firestoreMemberCount = group.memberCount);
      }
    } catch (_) {}
  }

  /// Section 6A: Load admin status from Firestore admins[] array.
  /// Falls back to creator check if Firestore is unavailable.
  Future<void> _loadAdminStatus() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();
      if (!mounted) return;
      final data = doc.data() ?? {};
      final admins = List<String>.from(data['admins'] ?? []);
      final members = List<String>.from(data['members'] ?? []);
      setState(() {
        _isAdminFromFirestore = admins.contains(uid);
        _firestoreMembersListCount = members.length;
      });
    } catch (_) {
      // Admin status defaults to creator check if Firestore unavailable
    }
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
      memberCount: (_firestoreMemberCount ?? widget.memberCount ?? 0) + 1,
      category: '',
      isJoined: true,
      privacy: widget.isPrivate ? GroupPrivacy.private_ : GroupPrivacy.public,
      // Pass creatorBorough so the borough guard in joinPublicGroup() doesn't
      // silently block the join when targetBorough is null/empty.
      creatorBorough: widget.creatorBorough,
      creatorId: widget.creatorId,
    );
    await _invitationService.joinPublicGroup(group, userName);

    if (mounted) {
      setState(() {
        _isJoined = true;
        _isJoining = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Joined ${widget.groupName}! Go to Messages tab to start chatting.',
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: HuddlColors.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _shareGroup() {
    final shareText =
        '$_editableName\n👥 ${widget.memberCount ?? 0} members'
        '${widget.isPrivate ? ' · Private group' : ''}'
        '\n\nJoin us on Huddl!';
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
                            icon: const Icon(Icons.link, size: 18, color: HuddlColors.textDark),
                            label: Text(
                              'Share link',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.textTertiary,
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
                                      color: HuddlColors.divider),
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
                                    color: HuddlColors.textSecondary,
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
                          color: context.hc.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        // Remove from Firestore members/admins arrays
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid != null) {
                          try {
                            await FirebaseFirestore.instance
                                .collection('groups')
                                .doc(widget.groupId)
                                .update({
                              'memberIds': FieldValue.arrayRemove([uid]),
                              'members':   FieldValue.arrayRemove([uid]),
                              'admins':    FieldValue.arrayRemove([uid]),
                            });
                          } catch (_) {}
                        }
                        await _executeLocalLeave();
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Left ${widget.groupName}'),
                              backgroundColor: HuddlColors.primary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
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
    final memberCount = _firestoreMemberCount ?? widget.memberCount ?? 0;
    final savedCount = _savedMessageService.getSavedForGroup(widget.groupId).length;

    return Scaffold(
      backgroundColor: context.hc.scaffold,

      // ── Bottom CTA: locked Join/Chat button (matches Events detail pattern) ──
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Primary action: Open Chat (joined) or Join (not joined)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isJoining
                    ? null
                    : _isJoined
                        ? () => Navigator.pushNamed(context, '/group_chat', arguments: {
                              'groupId': widget.groupId,
                              'groupName': _editableName,
                              'groupImageUrl': widget.groupImageUrl,
                            })
                        : _joinGroup,
                icon: _isJoining
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(
                        _isJoined ? Icons.chat_bubble_outline : Icons.group_add_outlined,
                        color: context.hc.surface,
                        size: 20,
                      ),
                label: Text(
                  _isJoining ? 'Joining…' : _isJoined ? 'Open Chat' : 'Join',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.hc.surface,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isJoined ? HuddlColors.teal : HuddlColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 0,
                ),
              ),
            ),
            // Invite row — only for private-group admins/creators when already joined
            if (_isJoined && widget.isPrivate && _isAdmin) ...
              [
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showInviteMembersSheet,
                    icon: const Icon(Icons.person_add_outlined,
                        color: HuddlColors.textDark, size: 18),
                    label: Text(
                      'Invite Members',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textDark,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: HuddlColors.divider),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            // Helper text when not yet joined
            if (!_isJoined) ...
              [
                const SizedBox(height: 6),
                Text(
                  'Join to start chatting with this group',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.hc.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ],
          ],
        ),
      ),

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
                        color: HuddlColors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 14, color: HuddlColors.teal),
                          const SizedBox(width: 4),
                          Text(
                            'You created this group',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.teal,
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
                      color: HuddlColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _extractCategory(_editableName),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textTertiary,
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
                                  color: HuddlColors.divider),
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
                          textInputAction: TextInputAction.done,
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
                                  color: HuddlColors.divider),
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
                                'groupId': widget.groupId,
                                'groupName': widget.groupName,
                                'memberCount': memberCount,
                                'creatorId': widget.creatorId,
                              });
                        },
                        child: Text(
                          'See all',
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: HuddlColors.textTertiary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Member avatar preview — shows only the current user plus
                  // a "+N members" pill. Dummy names removed so no fake users
                  // appear. Full list is loaded from Firestore in GroupMembersScreen.
                  SizedBox(
                    height: 72,
                    child: Row(
                      children: [
                        // Current user placeholder
                        if (_isJoined)
                          Column(
                            children: [
                              MemberAvatar(
                                name: 'You',
                                size: 48,
                                accentColor: HuddlColors.primary,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'You',
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: context.hc.textSecondary),
                              ),
                            ],
                          ),
                        const SizedBox(width: 12),
                        // Member count pill
                        Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: HuddlColors.background,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$memberCount member${memberCount != 1 ? 's' : ''}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.textTertiary,
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
                      color: HuddlColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bookmark_outline,
                        color: HuddlColors.textDark, size: 22),
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

          // ── Polls section — only visible to members ──────────────
          if (_isJoined)
            SliverToBoxAdapter(
              child: Container(
                color: context.hc.surface,
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: HuddlColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.poll_outlined,
                        color: HuddlColors.textDark, size: 22),
                  ),
                  title: Text(
                    'Polls',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w500, color: context.hc.textPrimary),
                  ),
                  subtitle: Text(
                    'View group polls',
                    style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
                  ),
                  trailing: Icon(Icons.chevron_right, color: context.hc.textTertiary),
                  onTap: () {
                    // Navigate to dedicated polls screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupPollsScreen(
                          groupId: widget.groupId,
                          groupName: _editableName,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          if (_isJoined)
            const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Bottom spacer so content clears the fixed bottom bar
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
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
      color: HuddlColors.background,
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

  // ─── Section 3D: Role-aware three-dot menu ────────────────────────────────
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
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: context.hc.divider, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),

            // ── NON-MEMBER: only show Share + Join ───────────────────────
            if (!_isJoined) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: HuddlColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: HuddlColors.textDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Join this group to access member features.',
                        style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: Icon(Icons.share_outlined, color: context.hc.textPrimary),
                title: Text('Share group', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () { Navigator.pop(c); _shareGroup(); },
              ),
              ListTile(
                leading: Icon(Icons.group_add_outlined, color: HuddlColors.textDark),
                title: Text('Join group', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                onTap: () { Navigator.pop(c); _joinGroup(); },
              ),
            ],

            // ── MEMBER (admin or regular) ─────────────────────────────────
            if (_isJoined) ...[

              // ── ADMIN banner (replaces the lock notice) ──────────────
              if (_isAdmin)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: HuddlColors.teal.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: HuddlColors.teal),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You\'re an admin of this group',
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.teal, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── PUBLIC group notice (member, non-admin only) ──────────
              if (_isPublicGroup && !_isAdmin)
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
                          style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textSecondary, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── PRIVATE non-admin notice ──────────────────────────────
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
                          'Only admins can edit group details.',
                          style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textSecondary, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── ADMIN-ONLY options ────────────────────────────────────
              if (_isAdmin) ...[
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: context.hc.textPrimary),
                  title: Text('Edit group', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(c);
                    Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => EditGroupScreen(
                          groupId: widget.groupId,
                          groupName: _editableName,
                          groupDescription: _editableDescription,
                          groupImageUrl: widget.groupImageUrl,
                          isPrivate: widget.isPrivate,
                          onGroupUpdated: (newName, newDesc, {String? newImageUrl}) {
                            if (mounted) {
                              setState(() {
                                _editableName = newName;
                                _editableDescription = newDesc;
                              });
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.manage_accounts_outlined, color: context.hc.textPrimary),
                  title: Text('Manage admins', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(c);
                    Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => ManageAdminsScreen(
                          groupId: widget.groupId,
                          groupName: _editableName,
                        ),
                      ),
                    );
                  },
                ),
              ],

              // ── ALL MEMBERS options ───────────────────────────────────
              ListTile(
                leading: Icon(Icons.notifications_outlined, color: context.hc.textPrimary),
                title: Text('Mute notifications', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(c);
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Notifications muted')));
                },
              ),
              ListTile(
                leading: Icon(Icons.bookmark_outline, color: context.hc.textPrimary),
                title: Text('Saved messages', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(c);
                  Navigator.pushNamed(ctx, '/saved_messages_for_group', arguments: {
                    'groupId': widget.groupId,
                    'groupName': _editableName,
                  });
                },
              ),
              ListTile(
                leading: Icon(Icons.share_outlined, color: context.hc.textPrimary),
                title: Text('Share group', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () { Navigator.pop(c); _shareGroup(); },
              ),

              // ── ADMIN: Delete group ───────────────────────────────────
              if (_isAdmin)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: HuddlColors.error),
                  title: Text('Delete group', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: HuddlColors.error)),
                  onTap: () { Navigator.pop(c); _confirmDeleteGroup(ctx); },
                ),

              // ── Leave group (admin → admin leave flow, member → standard) ─
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: HuddlColors.error),
                title: Text('Leave group', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: HuddlColors.error)),
                onTap: () {
                  Navigator.pop(c);
                  if (_isAdmin) {
                    _handleAdminLeave(ctx);
                  } else {
                    _showLeaveGroupDialog();
                  }
                },
              ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Section 6D: Admin leave flow ─────────────────────────────────────────

  /// Entry point — determine which Case applies and route accordingly.
  Future<void> _handleAdminLeave(BuildContext ctx) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) { _showLeaveGroupDialog(); return; }

      final doc = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get();
      final data = doc.data() ?? {};
      final admins  = List<String>.from(data['admins']  ?? []);
      final members = List<String>.from(data['members'] ?? []);

      final otherMembers = members.where((id) => id != uid).toList();
      final otherAdmins  = admins.where((id)  => id != uid).toList();

      if (!context.mounted) return;

      if (otherAdmins.isNotEmpty) {
        // Case 1: other admins exist
        _showLeaveGroupDialog();
      } else if (otherMembers.isEmpty) {
        // Case 3: sole member — offer delete
        _showSoleMemberDeleteModal(ctx);
      } else {
        // Case 2: sole admin, other members exist — show successor picker
        _showSuccessorPickerSheet(ctx, otherMembers);
      }
    } catch (_) {
      _showLeaveGroupDialog(); // fallback to standard flow
    }
  }

  /// Case 3: Sole member — leave deletes the group.
  void _showSoleMemberDeleteModal(BuildContext ctx) {
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
                width: 56, height: 56,
                decoration: BoxDecoration(color: HuddlColors.error.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline, size: 32, color: HuddlColors.error),
              ),
              const SizedBox(height: 18),
              Text('Leave and delete this group?',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: context.hc.textPrimary),
                textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'You\'re the only member. Leaving will permanently delete this group and all its content. This cannot be undone.',
                style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textSecondary, height: 1.5),
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text('Cancel', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: context.hc.textSecondary)),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        await _executeGroupDelete(ctx);
                      },
                      child: Text('Delete group', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.error)),
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

  /// Case 2: Sole admin — show successor picker bottom sheet.
  void _showSuccessorPickerSheet(BuildContext ctx, List<String> otherMemberIds) {
    String? selectedSuccessorId;
    String? selectedSuccessorName;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          return DraggableScrollableSheet(
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            expand: false,
            builder: (_, scroll) => Column(
              children: [
                const SizedBox(height: 8),
                Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: context.hc.divider, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Who should take over as admin?',
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: context.hc.textPrimary),
                    textAlign: TextAlign.center),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Pick a member to become the new admin, or we\'ll automatically assign the most active member.',
                    style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textSecondary, height: 1.5),
                    textAlign: TextAlign.center),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchMembersWithActivity(otherMemberIds),
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: HuddlColors.textTertiary));
                      }
                      final memberList = snap.data ?? [];
                      return ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: memberList.length,
                        itemBuilder: (_, i) {
                          final m = memberList[i];
                          final mid = m['uid'] as String;
                          final mname = m['name'] as String;
                          final msgCount = m['messageCount'] as int;
                          final isSelected = selectedSuccessorId == mid;
                          return GestureDetector(
                            onTap: () => setSheet(() {
                              selectedSuccessorId = mid;
                              selectedSuccessorName = mname;
                            }),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? HuddlColors.primary.withValues(alpha: 0.07) : context.hc.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSelected ? HuddlColors.primary : context.hc.divider),
                              ),
                              child: Row(
                                children: [
                                  MemberAvatar(name: mname, size: 40, accentColor: HuddlColors.primary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(mname, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: context.hc.textPrimary)),
                                        Text('$msgCount messages', style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary)),
                                      ],
                                    ),
                                  ),
                                  if (isSelected) const Icon(Icons.check_circle, color: HuddlColors.primary, size: 22),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(c).padding.bottom + 16),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity, height: 52,
                        child: ElevatedButton(
                          onPressed: selectedSuccessorId == null ? null : () async {
                            Navigator.pop(c);
                            await _executeAdminHandoff(ctx, selectedSuccessorId!, selectedSuccessorName!);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HuddlColors.primary,
                            disabledBackgroundColor: HuddlColors.primary.withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                            elevation: 0,
                          ),
                          child: Text(
                            selectedSuccessorName != null ? 'Leave and assign ${selectedSuccessorName!}' : 'Leave and assign',
                            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          Navigator.pop(c);
                          await _executeAutoPromotion(ctx);
                        },
                        child: Text('Skip — assign automatically',
                          style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textSecondary,
                            decoration: TextDecoration.underline)),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: Text('Cancel', style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textTertiary)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Fetch member display names + activity counts for the successor picker.
  Future<List<Map<String, dynamic>>> _fetchMembersWithActivity(List<String> uids) async {
    final db = FirebaseFirestore.instance;
    final List<Map<String, dynamic>> result = [];
    // Fetch activity counts
    final Map<String, int> counts = {};
    try {
      for (final uid in uids) {
        final actDoc = await db.collection('groups').doc(widget.groupId)
            .collection('memberActivity').doc(uid).get();
        counts[uid] = (actDoc.data()?['messageCount'] as int?) ?? 0;
      }
    } catch (_) {}
    // Fetch user names in batches of 10
    for (int i = 0; i < uids.length; i += 10) {
      final batch = uids.sublist(i, (i + 10).clamp(0, uids.length));
      try {
        final snap = await db.collection('users').where(FieldPath.documentId, whereIn: batch).get();
        for (final doc in snap.docs) {
          final name = (doc.data()['name'] as String?)?.trim() ?? 'Member';
          result.add({'uid': doc.id, 'name': name, 'messageCount': counts[doc.id] ?? 0});
        }
      } catch (_) {}
    }
    result.sort((a, b) => (b['messageCount'] as int).compareTo(a['messageCount'] as int));
    return result;
  }

  /// Execute admin handoff — assign chosen successor, then leave.
  Future<void> _executeAdminHandoff(BuildContext ctx, String successorId, String successorName) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final ref = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
      await ref.update({
        'admins': FieldValue.arrayUnion([successorId]),
      });
      await ref.update({
        'admins':    FieldValue.arrayRemove([uid]),
        'members':   FieldValue.arrayRemove([uid]),
        'memberIds': FieldValue.arrayRemove([uid]),
      });
      await _executeLocalLeave();
      if (ctx.mounted) {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Left ${widget.groupName}. $successorName is the new admin.'),
          backgroundColor: HuddlColors.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: HuddlColors.error,
        ));
      }
    }
  }

  /// Execute auto-promotion — pick most active member, then leave.
  Future<void> _executeAutoPromotion(BuildContext ctx) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final db = FirebaseFirestore.instance;
      // Query memberActivity to find most active member (excluding self)
      final actSnap = await db.collection('groups').doc(widget.groupId)
          .collection('memberActivity')
          .orderBy('messageCount', descending: true)
          .orderBy('joinedAt', descending: false)
          .limit(10)
          .get();
      String? promoteeId;
      for (final doc in actSnap.docs) {
        final id = doc.data()['userId'] as String? ?? doc.id;
        if (id != uid) { promoteeId = id; break; }
      }
      if (promoteeId == null) {
        // Fallback: pick any other member
        final groupDoc = await db.collection('groups').doc(widget.groupId).get();
        final members = List<String>.from(groupDoc.data()?['members'] ?? []);
        promoteeId = members.firstWhere((id) => id != uid, orElse: () => '');
      }
      if (promoteeId.isNotEmpty) {
        await db.collection('groups').doc(widget.groupId).update({
          'admins': FieldValue.arrayUnion([promoteeId]),
        });
      }
      await db.collection('groups').doc(widget.groupId).update({
        'admins':    FieldValue.arrayRemove([uid]),
        'members':   FieldValue.arrayRemove([uid]),
        'memberIds': FieldValue.arrayRemove([uid]),
      });
      await _executeLocalLeave();
      if (ctx.mounted) {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Left ${widget.groupName}'),
          backgroundColor: HuddlColors.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: HuddlColors.error,
        ));
      }
    }
  }

  /// Helper: removes user from local storage and invitation service.
  Future<void> _executeLocalLeave() async {
    final onboarding = OnboardingDataService();
    await onboarding.initialize();
    final userName = onboarding.name ?? 'You';
    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    final userId = firebaseUid ?? 'user_${onboarding.name?.hashCode ?? 0}';

    await _invitationService.leaveGroup(widget.groupId, userName);
    await DefaultGroupService().leaveGroup(userId, widget.groupId);

    try {
      final raw = await BrowserStorage.getString('user_created_groups_v1');
      if (raw != null) {
        final List<dynamic> groups = json.decode(raw);
        groups.removeWhere((j) => (j as Map<String, dynamic>)['id'] == widget.groupId);
        await BrowserStorage.setString('user_created_groups_v1', json.encode(groups));
      }
    } catch (_) {}

    try {
      final leftRaw = await BrowserStorage.getString('left_groups_v1');
      final List<String> leftIds = leftRaw != null ? List<String>.from(json.decode(leftRaw) as List) : [];
      if (!leftIds.contains(widget.groupId)) {
        leftIds.add(widget.groupId);
        await BrowserStorage.setString('left_groups_v1', json.encode(leftIds));
      }
    } catch (_) {}
  }

  /// Execute full group deletion (Cases 3 & 4).
  Future<void> _executeGroupDelete(BuildContext ctx) async {
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('groups').doc(widget.groupId).delete();
      await _executeLocalLeave();
      if (ctx.mounted) {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('${widget.groupName} has been deleted'),
          backgroundColor: HuddlColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: HuddlColors.error,
        ));
      }
    }
  }

  // ─── Case 4: Explicit delete (from three-dot menu) ────────────────────────
  void _confirmDeleteGroup(BuildContext ctx) {
    final memberCount = _firestoreMembersListCount ?? _firestoreMemberCount ?? widget.memberCount ?? 0;
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
                width: 56, height: 56,
                decoration: BoxDecoration(color: HuddlColors.error.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline, size: 32, color: HuddlColors.error),
              ),
              const SizedBox(height: 18),
              Text('Delete this group?',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: context.hc.textPrimary),
                textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'This will permanently delete the group, all messages, and remove all $memberCount member${memberCount == 1 ? '' : 's'}. This cannot be undone.',
                style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textSecondary, height: 1.5),
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text('Cancel', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: context.hc.textSecondary)),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        await _executeGroupDelete(ctx);
                      },
                      child: Text('Delete group', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.error)),
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
    final paintPrimary = Paint()..color = HuddlColors.textDark;
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
