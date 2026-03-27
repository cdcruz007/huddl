import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/invitation_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';

/// Screen that lists all borough members so the user can pick one to start
/// a direct message conversation with.
class NewDMScreen extends StatefulWidget {
  const NewDMScreen({super.key});

  @override
  State<NewDMScreen> createState() => _NewDMScreenState();
}

class _NewDMScreenState extends State<NewDMScreen> {
  final OnboardingDataService _onboarding = OnboardingDataService();
  final TextEditingController _searchController = TextEditingController();

  List<BoroughMember> _allMembers = [];
  List<BoroughMember> _filtered = [];
  String _searchQuery = '';
  bool _isLoading = true;
  String _borough = '';

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    await _onboarding.initialize();
    final postcode = _onboarding.postcode;
    _borough = PostcodeService().getBoroughFromPostcode(postcode) ?? '';
    _allMembers = InvitationService.getBoroughMembers(_borough);
    _filtered = List.from(_allMembers);
    setState(() => _isLoading = false);
  }

  void _applyFilter(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filtered = List.from(_allMembers);
      } else {
        final q = query.toLowerCase();
        _filtered = _allMembers
            .where((m) => m.name.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  void _selectMember(BoroughMember member) {
    // Assign a colour based on the member's name
    final colours = [
      '#FF975C',
      '#3580F0',
      '#199A85',
      '#A16AE9',
      '#5B9DFF',
      '#E8A838',
      '#FF7575',
      '#34C759',
    ];
    final color = colours[member.name.hashCode.abs() % colours.length];

    Navigator.pushReplacementNamed(context, '/dm_chat', arguments: {
      'recipientId': member.id,
      'recipientName': member.name,
      'recipientAvatarColor': color,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        surfaceTintColor: HuddlColors.white,
        leading: IconButton(
          icon: const Icon(Icons.close, color: HuddlColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'New Message',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: HuddlColors.divider),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: HuddlColors.primary))
          : Column(
              children: [
                // ── Search bar ──────────────────────────────────────
                Container(
                  color: HuddlColors.white,
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: HuddlColors.background,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        const Icon(Icons.search,
                            size: 20, color: HuddlColors.textHint),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: GoogleFonts.poppins(
                                fontSize: 14, color: HuddlColors.textDark),
                            decoration: InputDecoration(
                              hintText: 'Search members...',
                              hintStyle: GoogleFonts.poppins(
                                  fontSize: 14, color: HuddlColors.textHint),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onChanged: _applyFilter,
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              _applyFilter('');
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.close,
                                  size: 18, color: HuddlColors.textHint),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ── Borough label ────────────────────────────────────
                if (_borough.isNotEmpty && _borough != 'Unknown Borough')
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Members in $_borough',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textHint,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                // ── Member list ──────────────────────────────────────
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.person_search,
                                  size: 48, color: HuddlColors.textHint),
                              const SizedBox(height: 12),
                              Text(
                                'No members found',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try a different search term.',
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: HuddlColors.textHint),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 72,
                            color: HuddlColors.divider,
                          ),
                          itemBuilder: (context, index) {
                            final member = _filtered[index];
                            return _MemberTile(
                              member: member,
                              onTap: () => _selectMember(member),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMBER TILE
// ═══════════════════════════════════════════════════════════════════════════════

class _MemberTile extends StatelessWidget {
  final BoroughMember member;
  final VoidCallback onTap;

  const _MemberTile({required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colours = [
      '#FF975C',
      '#3580F0',
      '#199A85',
      '#A16AE9',
      '#5B9DFF',
      '#E8A838',
      '#FF7575',
      '#34C759',
    ];
    final color = _colorFromHex(
        colours[member.name.hashCode.abs() % colours.length]);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: HuddlColors.white,
        child: Row(
          children: [
            // Avatar with profile photo
            MemberAvatar(
              name: member.name,
              size: 48,
              accentColor: color,
              showOnlineDot: true,
              isOnline: true,
            ),
            const SizedBox(width: 14),
            // Name and parent type
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.parentType == 'mum' ? 'Mum' : 'Dad',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            // Online indicator
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0xFF34C759),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chat_bubble_outline,
                size: 20, color: HuddlColors.textHint),
          ],
        ),
      ),
    );
  }
}

Color _colorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return HuddlColors.primary;
}
