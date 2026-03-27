import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';

// ── Design tokens ────────────────────────────────────────────────────────
const Color _kOnline = Color(0xFF34C759);

class GroupMembersScreen extends StatefulWidget {
  final String groupName;
  final int memberCount;

  const GroupMembersScreen({
    super.key,
    required this.groupName,
    required this.memberCount,
  });

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Admins', 'Members'];

  // ── Sample members with profile photos ─────────────────────────────────
  static final List<_Member> _members = [
    _Member(
      name: 'Emma Watson',
      role: 'admin',
      accentColor: HuddlColors.primary,
      isOnline: true,
    ),
    _Member(
      name: 'Sophie Turner',
      role: 'admin',
      accentColor: const Color(0xFF3580F0),
      isOnline: true,
    ),
    _Member(
      name: 'Kate Middleton',
      role: 'member',
      accentColor: const Color(0xFF199A85),
      isOnline: true,
    ),
    _Member(
      name: 'Lucy Chen',
      role: 'member',
      accentColor: const Color(0xFFA16AE9),
      isOnline: false,
    ),
    _Member(
      name: 'James Smith',
      role: 'member',
      accentColor: const Color(0xFF5B9DFF),
      isOnline: true,
    ),
    _Member(
      name: 'Anna Taylor',
      role: 'member',
      accentColor: const Color(0xFFE8A838),
      isOnline: false,
    ),
    _Member(
      name: 'Mia Johnson',
      role: 'member',
      accentColor: const Color(0xFFFF7575),
      isOnline: false,
    ),
    _Member(
      name: 'Oliver Brown',
      role: 'member',
      accentColor: const Color(0xFF199A85),
      isOnline: true,
    ),
    _Member(
      name: 'Isabella Davis',
      role: 'member',
      accentColor: const Color(0xFF3580F0),
      isOnline: false,
    ),
    _Member(
      name: 'Charlotte Wilson',
      role: 'member',
      accentColor: const Color(0xFFA16AE9),
      isOnline: true,
    ),
    _Member(
      name: 'You',
      role: 'member',
      accentColor: HuddlColors.teal,
      isOnline: true,
    ),
  ];

  List<_Member> get _filteredMembers {
    var list = List<_Member>.from(_members);

    if (_selectedFilter == 'Admins') {
      list = list.where((m) => m.role == 'admin').toList();
    } else if (_selectedFilter == 'Members') {
      list = list.where((m) => m.role == 'member').toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((m) => m.name.toLowerCase().contains(q)).toList();
    }

    list.sort((a, b) {
      if (a.role == 'admin' && b.role != 'admin') return -1;
      if (a.role != 'admin' && b.role == 'admin') return 1;
      if (a.isOnline && !b.isOnline) return -1;
      if (!a.isOnline && b.isOnline) return 1;
      return a.name.compareTo(b.name);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMembers;

    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        surfaceTintColor: HuddlColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: HuddlColors.textDark),
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
                color: HuddlColors.textDark,
              ),
            ),
            Text(
              '${_members.length} members',
              style:
                  GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: HuddlColors.divider),
        ),
      ),
      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────
          Container(
            color: HuddlColors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: HuddlColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, size: 20, color: HuddlColors.textHint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (val) =>
                          setState(() => _searchQuery = val),
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: HuddlColors.textDark),
                      decoration: InputDecoration(
                        hintText: 'Search members',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 14, color: HuddlColors.textHint),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Role filter chips ───────────────────────────────────────
          Container(
            color: HuddlColors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: _filters.map((f) {
                final isSelected = _selectedFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFilter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color:
                            isSelected ? HuddlColors.primary : HuddlColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isSelected
                                ? HuddlColors.primary
                                : HuddlColors.divider),
                      ),
                      child: Text(
                        f,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? HuddlColors.white
                              : HuddlColors.textSecondary,
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
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No members found',
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: HuddlColors.textHint),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: 72,
                      color: HuddlColors.divider,
                    ),
                    itemBuilder: (context, index) {
                      final member = filtered[index];
                      return _MemberTile(member: member);
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
      color: HuddlColors.white,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: MemberAvatar(
          name: member.name,
          size: 44,
          accentColor: member.accentColor,
          showOnlineDot: true,
          isOnline: member.isOnline,
        ),
        title: Row(
          children: [
            Text(
              member.name,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: HuddlColors.textDark,
              ),
            ),
            if (member.role == 'admin') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
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
          member.isOnline ? 'Online' : 'Offline',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: member.isOnline ? _kOnline : HuddlColors.textHint,
          ),
        ),
        trailing:
            const Icon(Icons.chevron_right, color: HuddlColors.textHint),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Viewing ${member.name}\'s profile'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
    );
  }
}

class _Member {
  final String name;
  final String role;
  final Color accentColor;
  final bool isOnline;

  const _Member({
    required this.name,
    required this.role,
    required this.accentColor,
    required this.isOnline,
  });
}
