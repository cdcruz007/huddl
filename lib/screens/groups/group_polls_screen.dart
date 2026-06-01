import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../widgets/animations/huddl_spring_animations.dart';
import '../../widgets/huddl_character.dart';
import '../../theme/huddl_colors.dart';
import '../../services/poll_service.dart';
import 'poll_detail_screen.dart';
import '../../constants/app_text_styles.dart';

// ignore: unused_import
import '../../widgets/huddl_widgets.dart';

/// Screen showing all polls for a group
class GroupPollsScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupPollsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupPollsScreen> createState() => _GroupPollsScreenState();
}

class _GroupPollsScreenState extends State<GroupPollsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PollService _pollService = PollService();
  bool _isLoading = true;

  List<ActivePoll> get _allPolls => _pollService.getPolls(widget.groupId);

  List<ActivePoll> get _activePolls =>
      _allPolls.where((p) => !p.isExpired && !p.isDeleted).toList();

  List<ActivePoll> get _closedPolls =>
      _allPolls.where((p) => p.isExpired || p.isDeleted).toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pollService.addListener(_onPollsChanged);
    _loadPolls();
  }

  @override
  void dispose() {
    _pollService.removeListener(_onPollsChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onPollsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPolls() async {
    await _pollService.loadPolls(widget.groupId);
    if (mounted) setState(() => _isLoading = false);
  }

  void _votePoll(String pollId, int optionIndex) {
    setState(() {
      final idx = _allPolls.indexWhere((p) => p.id == pollId);
      if (idx == -1) return;
      final poll = _allPolls[idx];
      if (poll.isExpired) return;

      final myUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
      if (poll.data.allowMultiple) {
        if (poll.myVotes.contains(optionIndex)) {
          poll.myVotes.remove(optionIndex);
          poll.votes.removeWhere((v) =>
              v.memberId == myUid && v.optionIndex == optionIndex);
        } else {
          poll.myVotes.add(optionIndex);
          poll.votes.add(PollVote(
            memberId: myUid,
            memberName: 'You',
            optionIndex: optionIndex,
          ));
        }
      } else {
        poll.myVotes.clear();
        poll.votes.removeWhere((v) => v.memberId == myUid);
        poll.myVotes.add(optionIndex);
        poll.votes.add(PollVote(
          memberId: myUid,
          memberName: 'You',
          optionIndex: optionIndex,
        ));
      }
    });
    _pollService.savePolls(widget.groupId, List.from(_allPolls));
  }

  void _viewPollDetails(ActivePoll poll) {
    Navigator.push(
      context,
      HuddlSpringPageRoute(page: PollDetailScreen(poll: poll)),
    );
  }

  void _togglePollPin(String pollId) {
    setState(() {
      final idx = _allPolls.indexWhere((p) => p.id == pollId);
      if (idx == -1) return;
      _allPolls[idx].isPinned = !_allPolls[idx].isPinned;
    });
    _pollService.savePolls(widget.groupId, List.from(_allPolls));
  }

  void _deletePoll(String pollId) {
    setState(() {
      final idx = _allPolls.indexWhere((p) => p.id == pollId);
      if (idx == -1) return;
      _allPolls[idx].isDeleted = true;
    });
    _pollService.savePolls(widget.groupId, List.from(_allPolls));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Poll deleted'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: hc.surfaceAlt,
        appBar: AppBar(
          backgroundColor: hc.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: hc.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Polls',
              style: HuddlText.heading(color: hc.textPrimary)),
        ),
        body: const Center(
            child: CircularProgressIndicator(color: HuddlColors.textTertiary)),
      );
    }

    return Scaffold(
      backgroundColor: hc.surfaceAlt,
      appBar: AppBar(
        backgroundColor: hc.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Polls',
              style: HuddlText.heading(),
            ),
            Text(
              widget.groupName,
              style: HuddlText.caption(),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: HuddlColors.primary,
          unselectedLabelColor: hc.textTertiary,
          indicatorColor: HuddlColors.primary,
          labelStyle: HuddlText.caption(weight: FontWeight.w600),
          unselectedLabelStyle: HuddlText.caption(),
          tabs: [
            Tab(text: 'Active (${_activePolls.length})'),
            Tab(text: 'Closed (${_closedPolls.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPollsList(_activePolls, isActive: true),
          _buildPollsList(_closedPolls, isActive: false),
        ],
      ),
    );
  }

  Widget _buildPollsList(List<ActivePoll> polls, {required bool isActive}) {
    if (polls.isEmpty) {
      return HuddlEmptyState(
        mood: HuddlMood.neutral,
        illustrationAsset: isActive
            ? 'assets/illustrations/questions.png'
            : null, // closed polls: icon fallback is appropriate
        title: isActive ? 'No polls yet' : 'No closed polls',
        subtitle: isActive
            ? 'Polls created in this group will appear here for everyone to vote on.'
            : 'Expired or deleted polls will appear here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: polls.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final poll = polls[index];
        return PollCard(
          poll: poll,
          onSelectOption: (i) => _votePoll(poll.id, i),
          onViewDetails: () => _viewPollDetails(poll),
          onTogglePin: () => _togglePollPin(poll.id),
          onDeletePoll: () => _deletePoll(poll.id),
          onSeeResults: () => _viewPollDetails(poll),
          onChangeVote: () {
            // Allow changing vote
          },
        );
      },
    );
  }
}
