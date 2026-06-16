import 'package:flutter/foundation.dart';
import '../../theme/huddl_icons.dart';
import 'package:flutter/material.dart';
import '../../widgets/animations/huddl_spring_animations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/user_privacy_prefs_service.dart';
import 'manage_admins_screen.dart';
import '../../constants/app_text_styles.dart';

// ── Design tokens ────────────────────────────────────────────────────────
const Color _kOnline = HuddlColors.success;

class GroupMembersScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final int memberCount;
  final String? creatorId;

  const GroupMembersScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.memberCount,
    this.creatorId,
  });

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Admins', 'Members'];

  List<_Member> _members = [];
  bool _isLoading = true;
  String? _error;
  // Section 6E: current user's admin status from Firestore admins[] array
  bool _currentUserIsAdmin = false;
  String? _currentUid;

  @override
  void initState() {
    super.initState();
    _currentUid = FirebaseAuth.instance.currentUser?.uid;
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      setState(() { _isLoading = true; _error = null; });

      final db = FirebaseFirestore.instance;
      final currentUid = FirebaseAuth.instance.currentUser?.uid;

      // 1. Fetch the group doc to get the memberIds array
      final groupDoc = await db.collection('groups').doc(widget.groupId).get();
      if (!groupDoc.exists) {
        setState(() { _isLoading = false; _error = 'Group not found.'; });
        return;
      }

      final data = groupDoc.data() ?? {};
      // Read from memberIds[] (canonical) then fall back to members[] (admin-role field)
      // so both legacy and new groups always show their member list.
      final rawMemberIds = List<String>.from(data['memberIds'] ?? []);
      final rawMembers   = List<String>.from(data['members']   ?? []);
      // Union both arrays so a member present in either field is included
      List<String> memberIds = {...rawMemberIds, ...rawMembers}.toList();
      final creatorId = widget.creatorId ?? data['creatorId'] as String?;
      // Section 6E: detect admin status from admins[] array
      final adminIds = List<String>.from(data['admins'] ?? []);
      final isAdminFromFirestore = _currentUid != null && adminIds.contains(_currentUid);
      final isCreatorCheck = _currentUid != null && _currentUid == (widget.creatorId ?? data['creatorId']);

      if (memberIds.isEmpty) {
        setState(() { _isLoading = false; _members = []; });
        return;
      }

      // 2. Fetch user documents in batches of 10 (Firestore whereIn limit)
      final List<_Member> loaded = [];
      for (int i = 0; i < memberIds.length; i += 10) {
        final batch = memberIds.sublist(i, i + 10 > memberIds.length ? memberIds.length : i + 10);
        final snap = await db.collection('users_public')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in snap.docs) {
          final ud = doc.data();
          final uid = doc.id;
          final name = (ud['name'] as String?)?.trim() ?? '';
          if (name.isEmpty) continue; // skip users with no name yet

          final isOnline = (ud['isOnline'] as bool?) ?? false;
          final isCreator = uid == creatorId;
          final isCurrentUser = uid == currentUid;

          // Bug 4 fix: read photoUrl from the user document
          final photoUrl = (ud['photoUrl'] as String?)?.trim();

          // Section 6E: use admins[] array for role detection; fall back to creatorId
          final isAdminMember = adminIds.contains(uid) || isCreator;
          loaded.add(_Member(
            uid: uid,
            name: isCurrentUser ? 'You' : name,
            role: isAdminMember ? 'admin' : 'member',
            accentColor: _colorForUid(uid),
            isOnline: isOnline,
            parentType: (ud['parentType'] as String?) ?? '',
            borough: (ud['borough'] as String?) ?? '',
            photoUrl: (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
          ));
        }
      }

      // Sort: admins first, then online, then alphabetical
      loaded.sort((a, b) {
        if (a.role == 'admin' && b.role != 'admin') return -1;
        if (a.role != 'admin' && b.role == 'admin') return 1;
        if (a.isOnline && !b.isOnline) return -1;
        if (!a.isOnline && b.isOnline) return 1;
        return a.name.compareTo(b.name);
      });

      setState(() {
        _members = loaded;
        _isLoading = false;
        _currentUserIsAdmin = isAdminFromFirestore || isCreatorCheck;
      });
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[GroupMembersScreen] Error loading members: $e');
      }
      setState(() { _isLoading = false; _error = 'Could not load members. Tap to retry.'; });
    }
  }

  Color _colorForUid(String uid) {
    const colors = [
      HuddlColors.primary,
      HuddlColors.nearBlack,
      HuddlColors.primaryDark,
      HuddlColors.primary,
      HuddlColors.yellow,
      HuddlColors.accentCoral,
    ];
    return colors[uid.hashCode.abs() % colors.length];
  }

  List<_Member> get _filteredMembers {
    var list = List<_Member>.from(_members);
    if (_selectedFilter == 'Admins') {
      list = list.where((m) => m.role == 'admin').toList();
    } else if (_selectedFilter == 'Members') {
      list = list.where((m) => m.role == 'member').toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((m) =>
          m.name.toLowerCase().contains(q) ||
          m.borough.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMembers;

    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        surfaceTintColor: HuddlColors.white,
        leading: IconButton(
          icon: Icon(HuddlIcons.arrowBack, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Members',
              style: HuddlText.heading(),
            ),
            Text(
              _isLoading ? 'Loading...' : '${_members.length} member${_members.length == 1 ? '' : 's'}',
              style: HuddlText.caption(color: context.hc.textTertiary),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.hc.divider),
        ),
      ),
      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────
          Container(
            color: context.hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: context.hc.scaffold,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(HuddlIcons.search, size: 20, color: context.hc.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      textAlignVertical: TextAlignVertical.center,
                      style: HuddlText.body(color: context.hc.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search members',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        isDense: true,
                        hintStyle: HuddlText.body(color: context.hc.textTertiary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Role filter chips ───────────────────────────────────────
          Container(
            color: context.hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: _filters.map((f) {
                final isSelected = _selectedFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFilter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? HuddlColors.primary : HuddlColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isSelected ? HuddlColors.primary : HuddlColors.divider),
                      ),
                      child: Text(
                        f,
                        style: HuddlText.body(),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Members list ────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: HuddlColors.textTertiary))
                : _error != null
                    ? GestureDetector(
                        onTap: _loadMembers,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(HuddlIcons.refresh, size: 40, color: context.hc.textTertiary),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  style: HuddlText.body(color: context.hc.textTertiary),
                                  textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isNotEmpty ? 'No members found' : 'No members yet',
                              style: HuddlText.body(color: context.hc.textTertiary),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, indent: 72, color: context.hc.divider),
                            itemBuilder: (context, index) {
                              final m = filtered[index];
                              return _MemberTile(
                                member: m,
                                currentUserIsAdmin: _currentUserIsAdmin,
                                currentUid: _currentUid,
                                groupId: widget.groupId,
                                groupName: widget.groupName,
                                onMemberRemoved: () {
                                  setState(() => _members.removeWhere((x) => x.uid == m.uid));
                                },
                                onAdminManage: () {
                                  Navigator.push(
                                    context,
                                    HuddlSpringPageRoute(page: ManageAdminsScreen(
                                      groupId: widget.groupId,
                                      groupName: widget.groupName,
                                    )),
                                  );
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Section 6E: Member tile with admin action controls ────────────────────
class _MemberTile extends StatelessWidget {
  final _Member member;
  final bool currentUserIsAdmin;
  final String? currentUid;
  final String groupId;
  final String groupName;
  final VoidCallback? onMemberRemoved;
  final VoidCallback? onAdminManage;

  const _MemberTile({
    required this.member,
    required this.currentUserIsAdmin,
    required this.currentUid,
    required this.groupId,
    required this.groupName,
    this.onMemberRemoved,
    this.onAdminManage,
  });

  // Returns true if the current user can act on this row
  bool get _canActOnMember =>
      currentUserIsAdmin && member.uid != currentUid;

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
            // Make admin
            ListTile(
              leading: Icon(HuddlIcons.shield, color: context.hc.textPrimary),
              title: Text('Make admin',
                style: HuddlText.body(color: context.hc.textPrimary)),
              onTap: () {
                Navigator.pop(c);
                onAdminManage?.call();
              },
            ),
            // Remove from group
            ListTile(
              leading: const Icon(HuddlIcons.personRemove, color: HuddlColors.error),
              title: Text('Remove from group',
                style: HuddlText.body(color: HuddlColors.error)),
              onTap: () {
                Navigator.pop(c);
                _confirmRemove(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Remove ${member.name}?',
                style: HuddlText.heading(color: context.hc.textPrimary),
                textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text('Remove ${member.name} from this group? They will need to rejoin if they want to participate.',
                style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.5),
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text('Cancel',
                        style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textSecondary)),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text('Remove',
                        style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('groups').doc(groupId).update({
          'memberIds': FieldValue.arrayRemove([member.uid]),
          'members':   FieldValue.arrayRemove([member.uid]),
          'admins':    FieldValue.arrayRemove([member.uid]),
          'memberCount': FieldValue.increment(-1),
        });
        onMemberRemoved?.call();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${member.name} has been removed from $groupName.'),
            backgroundColor: HuddlColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to remove member. Please try again.'),
            backgroundColor: HuddlColors.error,
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.hc.surface,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: MemberAvatar(
          name: member.name,
          size: 44,
          accentColor: member.accentColor,
          showOnlineDot: true,
          isOnline: (member.name == 'You')
              ? (member.isOnline && UserPrivacyPrefsService().showOnlineStatus)
              : member.isOnline,
          imageUrl: member.photoUrl,
          parentType: member.parentType,
        ),
        title: Row(
          children: [
            Text(
              member.name,
              style: HuddlText.body(color: context.hc.textPrimary),
            ),
            if (member.role == 'admin') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: HuddlColors.neutral50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Admin',
                  style: HuddlText.label(color: HuddlColors.textDark),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          member.borough.isNotEmpty
              ? '${member.isOnline ? 'Online' : 'Offline'} · ${member.borough}'
              : (member.isOnline ? 'Online' : 'Offline'),
          style: HuddlText.caption(color: member.isOnline ? _kOnline : context.hc.textTertiary),
        ),
        // Section 6E: show ⋮ button for admin users (not on own row)
        trailing: _canActOnMember
            ? IconButton(
                icon: Icon(HuddlIcons.moreVert, color: context.hc.textTertiary, size: 22),
                onPressed: () => _showOptions(context),
                tooltip: 'Member options',
              )
            : Icon(HuddlIcons.caretRight, color: context.hc.textTertiary),
        onTap: () {},
      ),
    );
  }
}

class _Member {
  final String uid;
  final String name;
  final String role;
  final Color accentColor;
  final bool isOnline;
  final String parentType;
  final String borough;
  final String? photoUrl;  // Bug 4 fix: profile photo URL

  const _Member({
    required this.uid,
    required this.name,
    required this.role,
    required this.accentColor,
    required this.isOnline,
    required this.parentType,
    required this.borough,
    this.photoUrl,
  });
}
