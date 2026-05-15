import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/huddl_colors.dart';
import '../../services/ai_matchmaker_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AI MATCHMAKER BOTTOM SHEET
// Shows AI-suggested meetups with matched parents
// ═══════════════════════════════════════════════════════════════════════════════

class AiMatchmakerSheet extends StatefulWidget {
  const AiMatchmakerSheet({super.key});

  @override
  State<AiMatchmakerSheet> createState() => _AiMatchmakerSheetState();
}

class _AiMatchmakerSheetState extends State<AiMatchmakerSheet> {
  final AiMatchmakerService _matchmaker = AiMatchmakerService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _matchmaker.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.hc.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: context.hc.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: HuddlColors.aiGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.auto_awesome, color: context.hc.surface, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Matchmaker',
                            style: GoogleFonts.poppins(
                              fontSize: 20, fontWeight: FontWeight.w700,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          Text(
                            'Personalised meetup suggestions just for you',
                            style: GoogleFonts.poppins(
                              fontSize: 12, color: context.hc.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: context.hc.textTertiary),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.hc.divider),
              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: HuddlColors.aiBlue))
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Nearby parents section
                          _buildNearbyParentsSection(),
                          const SizedBox(height: 20),
                          // Suggestions
                          Text(
                            'Suggested Meetups',
                            style: GoogleFonts.poppins(
                              fontSize: 17, fontWeight: FontWeight.w600,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Based on your profile, child ages, and community activity',
                            style: GoogleFonts.poppins(
                              fontSize: 12, color: context.hc.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._matchmaker.suggestions.map(_buildSuggestionCard),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNearbyParentsSection() {
    final parents = _matchmaker.nearbyParents.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Compatible Parents Nearby',
          style: GoogleFonts.poppins(
            fontSize: 17, fontWeight: FontWeight.w600,
            color: context.hc.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Parents with similar-aged kids in your area',
          style: GoogleFonts.poppins(
            fontSize: 12, color: context.hc.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: parents.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _buildParentChip(parents[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildParentChip(MatchableParent parent) {
    final pct = (parent.compatibilityScore * 100).round();
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: HuddlColors.primary.withValues(alpha: 0.08),
                backgroundImage: parent.avatarUrl != null
                    ? CachedNetworkImageProvider(parent.avatarUrl!)
                    : null,
                child: parent.avatarUrl == null
                    ? Text(parent.name[0], style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w600,
                        color: HuddlColors.primary,
                      ))
                    : null,
              ),
              Positioned(
                bottom: -4, right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: pct >= 80 ? HuddlColors.success : HuddlColors.blue,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.hc.surface, width: 1.5),
                  ),
                  child: Text(
                    '$pct%',
                    style: GoogleFonts.poppins(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: context.hc.surface,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            parent.name.split(' ').first,
            style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w500,
              color: context.hc.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (parent.childAges.isNotEmpty)
            Text(
              parent.childAges.first,
              style: GoogleFonts.poppins(
                fontSize: 9, color: context.hc.textTertiary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(SuggestedMeetup suggestion) {
    final pct = (suggestion.confidenceScore * 100).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.hc.divider),
        boxShadow: [
          BoxShadow(
            color: HuddlColors.gray900.withValues(alpha: 0.06),
            blurRadius: 12, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar with confidence
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              color: context.hc.scaffold,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Text(suggestion.iconEmoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.title,
                        style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary,
                        ),
                      ),
                      Text(
                        '${suggestion.suggestedDate} \u00B7 ${suggestion.suggestedTime}',
                        style: GoogleFonts.poppins(
                          fontSize: 12, color: context.hc.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: pct >= 90
                        ? HuddlColors.success.withValues(alpha: 0.15)
                        : HuddlColors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$pct% match',
                    style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: pct >= 90 ? HuddlColors.success : HuddlColors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Location
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: context.hc.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      suggestion.suggestedLocation,
                      style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Description
                Text(
                  suggestion.description,
                  style: GoogleFonts.poppins(
                    fontSize: 13, color: context.hc.textSecondary, height: 1.4,
                  ),
                ),
                if (suggestion.weatherNote != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: HuddlColors.blueBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.wb_cloudy_outlined, size: 16, color: HuddlColors.blue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            suggestion.weatherNote!,
                            style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                // AI reasoning
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome, size: 14, color: HuddlColors.aiBlue),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        suggestion.reasoning,
                        style: GoogleFonts.poppins(
                          fontSize: 11, color: HuddlColors.aiBlue,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Matched parents avatars
                Row(
                  children: [
                    ...suggestion.matchedParents.take(4).map((p) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: HuddlColors.primary.withValues(alpha: 0.08),
                        backgroundImage: p.avatarUrl != null
                            ? CachedNetworkImageProvider(p.avatarUrl!)
                            : null,
                        child: p.avatarUrl == null
                            ? Text(p.name[0], style: const TextStyle(fontSize: 10))
                            : null,
                      ),
                    )),
                    if (suggestion.matchedParents.length > 4)
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: HuddlColors.primary.withValues(alpha: 0.08),
                        child: Text(
                          '+${suggestion.matchedParents.length - 4}',
                          style: GoogleFonts.poppins(
                            fontSize: 10, fontWeight: FontWeight.w600,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ),
                    const Spacer(),
                    // CTA button
                    GestureDetector(
                      onTap: () {
                        _matchmaker.createMeetupFromSuggestion(suggestion);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Meetup created! Invitations sent to ${suggestion.matchedParents.length} parents',
                              style: GoogleFonts.poppins(fontSize: 13),
                            ),
                            backgroundColor: HuddlColors.success,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: HuddlColors.aiGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add, size: 16, color: HuddlColors.white),
                            const SizedBox(width: 4),
                            Text(
                              'Create & Invite',
                              style: GoogleFonts.poppins(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: context.hc.surface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
