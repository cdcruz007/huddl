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

  Map<String, dynamic> toJson() => {
        'memberId': memberId,
        'memberName': memberName,
        'optionIndex': optionIndex,
      };

  factory PollVote.fromJson(Map<String, dynamic> j) => PollVote(
        memberId: j['memberId'] as String? ?? '',
        memberName: j['memberName'] as String? ?? 'Unknown',
        optionIndex: j['optionIndex'] as int? ?? 0,
      );
}

/// Runtime model for an active poll in a group chat.
/// Supports multi-user scenarios where each user has their own vote state.
class ActivePoll {
  final String id;
  final PollData data;
  final String creatorName;
  final String creatorId;
  final DateTime createdAt;
  final List<PollVote> votes;
  final Set<int> myVotes; // option indices the current user voted for
  bool isPinned; // creator can pin to keep visible in chat flow after voting
  bool isDeleted; // soft-deleted by creator

  ActivePoll({
    required this.id,
    required this.data,
    required this.creatorName,
    this.creatorId = 'current_user',
    required this.createdAt,
    List<PollVote>? votes,
    Set<int>? myVotes,
    this.isPinned = false, // NOT pinned by default — creator opts in
    this.isDeleted = false,
  })  : votes = votes ?? [],
        myVotes = myVotes ?? {};

  bool get isExpired =>
      data.expiresAt != null && DateTime.now().isAfter(data.expiresAt!);

  int votesFor(int optionIndex) =>
      votes.where((v) => v.optionIndex == optionIndex).length;

  int get totalVotes => votes.length;

  bool get isCreatedByMe => creatorId == 'current_user';

  /// Whether the current user has already voted on this poll
  bool get hasVoted => myVotes.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'data': data.toJson(),
        'creatorName': creatorName,
        'creatorId': creatorId,
        'createdAt': createdAt.toIso8601String(),
        'votes': votes.map((v) => v.toJson()).toList(),
        'myVotes': myVotes.toList(),
        'isPinned': isPinned,
        'isDeleted': isDeleted,
      };

  factory ActivePoll.fromJson(Map<String, dynamic> j) => ActivePoll(
        id: j['id'] as String,
        data: PollData.fromJson(j['data'] as Map<String, dynamic>),
        creatorName: j['creatorName'] as String? ?? 'Unknown',
        creatorId: j['creatorId'] as String? ?? 'current_user',
        createdAt: DateTime.parse(j['createdAt'] as String),
        votes: (j['votes'] as List<dynamic>?)
                ?.map((v) => PollVote.fromJson(v as Map<String, dynamic>))
                .toList() ??
            [],
        myVotes: ((j['myVotes'] as List<dynamic>?) ?? [])
            .map((e) => e as int)
            .toSet(),
        isPinned: j['isPinned'] as bool? ?? false,
        isDeleted: j['isDeleted'] as bool? ?? false,
      );

  /// Whether this poll should be visible in the main chat flow.
  ///
  /// Rules:
  /// - Creator, not voted yet: visible (so they can vote and access results)
  /// - Creator, voted, NOT pinned: HIDDEN (dismissed after voting, access via Active Polls)
  /// - Creator, voted, pinned: VISIBLE (creator explicitly pinned it)
  /// - Non-creator, not voted yet: visible (needs to vote)
  /// - Non-creator, voted, NOT pinned: HIDDEN (auto-dismissed after voting)
  /// - Non-creator, voted, pinned by creator: VISIBLE (creator chose to keep it)
  bool get visibleInFlow {
    if (!hasVoted) return true; // everyone sees unvoted polls
    return isPinned; // voted → only stay visible if pinned
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// POLL CARD — displayed as a chat bubble in the group chat
// ═══════════════════════════════════════════════════════════════════════════

class PollCard extends StatelessWidget {
  final ActivePoll poll;
  final void Function(int optionIndex)? onSelectOption;
  final VoidCallback? onViewDetails;
  final VoidCallback? onTogglePin;
  final VoidCallback? onDeletePoll;
  final VoidCallback? onSeeResults;
  final VoidCallback? onChangeVote;

  const PollCard({
    super.key,
    required this.poll,
    this.onSelectOption,
    this.onViewDetails,
    this.onTogglePin,
    this.onDeletePoll,
    this.onSeeResults,
    this.onChangeVote,
  });

  @override
  Widget build(BuildContext context) {
    final expired = poll.isExpired;
    final isCreator = poll.isCreatedByMe;
    final hasVoted = poll.hasVoted;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: expired ? context.hc.scaffold : HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: expired
              ? HuddlColors.divider
              : poll.isPinned
                  ? HuddlColors.primary.withValues(alpha: 0.4)
                  : HuddlColors.primary.withValues(alpha: 0.25),
          width: poll.isPinned && !expired ? 1.5 : 1.0,
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
        opacity: expired ? 0.65 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row — poll icon + creator + pin badge + 3-dot menu ──
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.poll_outlined,
                      size: 16, color: HuddlColors.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Poll by ${poll.creatorName}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textTertiary,
                    ),
                  ),
                ),
                // Pinned badge — creator can tap to unpin; non-creator sees read-only
                if (poll.isPinned && !expired)
                  GestureDetector(
                    onTap: isCreator ? onTogglePin : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: HuddlColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.push_pin,
                              size: 12, color: HuddlColors.primary),
                          const SizedBox(width: 3),
                          Text(
                            'Pinned',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary,
                            ),
                          ),
                          if (isCreator) ...[
                            const SizedBox(width: 3),
                            Icon(Icons.close,
                                size: 11,
                                color:
                                    HuddlColors.primary.withValues(alpha: 0.6)),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (expired)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HuddlColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Expired',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.error,
                      ),
                    ),
                  ),
                // 3-dot context menu
                _buildPollMenu(context),
              ],
            ),
            const SizedBox(height: 12),

            // ── Question ─────────────────────────────────────────────────
            Text(
              poll.data.question,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.hc.textPrimary,
              ),
            ),
            if (poll.data.isCalendarMode)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 12,
                        color: HuddlColors.primary.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text(
                      'Calendar poll',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: HuddlColors.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // ── Options ───────────────────────────────────────────────────
            ...List.generate(poll.data.options.length, (i) {
              final selected = poll.myVotes.contains(i);
              final count = poll.votesFor(i);
              final total = poll.totalVotes;
              final pct = total > 0 ? (count / total * 100).round() : 0;

              // Only the creator sees vote counts / percentages inline.
              // Non-creators NEVER see results — privacy by design.
              final showCounts = isCreator;

              // Anyone (including the creator) can vote if:
              //   • poll not expired
              //   • hasn't voted yet (single-choice), OR poll allows multiple
              final canVote = !expired &&
                  (!hasVoted || poll.data.allowMultiple);

              return GestureDetector(
                onTap: canVote ? () => onSelectOption?.call(i) : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? HuddlColors.primary.withValues(alpha: 0.1)
                        : context.hc.scaffold,
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
                          color: selected
                              ? HuddlColors.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: selected
                                ? HuddlColors.primary
                                : HuddlColors.textHint,
                            width: 1.5,
                          ),
                        ),
                        child: selected
                            ? const Icon(Icons.check,
                                size: 13, color: HuddlColors.white)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            if (poll.data.isCalendarMode)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.calendar_today_outlined,
                                  size: 14,
                                  color: selected
                                      ? HuddlColors.primary
                                      : HuddlColors.textHint,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                poll.data.options[i],
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: context.hc.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Creator sees vote counts; non-creators do not
                      if (showCounts) ...[
                        Text(
                          '$count',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? HuddlColors.primary
                                : HuddlColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '($pct%)',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: context.hc.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 8),

            // ── Footer ────────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.how_to_vote_outlined,
                    size: 14, color: context.hc.textTertiary),
                const SizedBox(width: 4),
                // Creator always sees total vote count
                if (isCreator)
                  Text(
                    '${poll.totalVotes} vote${poll.totalVotes != 1 ? 's' : ''}',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: context.hc.textTertiary),
                  )
                else
                  // Non-creator: just acknowledge their status
                  Text(
                    hasVoted ? 'Vote recorded' : 'Tap to vote',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: context.hc.textTertiary),
                  ),
                if (poll.data.expiresAt != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.access_time,
                      size: 14,
                      color: expired
                          ? HuddlColors.error
                          : context.hc.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    expired
                        ? 'Poll expired'
                        : 'Closes ${_relativeTime(poll.data.expiresAt!)}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: expired
                          ? HuddlColors.error
                          : context.hc.textTertiary,
                    ),
                  ),
                ],
                const Spacer(),
                // Creator always sees "View results"
                if (isCreator)
                  GestureDetector(
                    onTap: onViewDetails,
                    child: Text(
                      'View results',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.primary,
                      ),
                    ),
                  )
                // Non-creator who has voted can change vote (until expiry)
                else if (!isCreator && hasVoted && !expired)
                  GestureDetector(
                    onTap: onChangeVote,
                    child: Text(
                      'Change vote',
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
    );
  }

  Widget _buildPollMenu(BuildContext context) {
    final isCreator = poll.isCreatedByMe;

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert,
          size: 20,
          color: context.hc.textTertiary.withValues(alpha: 0.7)),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      offset: const Offset(0, 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: context.hc.surface,
      elevation: 8,
      onSelected: (value) {
        switch (value) {
          case 'pin':
            onTogglePin?.call();
            break;
          case 'results':
            onSeeResults?.call();
            break;
          case 'change_vote':
            onChangeVote?.call();
            break;
          case 'delete':
            onDeletePoll?.call();
            break;
        }
      },
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<String>>[];

        if (isCreator) {
          // ── Creator menu ──────────────────────────────────────────────
          // Pin / Unpin (only for active polls)
          if (!poll.isExpired) {
            items.add(PopupMenuItem<String>(
              value: 'pin',
              child: Row(
                children: [
                  Icon(
                    poll.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                    size: 20,
                    color: context.hc.textPrimary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    poll.isPinned ? 'Unpin poll' : 'Pin poll',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                ],
              ),
            ));
          }
          // See Results — always available to creator
          items.add(PopupMenuItem<String>(
            value: 'results',
            child: Row(
              children: [
                Icon(Icons.bar_chart_outlined,
                    size: 20, color: context.hc.textPrimary),
                const SizedBox(width: 12),
                Text(
                  'See Results',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.hc.textPrimary,
                  ),
                ),
              ],
            ),
          ));
          // Delete Poll
          items.add(PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_outline,
                    size: 20, color: HuddlColors.error),
                const SizedBox(width: 12),
                Text(
                  'Delete Poll',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.error,
                  ),
                ),
              ],
            ),
          ));
        } else {
          // ── Non-creator menu ──────────────────────────────────────────
          // Change vote (only if already voted and poll still active)
          if (poll.hasVoted && !poll.isExpired) {
            items.add(PopupMenuItem<String>(
              value: 'change_vote',
              child: Row(
                children: [
                  Icon(Icons.how_to_vote_outlined,
                      size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text(
                    'Change my vote',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                ],
              ),
            ));
          }
          // Non-creators NEVER get a "See Results" option
        }

        return items;
      },
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
// ACTIVE POLLS BOTTOM SHEET
// Accessible via the top-right ⋮ menu. Lists ALL live polls from ALL users.
// - Creators: see results, pin/unpin, delete
// - Non-creators: vote, change vote (until expiry), no results visible
// ═══════════════════════════════════════════════════════════════════════════

class ActivePollsSheet extends StatefulWidget {
  final List<ActivePoll> polls;
  final void Function(String pollId, int optionIndex) onVote;
  final void Function(ActivePoll poll) onViewDetails;
  final void Function(String pollId) onTogglePin;
  final void Function(String pollId) onDeletePoll;

  const ActivePollsSheet({
    super.key,
    required this.polls,
    required this.onVote,
    required this.onViewDetails,
    required this.onTogglePin,
    required this.onDeletePoll,
  });

  @override
  State<ActivePollsSheet> createState() => _ActivePollsSheetState();
}

class _ActivePollsSheetState extends State<ActivePollsSheet> {
  @override
  Widget build(BuildContext context) {
    // All non-deleted polls sorted: active first, then expired
    final activePolls =
        widget.polls.where((p) => !p.isDeleted && !p.isExpired).toList();
    final expiredPolls =
        widget.polls.where((p) => !p.isDeleted && p.isExpired).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.hc.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── Handle ────────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // ── Title ─────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: HuddlColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.poll_outlined,
                          size: 18, color: HuddlColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active Polls',
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          if (activePolls.isNotEmpty)
                            Text(
                              'All polls from this group',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: context.hc.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (activePolls.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: HuddlColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${activePolls.length}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: HuddlColors.white,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close,
                          color: context.hc.textTertiary, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.hc.divider),
              // ── Poll list ─────────────────────────────────────────────
              Expanded(
                child: (activePolls.isEmpty && expiredPolls.isEmpty)
                    ? _buildEmptyState(context)
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        children: [
                          if (activePolls.isNotEmpty) ...[
                            _sectionHeader(
                                context, 'Live Polls', activePolls.length),
                            const SizedBox(height: 8),
                            ...activePolls.map((poll) => _PollSheetItem(
                                  poll: poll,
                                  onVote: (i) {
                                    widget.onVote(poll.id, i);
                                    setState(() {}); // refresh sheet state
                                  },
                                  onViewDetails: poll.isCreatedByMe
                                      ? () {
                                          Navigator.pop(context);
                                          widget.onViewDetails(poll);
                                        }
                                      : null,
                                  onTogglePin: poll.isCreatedByMe
                                      ? () {
                                          widget.onTogglePin(poll.id);
                                          setState(() {});
                                        }
                                      : null,
                                  onDeletePoll: poll.isCreatedByMe
                                      ? () {
                                          Navigator.pop(context);
                                          widget.onDeletePoll(poll.id);
                                        }
                                      : null,
                                )),
                          ],
                          if (expiredPolls.isNotEmpty) ...[
                            if (activePolls.isNotEmpty)
                              const SizedBox(height: 16),
                            _sectionHeader(context, 'Expired Polls',
                                expiredPolls.length),
                            const SizedBox(height: 8),
                            ...expiredPolls.map((poll) => _PollSheetItem(
                                  poll: poll,
                                  onVote: null, // expired — no voting
                                  onViewDetails: poll.isCreatedByMe
                                      ? () {
                                          Navigator.pop(context);
                                          widget.onViewDetails(poll);
                                        }
                                      : null,
                                  onTogglePin: null, // can't pin expired
                                  onDeletePoll: poll.isCreatedByMe
                                      ? () {
                                          Navigator.pop(context);
                                          widget.onDeletePoll(poll.id);
                                        }
                                      : null,
                                )),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.hc.textTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '($count)',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: context.hc.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.poll_outlined,
              size: 48, color: context.hc.textTertiary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            'No polls yet',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.hc.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Polls created in this group will\nappear here for everyone to vote on.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: context.hc.textTertiary.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Individual poll item inside the Active Polls sheet ───────────────────
//
// BEHAVIOUR:
// • Creator:      sees vote counts, percentages, can pin/delete/view results
// • Non-creator:  sees only their own selection highlighted; no counts shown
//                 can vote if not yet voted; can CHANGE their vote (tapping a
//                 different option) at any time until expiry
// ─────────────────────────────────────────────────────────────────────────

class _PollSheetItem extends StatelessWidget {
  final ActivePoll poll;
  final void Function(int)? onVote;
  final VoidCallback? onViewDetails;
  final VoidCallback? onTogglePin;
  final VoidCallback? onDeletePoll;

  const _PollSheetItem({
    required this.poll,
    required this.onVote,
    required this.onViewDetails,
    required this.onTogglePin,
    required this.onDeletePoll,
  });

  @override
  Widget build(BuildContext context) {
    final expired = poll.isExpired;
    final isCreator = poll.isCreatedByMe;
    final hasVoted = poll.hasVoted;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: expired ? context.hc.scaffold : context.hc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expired
              ? HuddlColors.divider
              : poll.isPinned
                  ? HuddlColors.primary.withValues(alpha: 0.35)
                  : HuddlColors.divider,
          width: poll.isPinned && !expired ? 1.5 : 1.0,
        ),
      ),
      child: Opacity(
        opacity: expired ? 0.65 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'By ${poll.creatorName}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: context.hc.textTertiary,
                        ),
                      ),
                      if (poll.isPinned && !expired) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.push_pin,
                            size: 12, color: HuddlColors.primary),
                      ],
                      if (expired) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: HuddlColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Expired',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Creator context menu
                if (isCreator)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 18,
                        color:
                            context.hc.textTertiary.withValues(alpha: 0.7)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    offset: const Offset(0, 28),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    color: context.hc.surface,
                    elevation: 8,
                    onSelected: (v) {
                      switch (v) {
                        case 'results':
                          onViewDetails?.call();
                          break;
                        case 'pin':
                          onTogglePin?.call();
                          break;
                        case 'delete':
                          onDeletePoll?.call();
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(
                        value: 'results',
                        child: Row(
                          children: [
                            Icon(Icons.bar_chart_outlined,
                                size: 18, color: context.hc.textPrimary),
                            const SizedBox(width: 10),
                            Text('See Results',
                                style: GoogleFonts.poppins(fontSize: 13)),
                          ],
                        ),
                      ),
                      if (!expired)
                        PopupMenuItem<String>(
                          value: 'pin',
                          child: Row(
                            children: [
                              Icon(
                                poll.isPinned
                                    ? Icons.push_pin_outlined
                                    : Icons.push_pin,
                                size: 18,
                                color: context.hc.textPrimary,
                              ),
                              const SizedBox(width: 10),
                              Text(poll.isPinned ? 'Unpin' : 'Pin poll',
                                  style:
                                      GoogleFonts.poppins(fontSize: 13)),
                            ],
                          ),
                        ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline,
                                size: 18, color: HuddlColors.error),
                            const SizedBox(width: 10),
                            Text('Delete',
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: HuddlColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Question ───────────────────────────────────────────────
            Text(
              poll.data.question,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.hc.textPrimary,
              ),
            ),
            const SizedBox(height: 10),

            // ── Options ────────────────────────────────────────────────
            ...List.generate(poll.data.options.length, (i) {
              final selected = poll.myVotes.contains(i);
              final count = poll.votesFor(i);
              final total = poll.totalVotes;
              final pct = total > 0 ? (count / total * 100).round() : 0;

              // Anyone (creator or member) can vote/change vote until expiry.
              // Single-choice: tapping a different option changes the vote.
              // Multi-choice: tapping toggles each option.
              final canTap = !expired &&
                  (!hasVoted || poll.data.allowMultiple) &&
                  onVote != null;

              return GestureDetector(
                onTap: canTap ? () => onVote?.call(i) : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected
                        ? HuddlColors.primary.withValues(alpha: 0.1)
                        : context.hc.scaffold,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? HuddlColors.primary
                          : HuddlColors.divider,
                      width: selected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Selection indicator
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? HuddlColors.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: selected
                                ? HuddlColors.primary
                                : HuddlColors.textHint,
                            width: 1.5,
                          ),
                        ),
                        child: selected
                            ? const Icon(Icons.check,
                                size: 11, color: HuddlColors.white)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          poll.data.options[i],
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: context.hc.textPrimary,
                          ),
                        ),
                      ),
                      // ONLY creator sees vote counts / percentages
                      if (isCreator && total > 0) ...[
                        Text(
                          '$pct%',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? HuddlColors.primary
                                : HuddlColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '($count)',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: context.hc.textTertiary,
                          ),
                        ),
                      ],
                      // Non-creator who has voted: show "change" hint on unselected
                      if (!isCreator && hasVoted && !selected && !expired)
                        Text(
                          'Change',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color:
                                HuddlColors.primary.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 6),

            // ── Footer ─────────────────────────────────────────────────
            Row(
              children: [
                if (isCreator)
                  Text(
                    '${poll.totalVotes} vote${poll.totalVotes != 1 ? 's' : ''}',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: context.hc.textTertiary),
                  )
                else
                  Text(
                    expired
                        ? (hasVoted ? 'Your vote was recorded' : 'No vote cast')
                        : (hasVoted
                            ? 'Tap another option to change vote'
                            : 'Tap an option to vote'),
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: hasVoted && !expired
                            ? HuddlColors.primary.withValues(alpha: 0.8)
                            : context.hc.textTertiary),
                  ),
                if (poll.data.expiresAt != null) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.access_time,
                      size: 13,
                      color: expired
                          ? HuddlColors.error
                          : context.hc.textTertiary),
                  const SizedBox(width: 3),
                  Text(
                    expired
                        ? 'Expired'
                        : 'Closes ${_relativeTime(poll.data.expiresAt!)}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: expired
                          ? HuddlColors.error
                          : context.hc.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ],
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
// ONLY accessible by the poll creator
// ═══════════════════════════════════════════════════════════════════════════

class PollDetailScreen extends StatelessWidget {
  final ActivePoll poll;
  final VoidCallback? onDeletePoll;

  const PollDetailScreen({
    super.key,
    required this.poll,
    this.onDeletePoll,
  });

  @override
  Widget build(BuildContext context) {
    final total = poll.totalVotes;

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
        title: Text(
          'Poll Results',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: context.hc.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          if (poll.isCreatedByMe && onDeletePoll != null)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: HuddlColors.error, size: 22),
              onPressed: () {
                Navigator.pop(context);
                onDeletePoll?.call();
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.hc.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Question header ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.hc.surface,
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
                      child: const Icon(Icons.poll_outlined,
                          size: 18, color: HuddlColors.primary),
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
                              color: context.hc.textTertiary,
                            ),
                          ),
                          if (poll.isExpired)
                            Text(
                              'Poll expired',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.error,
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
                    color: context.hc.textPrimary,
                  ),
                ),
                if (poll.data.isCalendarMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 13,
                            color:
                                HuddlColors.primary.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          'Calendar poll',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color:
                                HuddlColors.primary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Options with full vote breakdown (creator only) ───────────
          ...List.generate(poll.data.options.length, (i) {
            final count = poll.votesFor(i);
            final pct = total > 0 ? (count / total * 100).round() : 0;
            final voters =
                poll.votes.where((v) => v.optionIndex == i).toList();
            final isMyVote = poll.myVotes.contains(i);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.hc.surface,
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
                      if (poll.data.isCalendarMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.calendar_today_outlined,
                              size: 16,
                              color: isMyVote
                                  ? HuddlColors.primary
                                  : HuddlColors.textHint),
                        ),
                      Expanded(
                        child: Text(
                          poll.data.options[i],
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isMyVote
                              ? HuddlColors.primary
                              : HuddlColors.textDark,
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
                      color: isMyVote
                          ? HuddlColors.primary
                          : HuddlColors.textHint,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$count vote${count != 1 ? 's' : ''}',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: context.hc.textTertiary),
                  ),
                  if (voters.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Divider(height: 1, color: context.hc.divider),
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
                                  color: context.hc.textSecondary,
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

          // ── Delete button for creator ─────────────────────────────────
          if (poll.isCreatedByMe && onDeletePoll != null) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onDeletePoll?.call();
                },
                icon: Icon(Icons.delete_outline,
                    color: context.hc.surface, size: 20),
                label: Text(
                  'Delete Poll',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.hc.surface,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.error,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
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
                  vote.memberName.isNotEmpty
                      ? vote.memberName[0].toUpperCase()
                      : '?',
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
                vote.memberName.isNotEmpty
                    ? vote.memberName[0].toUpperCase()
                    : '?',
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
