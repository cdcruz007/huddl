import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/user_privacy_prefs_service.dart';

// ── Design tokens ────────────────────────────────────────────────────────
const Color _kOnline = HuddlColors.teal;

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

  @override
  void initState() {
    super.initState();
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
      List<String> memberIds = List<String>.from(data['memberIds'] ?? []);
      final creatorId = widget.creatorId ?? data['creatorId'] as String?;

      // Bug 3b fix: if memberIds is empty (common for onboarding-created groups
      // that weren't written with a memberIds array), fall back to querying the
      // users collection for anyone whose groupIds array contains this groupId.
      if (memberIds.isEmpty) {
        if (kDebugMode) {
          debugPrint('[GroupMembersScreen] memberIds empty for ${widget.groupId}, '
              'falling back to groupIds query');
        }
        try {
          final fallbackSnap = await db
              .collection('users')
              .where('groupIds', arrayContains: widget.groupId)
              .get();
          memberIds = fallbackSnap.docs.map((d) => d.id).toList();
        } catch (_) {
          // groupIds field may not exist — leave memberIds empty and show
          // the empty state rather than crashing.
        }
      }

      if (memberIds.isEmpty) {
        setState(() { _isLoading = false; _members = []; });
        return;
      }

      // 2. Fetch user documents in batches of 10 (Firestore whereIn limit)
      final List<_Member> loaded = [];
      for (int i = 0; i < memberIds.length; i += 10) {
        final batch = memberIds.sublist(i, i + 10 > memberIds.length ? memberIds.length : i + 10);
        final snap = await db.collection('users')
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

          loaded.add(_Member(
            uid: uid,
            name: isCurrentUser ? 'You' : name,
            role: isCreator ? 'admin' : 'member',
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

      setState(() { _members = loaded; _isLoading = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('[GroupMembersScreen] Error loading members: $e');
      setState(() { _isLoading = false; _error = 'Could not load members. Tap to retry.'; });
    }
  }

  Color _colorForUid(String uid) {
    const colors = [
      HuddlColors.primary,
      HuddlColors.teal,
      HuddlColors.primaryDark,
      HuddlColors.accentAmber,
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
          icon: Icon(Icons.arrow_back, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Members',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.hc.textPrimary,
              ),
            ),
            Text(
              _isLoading ? 'Loading...' : '${_members.length} member${_members.length == 1 ? '' : 's'}',
              style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
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
                  Icon(Icons.search, size: 20, color: context.hc.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      textAlignVertical: TextAlignVertical.center,
                      style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search members',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        isDense: true,
                        hintStyle: GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
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
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? HuddlColors.white : HuddlColors.textSecondary,
                        ),
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
                ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
                : _error != null
                    ? GestureDetector(
                        onTap: _loadMembers,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.refresh, size: 40, color: context.hc.textTertiary),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  style: GoogleFonts.poppins(
                                      fontSize: 14, color: context.hc.textTertiary),
                                  textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isNotEmpty ? 'No members found' : 'No members yet',
                              style: GoogleFonts.poppins(
                                  fontSize: 14, color: context.hc.textTertiary),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, indent: 72, color: context.hc.divider),
                            itemBuilder: (context, index) {
                              return _MemberTile(member: filtered[index]);
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final _Member member;
  const _MemberTile({required this.member});

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
          // Bug 4 fix: pass photoUrl so real profile photos are shown
          imageUrl: member.photoUrl,
        ),
        title: Row(
          children: [
            Text(
              member.name,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.hc.textPrimary,
              ),
            ),
            if (member.role == 'admin') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Admin',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          member.borough.isNotEmpty
              ? '${member.isOnline ? 'Online' : 'Offline'} · ${member.borough}'
              : (member.isOnline ? 'Online' : 'Offline'),
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: member.isOnline ? _kOnline : context.hc.textTertiary,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: context.hc.textTertiary),
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
