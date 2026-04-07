import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';

// ── Design tokens ────────────────────────────────────────────────────────
const Color _kOnline = Color(0xFF199A85); // HuddlColors.teal — online = positive status

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
      accentColor: HuddlColors.blue,
      isOnline: true,
    ),
    _Member(
      name: 'Kate Middleton',
      role: 'member',
      accentColor: HuddlColors.accentAmber,
      isOnline: true,
    ),
    _Member(
      name: 'Lucy Chen',
      role: 'member',
      accentColor: HuddlColors.paleBlue,
      isOnline: false,
    ),
    _Member(
      name: 'James Smith',
      role: 'member',
      accentColor: HuddlColors.lightBlue,
      isOnline: true,
    ),
    _Member(
      name: 'Anna Taylor',
      role: 'member',
      accentColor: HuddlColors.accentCoral,
      isOnline: false,
    ),
    _Member(
      name: 'Mia Johnson',
      role: 'member',
      accentColor: HuddlColors.primaryDark,
      isOnline: false,
    ),
    _Member(
      name: 'Oliver Brown',
      role: 'member',
      accentColor: HuddlColors.accentAmber,
      isOnline: true,
    ),
    _Member(
      name: 'Isabella Davis',
      role: 'member',
      accentColor: HuddlColors.blue,
      isOnline: false,
    ),
    _Member(
      name: 'Charlotte Wilson',
      role: 'member',
      accentColor: HuddlColors.paleBlue,
      isOnline: true,
    ),
    _Member(
      name: 'You',
      role: 'member',
      accentColor: HuddlColors.blue,
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
              '${_members.length} members',
              style:
                  GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
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
                      onChanged: (val) =>
                          setState(() => _searchQuery = val),
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: context.hc.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search members',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 14, color: context.hc.textTertiary),
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
                          fontSize: 14, color: context.hc.textTertiary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 72,
                      color: context.hc.divider,
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
      color: context.hc.surface,
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
                color: context.hc.textPrimary,
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
            color: member.isOnline ? _kOnline : context.hc.textTertiary,
          ),
        ),
        trailing:
            Icon(Icons.chevron_right, color: context.hc.textTertiary),
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
