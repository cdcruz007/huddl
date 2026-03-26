import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import 'create_poll_screen.dart';
import 'dm_chat_screen.dart' show getProfilePhotoForMember;

/// Represents a vote on a poll option
class PollVote {
  final String memberId;
  final String memberName;
  final int optionIndex;

  const PollVote({
    required this.memberId,
    required this.memberName,
    required this.optionIndex,
  });
}

/// Runtime model for an active poll in a group chat
class ActivePoll {
  final String id;
  final PollData data;
  final String creatorName;
  final DateTime createdAt;
  final List<PollVote> votes;
  final Set<int> myVotes; // option indices the current user voted for

  ActivePoll({
    required this.id,
    required this.data,
    required this.creatorName,
    required this.createdAt,
    List<PollVote>? votes,
    Set<int>? myVotes,
  })  : votes = votes ?? [],
        myVotes = myVotes ?? {};

  bool get isExpired =>
      data.expiresAt != null && DateTime.now().isAfter(data.expiresAt!);

  int votesFor(int optionIndex) =>
      votes.where((v) => v.optionIndex == optionIndex).length;

  int get totalVotes => votes.length;
}

// ═══════════════════════════════════════════════════════════════════════════
// POLL CARD — displayed as a chat bubble in the group chat
// ═══════════════════════════════════════════════════════════════════════════

class PollCard extends StatelessWidget {
  final ActivePoll poll;
  final VoidCallback? onVote;
  final void Function(int optionIndex)? onSelectOption;
  final VoidCallback? onViewDetails;

  const PollCard({
    super.key,
    required this.poll,
    this.onVote,
    this.onSelectOption,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final expired = poll.isExpired;

    return GestureDetector(
      onTap: onViewDetails,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: expired ? HuddlColors.background : HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: expired ? HuddlColors.divider : HuddlColors.primary.withValues(alpha: 0.25),
          ),
          boxShadow: expired
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Opacity(
          opacity: expired ? 0.55 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row — poll icon + creator
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: HuddlColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.poll_outlined, size: 16, color: HuddlColors.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Poll by ${poll.creatorName}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ),
                  if (expired)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Expired',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Question
              Text(
                poll.data.question,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark,
                ),
              ),
              const SizedBox(height: 12),

              // Options
              ...List.generate(poll.data.options.length, (i) {
                final selected = poll.myVotes.contains(i);
                final count = poll.votesFor(i);
                final total = poll.totalVotes;
                final pct = total > 0 ? (count / total * 100).round() : 0;
                final showResults = poll.myVotes.isNotEmpty || expired;

                return GestureDetector(
                  onTap: expired ? null : () => onSelectOption?.call(i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? HuddlColors.primary.withValues(alpha: 0.1)
                          : HuddlColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? HuddlColors.primary
                            : HuddlColors.divider,
                        width: selected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Radio / check indicator
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? HuddlColors.primary : Colors.transparent,
                            border: Border.all(
                              color: selected ? HuddlColors.primary : HuddlColors.textHint,
                              width: 1.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check, size: 13, color: HuddlColors.white)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            poll.data.options[i],
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: HuddlColors.textDark,
                            ),
                          ),
                        ),
                        if (showResults) ...[
                          Text(
                            '$count',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? HuddlColors.primary : HuddlColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '($pct%)',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: HuddlColors.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 8),

              // Footer — total votes + expiry
              Row(
                children: [
                  Icon(Icons.how_to_vote_outlined, size: 14, color: HuddlColors.textHint),
                  const SizedBox(width: 4),
                  Text(
                    '${poll.totalVotes} vote${poll.totalVotes != 1 ? 's' : ''}',
                    style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint),
                  ),
                  if (poll.data.expiresAt != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.access_time, size: 14,
                        color: expired ? Colors.red : HuddlColors.textHint),
                    const SizedBox(width: 4),
                    Text(
                      expired
                          ? 'Poll expired'
                          : 'Closes ${_relativeTime(poll.data.expiresAt!)}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: expired ? Colors.red : HuddlColors.textHint,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (poll.myVotes.isNotEmpty || expired)
                    GestureDetector(
                      onTap: onViewDetails,
                      child: Text(
                        'View details',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.primary,
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

  String _relativeTime(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'expired';
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'in ${diff.inMinutes}m';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// POLL DETAIL SCREEN — full results with voter names per option
// ═══════════════════════════════════════════════════════════════════════════

class PollDetailScreen extends StatelessWidget {
  final ActivePoll poll;

  const PollDetailScreen({super.key, required this.poll});

  @override
  Widget build(BuildContext context) {
    final total = poll.totalVotes;

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
        title: Text(
          'Poll Details',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: HuddlColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Question
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HuddlColors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: HuddlColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.poll_outlined, size: 18, color: HuddlColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Created by ${poll.creatorName}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: HuddlColors.textHint,
                            ),
                          ),
                          if (poll.isExpired)
                            Text(
                              'Poll expired',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '$total vote${total != 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  poll.data.question,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Options with voters
          ...List.generate(poll.data.options.length, (i) {
            final count = poll.votesFor(i);
            final pct = total > 0 ? (count / total * 100).round() : 0;
            final voters = poll.votes.where((v) => v.optionIndex == i).toList();
            final isMyVote = poll.myVotes.contains(i);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: HuddlColors.white,
                borderRadius: BorderRadius.circular(16),
                border: isMyVote
                    ? Border.all(color: HuddlColors.primary, width: 1.5)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Option text + percentage
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          poll.data.options[i],
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark,
                          ),
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isMyVote ? HuddlColors.primary : HuddlColors.textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total > 0 ? count / total : 0,
                      backgroundColor: HuddlColors.divider,
                      color: isMyVote ? HuddlColors.primary : HuddlColors.textHint,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$count vote${count != 1 ? 's' : ''}',
                    style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint),
                  ),
                  if (voters.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1, color: HuddlColors.divider),
                    const SizedBox(height: 10),
                    ...voters.map((v) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              _buildVoterAvatar(v),
                              const SizedBox(width: 8),
                              Text(
                                v.memberName,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: HuddlColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildVoterAvatar(PollVote vote) {
    final photoUrl = getProfilePhotoForMember(vote.memberId);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: HuddlColors.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl != null
          ? Image.network(
              photoUrl,
              fit: BoxFit.cover,
              width: 28,
              height: 28,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  vote.memberName.isNotEmpty ? vote.memberName[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primary,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                vote.memberName.isNotEmpty ? vote.memberName[0].toUpperCase() : '?',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.primary,
                ),
              ),
            ),
    );
  }
}
