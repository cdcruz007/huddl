import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import 'poll_detail_screen.dart';
import 'create_poll_screen.dart';

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

  // Mock data - in real app this would come from Firebase/backend
  final List<ActivePoll> _allPolls = [
    ActivePoll(
      id: 'poll_1',
      data: PollData(
        question: 'What time works best for the next meetup?',
        options: ['Saturday 2pm', 'Saturday 5pm', 'Sunday 11am', 'Sunday 3pm'],
        allowMultiple: false,
        expiresAt: DateTime.now().add(const Duration(days: 3)),
      ),
      creatorName: 'Sarah Johnson',
      creatorId: 'user_1',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      votes: [
        const PollVote(memberId: 'user_2', memberName: 'John Doe', optionIndex: 0),
        const PollVote(memberId: 'user_3', memberName: 'Jane Smith', optionIndex: 1),
        const PollVote(memberId: 'user_4', memberName: 'Mike Brown', optionIndex: 0),
        const PollVote(memberId: 'user_5', memberName: 'Emily Davis', optionIndex: 2),
      ],
      myVotes: {0},
      isPinned: true,
    ),
    ActivePoll(
      id: 'poll_2',
      data: PollData(
        question: 'Which activity should we do this month?',
        options: ['Bowling', 'Mini Golf', 'Movie Night', 'Picnic'],
        allowMultiple: true,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      ),
      creatorName: 'Tom Wilson',
      creatorId: 'user_6',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      votes: [
        const PollVote(memberId: 'user_1', memberName: 'Sarah Johnson', optionIndex: 0),
        const PollVote(memberId: 'user_1', memberName: 'Sarah Johnson', optionIndex: 2),
        const PollVote(memberId: 'user_2', memberName: 'John Doe', optionIndex: 1),
        const PollVote(memberId: 'user_3', memberName: 'Jane Smith', optionIndex: 3),
        const PollVote(memberId: 'user_4', memberName: 'Mike Brown', optionIndex: 0),
      ],
      myVotes: {0, 2},
      isPinned: false,
    ),
  ];

  List<ActivePoll> get _activePolls =>
      _allPolls.where((p) => !p.isExpired && !p.isDeleted).toList();

  List<ActivePoll> get _closedPolls =>
      _allPolls.where((p) => p.isExpired || p.isDeleted).toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _votePoll(String pollId, int optionIndex) {
    setState(() {
      final poll = _allPolls.firstWhere((p) => p.id == pollId);
      if (poll.isExpired) return;

      if (poll.data.allowMultiple) {
        if (poll.myVotes.contains(optionIndex)) {
          poll.myVotes.remove(optionIndex);
          poll.votes.removeWhere((v) =>
              v.memberId == 'current_user' && v.optionIndex == optionIndex);
        } else {
          poll.myVotes.add(optionIndex);
          poll.votes.add(PollVote(
            memberId: 'current_user',
            memberName: 'You',
            optionIndex: optionIndex,
          ));
        }
      } else {
        poll.myVotes.clear();
        poll.votes.removeWhere((v) => v.memberId == 'current_user');
        poll.myVotes.add(optionIndex);
        poll.votes.add(PollVote(
          memberId: 'current_user',
          memberName: 'You',
          optionIndex: optionIndex,
        ));
      }
    });
  }

  void _viewPollDetails(ActivePoll poll) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PollDetailScreen(poll: poll),
      ),
    );
  }

  void _togglePollPin(String pollId) {
    setState(() {
      final poll = _allPolls.firstWhere((p) => p.id == pollId);
      poll.isPinned = !poll.isPinned;
    });
  }

  void _deletePoll(String pollId) {
    setState(() {
      final poll = _allPolls.firstWhere((p) => p.id == pollId);
      poll.isDeleted = true;
    });
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
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: hc.textPrimary,
              ),
            ),
            Text(
              widget.groupName,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: hc.textSecondary,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: HuddlColors.primary,
          unselectedLabelColor: hc.textTertiary,
          indicatorColor: HuddlColors.primary,
          labelStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
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
    final hc = context.hc;

    if (polls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.poll_outlined,
              size: 64,
              color: hc.textTertiary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              isActive ? 'No active polls' : 'No closed polls',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: hc.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isActive
                  ? 'Create a poll in the group chat'
                  : 'Expired polls will appear here',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: hc.textTertiary,
              ),
            ),
          ],
        ),
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
