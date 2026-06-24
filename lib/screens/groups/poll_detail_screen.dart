import 'dart:async';
import '../../theme/huddl_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/animations/huddl_spring_animations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../theme/huddl_colors.dart';
import 'create_poll_screen.dart';
import 'dm_chat_screen.dart' show getProfilePhotoForMember;
import '../../constants/app_text_styles.dart';
import '../../widgets/common/huddl_button.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FIRESTORE POLL MODEL
// Mirrors the `polls/{pollId}` Firestore document schema.
// ═══════════════════════════════════════════════════════════════════════════

class FirestorePollOption {
  final String id;
  final String label;
  final int voteCount;

  const FirestorePollOption({
    required this.id,
    required this.label,
    required this.voteCount,
  });

  factory FirestorePollOption.fromMap(Map<String, dynamic> m) =>
      FirestorePollOption(
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
        voteCount: (m['voteCount'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() =>
      {'id': id, 'label': label, 'voteCount': voteCount};
}

class FirestorePoll {
  final String id;
  final String question;
  /// 'single' or 'multiple'
  final String pollType;
  final String createdByUid;
  final String createdByName;
  final String groupId;
  /// The group_messages doc ID — used as dedup key when loading from stream.
  final String groupMsgId;
  final DateTime? createdAt;
  final DateTime? closesAt;
  final bool isCalendarMode;
  final List<FirestorePollOption> options;
  /// Map of uid → [optionId, …]
  final Map<String, List<String>> voters;

  const FirestorePoll({
    required this.id,
    required this.question,
    required this.pollType,
    required this.createdByUid,
    required this.createdByName,
    required this.groupId,
    required this.groupMsgId,
    required this.createdAt,
    required this.closesAt,
    required this.isCalendarMode,
    required this.options,
    required this.voters,
  });

  factory FirestorePoll.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    return FirestorePoll(
      id: doc.id,
      question: m['question'] as String? ?? '',
      pollType: m['pollType'] as String? ?? 'single',
      createdByUid: m['createdByUid'] as String? ?? '',
      createdByName: m['createdByName'] as String? ?? 'Unknown',
      groupId: m['groupId'] as String? ?? '',
      groupMsgId: m['groupMsgId'] as String? ?? '',
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      closesAt: (m['closesAt'] as Timestamp?)?.toDate(),
      isCalendarMode: m['isCalendarMode'] as bool? ?? false,
      options: ((m['options'] as List?) ?? [])
          .map((e) =>
              FirestorePollOption.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      voters: _parseVoters(m['voters']),
    );
  }

  static Map<String, List<String>> _parseVoters(dynamic raw) {
    if (raw == null) return {};
    final map = raw as Map;
    return map.map((k, v) =>
        MapEntry(k as String, List<String>.from(v as List? ?? [])));
  }

  bool get isMultiple => pollType == 'multiple';
  bool get isExpired =>
      closesAt != null && DateTime.now().isAfter(closesAt!);

  int get totalVoters => voters.length;

  /// Total vote-weight across all options (used for % calc).
  /// For multi-choice, this is sum of voteCount per option, not unique voters.
  int get totalVoteCount =>
      options.fold(0, (acc, o) => acc + o.voteCount);

  /// Option IDs the current user has selected.
  List<String> myVotedOptionIds(String uid) =>
      voters[uid] ?? [];

  bool hasVoted(String uid) => voters.containsKey(uid);

  bool get isCreatedByMe {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return myUid != null && myUid == createdByUid;
  }

  /// All UIDs that voted for a specific option.
  List<String> votersForOption(String optionId) => voters.entries
      .where((e) => e.value.contains(optionId))
      .map((e) => e.key)
      .toList();
}

// ═══════════════════════════════════════════════════════════════════════════
// LEGACY LOCAL MODEL — kept for backward compat with PollService (local cache)
// New polls use FirestorePoll; legacy polls loaded from BrowserStorage continue
// to use ActivePoll until migrated.
// ═══════════════════════════════════════════════════════════════════════════

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

class ActivePoll {
  final String id;
  final PollData data;
  final String creatorName;
  final String creatorId;
  final DateTime createdAt;
  final List<PollVote> votes;
  final Set<int> myVotes;
  bool isPinned;
  bool isDeleted;
  /// Non-null when this poll has been written to Firestore `polls/` collection.
  final String? firestorePollId;

  ActivePoll({
    required this.id,
    required this.data,
    required this.creatorName,
    String? creatorId,
    required this.createdAt,
    List<PollVote>? votes,
    Set<int>? myVotes,
    this.isPinned = false,
    this.isDeleted = false,
    this.firestorePollId,
  })  : creatorId =
            creatorId ?? FirebaseAuth.instance.currentUser?.uid ?? 'current_user',
        votes = votes ?? [],
        myVotes = myVotes ?? {};

  bool get isExpired =>
      data.expiresAt != null && DateTime.now().isAfter(data.expiresAt!);

  int votesFor(int optionIndex) =>
      votes.where((v) => v.optionIndex == optionIndex).length;

  int get totalVotes => votes.length;

  bool get isCreatedByMe {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return myUid != null ? creatorId == myUid : creatorId == 'current_user';
  }

  bool get hasVoted => myVotes.isNotEmpty;

  bool get visibleInFlow {
    if (!hasVoted) return true;
    return isPinned;
  }

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
        if (firestorePollId != null) 'firestorePollId': firestorePollId,
      };

  factory ActivePoll.fromJson(Map<String, dynamic> j) => ActivePoll(
        id: j['id'] as String,
        data: PollData.fromJson(j['data'] as Map<String, dynamic>),
        creatorName: j['creatorName'] as String? ?? 'Unknown',
        creatorId: j['creatorId'] as String?,
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
        firestorePollId: j['firestorePollId'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// FIRESTORE POLL CARD
// Real-time widget backed by a StreamBuilder on `polls/{pollId}`.
// Handles: single/multi-choice UI, creator vs member roles, expiry.
// ═══════════════════════════════════════════════════════════════════════════

class FirestorePollCard extends StatefulWidget {
  final String pollId;
  final VoidCallback? onTogglePin;
  final VoidCallback? onDeletePoll;

  const FirestorePollCard({
    super.key,
    required this.pollId,
    this.onTogglePin,
    this.onDeletePoll,
  });

  @override
  State<FirestorePollCard> createState() => _FirestorePollCardState();
}

class _FirestorePollCardState extends State<FirestorePollCard> {
  /// Pending selection for multi-choice (before user taps Submit)
  Set<String> _pendingSelection = {};
  bool _submitting = false;

  String get _myUid =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _submitVote(FirestorePoll poll) async {
    if (_submitting) return;
    final selectedIds = _pendingSelection.toList();
    if (selectedIds.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await FirestoreService().submitPollVote(
        pollId: widget.pollId,
        uid: _myUid,
        selectedOptionIds: selectedIds,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PollCard] vote error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _selectSingle(FirestorePoll poll, String optId) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _pendingSelection = {optId};
    });
    try {
      await FirestoreService().submitPollVote(
        pollId: widget.pollId,
        uid: _myUid,
        selectedOptionIds: [optId],
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PollCard] vote error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService().pollStream(widget.pollId),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final poll = FirestorePoll.fromDoc(snap.data!);

        // Sync pendingSelection with actual Firestore votes on first load
        // (only when not mid-submission)
        if (!_submitting) {
          final myVoted = poll.myVotedOptionIds(_myUid).toSet();
          if (myVoted.isNotEmpty && _pendingSelection.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _pendingSelection = myVoted);
            });
          }
        }

        return _PollCardBody(
          poll: poll,
          myUid: _myUid,
          pendingSelection: _pendingSelection,
          submitting: _submitting,
          onToggleMulti: (optId) {
            if (poll.isExpired) return;
            setState(() {
              if (_pendingSelection.contains(optId)) {
                _pendingSelection.remove(optId);
              } else {
                _pendingSelection.add(optId);
              }
            });
          },
          onSelectSingle: (optId) => _selectSingle(poll, optId),
          onSubmitMulti: () => _submitVote(poll),
          onDeletePoll: widget.onDeletePoll,
          onViewResults: () => _openResults(context, poll),
        );
      },
    );
  }

  void _openResults(BuildContext context, FirestorePoll poll) {
    Navigator.push(
      context,
      HuddlSpringPageRoute(page: PollResultsScreen(
        pollId: widget.pollId,
        onDeletePoll: poll.isCreatedByMe ? widget.onDeletePoll : null,
      )),
    );
  }
}

// ─── Card body (stateless, receives all state from parent) ─────────────────

class _PollCardBody extends StatelessWidget {
  final FirestorePoll poll;
  final String myUid;
  final Set<String> pendingSelection;
  final bool submitting;
  final void Function(String optId) onToggleMulti;
  final void Function(String optId) onSelectSingle;
  final VoidCallback onSubmitMulti;
  final VoidCallback? onDeletePoll;
  final VoidCallback? onViewResults;

  const _PollCardBody({
    required this.poll,
    required this.myUid,
    required this.pendingSelection,
    required this.submitting,
    required this.onToggleMulti,
    required this.onSelectSingle,
    required this.onSubmitMulti,
    required this.onDeletePoll,
    required this.onViewResults,
  });

  @override
  Widget build(BuildContext context) {
    final expired = poll.isExpired;
    final isCreator = poll.isCreatedByMe;
    final hasVoted = poll.hasVoted(myUid);
    final myVotedIds = poll.myVotedOptionIds(myUid).toSet();
    final total = poll.totalVoteCount;

    // ── Creator sees results immediately, never the voting UI ──────────
    if (isCreator) {
      return _buildResultsView(context, expired, total, hasVoted);
    }

    // ── Expired → show read-only results for everyone ──────────────────
    if (expired) {
      return _buildExpiredView(context, total);
    }

    // ── Non-creator, not yet voted → voting UI ─────────────────────────
    if (!hasVoted) {
      return _buildVotingUI(context, expired, myVotedIds, total);
    }

    // ── Non-creator, already voted → thank-you / results view ──────────
    return _buildVotedView(context, myVotedIds, total);
  }

  // ── Creator: always sees results with live counts ──────────────────────
  Widget _buildResultsView(
      BuildContext context, bool expired, int total, bool hasVoted) {
    return _PollContainer(
      expired: expired,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PollHeader(
            poll: poll,
            isCreator: true,
            expired: expired,
            badge: expired ? 'Closed' : 'Your poll',
            badgeColor: expired ? HuddlColors.error : HuddlColors.primary,
            onDeletePoll: onDeletePoll,
          ),
          const SizedBox(height: 10),
          _PollQuestion(poll: poll),
          const SizedBox(height: 12),
          // Creator label
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: HuddlColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(HuddlIcons.info,
                    size: 14, color: HuddlColors.primary),
                const SizedBox(width: 6),
                Text(
                  'You created this poll — results are live',
                  style: HuddlText.caption(color: HuddlColors.primary),
                ),
              ],
            ),
          ),
          // Results bars
          ...poll.options.map((opt) => _ResultBar(
                option: opt,
                total: total,
                isHighlighted: false,
              )),
          _PollFooter(
            poll: poll,
            label: '${poll.totalVoters} voter${poll.totalVoters != 1 ? 's' : ''}',
            trailing: GestureDetector(
              onTap: onViewResults,
              child: Text(
                'Full results',
                style: HuddlText.caption(weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Expired: read-only results for non-creators ────────────────────────
  Widget _buildExpiredView(BuildContext context, int total) {
    final myVotedIds = poll.myVotedOptionIds(myUid).toSet();
    return _PollContainer(
      expired: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PollHeader(
            poll: poll,
            isCreator: false,
            expired: true,
            badge: 'Poll closed',
            badgeColor: HuddlColors.error,
          ),
          const SizedBox(height: 10),
          _PollQuestion(poll: poll),
          const SizedBox(height: 12),
          ...poll.options.map((opt) => _ResultBar(
                option: opt,
                total: total,
                isHighlighted: myVotedIds.contains(opt.id),
              )),
          _PollFooter(
            poll: poll,
            label: '${poll.totalVoters} voter${poll.totalVoters != 1 ? 's' : ''}',
          ),
        ],
      ),
    );
  }

  // ── Voting UI (non-creator, not yet voted, not expired) ────────────────
  Widget _buildVotingUI(BuildContext context, bool expired,
      Set<String> myVotedIds, int total) {
    final isMulti = poll.isMultiple;

    return _PollContainer(
      expired: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PollHeader(poll: poll, isCreator: false, expired: false),
          const SizedBox(height: 10),
          _PollQuestion(poll: poll),
          if (isMulti)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Select all that apply',
                style: HuddlText.caption(color: HuddlColors.primary.withValues(alpha: 0.8))),
            )
          else
            const SizedBox(height: 12),
          // Option rows — checkbox for multi, radio for single
          ...poll.options.map((opt) {
            final selected = pendingSelection.contains(opt.id);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: submitting
                  ? null
                  : () => isMulti
                      ? onToggleMulti(opt.id)
                      : onSelectSingle(opt.id),
              child: AnimatedScale(
                scale: selected ? 1.02 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  constraints: const BoxConstraints(minHeight: 48),
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
                      // Checkbox (multi) or Radio (single) — min 48dp tap target
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: isMulti
                            ? _CheckIcon(selected: selected)
                            : _RadioIcon(selected: selected),
                      ),
                      const SizedBox(width: 12),
                      if (poll.isCalendarMode)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(HuddlIcons.calendar,
                              size: 14, color: HuddlColors.textHint),
                        ),
                      Expanded(
                        child: Text(
                          opt.label,
                          style: HuddlText.body(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          // Submit button for multi-choice
          if (isMulti) ...[
            const SizedBox(height: 4),
            HuddlButton(
              label: 'Submit vote',
              variant: HuddlButtonVariant.primary,
              isLoading: submitting,
              fullWidth: true,
              onPressed: (submitting || pendingSelection.isEmpty)
                  ? null
                  : onSubmitMulti,
            ),
          ],
          _PollFooter(poll: poll, label: 'Tap to vote'),
        ],
      ),
    );
  }

  // ── Already voted (non-creator) → thank-you with their choice highlighted
  Widget _buildVotedView(
      BuildContext context, Set<String> myVotedIds, int total) {
    return _PollContainer(
      expired: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PollHeader(poll: poll, isCreator: false, expired: false),
          const SizedBox(height: 10),
          _PollQuestion(poll: poll),
          const SizedBox(height: 12),
          // Show result bars with user's choice highlighted
          ...poll.options.map((opt) => _ResultBar(
                option: opt,
                total: total,
                isHighlighted: myVotedIds.contains(opt.id),
              )),
          _PollFooter(
            poll: poll,
            label: 'Vote recorded ✓',
            trailing: GestureDetector(
              onTap: onViewResults,
              child: Text(
                'View results',
                style: HuddlText.caption(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared sub-widgets ──────────────────────────────────────────────────────

class _PollContainer extends StatelessWidget {
  final bool expired;
  final Widget child;
  const _PollContainer({required this.expired, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: expired ? context.hc.scaffold : HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: expired
              ? HuddlColors.divider
              : HuddlColors.primary.withValues(alpha: 0.25),
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
      child: Opacity(opacity: expired ? 0.7 : 1.0, child: child),
    );
  }
}

class _PollHeader extends StatelessWidget {
  final FirestorePoll poll;
  final bool isCreator;
  final bool expired;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback? onDeletePoll;

  const _PollHeader({
    required this.poll,
    required this.isCreator,
    required this.expired,
    this.badge,
    this.badgeColor,
    this.onDeletePoll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: HuddlColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(HuddlIcons.poll,
              size: 16, color: HuddlColors.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Poll by ${poll.createdByName}',
            style: HuddlText.caption(),
          ),
        ),
        if (badge != null)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: (badgeColor ?? HuddlColors.primary)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badge!,
              style: HuddlText.label(),
            ),
          ),
        // Creator 3-dot menu
        if (isCreator)
          PopupMenuButton<String>(
            icon: Icon(HuddlIcons.moreVert,
                size: 20,
                color: context.hc.textTertiary.withValues(alpha: 0.7)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            offset: const Offset(0, 32),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            color: context.hc.surface,
            elevation: 8,
            onSelected: (v) {
              if (v == 'delete') onDeletePoll?.call();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(HuddlIcons.delete,
                        size: 20, color: HuddlColors.error),
                    const SizedBox(width: 12),
                    Text(
                      'Delete Poll',
                      style: HuddlText.body(),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _PollQuestion extends StatelessWidget {
  final FirestorePoll poll;
  const _PollQuestion({required this.poll});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          poll.question,
          style: HuddlText.body(weight: FontWeight.w600),
        ),
        if (poll.isCalendarMode)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(HuddlIcons.calendar,
                    size: 12,
                    color: HuddlColors.primary.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text(
                  'Calendar poll',
                  style: HuddlText.caption(color: HuddlColors.primary.withValues(alpha: 0.7))),
              ],
            ),
          ),
      ],
    );
  }
}

class _ResultBar extends StatelessWidget {
  final FirestorePollOption option;
  final int total;
  final bool isHighlighted;

  const _ResultBar({
    required this.option,
    required this.total,
    required this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0
        ? (option.voteCount / total * 100).round()
        : 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isHighlighted
            ? HuddlColors.primary.withValues(alpha: 0.08)
            : context.hc.scaffold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted ? HuddlColors.primary : HuddlColors.divider,
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  style: HuddlText.body(),
                ),
              ),
              Text(
                '$pct%',
                style: HuddlText.body(weight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              Text(
                '(${option.voteCount})',
                style: HuddlText.caption(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0.0,
              end: total > 0 ? option.voteCount / total : 0.0,
            ),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: HuddlColors.divider,
                color: isHighlighted ? HuddlColors.primary : HuddlColors.neutral900,
                minHeight: 5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PollFooter extends StatelessWidget {
  final FirestorePoll poll;
  final String label;
  final Widget? trailing;

  const _PollFooter({
    required this.poll,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(HuddlIcons.howToVote,
              size: 14, color: context.hc.textTertiary),
          const SizedBox(width: 4),
          Text(
            label,
            style: HuddlText.caption(color: context.hc.textTertiary),
          ),
          if (poll.closesAt != null) ...[
            const SizedBox(width: 10),
            Icon(HuddlIcons.clock,
                size: 14,
                color: poll.isExpired
                    ? HuddlColors.error
                    : context.hc.textTertiary),
            const SizedBox(width: 3),
            Text(
              poll.isExpired
                  ? 'Poll closed'
                  : 'Closes ${_relativeTime(poll.closesAt!)}',
              style: HuddlText.caption(),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'closed';
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'in ${diff.inMinutes}m';
  }
}

class _CheckIcon extends StatelessWidget {
  final bool selected;
  const _CheckIcon({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected ? HuddlColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: selected ? HuddlColors.primary : HuddlColors.textHint,
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(HuddlIcons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _RadioIcon extends StatelessWidget {
  final bool selected;
  const _RadioIcon({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(
          color: selected ? HuddlColors.primary : HuddlColors.textHint,
          width: 1.5,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: HuddlColors.primary,
                ),
              ),
            )
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// POLL RESULTS SCREEN — full breakdown, real-time StreamBuilder
// Accessible by creator (with delete) and non-creators (read-only).
// ═══════════════════════════════════════════════════════════════════════════

class PollResultsScreen extends StatelessWidget {
  final String pollId;
  final VoidCallback? onDeletePoll;

  const PollResultsScreen({
    super.key,
    required this.pollId,
    this.onDeletePoll,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService().pollStream(pollId),
      builder: (context, snap) {
        final loading = !snap.hasData;
        final missing = snap.hasData && !snap.data!.exists;

        return Scaffold(
          backgroundColor: context.hc.scaffold,
          appBar: AppBar(
            backgroundColor: context.hc.surface,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(HuddlIcons.arrowBack, color: context.hc.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Poll Results',
              style: HuddlText.heading(),
            ),
            centerTitle: true,
            actions: [
              // Delete only available to creator
              if (!loading && !missing && snap.data!.data()!['createdByUid'] ==
                  FirebaseAuth.instance.currentUser?.uid &&
                  onDeletePoll != null)
                IconButton(
                  icon: const Icon(HuddlIcons.delete,
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
          body: loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: HuddlColors.primary))
              : missing
                  ? Center(
                      child: Text('Poll not found',
                          style: HuddlText.body(color: context.hc.textTertiary)))
                  : _buildBody(context, FirestorePoll.fromDoc(snap.data!)),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, FirestorePoll poll) {
    final total = poll.totalVoteCount;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final myVotedIds = poll.myVotedOptionIds(myUid).toSet();
    final isCreator = poll.isCreatedByMe;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Question header ───────────────────────────────────────────
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
                    child: const Icon(HuddlIcons.poll,
                        size: 18, color: HuddlColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Created by ${poll.createdByName}',
                          style: HuddlText.caption(color: context.hc.textTertiary),
                        ),
                        if (poll.isExpired)
                          Text(
                            'Poll closed',
                            style: HuddlText.caption(weight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${poll.totalVoters} voter${poll.totalVoters != 1 ? 's' : ''}',
                    style: HuddlText.body(weight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                poll.question,
                style: HuddlText.heading(),
              ),
              if (poll.isCalendarMode)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(HuddlIcons.calendar,
                          size: 13,
                          color: HuddlColors.primary.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text(
                        'Calendar poll',
                        style: HuddlText.caption(color: HuddlColors.primary.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Options with full vote breakdown ──────────────────────────
        ...poll.options.map((opt) {
          final pct = total > 0
              ? (opt.voteCount / total * 100).round()
              : 0;
          final isMyVote = myVotedIds.contains(opt.id);
          // voter UIDs for this option — only creator sees names
          final voterUids = isCreator ? poll.votersForOption(opt.id) : <String>[];

          return AnimatedScale(
            scale: isMyVote ? 1.02 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: Container(
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
                Row(
                  children: [
                    if (poll.isCalendarMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(HuddlIcons.calendar,
                            size: 16,
                            color: isMyVote
                                ? HuddlColors.primary
                                : HuddlColors.textHint),
                      ),
                    Expanded(
                      child: Text(
                        opt.label,
                        style: HuddlText.body(weight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: HuddlText.heading(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 0.0,
                    end: total > 0 ? opt.voteCount / total : 0.0,
                  ),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value,
                      backgroundColor: HuddlColors.divider,
                      color: isMyVote
                          ? HuddlColors.primary
                          : HuddlColors.neutral900,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${opt.voteCount} vote${opt.voteCount != 1 ? 's' : ''}',
                  style: HuddlText.caption(color: context.hc.textTertiary),
                ),
                // Voter avatars — creator only
                if (voterUids.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: context.hc.divider),
                  const SizedBox(height: 10),
                  ...voterUids.map((uid) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _VoterRow(uid: uid),
                      )),
                ],
              ],
            ),
            ),
          );
        }),

        // ── Delete button — creator only ──────────────────────────────
        if (isCreator && onDeletePoll != null) ...[
          const SizedBox(height: 20),
          HuddlButton(
            label: 'Delete Poll',
            variant: HuddlButtonVariant.destructive,
            leadingIcon: HuddlIcons.delete,
            fullWidth: true,
            onPressed: () {
              Navigator.pop(context);
              onDeletePoll?.call();
            },
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }
}

// ─── Voter row (loads display name from Firestore user profile) ─────────────

class _VoterRow extends StatefulWidget {
  final String uid;
  const _VoterRow({required this.uid});

  @override
  State<_VoterRow> createState() => _VoterRowState();
}

class _VoterRowState extends State<_VoterRow> {
  String? _name;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      if (!mounted) return;
      final d = snap.data() ?? {};
      setState(() {
        _name = d['name'] as String? ??
            d['displayName'] as String? ??
            'Member';
        _photoUrl = d['photoUrl'] as String?;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final name = _name ?? '…';
    final photo = _photoUrl ?? getProfilePhotoForMember(widget.uid);
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: HuddlColors.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          clipBehavior: Clip.antiAlias,
          child: photo != null
              ? CachedNetworkImage(imageUrl: photo,
                  fit: BoxFit.cover,
                  width: 28,
                  height: 28,
                  memCacheWidth: 56,
                  errorWidget: (_, __, ___) => _initials(name))
              : _initials(name),
        ),
        const SizedBox(width: 8),
        Text(
          name,
          style: HuddlText.body(color: context.hc.textSecondary),
        ),
      ],
    );
  }

  Widget _initials(String name) => Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: HuddlText.caption(weight: FontWeight.w600),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// LEGACY PollCard — kept for backward-compat with polls that have no
// firestorePollId (created before this migration).
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
              : HuddlColors.primary.withValues(alpha: 0.25),
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
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(HuddlIcons.poll,
                      size: 16, color: HuddlColors.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Poll by ${poll.creatorName}',
                    style: HuddlText.caption(),
                  ),
                ),
                if (expired)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HuddlColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Expired',
                      style: HuddlText.label(),
                    ),
                  ),
                PopupMenuButton<String>(
                  icon: Icon(HuddlIcons.moreVert,
                      size: 20,
                      color: context.hc.textTertiary.withValues(alpha: 0.7)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  offset: const Offset(0, 32),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  color: context.hc.surface,
                  elevation: 8,
                  onSelected: (v) {
                    switch (v) {
                      case 'pin':
                        onTogglePin?.call();
                        break;
                      case 'results':
                        onSeeResults?.call();
                        break;
                      case 'delete':
                        onDeletePoll?.call();
                        break;
                    }
                  },
                  itemBuilder: (_) {
                    final items = <PopupMenuEntry<String>>[];
                    if (isCreator) {
                      if (!expired) {
                        items.add(PopupMenuItem<String>(
                          value: 'pin',
                          child: Row(children: [
                            Icon(
                                poll.isPinned
                                    ? HuddlIcons.pin
                                    : HuddlIcons.pin,
                                size: 20,
                                color: context.hc.textPrimary),
                            const SizedBox(width: 12),
                            Text(poll.isPinned ? 'Unpin' : 'Pin poll',
                                style: HuddlText.body()),
                          ]),
                        ));
                      }
                      items.add(PopupMenuItem<String>(
                        value: 'results',
                        child: Row(children: [
                          Icon(HuddlIcons.barChart,
                              size: 20, color: context.hc.textPrimary),
                          const SizedBox(width: 12),
                          Text('See Results',
                              style: HuddlText.body()),
                        ]),
                      ));
                      items.add(PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(children: [
                          const Icon(HuddlIcons.delete,
                              size: 20, color: HuddlColors.error),
                          const SizedBox(width: 12),
                          Text('Delete Poll',
                              style: HuddlText.body(color: HuddlColors.error)),
                        ]),
                      ));
                    }
                    return items;
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              poll.data.question,
              style: HuddlText.body(weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (isCreator)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(HuddlIcons.info,
                        size: 14, color: HuddlColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'You created this poll',
                      style: HuddlText.caption(color: HuddlColors.primary),
                    ),
                  ],
                ),
              ),
            ...List.generate(poll.data.options.length, (i) {
              final selected = poll.myVotes.contains(i);
              final count = poll.votesFor(i);
              final total = poll.totalVotes;
              final pct = total > 0 ? (count / total * 100).round() : 0;
              final canVote = !expired && !isCreator &&
                  (!hasVoted || poll.data.allowMultiple);
              return GestureDetector(
                onTap: canVote ? () => onSelectOption?.call(i) : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  constraints: const BoxConstraints(minHeight: 48),
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
                      if (!isCreator) ...[
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: poll.data.allowMultiple
                              ? _CheckIcon(selected: selected)
                              : _RadioIcon(selected: selected),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (poll.data.isCalendarMode)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(HuddlIcons.calendar,
                              size: 14, color: HuddlColors.textHint),
                        ),
                      Expanded(
                        child: Text(
                          poll.data.options[i],
                          style: HuddlText.body(),
                        ),
                      ),
                      if (isCreator || hasVoted) ...[
                        Text(
                          '$count ($pct%)',
                          style: HuddlText.caption(),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(HuddlIcons.howToVote,
                    size: 14, color: context.hc.textTertiary),
                const SizedBox(width: 4),
                Text(
                  isCreator
                      ? '${poll.totalVotes} vote${poll.totalVotes != 1 ? 's' : ''}'
                      : (hasVoted ? 'Vote recorded' : 'Tap to vote'),
                  style: HuddlText.caption(color: context.hc.textTertiary),
                ),
                if (poll.data.expiresAt != null) ...[
                  const SizedBox(width: 12),
                  Icon(HuddlIcons.clock,
                      size: 14,
                      color: expired
                          ? HuddlColors.error
                          : context.hc.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    expired
                        ? 'Poll expired'
                        : 'Closes ${_relativeTime(poll.data.expiresAt!)}',
                    style: HuddlText.caption(),
                  ),
                ],
                const Spacer(),
                if (isCreator)
                  GestureDetector(
                    onTap: onViewDetails,
                    child: Text(
                      'View results',
                      style: HuddlText.caption(),
                    ),
                  ),
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
// ACTIVE POLLS BOTTOM SHEET — unchanged for legacy polls
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
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
                      child: const Icon(HuddlIcons.poll,
                          size: 18, color: HuddlColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Active Polls',
                        style: HuddlText.heading(),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(HuddlIcons.close,
                          color: context.hc.textTertiary, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.hc.divider),
              Expanded(
                child: (activePolls.isEmpty && expiredPolls.isEmpty)
                    ? Center(
                        child: Text('No polls yet',
                            style: HuddlText.body(color: context.hc.textTertiary)))
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        children: [
                          ...activePolls.map((poll) => _LegacyPollSheetItem(
                                poll: poll,
                                onVote: (i) {
                                  widget.onVote(poll.id, i);
                                  setState(() {});
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
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LegacyPollSheetItem extends StatelessWidget {
  final ActivePoll poll;
  final void Function(int)? onVote;
  final VoidCallback? onViewDetails;
  final VoidCallback? onTogglePin;
  final VoidCallback? onDeletePoll;

  const _LegacyPollSheetItem({
    required this.poll,
    required this.onVote,
    required this.onViewDetails,
    required this.onTogglePin,
    required this.onDeletePoll,
  });

  @override
  Widget build(BuildContext context) {
    return PollCard(
      poll: poll,
      onSelectOption: onVote,
      onViewDetails: onViewDetails,
      onTogglePin: onTogglePin,
      onDeletePoll: onDeletePoll,
      onSeeResults: onViewDetails,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LEGACY PollDetailScreen — backward compat; new code uses PollResultsScreen
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
    // If this poll has a Firestore poll ID, delegate to the real-time screen
    if (poll.firestorePollId != null && poll.firestorePollId!.isNotEmpty) {
      return PollResultsScreen(
        pollId: poll.firestorePollId!,
        onDeletePoll: poll.isCreatedByMe ? onDeletePoll : null,
      );
    }

    // Legacy local-only poll
    final total = poll.totalVotes;
    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(HuddlIcons.arrowBack, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Poll Results',
          style: HuddlText.heading(),
        ),
        centerTitle: true,
        actions: [
          if (poll.isCreatedByMe && onDeletePoll != null)
            IconButton(
              icon: const Icon(HuddlIcons.delete,
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
                    Expanded(
                      child: Text('Created by ${poll.creatorName}',
                          style: HuddlText.caption(color: context.hc.textTertiary)),
                    ),
                    Text('$total vote${total != 1 ? 's' : ''}',
                        style: HuddlText.body(weight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 14),
                Text(poll.data.question,
                    style: HuddlText.heading()),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(poll.data.options.length, (i) {
            final count = poll.votesFor(i);
            final pct = total > 0 ? (count / total * 100).round() : 0;
            final isMyVote = poll.myVotes.contains(i);
            return AnimatedScale(
              scale: isMyVote ? 1.02 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Container(
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(poll.data.options[i],
                            style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                      ),
                      Text('$pct%',
                          style: HuddlText.heading(color: HuddlColors.textDark)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0.0,
                      end: total > 0 ? count / total : 0.0,
                    ),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: value,
                        backgroundColor: HuddlColors.divider,
                        color: isMyVote
                            ? HuddlColors.primary
                            : HuddlColors.neutral900,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('$count vote${count != 1 ? 's' : ''}',
                      style: HuddlText.caption(color: context.hc.textTertiary)),
                ],
              ),
              ),
            );
          }),
          if (poll.isCreatedByMe && onDeletePoll != null) ...[
            const SizedBox(height: 20),
            HuddlButton(
              label: 'Delete Poll',
              variant: HuddlButtonVariant.destructive,
              leadingIcon: HuddlIcons.delete,
              fullWidth: true,
              onPressed: () {
                Navigator.pop(context);
                onDeletePoll?.call();
              },
            ),
          ],
        ],
      ),
    );
  }
}
