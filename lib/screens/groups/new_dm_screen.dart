import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/invitation_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/upgrade_prompt.dart';

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

  void _selectMember(BoroughMember member) async {
    // ── Subscription gate: DM conversation limit ──────────────────
    final subService = SubscriptionService();
    await subService.initialize();
    if (!subService.canStartDM) {
      if (mounted) {
        showUpgradePrompt(
          context,
          feature: 'dm',
          message: subService.limitReachedMessage('dm'),
        );
      }
      return;
    }
    subService.recordDMStart();
    if (!mounted) return;

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
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        surfaceTintColor: HuddlColors.white,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'New Message',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.hc.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.hc.divider),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: HuddlColors.primary))
          : Column(
              children: [
                // ── Search bar ──────────────────────────────────────
                Container(
                  color: context.hc.surface,
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.hc.scaffold,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        Icon(Icons.search,
                            size: 20, color: context.hc.textTertiary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: GoogleFonts.poppins(
                                fontSize: 14, color: context.hc.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Search members...',
                              hintStyle: GoogleFonts.poppins(
                                  fontSize: 14, color: context.hc.textTertiary),
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
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.close,
                                  size: 18, color: context.hc.textTertiary),
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
                        color: context.hc.textTertiary,
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
                              Icon(Icons.person_search,
                                  size: 48, color: context.hc.textTertiary),
                              const SizedBox(height: 12),
                              Text(
                                'No members found',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: context.hc.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try a different search term.',
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: context.hc.textTertiary),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 72,
                            color: context.hc.divider,
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
        color: context.hc.surface,
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
                      color: context.hc.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.parentType == 'mum' ? 'Mum' : 'Dad',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: context.hc.textTertiary,
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
                color: HuddlColors.teal,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chat_bubble_outline,
                size: 20, color: context.hc.textTertiary),
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
