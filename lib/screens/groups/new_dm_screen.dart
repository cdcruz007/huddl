import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/huddl_user_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/upgrade_prompt.dart';

/// Screen that lists all real borough members from Firestore so the user can
/// pick one to start a direct message conversation with.
class NewDMScreen extends StatefulWidget {
  const NewDMScreen({super.key});

  @override
  State<NewDMScreen> createState() => _NewDMScreenState();
}

class _NewDMScreenState extends State<NewDMScreen> {
  final OnboardingDataService _onboarding = OnboardingDataService();
  final HuddlUserService _userService = HuddlUserService();
  final TextEditingController _searchController = TextEditingController();

  List<HuddlUser> _allMembers = [];
  List<HuddlUser> _filtered = [];
  String _searchQuery = '';
  bool _isLoading = true;
  String _borough = '';
  String? _error;

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
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _onboarding.initialize();
      final postcode = _onboarding.postcode;
      _borough = PostcodeService().getBoroughFromPostcode(postcode) ?? '';

      if (_borough.isEmpty || _borough == 'Unknown Borough') {
        setState(() {
          _isLoading = false;
          _error = 'Could not determine your borough from your postcode.';
        });
        return;
      }

      final members = await _userService.getBoroughMembers(_borough);
      _allMembers = members;
      _filtered = List.from(_allMembers);
    } catch (e) {
      _error = 'Failed to load members. Please try again.';
    }

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

  void _selectMember(HuddlUser member) async {
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

    Navigator.pushReplacementNamed(context, '/dm_chat', arguments: {
      'recipientId': member.uid,
      'recipientName': member.name,
      'recipientAvatarColor': member.avatarColor,
      'recipientBorough': member.borough,
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
              child: CircularProgressIndicator(color: HuddlColors.textTertiary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: context.hc.textTertiary),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: context.hc.textTertiary),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loadMembers,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
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
                                textAlignVertical: TextAlignVertical.center,
                                style: GoogleFonts.poppins(
                                    fontSize: 14, color: context.hc.textPrimary),
                                decoration: InputDecoration(
                                  hintText: 'Search members...',
                                  hintStyle: GoogleFonts.poppins(
                                      fontSize: 14, color: context.hc.textTertiary),
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  isDense: true,
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
                                  padding: const EdgeInsets.all(8.0),
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
                          'Parents in $_borough',
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
                                    _allMembers.isEmpty
                                        ? 'No other members in $_borough yet'
                                        : 'No members found',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: context.hc.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _allMembers.isEmpty
                                        ? 'Invite friends in your area to join Huddl!'
                                        : 'Try a different search term.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: context.hc.textTertiary),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadMembers,
                              child: ListView.separated(
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
  final HuddlUser member;
  final VoidCallback onTap;

  const _MemberTile({required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(member.avatarColor);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: context.hc.surface,
        child: Row(
          children: [
            // Avatar with profile photo or initials
            MemberAvatar(
              name: member.name,
              size: 48,
              accentColor: color,
              showOnlineDot: true,
              isOnline: member.isOnline,
              imageUrl: member.photoUrl.isNotEmpty ? member.photoUrl : null,
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
                    _parentTypeLabel(member.parentType, member.stagesOfLife),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: context.hc.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // Online indicator
            if (member.isOnline) ...[
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: HuddlColors.nearBlack,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chat_bubble_outline,
                size: 20, color: context.hc.textTertiary),
          ],
        ),
      ),
    );
  }

  String _parentTypeLabel(String parentType, List<String> stages) {
    final type = parentType == 'mum' ? 'Mum' : parentType == 'dad' ? 'Dad' : 'Parent';
    if (stages.contains('expecting')) return '$type · Expecting';
    if (stages.contains('aspiring')) return '$type · Aspiring';
    return type;
  }
}

Color _colorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return HuddlColors.primary;
}
